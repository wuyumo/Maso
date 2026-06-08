import Foundation

// 把 Plan 展开成 player 用的 Segment 数组
// (= web 端 src/lib/planSegments.ts 的 expandPlan)
//
// 一个 step × N sets 展开为:
//   exerciseSeg (set 1) → restSeg → exerciseSeg (set 2) → restSeg → … → exerciseSeg (set N)
//
// 休息时长 (组间 + 跨动作) 一律用 UserSettings 里的 Training Preference, 不再读 plan/step 里存的值.
//   - 组间 = defaultRest (settings.defaultRestSeconds)
//   - 跨动作 = defaultBetweenExerciseRest (settings.defaultBetweenExerciseRestSeconds)
//   - 用户要求: 休息严格跟随训练偏好, 不写进任何 plan; plan 里的 restBetweenSets/rest 字段被忽略.
//   - 想取消跨动作休息把 Settings 里 Exercise rest 调到 0 即可.

struct Segment: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case exercise(Exercise, setNumber: Int, totalSets: Int, targetReps: Int?, targetWeight: Double?, duration: Int?, countdown: Bool)
        case rest(duration: Int)
    }
    let id: String
    let stepId: String
    let kind: Kind

    var isRest: Bool {
        if case .rest = kind { return true }
        return false
    }
    var isExercise: Bool { !isRest }
}

func expandPlan(
    _ plan: Plan,
    exById: [String: Exercise],
    defaultRest: Int = 90,
    defaultBetweenExerciseRest: Int = 120
) -> [Segment] {
    var out: [Segment] = []
    var counter = 0
    func uid() -> String { counter += 1; return "\(plan.id)-seg-\(counter)" }

    for (stepIdx, step) in plan.steps.enumerated() {
        guard let ex = exById[step.exerciseId] else { continue }
        let totalSets = max(1, step.sets)
        // 仅 cardio 用倒计时; flexibility (拉伸) 跟 strength 一样用打勾 button 完成组.
        // 之前 `!= .strength` 把拉伸也丢进倒计时, 改了之后拉伸保留 duration 字段 (作为
        // 建议时长展示) 但不再自动倒计时, 用户按完一组打勾即可.
        let isCountdown = ex.category == .cardio && step.duration != nil
        for setN in 1...totalSets {
            out.append(Segment(
                id: uid(),
                stepId: step.id,
                kind: .exercise(
                    ex,
                    setNumber: setN,
                    totalSets: totalSets,
                    targetReps: step.repsForSet(setN),
                    targetWeight: step.weightForSet(setN),
                    duration: step.duration,
                    countdown: isCountdown
                )
            ))
            let isLast = setN == totalSets
            if !isLast {
                // 组间休息 — 一律用设置里的 Set rest, 忽略 plan 里存的 restBetweenSets.
                out.append(Segment(id: uid(), stepId: step.id, kind: .rest(duration: defaultRest)))
            }
        }
        // 步与步之间 — 跨动作过渡 rest. 一律用设置里的 Exercise rest, 忽略 plan 里存的 step.rest.
        // 用户把设置调到 0 即可禁用所有跨动作休息.
        let notLastStep = stepIdx < plan.steps.count - 1
        if notLastStep, defaultBetweenExerciseRest > 0 {
            out.append(Segment(id: uid(), stepId: step.id, kind: .rest(duration: defaultBetweenExerciseRest)))
        }
    }
    return out
}
