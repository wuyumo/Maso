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
                    photoURL: ex.photoURL,
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

// MARK: - RoutineReviewSheet — 第三方截图 OCR 识别后的置信度确认页 (#image-import)
//
// 三段, 随用户确认动态重组:
//   Added         — high 置信 + 已确认的: 默认勾选 → 计入 routine (展示库里规范名 + 图里识别的组数/重量).
//   Needs review  — uncertain: 醒目琥珀色卡, 原文 + "看起来像 X" → 用建议 / 换一个 / 存为自创 / 忽略.
//   Not in library — unmatched: 原文 + 组数重量 → 换一个 / 存为自创 / 忽略.
// 组数/重量一律用图里识别的 (即使该动作有历史数据也覆盖), 直接写进 PlanStep; 无则默认 3 组.
struct RoutineReviewSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onCommit: (Plan) -> Void

    @State private var candidates: [ImportCandidate]
    @State private var routineName: String
    @State private var pickTarget: PickTarget?
    @State private var committed = false   // 防连点 commit 重复加入

    private struct PickTarget: Identifiable { let id: String }
    private static let suggestBorder = Color.white.opacity(0.22)   // 浅白色虚线框 — 标记"建议/未确认"

    init(candidates: [ImportCandidate], onCommit: @escaping (Plan) -> Void) {
        self.onCommit = onCommit
        _candidates = State(initialValue: candidates)
        _routineName = State(initialValue: NSLocalizedString("Imported routine", comment: "imported routine default name"))
    }

    private var includeCount: Int { candidates.filter { $0.included && $0.exerciseId != nil }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    header.padding(.bottom, 8)
                    ForEach(candidates) { candidateRow($0) }
                    Color.clear.frame(height: 8)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 4)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) { commitBar }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $pickTarget) { t in
                ExercisePickerSheet(onPick: { ex in
                    resolve(t.id, exerciseId: ex.id)
                    pickTarget = nil
                })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
        }
        .tint(MasoColor.text)
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("IMPORT FROM PHOTO")
                .font(.system(size: 10, weight: .heavy)).tracking(1.5)
                .foregroundStyle(MasoColor.accent)
            TextField(NSLocalizedString("Routine name", comment: ""), text: $routineName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .textInputAutocapitalization(.words)
            Text("Uncheck anything you don't want. Dashed rows are our best guess — tap replace to swap.")
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: 统一候选行
    //
    // high / suggested / unmatched 都是同一种 checkbox 行 (用户都能 uncheck), 区别只在样式:
    //   high      → 实底, 无 caption, 无替换键.
    //   suggested → 浅白虚线框 + 识别原文 caption (主文案上方, 轻一级) + 替换键; 默认勾选.
    //   unmatched → 同 suggested 样式, 但还没对应动作 → 默认不勾, 必须替换后才能加入.
    private func candidateRow(_ c: ImportCandidate) -> some View {
        let dashed = c.confidence != .high          // 非完全匹配 → 浅白虚线框 + caption + 替换键
        let hasEx = c.exerciseId != nil
        return HStack(spacing: 12) {
            Button { if hasEx { toggle(c.id) } } label: {
                Image(systemName: (c.included && hasEx) ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle((c.included && hasEx) ? MasoColor.accent : MasoColor.textFaint)
            }
            .buttonStyle(.plain)
            .disabled(!hasEx)

            exImage(c.exerciseId)

            VStack(alignment: .leading, spacing: 2) {
                // 识别原文 — 轻一级, 在主文案上方, 标注来源 ("识别出 “XX”").
                // unmatched 没有库内对应 → 主文案就是原文, 不重复显示 caption.
                if dashed && hasEx {
                    Text(String(format: NSLocalizedString("Recognized “%@”", comment: "ocr caption"), c.ocrText))
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textFaint)
                        .lineLimit(1)
                }
                // 主文案 — 建议替换的库内动作 (无对应时退回识别原文)
                Text(hasEx ? exName(c.exerciseId) : c.ocrText)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasEx ? MasoColor.text : MasoColor.textDim)
                    .lineLimit(1)
                Text(metricText(c))
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)

            if dashed {
                Button { pickTarget = PickTarget(id: c.id) } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MasoColor.textSoft)
                        .frame(width: 34, height: 34)
                        .background(MasoColor.surfaceHi)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(NSLocalizedString("Replace exercise", comment: ""))
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay {
            if dashed {
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Self.suggestBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            }
        }
        .opacity((c.included && hasEx) ? 1 : 0.55)
        .contentShape(Rectangle())
        .onTapGesture { if hasEx { toggle(c.id) } }
    }

    // MARK: bottom CTA

    private var commitBar: some View {
        VStack(spacing: 0) {
            Button(action: commit) {
                Text(includeCount == 0
                     ? NSLocalizedString("Select at least one", comment: "")
                     : String(format: NSLocalizedString("Add %lld to routine", comment: ""), includeCount))
                    .font(.system(size: 15, weight: .heavy))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(includeCount == 0 ? MasoColor.textFaint : MasoColor.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(includeCount == 0)
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(MasoColor.background.opacity(0.96))
    }

    // MARK: small helpers

    @ViewBuilder private func exImage(_ exerciseId: String?) -> some View {
        if let id = exerciseId, let ex = data.exById[id] {
            ExerciseImage(category: ex.category, imageFolder: ex.imageFolder, photoURL: ex.photoURL,
                          cornerRadius: 8, size: 40, animated: false)
        } else {
            RoundedRectangle(cornerRadius: 8).fill(MasoColor.surfaceHi).frame(width: 40, height: 40)
                .overlay(Image(systemName: "dumbbell.fill").font(.system(size: 13)).foregroundStyle(MasoColor.textFaint))
        }
    }

    private func exName(_ exerciseId: String?) -> String {
        guard let id = exerciseId, let ex = data.exById[id] else { return "" }
        return ex.displayName
    }

    /// 诚实显示: 只展示从图里真正识别出的数字; 一项都没有 → 标注"默认 3 组" (commit 时的兜底值),
    /// 不冒充识别结果. 有次数没组数时只写 "10 reps", 不编造组数.
    private func metricText(_ c: ImportCandidate) -> String {
        var parts: [String] = []
        if let s = c.sets {
            if let r = c.reps { parts.append("\(s) × \(r)") }
            else { parts.append(String(format: NSLocalizedString("%lld sets", comment: ""), s)) }
        } else if let r = c.reps {
            parts.append(String(format: NSLocalizedString("%lld reps", comment: ""), r))
        }
        if let w = c.weight, w > 0 {
            let num = w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.1f", w)
            parts.append("\(num) kg")
        }
        if parts.isEmpty { return NSLocalizedString("3 sets · default", comment: "no metrics recognized") }
        return parts.joined(separator: " · ")
    }

    // MARK: mutations

    private func resolve(_ id: String, exerciseId: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].exerciseId = exerciseId
        candidates[i].included = true
        Haptics.tap()
    }

    private func toggle(_ id: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].included.toggle()
    }

    private func commit() {
        guard !committed else { return }
        let picked = candidates.filter { $0.included && $0.exerciseId != nil }
        guard !picked.isEmpty else { return }
        committed = true
        let now = Date()
        let steps: [PlanStep] = picked.enumerated().map { (i, c) in
            PlanStep(
                id: "step-import-\(i)-\(UUID().uuidString.prefix(4))",
                exerciseId: c.exerciseId!,
                sets: c.sets ?? 3,
                reps: c.reps,
                weight: c.weight,
                duration: nil,
                restBetweenSets: 90,
                rest: 0
            )
        }
        let trimmed = routineName.trimmingCharacters(in: .whitespacesAndNewlines)
        let plan = Plan(
            id: "plan-import-\(Int(now.timeIntervalSince1970))-\(UUID().uuidString.prefix(4))",
            name: trimmed.isEmpty ? NSLocalizedString("Imported routine", comment: "") : trimmed,
            steps: steps, createdAt: now, updatedAt: now
        )
        onCommit(plan)
    }
}

/// .sheet(item:) 用的 Identifiable 包装 — 装一组 OCR 候选, 驱动 RoutineReviewSheet.
struct RoutineReviewPayload: Identifiable {
    let id = UUID().uuidString
    let candidates: [ImportCandidate]
}
