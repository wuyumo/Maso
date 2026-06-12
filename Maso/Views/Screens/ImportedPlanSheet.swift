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

    private struct PickTarget: Identifiable { let id: String }
    private static let amber = Color(red: 0.96, green: 0.72, blue: 0.22)

    init(candidates: [ImportCandidate], onCommit: @escaping (Plan) -> Void) {
        self.onCommit = onCommit
        _candidates = State(initialValue: candidates)
        _routineName = State(initialValue: NSLocalizedString("Imported routine", comment: "imported routine default name"))
    }

    // 动态分组 — 一旦某条被确认 (exerciseId 非空) 就归到 Added.
    private var added: [ImportCandidate] { candidates.filter { $0.exerciseId != nil } }
    private var review: [ImportCandidate] { candidates.filter { $0.exerciseId == nil && $0.confidence == .uncertain } }
    private var unmatched: [ImportCandidate] { candidates.filter { $0.exerciseId == nil && $0.confidence == .unmatched } }
    private var includeCount: Int { candidates.filter { $0.included && $0.exerciseId != nil }.count }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    if !added.isEmpty { section(NSLocalizedString("ADDED", comment: ""), added.count) { ForEach(added) { addedRow($0) } } }
                    if !review.isEmpty { section(NSLocalizedString("NEEDS REVIEW", comment: ""), review.count) { ForEach(review) { reviewRow($0) } } }
                    if !unmatched.isEmpty { section(NSLocalizedString("NOT IN YOUR LIBRARY", comment: ""), unmatched.count) { ForEach(unmatched) { unmatchedRow($0) } } }
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
            Text("We added the moves we recognized. Review the rest — confirm, swap, or save as a custom move.")
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func section<Content: View>(_ title: String, _ count: Int, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 10, weight: .heavy)).tracking(1.5).foregroundStyle(MasoColor.textDim)
                Text("\(count)").font(.system(size: 10, weight: .heavy)).foregroundStyle(MasoColor.textFaint)
                Spacer()
            }
            content()
        }
    }

    // MARK: rows

    private func addedRow(_ c: ImportCandidate) -> some View {
        HStack(spacing: 12) {
            Button { toggle(c.id) } label: {
                Image(systemName: c.included ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(c.included ? MasoColor.accent : MasoColor.textFaint)
            }
            .buttonStyle(.plain)
            exImage(c.exerciseId)
            VStack(alignment: .leading, spacing: 3) {
                Text(exName(c.exerciseId)).font(.system(size: 14, weight: .semibold)).foregroundStyle(MasoColor.text).lineLimit(1)
                Text(metricText(c)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MasoColor.textDim).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .opacity(c.included ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { toggle(c.id) }
    }

    private func reviewRow(_ c: ImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.rawName).font(.system(size: 14, weight: .semibold)).foregroundStyle(MasoColor.text).lineLimit(2)
                    if let sug = c.suggestionId {
                        Text(String(format: NSLocalizedString("Looks like %@", comment: ""), exName(sug)))
                            .font(.system(size: 12)).foregroundStyle(Self.amber).lineLimit(1)
                    }
                    Text(metricText(c)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MasoColor.textFaint)
                }
                Spacer(minLength: 0)
                dismissButton(c.id)
            }
            chipRow {
                if let sug = c.suggestionId {
                    actionChip(String(format: NSLocalizedString("Use %@", comment: ""), exName(sug)), filled: true) { resolve(c.id, exerciseId: sug) }
                }
                actionChip(NSLocalizedString("Choose", comment: ""), systemImage: "magnifyingglass") { pickTarget = PickTarget(id: c.id) }
                actionChip(NSLocalizedString("Save as custom", comment: ""), systemImage: "plus") { addCustom(c) }
            }
        }
        .padding(12)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Self.amber.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        )
    }

    private func unmatchedRow(_ c: ImportCandidate) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(c.rawName).font(.system(size: 14, weight: .semibold)).foregroundStyle(MasoColor.text).lineLimit(2)
                    Text(NSLocalizedString("Not in your library", comment: "")).font(.system(size: 12)).foregroundStyle(MasoColor.textDim)
                    Text(metricText(c)).font(.system(size: 11).monospacedDigit()).foregroundStyle(MasoColor.textFaint)
                }
                Spacer(minLength: 0)
                dismissButton(c.id)
            }
            chipRow {
                actionChip(String(format: NSLocalizedString("Save “%@” as custom", comment: ""), c.rawName), systemImage: "plus", filled: true) { addCustom(c) }
                actionChip(NSLocalizedString("Choose", comment: ""), systemImage: "magnifyingglass") { pickTarget = PickTarget(id: c.id) }
            }
        }
        .padding(12)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MasoColor.borderSoft, lineWidth: 1))
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

    private func chipRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) { content() }
        }
    }

    private func actionChip(_ title: String, systemImage: String? = nil, filled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let s = systemImage { Image(systemName: s).font(.system(size: 10, weight: .bold)) }
                Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            }
            .foregroundStyle(filled ? .black : MasoColor.text)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(filled ? MasoColor.accent : MasoColor.surfaceHi)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func dismissButton(_ id: String) -> some View {
        Button { remove(id) } label: {
            Image(systemName: "xmark").font(.system(size: 11, weight: .bold)).foregroundStyle(MasoColor.textFaint)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
    }

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

    private func metricText(_ c: ImportCandidate) -> String {
        var parts: [String] = []
        let s = c.sets ?? 3
        if let r = c.reps { parts.append("\(s) × \(r)") }
        else { parts.append(String(format: NSLocalizedString("%lld sets", comment: ""), s)) }
        if let w = c.weight, w > 0 {
            let num = w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.1f", w)
            parts.append("· \(num) kg")
        }
        return parts.joined(separator: " ")
    }

    // MARK: mutations

    private func resolve(_ id: String, exerciseId: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].exerciseId = exerciseId
        candidates[i].included = true
        Haptics.tap()
    }

    private func addCustom(_ c: ImportCandidate) {
        let ex = data.createCustomExercise(named: c.rawName)
        resolve(c.id, exerciseId: ex.id)
    }

    private func toggle(_ id: String) {
        guard let i = candidates.firstIndex(where: { $0.id == id }) else { return }
        candidates[i].included.toggle()
    }

    private func remove(_ id: String) {
        candidates.removeAll { $0.id == id }
    }

    private func commit() {
        let picked = candidates.filter { $0.included && $0.exerciseId != nil }
        guard !picked.isEmpty else { return }
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
