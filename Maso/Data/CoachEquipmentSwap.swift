import Foundation

// 教练「把某肌群的某器械换成另一种器械」本地工具.
//
// 不走 LLM 重写整份计划: 意图解析 → 用目录元数据筛选 → 按运动模式找真实替代 →
// 预览确认后一次性写入 plans. 不改历史 SetRecord、不改动作库、不发明 exerciseId.
//
// 重量: 不同器械的负重不是等效负荷. 替换时清掉该 step 的处方重量 (weight / setWeights),
// 保留组数、次数、休息、顺序. 不把旧公斤数搬过去, 也不做 kg/lb 换算.
// 计划里没有 superset 分组字段 — step 是平铺数组, 就地换 exerciseId 即保留顺序和重复实例.

enum EquipmentSwapPersistence {
    /// 测试注入. nil = DataStore 走 PersistenceController.saveReportingFailure.
    /// 闭包在 plans 已经换成新值之后调用, 返回 false 时 DataStore 把 plans 滚回去.
    nonisolated(unsafe) static var saveOverride: (() -> Bool)?
}

enum CoachEquipmentSwap {

    struct Context {
        var plans: [Plan]
        /// 解析 step 用的全库 (含 niche / 合并前 id 的存活者). 不从这里挑替代.
        var library: [Exercise]
        /// 用户实际能选到的动作 (userLibrary: 非 niche 或已采纳 + 自创).
        var candidates: [Exercise]
        var availableEquipment: [String]
        var focusedPlanId: String?
        /// 当前对话里已经落成已存计划的 id (生成卡 id 或 savedIdMap 副本).
        var conversationPlanIds: [String]
        var onlyModifyName: String?
        var languageCode: String
    }

    enum AmbiguousTarget: Equatable {
        case genericGear      // 裸「器械」
        case plateLoaded      // 片载 — 目录没有这一档
        case mixed
    }

    enum Clarify: Equatable {
        case missingMuscle
        case missingSourceEquipment
        case missingTargetEquipment
        case ambiguousTarget(AmbiguousTarget)
        case ambiguousScope
        case mixedMuscles
    }

    struct Line: Equatable {
        let planId: String
        let planName: String
        let stepId: String
        let fromExerciseId: String
        let toExerciseId: String
        let fromName: String
        let toName: String
        let clearsWeight: Bool
    }

    struct Unreplaced: Equatable {
        enum Reason: Equatable {
            case noCandidate
            case equipmentUnavailable
        }
        let planId: String
        let planName: String
        let stepId: String
        let exerciseId: String
        let name: String
        let reason: Reason
    }

    struct Proposal: Equatable, Identifiable {
        let id: String
        let lines: [Line]
        let unreplaced: [Unreplaced]
        let scopePlanIds: [String]
        let source: EquipmentCategory
        let target: EquipmentCategory
        let muscle: MuscleGroup
        /// 用户在已打开/对话中的计划之外, 明确说了「所有计划」.
        let expandedBeyondFocus: Bool
        /// 预览不会写盘. 写入只发生在 confirm → commit 成功之后.
        var requiresConfirmation: Bool { true }
    }

    enum Outcome: Equatable {
        case notHandled
        case clarify(Clarify)
        case noMatches(scopePlanIds: [String])
        /// 命中了, 但没有一条有合格替代. 不提供确认按钮.
        case blocked(unreplaced: [Unreplaced], scopePlanIds: [String])
        case preview(Proposal)
    }

    struct UndoRecord: Equatable {
        let id: String
        let proposalId: String
        let previousPlans: [Plan]
    }

    enum CommitFailure: Equatable {
        case persist, conflict, missingPlan, missingStep, unknownExercise
    }

    enum CommitResult: Equatable {
        case applied([Plan])
        case alreadyApplied
        case failed(CommitFailure)
    }

    /// A short reply in the current chat, not a command the user has to memorize.
    /// Only the whole message counts. A longer sentence falls through to the coach.
    enum ChatFollowUp: Equatable { case confirm, cancel, undo }

    static func chatFollowUp(_ raw: String) -> ChatFollowUp? {
        let spoken = normalize(raw)
        let compact = spoken.split(whereSeparator: { $0.isWhitespace }).joined()
        guard !compact.isEmpty, compact.count <= 24 else { return nil }
        if confirmPhrases.contains(compact) { return .confirm }
        if cancelPhrases.contains(compact) { return .cancel }
        if undoPhrases.contains(compact) { return .undo }
        return nil
    }

    private static let confirmPhrases: Set<String> = [
        "确认", "确认替换", "确认修改", "就这样", "就这样改", "就这样改吧", "就这么改", "就这么办",
        "改吧", "可以改", "好的改", "好改吧", "执行", "可以", "好", "好的", "行",
        "yes", "ok", "okay", "confirm", "apply", "doit", "goahead",
    ]
    private static let cancelPhrases: Set<String> = [
        "取消", "算了", "不用了", "不用改", "不用改了", "不改", "不改了", "取消吧",
        "cancel", "nevermind", "stop", "no",
    ]
    private static let undoPhrases: Set<String> = [
        "撤销", "撤销这次", "撤销替换", "改回去", "改回来", "undo", "undothat",
    ]

    // MARK: - Interpret

    static func interpret(_ raw: String, context: Context) -> Outcome {
        let text = normalize(raw)
        guard let parts = splitSwap(text) else { return .notHandled }

        switch targetEquipment(in: parts.right) {
        case .missing: return .clarify(.missingTargetEquipment)
        case .ambiguous(let why): return .clarify(.ambiguousTarget(why))
        case .category(let target):
            let scope = resolveScope(text: text, context: context)
            switch scope {
            case .ambiguous: return .clarify(.ambiguousScope)
            case .plans(let ids, let expanded):
                let nameNeedle = context.onlyModifyName.map(normalizeName)
                if let needle = nameNeedle {
                    return interpretNamed(
                        needle: needle, target: target, scopeIds: ids,
                        expanded: expanded, left: parts.left, context: context)
                }
                switch sourceEquipment(in: parts.left) {
                case .missing: return .clarify(.missingSourceEquipment)
                case .ambiguous(let why): return .clarify(.ambiguousTarget(why))
                case .category(let source):
                    switch muscleTarget(in: text) {
                    case .missing: return .clarify(.missingMuscle)
                    case .mixed: return .clarify(.mixedMuscles)
                    case .one(let muscle):
                        return build(
                            muscle: muscle, source: source, target: target,
                            scopeIds: ids, expanded: expanded, nameNeedle: nil,
                            context: context)
                    }
                }
            }
        }
    }

    private static func interpretNamed(
        needle: String, target: EquipmentCategory, scopeIds: [String],
        expanded: Bool, left: String, context: Context
    ) -> Outcome {
        let index = CatalogIndex(library: context.library)
        let scoped = context.plans.filter { scopeIds.contains($0.id) }
        var named: [(Plan, PlanStep, Exercise)] = []
        for plan in scoped {
            for step in plan.steps {
                guard let ex = index.resolve(step.exerciseId) else { continue }
                guard nameKeys(ex).contains(needle) else { continue }
                named.append((plan, step, ex))
            }
        }
        guard !named.isEmpty else {
            return .noMatches(scopePlanIds: scopeIds)
        }
        // 文本里如果还写了肌群/原器械, 取交集; 没写就以点名的动作为准, 不外扩.
        let muscle: MuscleGroup? = {
            switch muscleTarget(in: left.isEmpty ? needle : left + " " + needle) {
            case .one(let m): return m
            case .missing, .mixed: return nil
            }
        }()
        if case .mixed = muscleTarget(in: left) { return .clarify(.mixedMuscles) }
        let source: EquipmentCategory? = {
            switch sourceEquipment(in: left) {
            case .category(let c): return c
            default: return nil
            }
        }()
        let filtered = named.filter { _, _, ex in
            if let muscle, !matchesMuscle(ex, target: muscle) { return false }
            if let source, primaryCategory(ex) != source { return false }
            return true
        }
        guard !filtered.isEmpty else { return .noMatches(scopePlanIds: scopeIds) }
        let muscles = Set(filtered.compactMap { angleKey($0.2) })
        let sources = Set(filtered.compactMap { primaryCategory($0.2) })
        guard muscles.count == 1, sources.count == 1, let source = sources.first else {
            return .clarify(.mixedMuscles)
        }
        let resolvedMuscle = filtered[0].2.primaryMuscles.first.flatMap { requestedMuscle(for: $0, hint: muscle) } ?? .chest
        return build(
            muscle: resolvedMuscle, source: source, target: target,
            scopeIds: scopeIds, expanded: expanded, nameNeedle: needle,
            context: context)
    }

    private static func requestedMuscle(for first: MuscleGroup, hint: MuscleGroup?) -> MuscleGroup {
        if let hint { return hint }
        return first.section ?? first
    }

    private static func build(
        muscle: MuscleGroup, source: EquipmentCategory, target: EquipmentCategory,
        scopeIds: [String], expanded: Bool, nameNeedle: String?, context: Context
    ) -> Outcome {
        let index = CatalogIndex(library: context.library)
        let available = Set(context.availableEquipment)
        var lines: [Line] = []
        var unreplaced: [Unreplaced] = []
        let scoped = context.plans.filter { scopeIds.contains($0.id) }
        for plan in scoped {
            for step in plan.steps {
                guard let ex = index.resolve(step.exerciseId) else { continue }
                if let needle = nameNeedle, !nameKeys(ex).contains(needle) { continue }
                guard matchesMuscle(ex, target: muscle) else { continue }
                guard primaryCategory(ex) == source else { continue }
                let title = exerciseTitle(ex, languageCode: context.languageCode)
                switch bestSubstitute(for: ex, target: target, candidates: context.candidates, available: available) {
                case .found(let repl):
                    let clears = step.weight != nil || (step.setWeights?.contains { $0 != nil } ?? false)
                    lines.append(Line(
                        planId: plan.id, planName: plan.name, stepId: step.id,
                        fromExerciseId: step.exerciseId, toExerciseId: repl.id,
                        fromName: title,
                        toName: exerciseTitle(repl, languageCode: context.languageCode),
                        clearsWeight: clears))
                case .unavailable:
                    unreplaced.append(Unreplaced(
                        planId: plan.id, planName: plan.name, stepId: step.id,
                        exerciseId: step.exerciseId, name: title, reason: .equipmentUnavailable))
                case .none:
                    unreplaced.append(Unreplaced(
                        planId: plan.id, planName: plan.name, stepId: step.id,
                        exerciseId: step.exerciseId, name: title, reason: .noCandidate))
                }
            }
        }
        if lines.isEmpty && unreplaced.isEmpty {
            return .noMatches(scopePlanIds: scopeIds)
        }
        if lines.isEmpty {
            return .blocked(unreplaced: unreplaced, scopePlanIds: scopeIds)
        }
        let id = proposalId(lines)
        let proposal = Proposal(
            id: id, lines: lines, unreplaced: unreplaced, scopePlanIds: scopeIds,
            source: source, target: target, muscle: muscle, expandedBeyondFocus: expanded)
        return .preview(proposal)
    }

    // MARK: - Commit (transaction)

    /// 内存里一次性改完再交给 persist. persist 返回 false → 调用方必须继续用旧 plans.
    /// 已经是目标动作的 step 跳过 (再次确认/再次执行不重复改).
    /// 任何一条对不上原动作、计划丢了、或目标 id 不在允许集合 → 整单失败, 不 persist.
    static func commit(
        plans: [Plan],
        proposal: Proposal,
        allowedExerciseIds: Set<String>,
        persist: ([Plan]) -> Bool
    ) -> CommitResult {
        var next = plans
        var touched = Set<Int>()
        var changed = false
        for line in proposal.lines {
            guard allowedExerciseIds.contains(line.toExerciseId) else {
                return .failed(.unknownExercise)
            }
            guard let pi = next.firstIndex(where: { $0.id == line.planId }) else {
                return .failed(.missingPlan)
            }
            guard let si = next[pi].steps.firstIndex(where: { $0.id == line.stepId }) else {
                return .failed(.missingStep)
            }
            let step = next[pi].steps[si]
            if step.exerciseId == line.toExerciseId { continue }
            if step.exerciseId != line.fromExerciseId { return .failed(.conflict) }
            // The current Mac PlanStep stores exerciseId as var (canonicalPlan assigns it).
            // Mutating the copy keeps every other stored field, including ones added after the cloud model.
            var updated = step
            updated.exerciseId = line.toExerciseId
            updated.weight = nil
            updated.setWeights = nil
            next[pi].steps[si] = updated
            touched.insert(pi)
            changed = true
        }
        guard changed else { return .alreadyApplied }
        let now = Date()
        for pi in touched { next[pi].updatedAt = now }
        if persist(next) { return .applied(next) }
        return .failed(.persist)
    }

    /// DataStore.confirmEquipmentSwap 的实际写入边界.
    /// 成功才换 plans; sets 与 aiTodayPlan 原样返回 (历史和今日副本不在这次编辑里).
    static func applyTransaction(
        plans: [Plan],
        sets: [SetRecord],
        aiTodayPlan: Plan?,
        proposal: Proposal,
        allowedExerciseIds: Set<String>,
        persist: ([Plan]) -> Bool
    ) -> (plans: [Plan], sets: [SetRecord], aiTodayPlan: Plan?, result: CommitResult, previousPlans: [Plan]?) {
        let result = commit(
            plans: plans, proposal: proposal,
            allowedExerciseIds: allowedExerciseIds, persist: persist)
        switch result {
        case .applied(let newPlans):
            return (newPlans, sets, aiTodayPlan, result, plans)
        case .alreadyApplied, .failed:
            return (plans, sets, aiTodayPlan, result, nil)
        }
    }

    /// 撤销只把 plans 放回快照. 历史和今日计划副本不动.
    static func undoTransaction(
        plans: [Plan],
        sets: [SetRecord],
        aiTodayPlan: Plan?,
        previousPlans: [Plan],
        persist: ([Plan]) -> Bool
    ) -> (plans: [Plan], sets: [SetRecord], aiTodayPlan: Plan?, saved: Bool) {
        if persist(previousPlans) {
            return (previousPlans, sets, aiTodayPlan, true)
        }
        return (plans, sets, aiTodayPlan, false)
    }

    // MARK: - Copy

    static func text(for outcome: Outcome, languageCode: String) -> String {
        let zh = languageCode.hasPrefix("zh")
        switch outcome {
        case .notHandled:
            return ""
        case .clarify(let why):
            return clarifyText(why, zh: zh)
        case .noMatches:
            return zh
                ? "在当前范围内的训练计划里, 没有符合这个肌群和器械的动作. 我没有改任何计划."
                : "No exercises in the routines I looked at match that muscle and equipment. Nothing was changed."
        case .blocked(let unreplaced, _):
            var lines = [zh
                ? "这些动作没有合适的替代, 我没有改计划:"
                : "No suitable replacement for these exercises, so I left the routines unchanged:"]
            for item in unreplaced {
                lines.append("• \(item.planName): \(item.name) — \(reasonText(item.reason, zh: zh))")
            }
            return lines.joined(separator: "\n")
        case .preview(let proposal):
            return previewText(proposal, zh: zh)
        }
    }

    static func textApplied(stepCount: Int, routineCount: Int, clearedWeight: Bool, languageCode: String) -> String {
        let zh = languageCode.hasPrefix("zh")
        var s = zh
            ? "已替换 \(stepCount) 个动作, 涉及 \(routineCount) 个计划."
            : "Replaced \(stepCount) exercises across \(routineCount) routines."
        if clearedWeight {
            s += zh
                ? " 不同器械的重量不能当等效负荷, 原重量已清掉, 练之前请重新设置."
                : " Different equipment isn’t the same load — the old weight was cleared. Set it before you train."
        }
        return s
    }

    static func textCancelled(languageCode: String) -> String {
        languageCode.hasPrefix("zh")
            ? "已取消. 没有改任何训练计划."
            : "Cancelled. No routines were changed."
    }

    static func textPersistFailed(languageCode: String) -> String {
        languageCode.hasPrefix("zh")
            ? "没能保存这次修改, 训练计划保持原样."
            : "Couldn’t save that change. The routines were left as they were."
    }

    static func textConflict(languageCode: String) -> String {
        languageCode.hasPrefix("zh")
            ? "计划在确认前被改过, 这次没有写入. 可以说一遍我再列新的预览."
            : "A routine changed before I could save, so I didn’t write anything. Ask again for a fresh preview."
    }

    static func textAlready(languageCode: String) -> String {
        languageCode.hasPrefix("zh")
            ? "这些动作已经是替换后的项目, 我没有再改一次."
            : "Those exercises are already the replacements. I didn’t edit them again."
    }

    static func textUndone(languageCode: String) -> String {
        languageCode.hasPrefix("zh")
            ? "已撤销这次替换, 计划回到确认前."
            : "Undid that replacement. The routines are back to what they were."
    }

    static func textUndoFailed(languageCode: String) -> String {
        languageCode.hasPrefix("zh")
            ? "撤销没能保存, 计划仍是替换后的版本."
            : "Couldn’t save the undo. The routines are still the replaced version."
    }

    private static func previewText(_ proposal: Proposal, zh: Bool) -> String {
        let routineCount = Set(proposal.lines.map(\.planId)).count
        var lines: [String] = []
        if zh {
            lines.append("将替换 \(proposal.lines.count) 处, 涉及 \(routineCount) 个计划. 还没写入. 回复我就按这个改, 或者说不改.")
            if proposal.expandedBeyondFocus {
                lines.append("这会超出当前打开的计划, 改到范围内的全部已存计划.")
            }
            lines.append("不同器械的重量不会当作等效负荷搬过去, 原重量会清掉, 需要你重新设置. 组数、次数和休息保持不变.")
        } else {
            lines.append("This will replace \(proposal.lines.count) exercises in \(routineCount) routines. Nothing is saved yet. Reply to make the change, or say to leave it.")
            if proposal.expandedBeyondFocus {
                lines.append("This goes beyond the routine in front of you and updates every saved routine in scope.")
            }
            lines.append("The old weight is not carried over — it isn’t an equivalent load. Sets, reps, and rest stay. Set the new weight before you train.")
        }
        var lastPlan: String?
        for line in proposal.lines {
            if line.planName != lastPlan {
                lines.append(line.planName)
                lastPlan = line.planName
            }
            lines.append("• \(line.fromName) → \(line.toName)")
        }
        if !proposal.unreplaced.isEmpty {
            lines.append(zh ? "以下没有合适替代, 会保持不动:" : "Left unchanged — no suitable replacement:")
            for item in proposal.unreplaced {
                lines.append("• \(item.planName): \(item.name)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func clarifyText(_ why: Clarify, zh: Bool) -> String {
        switch why {
        case .missingMuscle:
            return zh
                ? "要换成哪种器械之前, 先告诉我练的是哪个部位 (例如胸). 我不会按整个动作库来猜."
                : "Tell me which muscle (for example chest) before I swap equipment. I won’t guess across the whole library."
        case .missingSourceEquipment:
            return zh
                ? "要换掉的是哪种器械 (例如杠铃)? 我只按目录里的器械分类匹配, 不靠动作名字猜."
                : "Which equipment should I replace (for example barbell)? I match the catalog’s equipment, not words in the exercise name."
        case .missingTargetEquipment:
            return zh
                ? "要换成哪一类器械? 例如 machine (固定器械 / 选择式), 绳索, 或史密斯."
                : "Which equipment should I use instead? For example machine, cable, or Smith."
        case .ambiguousTarget(.genericGear):
            return zh
                ? "「器械」可能指固定器械、绳索或史密斯. 请说明是 machine、绳索, 还是史密斯. 我不会把它们当成同一种."
                : "“Machine” in that sentence is ambiguous — it could mean selectorized machines, cables, or a Smith machine. Say which one. I won’t treat them as the same."
        case .ambiguousTarget(.plateLoaded):
            return zh
                ? "动作库没有单独的「片载」分类. 固定/选择式器械归在 machine, 史密斯和绳索是另外两类. 如果要的是 machine, 请明确说 machine."
                : "The catalog has no separate plate-loaded category. Selectorized and leverage machines are “machine”; Smith and cable are their own types. Say machine if that’s what you want."
        case .ambiguousTarget(.mixed):
            return zh
                ? "这句话里有不止一种目标器械. 请只指定一种 (machine、绳索或史密斯)."
                : "That asks for more than one kind of equipment. Pick one: machine, cable, or Smith."
        case .ambiguousScope:
            return zh
                ? "这会改到不止一个训练计划. 要改全部已存计划请说「所有计划」, 或先打开要改的那一个. 我不会悄悄扩到整个计划库."
                : "That would change more than one routine. Say “all plans”, or open the one you mean. I won’t silently expand this to every routine."
        case .mixedMuscles:
            return zh
                ? "这句话同时点到了不同部位或不同器械的动作. 请收成一个部位、一种器械."
                : "That points at more than one muscle or equipment. Narrow it to one muscle and one equipment type."
        }
    }

    private static func reasonText(_ reason: Unreplaced.Reason, zh: Bool) -> String {
        switch reason {
        case .noCandidate:
            return zh ? "没有同等动作模式的 machine" : "no machine with the same movement"
        case .equipmentUnavailable:
            return zh ? "你的可用器械里没有这类 machine" : "that machine isn’t in your available equipment"
        }
    }

    // MARK: - Matching

    struct CatalogIndex {
        var exact: [String: Exercise] = [:]
        var folderAlias: [String: Exercise] = [:]
        var collapsedIds: Set<String> = []

        init(library: [Exercise]) {
            for ex in library {
                if exact[ex.id] == nil { exact[ex.id] = ex }
                for old in ex.mergedFrom ?? [] { collapsedIds.insert(old) }
            }
            for ex in library {
                if let folder = ex.imageFolder, exact[folder] == nil, folderAlias[folder] == nil {
                    folderAlias[folder] = ex
                }
            }
        }

        /// 只用这条 id 自己的元数据.
        /// mergedFrom 里的旧 id (例如把哑铃卧推并进杠铃卧推) 不能继承存活者的器械, 否则哑铃会被当成杠铃.
        func resolve(_ id: String) -> Exercise? {
            if let ex = exact[id] { return ex }
            if collapsedIds.contains(id) { return nil }
            return folderAlias[id]
        }
    }

    static func primaryCategory(_ ex: Exercise) -> EquipmentCategory? {
        let raw = (ex.equipmentAll?.first ?? ex.equipment ?? "").lowercased()
        guard !raw.isEmpty else { return nil }
        return EquipmentCategory.category(for: raw)
    }

    static func matchesMuscle(_ ex: Exercise, target: MuscleGroup) -> Bool {
        guard let first = ex.primaryMuscles.first else { return false }
        if let section = target.section, target != section {
            return first == target
        }
        let section = target.section ?? target
        return (first.section ?? first) == section
    }

    private static func angleKey(_ ex: Exercise) -> String {
        guard let m = ex.primaryMuscles.first else { return "none" }
        switch m {
        case .upperChest: return "upper"
        case .lowerChest: return "lower"
        case .midChest, .chest: return "mid"
        default: return (m.section ?? m).rawValue
        }
    }

    private enum SubstitutePick {
        case found(Exercise)
        case unavailable
        case none
    }

    private static func bestSubstitute(
        for source: Exercise, target: EquipmentCategory,
        candidates: [Exercise], available: Set<String>
    ) -> SubstitutePick {
        let structural = candidates.filter { structuralMatch(source, $0, target: target) }
        // The current library includes niche rows in userLibrary. Prefer a visible
        // substitute when one exists; use a niche row only when it is the only match.
        let visible = structural.filter { !$0.isNiche }
        let pool = visible.isEmpty ? structural : visible
        let usable = pool.filter { EquipmentCategory.allows($0, selected: available) }
        if let best = usable.min(by: isBetterSubstitute) { return .found(best) }
        if !structural.isEmpty { return .unavailable }
        return .none
    }

    /// 保持角度 (上/中/下)、推或飞鸟、单双侧、静力. 目标器械必须正好是该类, 不含史密斯/绳索/哑铃.
    private static func structuralMatch(_ source: Exercise, _ cand: Exercise, target: EquipmentCategory) -> Bool {
        guard cand.id != source.id else { return false }
        // niche 不在这里挡: 调用方传入的 candidates 已是用户能选到的库 (未采纳的 niche 不在里面).
        guard primaryCategory(cand) == target else { return false }
        guard angleKey(source) == angleKey(cand) else { return false }
        if let pattern = source.movementPattern {
            guard cand.movementPattern == pattern else { return false }
        } else if cand.movementPattern != nil {
            return false
        }
        if let mechanic = source.mechanic {
            guard cand.mechanic == mechanic else { return false }
        }
        guard (source.unilateral ?? false) == (cand.unilateral ?? false) else { return false }
        if let facet = source.movementFacet {
            guard cand.movementFacet == facet else { return false }
        }
        let sourceIso = source.tempo == .isometric || source.force == .static
        let candIso = cand.tempo == .isometric || cand.force == .static
        guard sourceIso == candIso else { return false }
        return true
    }

    private static func isBetterSubstitute(_ a: Exercise, _ b: Exercise) -> Bool {
        let aPlain = a.nameParts?.variation == nil
        let bPlain = b.nameParts?.variation == nil
        if aPlain != bPlain { return aPlain }
        let aCustom = a.id.hasPrefix("custom-")
        let bCustom = b.id.hasPrefix("custom-")
        if aCustom != bCustom { return !aCustom }
        if a.name.count != b.name.count { return a.name.count < b.name.count }
        return a.id < b.id
    }

    static func exerciseTitle(_ ex: Exercise, languageCode: String) -> String {
        if let map = ex.localizedName {
            if let hit = map[languageCode], !hit.isEmpty { return hit }
            if languageCode.hasPrefix("zh"), let hit = map["zh-Hans"], !hit.isEmpty { return hit }
            if let hit = map["en"], !hit.isEmpty { return hit }
        }
        return ex.name
    }

    static func nameKeys(_ ex: Exercise) -> Set<String> {
        var keys: Set<String> = [normalizeName(ex.name)]
        ex.localizedName?.values.forEach { keys.insert(normalizeName($0)) }
        ex.aliases?.forEach { keys.insert(normalizeName($0)) }
        keys.remove("")
        return keys
    }

    // MARK: - Language

    private enum EquipRead {
        case missing
        case category(EquipmentCategory)
        case ambiguous(AmbiguousTarget)
    }

    private enum MuscleRead {
        case missing, mixed, one(MuscleGroup)
    }

    private enum ScopeRead {
        case ambiguous
        case plans(ids: [String], expanded: Bool)
    }

    private struct Phrase {
        let text: String
        let latin: Bool
    }

    private static func targetEquipment(in side: String) -> EquipRead {
        readEquipment(side, role: .target)
    }

    private static func sourceEquipment(in side: String) -> EquipRead {
        readEquipment(side, role: .source)
    }

    private enum EquipRole { case source, target }

    private static func readEquipment(_ side: String, role: EquipRole) -> EquipRead {
        let found = equipmentHits(in: side)
        if found.contains(.plateLoaded) && role == .target { return .ambiguous(.plateLoaded) }
        var cats: [EquipmentCategory] = []
        var bare = false
        for hit in found {
            switch hit {
            case .category(let c):
                if !cats.contains(c) { cats.append(c) }
            case .bare: bare = true
            case .plateLoaded: break
            }
        }
        if cats.count > 1 { return .ambiguous(.mixed) }
        if let only = cats.first { return .category(only) }
        if bare { return .ambiguous(.genericGear) }
        return .missing
    }

    private enum EquipHit: Equatable { case category(EquipmentCategory), bare, plateLoaded }

    private static func equipmentHits(in text: String) -> [EquipHit] {
        let table: [(String, EquipHit)] = [
            ("smith machine", .category(.smith)),
            ("史密斯机", .category(.smith)),
            ("史密斯", .category(.smith)),
            ("smith", .category(.smith)),
            ("cable machine", .category(.cable)),
            ("cables", .category(.cable)),
            ("cable", .category(.cable)),
            ("绳索", .category(.cable)),
            ("龙门架", .category(.cable)),
            ("龙门", .category(.cable)),
            ("拉索", .category(.cable)),
            ("resistance bands", .category(.bands)),
            ("resistance band", .category(.bands)),
            ("弹力带", .category(.bands)),
            ("bands", .category(.bands)),
            ("band", .category(.bands)),
            ("dumbbells", .category(.dumbbell)),
            ("dumbbell", .category(.dumbbell)),
            ("哑铃", .category(.dumbbell)),
            ("kettlebells", .category(.kettlebell)),
            ("kettlebell", .category(.kettlebell)),
            ("壶铃", .category(.kettlebell)),
            ("plate-loaded", .plateLoaded),
            ("plate loaded", .plateLoaded),
            ("片载", .plateLoaded),
            ("挂片", .plateLoaded),
            ("selectorized", .category(.machine)),
            ("pin-loaded", .category(.machine)),
            ("pin loaded", .category(.machine)),
            ("选择式", .category(.machine)),
            ("插片", .category(.machine)),
            ("resistance machines", .category(.machine)),
            ("resistance machine", .category(.machine)),
            ("machines", .category(.machine)),
            ("machine", .category(.machine)),
            ("固定器械", .category(.machine)),
            ("器械机", .category(.machine)),
            ("力量器械", .category(.machine)),
            ("barbells", .category(.barbell)),
            ("barbell", .category(.barbell)),
            ("杠铃", .category(.barbell)),
            ("器械", .bare),
        ]
        return scan(text, phrases: table.map { ($0.0, $0.1) })
    }

    private static func muscleTarget(in text: String) -> MuscleRead {
        let table: [(String, MuscleGroup)] = [
            ("upper chest", .upperChest),
            ("lower chest", .lowerChest),
            ("middle chest", .midChest),
            ("mid chest", .midChest),
            ("上胸", .upperChest),
            ("下胸", .lowerChest),
            ("中胸", .midChest),
            ("胸大肌", .chest),
            ("胸肌", .chest),
            ("胸部", .chest),
            ("练胸", .chest),
            ("pecs", .chest),
            ("pec", .chest),
            ("chest", .chest),
            ("胸", .chest),
            ("shoulders", .shoulders),
            ("shoulder", .shoulders),
            ("肩膀", .shoulders),
            ("肩", .shoulders),
            ("back", .back),
            ("背部", .back),
            ("背", .back),
            ("legs", .legs),
            ("leg", .legs),
            ("腿", .legs),
            ("arms", .arms),
            ("手臂", .arms),
            ("core", .core),
            ("核心", .core),
        ]
        let hits = scan(text, phrases: table.map { ($0.0, $0.1) })
        var unique: [MuscleGroup] = []
        for h in hits where !unique.contains(h) { unique.append(h) }
        if unique.isEmpty { return .missing }
        if unique.count > 1 { return .mixed }
        return .one(unique[0])
    }

    private static func resolveScope(text: String, context: Context) -> ScopeRead {
        let allIds = context.plans.map(\.id)
        let explicitAll = containsPhrase(text, anyOf: [
            "all my routines", "all routines", "all plans", "all saved", "all workouts",
            "every routine", "every plan", "every workout",
            "所有计划", "全部计划", "所有训练计划", "全部训练计划", "我的所有计划",
        ])
        let mentionsAll = explicitAll || containsPhrase(text, anyOf: [
            "all", "every", "each", "所有", "全部", "都",
        ])
        let mentionsThis = containsPhrase(text, anyOf: [
            "this routine", "this plan", "this workout", "当前计划", "这个计划", "这份计划", "只改这个",
        ])
        let focused = context.focusedPlanId.flatMap { id in allIds.contains(id) ? id : nil }
        let conversation = unique(context.conversationPlanIds.filter { allIds.contains($0) })

        if explicitAll {
            let narrower = focused.map { [$0] } ?? (conversation.isEmpty ? nil : conversation)
            let expanded = narrower.map { Set($0) != Set(allIds) } ?? false
            return .plans(ids: allIds, expanded: expanded)
        }
        // 已经打开某个计划时, 「所有/都」只覆盖这个计划里的命中项.
        // 扩到其它计划必须显式说「所有计划」(上面的分支).
        if mentionsThis && focused == nil && !conversation.isEmpty {
            return .plans(ids: conversation, expanded: false)
        }
        if mentionsThis && focused == nil && conversation.isEmpty && allIds.count > 1 {
            return .ambiguous
        }
        if let focused {
            return .plans(ids: [focused], expanded: false)
        }
        if !conversation.isEmpty {
            return .plans(ids: conversation, expanded: false)
        }
        if allIds.isEmpty { return .plans(ids: [], expanded: false) }
        if mentionsAll || allIds.count == 1 {
            return .plans(ids: allIds, expanded: false)
        }
        return .ambiguous
    }

    private static func splitSwap(_ text: String) -> (left: String, right: String)? {
        let zhVerbs = ["替换成", "替换为", "换成", "换为", "换到", "改成", "换掉", "替换"]
        for verb in zhVerbs.sorted(by: { $0.count > $1.count }) {
            if let range = text.range(of: verb) {
                return (String(text[..<range.lowerBound]), String(text[range.upperBound...]))
            }
        }
        let pattern = "(replace|swap|switch|change)\\b(.{0,80}?)\\b(with|for|to|into)\\b"
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        guard let match = re.firstMatch(in: text, options: [], range: full), match.numberOfRanges >= 4 else {
            return nil
        }
        let before = ns.substring(with: NSRange(location: 0, length: match.range.location))
        let middle = ns.substring(with: match.range(at: 2))
        let afterLoc = match.range.location + match.range.length
        let after = ns.substring(with: NSRange(location: afterLoc, length: ns.length - afterLoc))
        return (before + " " + middle, after)
    }

    private static func scan<T>(_ text: String, phrases: [(String, T)]) -> [T] {
        var occs: [(range: Range<String.Index>, value: T, length: Int)] = []
        for (phrase, value) in phrases {
            var search = text.startIndex
            while search < text.endIndex, let range = text.range(of: phrase, range: search..<text.endIndex) {
                if isBounded(text, phrase: phrase, range: range) {
                    occs.append((range, value, phrase.count))
                }
                search = range.upperBound
            }
        }
        occs.sort { a, b in
            if a.length != b.length { return a.length > b.length }
            return a.range.lowerBound < b.range.lowerBound
        }
        var taken: [Range<String.Index>] = []
        var out: [T] = []
        for occ in occs {
            if taken.contains(where: { $0.overlaps(occ.range) }) { continue }
            taken.append(occ.range)
            out.append(occ.value)
        }
        return out
    }

    private static func isBounded(_ text: String, phrase: String, range: Range<String.Index>) -> Bool {
        let latin = phrase.unicodeScalars.contains { $0.isASCII && CharacterSet.alphanumerics.contains($0) }
        guard latin else { return true }
        if range.lowerBound > text.startIndex {
            let prev = text[text.index(before: range.lowerBound)]
            if prev.isLetter || prev.isNumber { return false }
        }
        if range.upperBound < text.endIndex {
            let next = text[range.upperBound]
            if next.isLetter || next.isNumber { return false }
        }
        return true
    }

    private static func containsPhrase(_ text: String, anyOf phrases: [String]) -> Bool {
        !scan(text, phrases: phrases.map { ($0, true) }).isEmpty
    }

    private static func normalize(_ raw: String) -> String {
        var s = raw.lowercased()
        let punct = CharacterSet(charactersIn: "，。！？、；：,.!?;:()（）【】[]\"'“”‘’")
        s = s.unicodeScalars.map { punct.contains($0) ? " " : String($0) }.joined()
        return s
    }

    private static func normalizeName(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private static func unique(_ ids: [String]) -> [String] {
        var seen = Set<String>()
        return ids.filter { seen.insert($0).inserted }
    }

    private static func proposalId(_ lines: [Line]) -> String {
        let raw = lines.map { "\($0.planId)|\($0.stepId)|\($0.fromExerciseId)|\($0.toExerciseId)" }
            .sorted().joined(separator: "\n")
        var hash: UInt64 = 14695981039346656037
        for byte in raw.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        return "swap-\(hash)"
    }
}
