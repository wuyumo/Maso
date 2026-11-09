import Foundation

// 直接编译进 CoachEquipmentSwap + ExerciseLibrary.load(data:), 读仓库里的 exercises.json.
// 不依赖模拟器. 失败打印 FAIL 并以非 0 退出.
//
// swiftc -O -o /tmp/coach-swap-test \
//   scripts/LanguageManagerStub.swift \
//   Maso/Models/MuscleGroup.swift Maso/Models/Exercise.swift Maso/Models/Plan.swift Maso/Models/Settings.swift \
//   Maso/Data/ExerciseLibrary.swift Maso/Data/CoachEquipmentSwap.swift \
//   scripts/CoachEquipmentSwapTests.swift
// /tmp/coach-swap-test

private var failures = 0

private func check(_ condition: Bool, _ message: String) {
    if !condition {
        failures += 1
        fputs("FAIL \(message)\n", stderr)
    }
}

private func loadLibrary() -> [Exercise] {
    let url = URL(fileURLWithPath: "Maso/Resources/exercises.json")
    let data = try! Data(contentsOf: url)
    let all = ExerciseLibrary.load(data: data)
    check(all.count > 700, "catalog decoded, count=\(all.count)")
    return all
}

private func userLibrary(_ all: [Exercise]) -> [Exercise] {
    all.filter { !$0.isNiche }
}

private func step(_ id: String, exercise: String, sets: Int = 3, reps: Int = 8,
                  weight: Double? = 80, rest: Int = 90, setWeights: [Double?]? = nil) -> PlanStep {
    PlanStep(id: id, exerciseId: exercise, sets: sets, reps: reps, weight: weight,
             setReps: nil, setWeights: setWeights, setDurations: nil,
             duration: nil, restBetweenSets: rest, rest: 15)
}

private func plan(_ id: String, _ name: String, _ steps: [PlanStep]) -> Plan {
    let t = Date(timeIntervalSince1970: 1_700_000_000)
    return Plan(id: id, name: name, steps: steps, createdAt: t, updatedAt: t)
}

private func context(plans: [Plan], library: [Exercise], focused: String? = nil,
                     conversation: [String] = [], only: String? = nil,
                     available: [String] = [], lang: String = "zh-Hans") -> CoachEquipmentSwap.Context {
    CoachEquipmentSwap.Context(
        plans: plans, library: library, candidates: userLibrary(library),
        availableEquipment: available, focusedPlanId: focused,
        conversationPlanIds: conversation, onlyModifyName: only, languageCode: lang)
}

private func ids(_ plan: Plan) -> [String] { plan.steps.map(\.exerciseId) }

private func preview(_ text: String, _ ctx: CoachEquipmentSwap.Context) -> CoachEquipmentSwap.Proposal? {
    if case .preview(let p) = CoachEquipmentSwap.interpret(text, context: ctx) { return p }
    return nil
}

private struct History {
    var sets: [SetRecord]
    var aiToday: Plan?
}

private func apply(_ proposal: CoachEquipmentSwap.Proposal, plans: [Plan], library: [Exercise],
                   history: History, persistOK: Bool,
                   persistCalls: inout Int) -> (plans: [Plan], history: History, result: CoachEquipmentSwap.CommitResult) {
    let allowed = Set(userLibrary(library).map(\.id))
    let out = CoachEquipmentSwap.applyTransaction(
        plans: plans, sets: history.sets, aiTodayPlan: history.aiToday,
        proposal: proposal, allowedExerciseIds: allowed
    ) { newPlans in
        persistCalls += 1
        _ = newPlans
        return persistOK
    }
    return (out.plans, History(sets: out.sets, aiToday: out.aiTodayPlan), out.result)
}

@main
enum CoachSwapTestRunner {
    static func main() { runTests() }
}

private func runTests() {
    let library = loadLibrary()
    let byId = Dictionary(uniqueKeysWithValues: library.map { ($0.id, $0) })
    check(byId["bench_press_barbell"] != nil, "bench_press_barbell in catalog")
    check(byId["bench_press_machine"] != nil, "bench_press_machine in catalog")
    check(CoachEquipmentSwap.primaryCategory(byId["bench_press_barbell"]!) == .barbell, "flat bench primary is barbell")
    check(CoachEquipmentSwap.primaryCategory(byId["bench_press_machine"]!) == .machine, "machine press primary is machine")
    check(CoachEquipmentSwap.primaryCategory(byId["incline_smith_close_grip"]!) == .smith, "smith is not machine")
    check(CoachEquipmentSwap.primaryCategory(byId["cable_fly_flat"]!) == .cable, "cable fly is cable")
    check(byId["bench_press_barbell"]!.mergedFrom?.contains("bench_press_dumbbell") == true,
          "dumbbell bench was merged away and must not inherit barbell metadata")

    // 卧推的中文名不含「杠铃/胸」, 只能靠元数据命中.
    check(byId["bench_press_barbell"]!.localizedName?["zh-Hans"] == "卧推", "zh name is 卧推")
    check(!(byId["bench_press_barbell"]!.localizedName?["zh-Hans"] ?? "").contains("杠铃"), "zh name has no 杠铃")

    let push = plan("push", "Push", [
        step("s1", exercise: "bench_press_barbell", sets: 4, reps: 6, weight: 100, rest: 120),
        step("s2", exercise: "bench_press_barbell", sets: 3, reps: 10, weight: 80, rest: 90),
        step("s3", exercise: "incline_bench_press_barbell", sets: 3, reps: 8, weight: 70, rest: 90),
        step("s4", exercise: "decline_bench_press_barbell", sets: 3, reps: 8, weight: 90, rest: 90),
        step("s5", exercise: "reverse_grip_bench_press", sets: 3, reps: 8, weight: 60, rest: 75),
        step("s6", exercise: "bench_press_neutral_grip_dumbbell", sets: 3, reps: 12, weight: 30, rest: 60),
        step("s7", exercise: "barbell_row", sets: 4, reps: 8, weight: 80, rest: 90),
        step("s8", exercise: "incline_smith_close_grip", sets: 3, reps: 8, weight: 50, rest: 75),
        step("s9", exercise: "cable_fly_flat", sets: 3, reps: 12, weight: 20, rest: 60),
        step("s10", exercise: "barbell_pullover", sets: 3, reps: 12, weight: 30, rest: 60),
        step("s11", exercise: "static_hold_bench_press", sets: 2, reps: 1, weight: 100, rest: 60),
        step("s12", exercise: "landmine_press", sets: 3, reps: 8, weight: 40, rest: 60),
        step("s13", exercise: "bench_press_dumbbell", sets: 3, reps: 10, weight: 28, rest: 60),
    ])
    let legs = plan("legs", "Legs", [
        step("l1", exercise: "squat_barbell", sets: 5, reps: 5, weight: 140, rest: 180),
        step("l2", exercise: "bench_press_barbell", sets: 3, reps: 5, weight: 110, rest: 150,
             setWeights: [100, 105, 110]),
    ])
    // squat id might differ. Check.
    let squatId = library.first { ex in
        CoachEquipmentSwap.primaryCategory(ex) == .barbell
            && ex.primaryMuscles.first?.section == .legs
            && ex.movementPattern == .squat
            && !ex.isNiche
    }?.id
    check(squatId != nil, "found a leg barbell squat")
    var legsPlan = legs
    if let squatId {
        legsPlan.steps[0] = step("l1", exercise: squatId, sets: 5, reps: 5, weight: 140, rest: 180)
    }

    let plans = [push, legsPlan]
    let phrase = "把所有练胸的杠铃器械都换成machine"
    let ctx = context(plans: plans, library: library)
    let outcome = CoachEquipmentSwap.interpret(phrase, context: ctx)
    guard case .preview(let proposal) = outcome else {
        check(false, "zh+machine phrase should preview, got \(outcome)")
        fputs("\(failures) failed\n", stderr)
        exit(1)
    }
    let rendered = CoachEquipmentSwap.text(for: .preview(proposal), languageCode: "zh-Hans")
    check(rendered.contains("卧推"), "preview names 卧推")
    check(rendered.contains("确认后才会写入"), "preview says it is not saved yet")
    check(rendered.contains("不会当作等效负荷") || rendered.contains("重量"), "preview warns weight is not equivalent")
    check(rendered.contains("曲臂上拉") || rendered.contains("Pullover"), "unreplaced pullover is listed")

    func line(_ stepId: String) -> CoachEquipmentSwap.Line? {
        proposal.lines.first { $0.stepId == stepId }
    }
    check(line("s1")?.toExerciseId == "bench_press_machine", "flat bench → machine press, not pec deck")
    check(line("s2")?.toExerciseId == "bench_press_machine", "duplicate flat bench also replaced")
    check(line("s1")?.fromExerciseId == "bench_press_barbell", "from id is the plan's id")
    check(line("s3")?.toExerciseId == "incline_bench_press_machine", "incline stays incline")
    check(line("s4")?.toExerciseId == "decline_bench_press_machine", "decline stays decline")
    check(line("s5")?.toExerciseId == "incline_bench_press_machine", "reverse-grip is upper chest, not flat machine")
    check(line("l2")?.toExerciseId == "bench_press_machine", "same exercise in a second routine")
    check(proposal.lines.contains { $0.stepId == "s6" } == false, "chest dumbbell not selected")
    check(proposal.lines.contains { $0.stepId == "s7" } == false, "barbell row not selected")
    check(proposal.lines.contains { $0.stepId == "s8" } == false, "smith chest not selected")
    check(proposal.lines.contains { $0.stepId == "s9" } == false, "cable fly not selected")
    check(proposal.lines.contains { $0.stepId == "l1" } == false, "leg barbell not selected")
    check(proposal.lines.contains { $0.stepId == "s13" } == false, "merged-away dumbbell id not treated as barbell")
    let unreplacedIds = Set(proposal.unreplaced.map(\.stepId))
    check(unreplacedIds.contains("s10"), "pullover reported, not forced into a press")
    check(unreplacedIds.contains("s11"), "isometric hold reported")
    check(unreplacedIds.contains("s12"), "unilateral landmine reported")
    check(proposal.lines.allSatisfy { byId[$0.toExerciseId] != nil }, "every replacement id exists")
    check(proposal.requiresConfirmation, "preview requires confirmation")

    // 英文同义
    let english = preview("Replace all chest barbell exercises with machines",
                          context(plans: plans, library: library, lang: "en"))
    check(english?.lines.map(\.stepId).sorted() == proposal.lines.map(\.stepId).sorted(),
          "english synonym hits the same steps")
    let pec = preview("Swap every pec barbell movement for a machine",
                      context(plans: plans, library: library, lang: "en"))
    check(pec?.lines.map(\.stepId).sorted() == proposal.lines.map(\.stepId).sorted(),
          "pec/for synonym hits the same steps")

    // 选择式 → machine 分类, 不落到史密斯
    let selector = preview("把所有练胸的杠铃都换成选择式器械", ctx)
    check(selector?.lines.first { $0.stepId == "s1" }?.toExerciseId == "bench_press_machine",
          "选择式 follows machine category")
    check(selector?.lines.allSatisfy { CoachEquipmentSwap.primaryCategory(byId[$0.toExerciseId]!) == .machine } == true,
          "no smith/cable substitute")

    // 不写盘的解释
    check(plans[0].steps.map(\.exerciseId) == push.steps.map(\.exerciseId), "interpret does not mutate plans")

    var calls = 0
    let history = History(sets: [
        SetRecord(id: "rec-1", exerciseId: "bench_press_barbell", exerciseName: "Bench Press",
                  category: .strength, weight: 100, reps: 6, duration: nil,
                  performedAt: Date(timeIntervalSince1970: 1_700_000_100), planId: "push", planName: "Push")
    ], aiToday: plan("today", "Today", [step("t1", exercise: "bench_press_barbell", weight: 100)]))

    // 取消 = 不调用 commit. 计划与历史不动.
    let cancelledPlans = plans
    check(cancelledPlans[0].steps[0].exerciseId == "bench_press_barbell", "cancel leaves plans")
    check(history.sets.count == 1 && history.sets[0].exerciseId == "bench_press_barbell", "cancel leaves history")

    // 持久化失败
    calls = 0
    let failed = apply(proposal, plans: plans, library: library, history: history, persistOK: false, persistCalls: &calls)
    check(calls == 1, "failed save still attempts once, calls=\(calls)")
    if case .failed(.persist) = failed.result {} else { check(false, "persist failure result \(failed.result)") }
    check(failed.plans[0].steps[0].exerciseId == "bench_press_barbell", "persist failure keeps original plans")
    check(failed.history.sets == history.sets, "persist failure keeps history")
    check(failed.history.aiToday?.steps.first?.exerciseId == "bench_press_barbell", "today plan untouched on failure")

    // 成功写入
    calls = 0
    let applied = apply(proposal, plans: plans, library: library, history: history, persistOK: true, persistCalls: &calls)
    guard case .applied(let written) = applied.result else {
        check(false, "apply should succeed")
        fputs("\(failures) failed\n", stderr)
        exit(1)
    }
    check(calls == 1, "one persist")
    check(applied.plans[0].id == "push" && applied.plans[1].id == "legs", "routine order kept")
    let pushAfter = applied.plans[0]
    check(pushAfter.steps.map(\.id) == push.steps.map(\.id), "step order and duplicates kept")
    check(pushAfter.steps[0].exerciseId == "bench_press_machine", "first flat replaced")
    check(pushAfter.steps[1].exerciseId == "bench_press_machine", "second flat replaced")
    check(pushAfter.steps[0].sets == 4 && pushAfter.steps[0].reps == 6 && pushAfter.steps[0].restBetweenSets == 120 && pushAfter.steps[0].rest == 15,
          "sets reps rest kept on first")
    check(pushAfter.steps[1].sets == 3 && pushAfter.steps[1].reps == 10, "second instance keeps its own reps")
    check(pushAfter.steps[0].weight == nil && pushAfter.steps[1].weight == nil, "barbell kg not copied onto machine")
    check(pushAfter.steps[2].exerciseId == "incline_bench_press_machine", "incline replaced in place")
    check(pushAfter.steps[3].exerciseId == "decline_bench_press_machine", "decline replaced in place")
    check(pushAfter.steps[5].exerciseId == "bench_press_neutral_grip_dumbbell" && pushAfter.steps[5].weight == 30,
          "dumbbell step untouched including weight")
    check(pushAfter.steps[6].exerciseId == "barbell_row" && pushAfter.steps[6].weight == 80, "row untouched")
    check(pushAfter.steps[7].exerciseId == "incline_smith_close_grip", "smith untouched")
    check(pushAfter.steps[8].exerciseId == "cable_fly_flat", "cable untouched")
    check(pushAfter.steps[9].exerciseId == "barbell_pullover" && pushAfter.steps[9].weight == 30, "pullover kept")
    check(pushAfter.steps[10].exerciseId == "static_hold_bench_press", "hold kept")
    check(pushAfter.steps[11].exerciseId == "landmine_press", "landmine kept")
    check(pushAfter.steps[12].exerciseId == "bench_press_dumbbell" && pushAfter.steps[12].weight == 28,
          "collapsed dumbbell id kept")
    let legsAfter = applied.plans[1]
    check(legsAfter.steps[0].exerciseId == squatId, "squat kept")
    check(legsAfter.steps[0].weight == 140, "squat weight kept")
    check(legsAfter.steps[1].exerciseId == "bench_press_machine", "legs-day bench replaced")
    check(legsAfter.steps[1].weight == nil && legsAfter.steps[1].setWeights == nil, "per-set barbell loads cleared")
    check(legsAfter.steps[1].sets == 3 && legsAfter.steps[1].reps == 5 && legsAfter.steps[1].restBetweenSets == 150,
          "legs-day bench keeps sets reps rest")
    check(applied.history.sets.count == 1 && applied.history.sets[0].exerciseId == "bench_press_barbell"
            && applied.history.sets[0].weight == 100, "history record unchanged")
    check(applied.history.aiToday?.id == "today" && applied.history.aiToday?.steps.first?.exerciseId == "bench_press_barbell",
          "ai today plan not edited")
    check(written.count == 2, "applied plans returned")

    // 重新打开: 用跟 PersistenceController 一样的 iso8601 编解码
    let enc = JSONEncoder(); enc.dateEncodingStrategy = .iso8601
    let dec = JSONDecoder(); dec.dateDecodingStrategy = .iso8601
    let blob = try! enc.encode(applied.plans)
    let reopened = try! dec.decode([Plan].self, from: blob)
    check(reopened[0].steps[0].exerciseId == "bench_press_machine", "reopen keeps machine press")
    check(reopened[0].steps[0].weight == nil, "reopen keeps cleared weight")
    check(reopened[0].steps[5].exerciseId == "bench_press_neutral_grip_dumbbell", "reopen keeps dumbbell")
    check(reopened[1].steps[1].setWeights == nil && reopened[1].steps[1].reps == 5, "reopen keeps reps, no set weights")

    // 再次执行同一提案: 幂等, 不再写盘
    calls = 0
    let again = apply(proposal, plans: applied.plans, library: library, history: applied.history, persistOK: true, persistCalls: &calls)
    check(calls == 0, "second apply does not persist, calls=\(calls)")
    if case .alreadyApplied = again.result {} else { check(false, "second apply \(again.result)") }
    check(again.plans[0].steps.map(\.exerciseId) == applied.plans[0].steps.map(\.exerciseId), "second apply no further edits")

    // 再问一遍: 可替换的杠铃卧推已经没了, 不能再生成同一批替换
    let secondAsk = CoachEquipmentSwap.interpret(phrase, context: context(plans: applied.plans, library: library))
    if case .preview(let againProposal) = secondAsk {
        check(againProposal.lines.isEmpty, "second utterance must not list already-replaced steps")
    } else if case .blocked = secondAsk {
        check(true, "only unreplaced leftovers remain")
    } else if case .noMatches = secondAsk {
        check(true, "nothing left")
    } else {
        check(false, "second utterance \(secondAsk)")
    }

    // 无匹配
    let onlyRow = [plan("back", "Back", [step("b1", exercise: "barbell_row", weight: 70)])]
    let none = CoachEquipmentSwap.interpret(phrase, context: context(plans: onlyRow, library: library))
    if case .noMatches = none {} else { check(false, "no chest barbell → noMatches \(none)") }
    check(CoachEquipmentSwap.text(for: none, languageCode: "zh-Hans").contains("没有改"), "no-match copy does not claim a swap")

    // 无替代: 只有上拉
    let onlyPullover = [plan("p", "Pullover day", [step("p1", exercise: "barbell_pullover", weight: 20)])]
    let blocked = CoachEquipmentSwap.interpret(phrase, context: context(plans: onlyPullover, library: library))
    if case .blocked(let items, _) = blocked {
        check(items.count == 1 && items[0].exerciseId == "barbell_pullover", "blocked reports pullover")
    } else { check(false, "pullover-only should block \(blocked)") }

    // 范围不明: 多个计划, 没说「所有」, 没打开某一个
    let vague = CoachEquipmentSwap.interpret("把练胸的杠铃换成machine", context: context(plans: plans, library: library))
    if case .clarify(.ambiguousScope) = vague {} else { check(false, "vague scope \(vague)") }
    check(CoachEquipmentSwap.text(for: vague, languageCode: "zh-Hans").contains("不会悄悄"), "vague copy refuses silent expansion")

    // 打开了 Push 时, 「所有」只改 Push
    let focused = preview(phrase, context(plans: plans, library: library, focused: "push"))
    check(focused?.scopePlanIds == ["push"], "focused routine scopes 所有 to that plan")
    check(focused?.lines.contains { $0.planId == "legs" } == false, "focused scope does not touch legs")
    check(focused?.expandedBeyondFocus == false, "not an expansion")

    // 明确「所有计划」且当前开着一份 → 扩大, 但仍然只是预览
    let expand = preview("把所有计划里练胸的杠铃都换成machine", context(plans: plans, library: library, focused: "push"))
    check(expand?.scopePlanIds.sorted() == ["legs", "push"], "explicit all plans expands")
    check(expand?.expandedBeyondFocus == true, "expansion is flagged")
    check(plans[1].steps[1].exerciseId == "bench_press_barbell", "flagged expansion still not written")

    // 对话范围: 只含 push 的已存副本
    let convo = preview(phrase, context(plans: plans, library: library, conversation: ["push"]))
    check(convo?.scopePlanIds == ["push"], "conversation scope stays inside that routine")

    // 片载 / 裸器械 要澄清, 不猜成全库
    let plate = CoachEquipmentSwap.interpret("把所有练胸的杠铃都换成片载器械", context: ctx)
    if case .clarify(.ambiguousTarget(.plateLoaded)) = plate {} else { check(false, "plate-loaded \(plate)") }
    let bare = CoachEquipmentSwap.interpret("把所有练胸的杠铃都换成器械", context: ctx)
    if case .clarify(.ambiguousTarget(.genericGear)) = bare {} else { check(false, "bare 器械 \(bare)") }

    // 不是替换请求 → 交给原来的教练生成
    let other = CoachEquipmentSwap.interpret("帮我排一个练胸的四周计划", context: ctx)
    if case .notHandled = other {} else { check(false, "unrelated coach text \(other)") }

    // 可用器械里没有 machine → 不改用哑铃顶上
    let unavailable = CoachEquipmentSwap.interpret(
        phrase, context: context(plans: plans, library: library, available: ["dumbbell", "barbell"]))
    if case .blocked(let items, _) = unavailable {
        check(items.contains { $0.stepId == "s1" && $0.reason == .equipmentUnavailable }, "flat bench unavailable, not swapped to dumbbell")
        check(!items.contains { $0.reason == .noCandidate && $0.stepId == "s1" }, "reason is availability")
    } else { check(false, "equipment gate \(unavailable)") }

    // 冲突: 确认前 step 被改成别的动作 → 整单失败, 调用方保留旧计划
    var raced = plans
    raced[0].steps[0] = step("s1", exercise: "bench_press_neutral_grip_dumbbell", weight: 30)
    calls = 0
    let conflict = apply(proposal, plans: raced, library: library, history: history, persistOK: true, persistCalls: &calls)
    if case .failed(.conflict) = conflict.result {} else { check(false, "conflict \(conflict.result)") }
    check(calls == 0, "conflict does not persist")
    check(conflict.plans[0].steps[0].exerciseId == "bench_press_neutral_grip_dumbbell", "conflict returns original plans")
    check(conflict.plans[0].steps[1].exerciseId == "bench_press_barbell", "conflict does not partially edit the duplicate")

    // 伪造的目标 id 不能写入
    calls = 0
    let banned = CoachEquipmentSwap.applyTransaction(
        plans: plans, sets: history.sets, aiTodayPlan: history.aiToday,
        proposal: proposal, allowedExerciseIds: [],
        persist: { _ in calls += 1; return true })
    if case .failed(.unknownExercise) = banned.result {} else { check(false, "unknown id \(banned.result)") }
    check(calls == 0 && banned.plans[0].steps[0].exerciseId == "bench_press_barbell", "forged target not written")

    // 撤销
    calls = 0
    let undone = CoachEquipmentSwap.undoTransaction(
        plans: applied.plans, sets: applied.history.sets, aiTodayPlan: applied.history.aiToday,
        previousPlans: plans, persist: { _ in calls += 1; return true })
    check(calls == 1 && undone.saved, "undo persists")
    check(undone.plans[0].steps[0].exerciseId == "bench_press_barbell", "undo restores barbell")
    check(undone.plans[0].steps[0].weight == 100, "undo restores weight")
    check(undone.sets[0].exerciseId == "bench_press_barbell", "undo leaves history")
    check(undone.aiTodayPlan?.steps.first?.exerciseId == "bench_press_barbell", "undo leaves today")
    calls = 0
    let undoFail = CoachEquipmentSwap.undoTransaction(
        plans: applied.plans, sets: applied.history.sets, aiTodayPlan: nil,
        previousPlans: plans, persist: { _ in calls += 1; return false })
    check(undoFail.saved == false && undoFail.plans[0].steps[0].exerciseId == "bench_press_machine",
          "failed undo keeps replaced plans")

    // 点名「卧推」且打开了 Push: 只换这个名字, 不连带上斜, 也不跨到 Legs.
    let named = preview("换成machine", context(plans: plans, library: library, focused: "push", only: "卧推"))
    let namedSteps = Set(named?.lines.map(\.stepId) ?? [])
    check(namedSteps == ["s1", "s2"], "onlyModify 卧推 stays on that name inside the open routine, got \(namedSteps)")
    // 没打开计划、又没说全部: 点名也不许扩到每个计划
    let namedVague = CoachEquipmentSwap.interpret(
        "换成machine", context: context(plans: plans, library: library, only: "卧推"))
    if case .clarify(.ambiguousScope) = namedVague {} else { check(false, "named without scope \(namedVague)") }

    if failures == 0 {
        fputs("OK \(library.count) exercises\n", stdout)
        exit(0)
    }
    fputs("\(failures) failed\n", stderr)
    exit(1)
}
