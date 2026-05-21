import Foundation

// 把 Plan 展开成 player 用的 Segment 数组
// (= web 端 src/lib/planSegments.ts 的 expandPlan)
//
// 一个 step × N sets 展开为:
//   exerciseSeg (set 1) → restSeg → exerciseSeg (set 2) → restSeg → … → exerciseSeg (set N)
//
// 步与步之间:
//   - 若 step.rest > 0 → 用 step.rest (per-plan 覆盖)
//   - 否则用 defaultBetweenExerciseRest (来自 UserSettings, 默认 120s)
//   - 想取消可在 Settings 里把它设到 0 (Stepper 最小值)

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
                    targetReps: step.reps,
                    targetWeight: step.weight,
                    duration: step.duration,
                    countdown: isCountdown
                )
            ))
            let isLast = setN == totalSets
            if !isLast {
                let restSec = step.restBetweenSets > 0 ? step.restBetweenSets : defaultRest
                out.append(Segment(id: uid(), stepId: step.id, kind: .rest(duration: restSec)))
            }
        }
        // 步与步之间 — 跨动作过渡 rest
        // - step.rest > 0: 用 plan 自带的 (per-step 覆盖)
        // - 否则回退到 user 设置里的 defaultBetweenExerciseRest
        // - 用户把设置调到 0 即可禁用所有跨动作休息
        let notLastStep = stepIdx < plan.steps.count - 1
        if notLastStep {
            let crossRest = step.rest > 0 ? step.rest : defaultBetweenExerciseRest
            if crossRest > 0 {
                out.append(Segment(id: uid(), stepId: step.id, kind: .rest(duration: crossRest)))
            }
        }
    }
    return out
}
