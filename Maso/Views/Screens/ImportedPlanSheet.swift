import SwiftUI

// ImportedPlanSheet — 从 maso://import?plan=... deep link 接收到的 plan 预览页.
//
// 流程:
//   - 朋友在 PlanDetailSheet 点 Share → 复制 / 发链接 (Messages / AirDrop / 微信...)
//   - 你点链接 → MasoApp.onOpenURL → PlanShareCodec.decodePlan → 弹这个 sheet
//   - 你看完 plan 内容 → 点 "Add to my plans" → clone 到 data.plans
//
// 跟 CommunityPlanDetailSheet 一样的视觉骨架, 但简化:
//   - community plan 有多 session, 这里只有单个 Plan
//   - 没有 kicker / level chip / 难度分类 — 朋友分享的 plan 没这些元数据
//   - 顶部多一段 disclaimer "Got a plan from a friend? ..." — 给上下文.
struct ImportedPlanSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    /// 解码出来的 plan — 已经有新 id (PlanShareCodec 处理), 直接 append 进 data.plans 即可
    let plan: Plan
    /// 父级处理实际 add — 让 root view 控制顺序 (先 dismiss 再 mutate data, 防视觉闪动)
    let onAdd: (Plan) -> Void

    private var totalSets: Int { plan.steps.reduce(0) { $0 + $1.sets } }
    private var stepCount: Int { plan.steps.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Header — kicker + plan 名 + disclaimer
                    VStack(alignment: .leading, spacing: 8) {
                        Text("IMPORTED PLAN")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                        Text(plan.name.isEmpty
                             ? NSLocalizedString("Imported plan", comment: "fallback name for unnamed shared plan")
                             : plan.name)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Got a plan from a friend? Tap Add to save it to your library.")
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                            .fixedSize(horizontal: false, vertical: true)
                        // chips — 动作数 / 总组数 (没 difficulty chip, 朋友分享时不存这种 metadata)
                        HStack(spacing: 6) {
                            ImportChip(text: String(
                                format: NSLocalizedString("%lld exercises", comment: ""),
                                stepCount
                            ))
                            ImportChip(text: "\(totalSets) sets")
                        }
                    }
                    .padding(.top, 4)

                    // Step list — 跟 CommunityPlanDetailSheet 同款 row
                    VStack(spacing: 8) {
                        ForEach(plan.steps) { step in
                            ImportedStepRow(step: step, exercise: data.exById[step.exerciseId])
                        }
                    }

                    // 底部 CTA — Add to my plans (跟 community 同款绿胶囊)
                    Button(action: { onAdd(plan) }) {
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
                    .accessibilityLabel("Add to my plans")

                    Color.clear.frame(height: 16)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(MasoColor.text)
    }
}

// MARK: - Imported plan helpers

private struct ImportChip: View {
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

/// 单条动作 row — 跟 Community 版同款, 但用 PlanStep 而不是 CommunityStep.
private struct ImportedStepRow: View {
    let step: PlanStep
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
                // 朋友分享的 plan 里如果 exerciseId 在我们 library 找不到 (理论上不会, 因为
                // ExerciseLibrary 是 bundled, 两台 iPhone 同 app 版本 → 同一份).
                // 但跨版本时 (老版本 share, 新版本没这个 exercise 了) 可能出现, fallback 防崩.
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
