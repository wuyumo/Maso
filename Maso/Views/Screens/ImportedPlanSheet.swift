import SwiftUI

// ImportedPlanSheet — 从 maso://import?plan=... deep link 接收到的 plan 预览页.
//
// 流程:
//   - 朋友在 PlanDetailSheet 点 Share → 复制 / 发链接 (Messages / AirDrop / 微信...)
//   - 你点链接 → MasoApp.onOpenURL → PlanShareCodec.decodePlan → 弹这个 sheet
//   - 你看完 plan 内容 → 点 "Add to my plans" → clone 到 data.plans
//
// Shared native exercise section; import owns only decoding and acceptance.
struct ImportedPlanSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    /// 解码出来的 plan — 已经有新 id (PlanShareCodec 处理), 直接 append 进 data.plans 即可
    let plan: Plan
    /// 父级处理实际 add — 让 root view 控制顺序 (先 dismiss 再 mutate data, 防视觉闪动)
    let onAdd: (Plan) -> Void

    @State private var useCardLayout = false
    @State private var selectedExercise: Exercise?
    @State private var paywallPresented = false

    private var totalSets: Int { plan.steps.reduce(0) { $0 + $1.sets } }
    private var stepCount: Int { plan.steps.count }

    var body: some View {

        AppNavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Imported plan").font(.caption).foregroundStyle(.secondary)
                        Text(plan.name.isEmpty ? NSLocalizedString("Imported plan", comment: "") : plan.name)
                            .font(.title2.weight(.bold)).fixedSize(horizontal: false, vertical: true)
                        Text("\(pluralizedExercises(stepCount)) · \(pluralizedSets(totalSets))")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }.padding(.vertical, 8)
                }.listRowBackground(Color.clear)
                WorkoutExercisesSection(items: plan.steps, useCardLayout: $useCardLayout, emptyTitle: "No exercises in this workout") { step in
                    ImportedStepRow(step: step, exercise: data.exById[step.exerciseId],
                                    onTapImage: { selectedExercise = data.exById[step.exerciseId] }, grid: useCardLayout)
                }
            }
            .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(MasoColor.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: "Add to my plans") {
                    guard data.canSaveImportedPlans([plan]) else { paywallPresented = true; return }
                    onAdd(plan)
                }
                    .padding(MasoMetrics.pagePaddingHorizontal)
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .sheet(item: $selectedExercise) { ExerciseDetailSheet(exercise: $0).presentationDetents([.large]) }
            .sheet(isPresented: $paywallPresented) { PaywallScreen(source: "import_plan_limit") }
        }.tint(MasoColor.text)
    }


}

// MARK: - Imported plan helpers

/// 单条动作 row — 跟 Community 版同款, 但用 PlanStep 而不是 CommunityStep.
private struct ImportedStepRow: View {
    let step: PlanStep
    let exercise: Exercise?
    var onTapImage: (() -> Void)? = nil
    var grid = false

    var body: some View {

        if let exercise {
            if grid { WorkoutExerciseGridCard(detailLine: stepMeta, exercise: exercise, onTapImage: onTapImage, parameterStep: step) }
            else { WorkoutExerciseRow(detailLine: stepMeta, exercise: exercise, onTapImage: onTapImage, parameterStep: step) }
        } else {
            Label { VStack(alignment: .leading, spacing: 4) {
                Text(step.exerciseId).font(.body)
                Text(stepMeta).font(.footnote).foregroundStyle(.secondary)
            } } icon: { Image(systemName: "questionmark").foregroundStyle(.secondary) }
                .padding(.vertical, 8)
        }


    }

    private var stepMeta: String { planStepDetailLine(step) }

}

// MARK: - RoutineReviewSheet — 第三方截图 OCR 识别后的置信度确认页 (#image-import)
//
// 三段, 随用户确认动态重组:
//   Added         — high 置信 + 已确认的: 默认勾选 → 计入 routine (展示库里规范名 + 图里识别的组数/重量).
//   Needs review  — uncertain: 浅白虚线卡, 原文 + "看起来像 X" → 用建议 / 换一个 / 忽略.
//   Not in library — unmatched: 原文 + 组数重量 → 必须从库里换一个才可加入 / 忽略.
//   (不提供"存为自创" — 自创动作唯一入口是动作库 "+", 那里有 Pro gate, 这里不开旁门.)
// 组数/重量一律用图里识别的 (即使该动作有历史数据也覆盖), 直接写进 PlanStep; 无则默认 3 组.
struct RoutineReviewSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let onCommit: (Plan) -> Void

    @State private var candidates: [ImportCandidate]
    @State private var routineName: String
    @State private var pickTarget: PickTarget?
    @State private var committed = false   // 防连点 commit 重复加入
    @State private var paywallPresented = false

    private struct PickTarget: Identifiable { let id: String }

    init(candidates: [ImportCandidate], onCommit: @escaping (Plan) -> Void) {
        self.onCommit = onCommit
        _candidates = State(initialValue: candidates)
        _routineName = State(initialValue: NSLocalizedString("Imported routine", comment: "imported routine default name"))
    }

    private var includeCount: Int { candidates.filter { $0.included && $0.exerciseId != nil }.count }

    var body: some View {
        AppNavigationStack {
            List {
                Section { header }.listRowBackground(Color.clear)
                Section { ForEach(candidates) { candidateRow($0) } }
            }.listStyle(.insetGrouped).scrollContentBackground(.hidden)
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
        .sheet(isPresented: $paywallPresented) { PaywallScreen(source: "import_plan_limit") }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Import from photo")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField(NSLocalizedString("Routine name", comment: ""), text: $routineName)
                .font(.title2.weight(.bold))
                .foregroundStyle(MasoColor.text)
                .textInputAutocapitalization(.words)
            Text(NSLocalizedString("NEEDS REVIEW", comment: "").localizedCapitalized)
                .font(.subheadline)
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // OCR source, confidence, selection and replacement sit around the shared exercise row.
    private func candidateRow(_ c: ImportCandidate) -> some View {

        let exercise = c.exerciseId.flatMap { data.exById[$0] }
        return HStack(spacing: 12) {
            NativeSelectionRow(selected: c.included && exercise != nil, action: { if exercise != nil { toggle(c.id) } }) {
                VStack(alignment: .leading, spacing: 4) {
                    if c.confidence != .high, exercise != nil {
                        Text(String(format: NSLocalizedString("Recognized “%@”", comment: ""), c.ocrText))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if let exercise {
                        ExerciseRowContent(exercise: exercise, detailLine: metricText(c))
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(c.ocrText).font(.body)
                            Text(metricText(c)).font(.footnote).foregroundStyle(.secondary)
                            Text("Not in your library").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 8)
                    }
                    if c.confidence != .high, exercise != nil {
                        Text(NSLocalizedString("NEEDS REVIEW", comment: "").localizedCapitalized).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            if c.confidence != .high {
                Button { pickTarget = PickTarget(id: c.id) } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }.nativeGlassButtonStyle().controlSize(.mini).tint(MasoColor.text)
                    .accessibilityLabel("Replace exercise")
            }
        }.opacity(c.included && exercise != nil ? 1 : 0.55)


    }

    // MARK: bottom CTA

    private var commitBar: some View {

        PrimaryActionButton(title: LocalizedStringKey(includeCount == 0
            ? NSLocalizedString("Select at least one", comment: "")
            : String(format: NSLocalizedString("Add %lld to routine", comment: ""), includeCount)), action: commit)
            .disabled(includeCount == 0 || committed)
            .padding(MasoMetrics.pagePaddingHorizontal)
            .background(MasoColor.background)


    }

    // MARK: small helpers

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
            // 识别值按 kg 落库 (OCR 里的 lb/磅 已在 PlanShareCodec 换算), 显示走用户单位
            parts.append(weightLabel(w))
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
        guard data.canSaveImportedPlans([plan]) else { paywallPresented = true; return }
        committed = true
        onCommit(plan)
    }
}

/// .sheet(item:) 用的 Identifiable 包装 — 装一组 OCR 候选, 驱动 RoutineReviewSheet.
struct RoutineReviewPayload: Identifiable {
    let id = UUID().uuidString
    let candidates: [ImportCandidate]
}

// MARK: - 批量导入 (#routines-batch-share) — 批量分享卡 QR 里 ≥2 个计划时的确认页

/// sheet(item:) 载荷 — [Plan] 自身不 Identifiable, 包一层.
struct ImportedPlansPayload: Identifiable {
    let id = UUID()
    let plans: [Plan]
}

/// 多计划导入确认 — 逐个勾选 (默认全选) + 「添加 (n)」. 名称/逐组数据已在解码侧 1:1 保留,
/// 这里只做"要哪几个"的取舍, 不提供编辑 (导入后随时可改).
struct ImportedPlansSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    let plans: [Plan]
    let onAdd: ([Plan]) -> Void
    @State private var selected: Set<String> = []
    @State private var seeded = false
    @State private var paywallPresented = false

    private var chosen: [Plan] { plans.filter { selected.contains($0.id) } }

    var body: some View {
        AppNavigationStack {
            List(plans) { plan in row(plan) }
                .listStyle(.insetGrouped).scrollContentBackground(.hidden)
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Import routines", comment: "batch import sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                PrimaryActionButton(title: LocalizedStringKey(String(format: NSLocalizedString("Add (%lld)", comment: ""), chosen.count))) {
                    guard !chosen.isEmpty else { return }
                    guard data.canSaveImportedPlans(chosen) else { paywallPresented = true; return }
                    onAdd(chosen)
                    dismiss()
                }
                .disabled(chosen.isEmpty)
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(MasoColor.background)
            }
            .tint(MasoColor.text)
            .sheet(isPresented: $paywallPresented) { PaywallScreen(source: "import_plan_limit") }
        }
        .onAppear {
            if !seeded { seeded = true; selected = Set(plans.map(\.id)) }   // 默认全选
        }
    }

    private func row(_ plan: Plan) -> some View {

        NativeSelectionRow(selected: selected.contains(plan.id), action: {
            Haptics.tap()
            if selected.contains(plan.id) { selected.remove(plan.id) } else { selected.insert(plan.id) }
        }) { WorkoutSummaryContent(plan: plan).padding(.vertical, 8) }
    }


}
