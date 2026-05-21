import SwiftUI

// Community — 精选训练计划 (MVP)
//
// 入口: PlansScreen 列表底部 "Browse community plans"
// 流程:
//   - sheet 弹出, 展示 CommunityPlans.all (8 张精选)
//   - 用户 tap "Add to my plans"
//     - 若 free + plans.count >= FreeLimit.maxPlans → 弹 paywall
//     - 否则 clone 进 data.plans → 显示 "Added" 1.2s → dismiss
//
// "发布" 功能不在 MVP — 顶部一行 disclaimer 占位.
struct CommunityScreen: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    /// "Added" toast 状态 — set 完 1.2s 后 dismiss sheet
    @State private var addedToastVisible: Bool = false
    /// Free 用户撞 plan 上限时弹的 paywall
    @State private var paywallPresented: Bool = false
    /// tap 卡片打开详情 preview
    @State private var detailPlan: CommunityPlan? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 顶部: subtitle + publish coming-soon disclaimer
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Curated workout plans. Add any to your library.")
                            .font(.system(size: 14))
                            .foregroundStyle(MasoColor.textDim)
                            .fixedSize(horizontal: false, vertical: true)

                        // 之前: "Want to publish your plan? Coming soon." (被动等待)
                        // 现在: 主动指引到分享入口 (Plans 详情页的 Share 按钮),
                        // 让用户知道分享功能已经上线 + 操作路径.
                        Text("Want to share your plan? Open it in Plans → tap Share.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textFaint)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.top, 8)

                    // Plan cards — 整张可点 → 弹详情 preview; 卡内"Add" 按钮 = quick add
                    LazyVStack(spacing: 12) {
                        ForEach(CommunityPlans.all) { plan in
                            CommunityPlanCard(
                                plan: plan,
                                onTapBody: { detailPlan = plan },
                                onAdd: { handleAdd(plan) }
                            )
                        }
                    }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    Color.clear.frame(height: 24)
                }
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Community")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Text("Done")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(MasoColor.text)
                    }
                }
            }
            .overlay(alignment: .top) {
                if addedToastVisible {
                    AddedToast()
                        .padding(.top, 60)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .sheet(isPresented: $paywallPresented) {
                PaywallScreen()
            }
            .sheet(item: $detailPlan) { plan in
                CommunityPlanDetailSheet(
                    plan: plan,
                    onAdd: {
                        detailPlan = nil
                        // 让 sheet 关一帧再 add — 不然 toast 跟 sheet 状态冲突
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                            handleAdd(plan)
                        }
                    }
                )
                .presentationDetents([.large])
            }
        }
        .tint(MasoColor.text)
    }

    private func handleAdd(_ plan: CommunityPlan) {
        // Free-cap check — 实例化后的 session 数会让总 plans 超 FreeLimit.maxPlans 也算撞墙
        // (一次性 add 一张 community plan, 但它可能包含 5 个 session = 5 张 Plan)
        let willAddCount = plan.sessions.count
        if !data.settings.isPro && data.plans.count + willAddCount > FreeLimit.maxPlans {
            paywallPresented = true
            return
        }

        let newPlans = plan.materialize(byId: data.exById)
        guard !newPlans.isEmpty else { return }

        data.plans.append(contentsOf: newPlans)
        data.save()

        Haptics.tap()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            addedToastVisible = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.easeOut(duration: 0.2)) {
                addedToastVisible = false
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                dismiss()
            }
        }
    }
}

// MARK: - CommunityPlanCard

private struct CommunityPlanCard: View {
    let plan: CommunityPlan
    let onTapBody: () -> Void
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // kicker
            Text(plan.kicker)
                .font(.system(size: 10, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(MasoColor.accent)

            // 大标题
            Text(NSLocalizedString(plan.nameKey, comment: ""))
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // 副标题 (一行说明)
            Text(NSLocalizedString(plan.descKey, comment: ""))
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            // chips: 频率 / 难度 / 动作数
            HStack(spacing: 6) {
                Chip(
                    text: String(
                        format: NSLocalizedString("%lld days/wk", comment: "frequency chip — days per week"),
                        plan.frequencyDaysPerWeek
                    )
                )
                Chip(text: NSLocalizedString(plan.levelKey, comment: "level chip"))
                Chip(
                    text: String(
                        format: NSLocalizedString("%lld exercises", comment: "exercise count chip"),
                        plan.totalExerciseCount
                    )
                )
                Spacer(minLength: 0)
            }
            .padding(.top, 2)

            // CTA 右下
            HStack {
                Spacer()
                Button(action: onAdd) {
                    HStack(spacing: 6) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("Add to my plans")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(MasoColor.background)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(MasoColor.accent)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Add to my plans")
            }
            .padding(.top, 4)
        }
        .padding(MasoMetrics.cardPadding - 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        // 整张卡 tap 弹详情 preview (Add 按钮自己有 hit area, 不冲突)
        .contentShape(Rectangle())
        .onTapGesture { onTapBody() }
    }
}

// MARK: - Chip

private struct Chip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

// MARK: - CommunityPlanDetailSheet — 详情预览 (read-only, 横跨所有 session)

private struct CommunityPlanDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let plan: CommunityPlan
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header — kicker, title, description, chips
                    VStack(alignment: .leading, spacing: 8) {
                        Text(plan.kicker)
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                        Text(NSLocalizedString(plan.nameKey, comment: ""))
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(NSLocalizedString(plan.descKey, comment: ""))
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 6) {
                            DetailChip(text: String(
                                format: NSLocalizedString("%lld days/wk", comment: ""),
                                plan.frequencyDaysPerWeek
                            ))
                            DetailChip(text: NSLocalizedString(plan.levelKey, comment: ""))
                            DetailChip(text: String(
                                format: NSLocalizedString("%lld exercises", comment: ""),
                                plan.totalExerciseCount
                            ))
                        }
                    }
                    .padding(.top, 4)

                    // Sessions list — 每个 session 一段 (kicker 标题 + 动作行)
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(Array(plan.sessions.enumerated()), id: \.offset) { _, session in
                            SessionPreviewBlock(session: session, exById: data.exById)
                        }
                    }

                    // 底部 CTA — Add to my plans (跟卡内按钮同款绿胶囊)
                    Button(action: onAdd) {
                        HStack(spacing: 8) {
                            Image(systemName: "plus")
                                .font(.system(size: 14, weight: .bold))
                            Text("Add to my plans")
                                .font(.system(size: 15, weight: .heavy))
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(MasoColor.accent)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .tint(MasoColor.text)
    }
}

private struct DetailChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(MasoColor.textSoft)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(MasoColor.surfaceHi)
            .clipShape(Capsule())
            .lineLimit(1)
    }
}

/// Session preview — kicker ("PUSH DAY") + 该 session 的 exercise 行列表
private struct SessionPreviewBlock: View {
    let session: CommunitySession
    let exById: [String: Exercise]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString(session.nameKey, comment: "").uppercased())
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(MasoColor.accent)
            VStack(spacing: 8) {
                ForEach(Array(session.steps.enumerated()), id: \.offset) { _, step in
                    StepRow(step: step, exercise: exById[step.exerciseId])
                }
            }
        }
    }
}

/// 单条动作 row — image thumbnail + name + sets×reps + rest
private struct StepRow: View {
    let step: CommunityStep
    let exercise: Exercise?

    var body: some View {
        HStack(spacing: 12) {
            if let ex = exercise {
                ExerciseImage(
                    category: ex.category,
                    imageFolder: ex.imageFolder,
                    cornerRadius: 8,
                    size: 44,
                    animated: false
                )
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(MasoColor.surfaceHi)
                    .frame(width: 44, height: 44)
                    .overlay(
                        Image(systemName: "questionmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MasoColor.textFaint)
                    )
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(exercise?.displayName ?? step.exerciseId)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                Text(stepMeta)
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var stepMeta: String {
        var parts: [String] = []
        if let reps = step.reps {
            parts.append("\(step.sets)×\(reps)")
        } else if let dur = step.duration {
            parts.append("\(step.sets)×\(dur)s")
        } else {
            parts.append("\(step.sets) sets")
        }
        parts.append("· \(step.restBetweenSets)s rest")
        return parts.joined(separator: " ")
    }
}

// MARK: - AddedToast

private struct AddedToast: View {
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MasoColor.accent)
            Text("Added")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MasoColor.text)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MasoColor.surfaceHi)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}
