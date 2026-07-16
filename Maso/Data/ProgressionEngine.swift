import Foundation

// 渐进超负荷建议引擎 — "下次该做多重" (double progression, 全本地, 透明规则).
//
// 为什么是它: 调研里唯一被真实用户反复验证"有用"的 AI/智能功能就是基于历史的
// 下次重量建议 (Dr. Muscle / Alpha Progression / Gymverse 靠它立住; Fitbod 的
// 每日黑盒重排反而被弃). Masso 的 e1RM/PR 数据管道现成, 规则透明可解释 —
// 不用 LLM, 零成本零延迟离线可用.
//
// 规则 (业界标准 double progression):
//   1. 取该动作最近一个训练日的工作组 (同重量的众数组; 排除 30 分钟内 = 本场).
//   2. 全部工作组都打满目标次数 → 建议加一档:
//        杠铃/固定器械 +2.5kg; 哑铃 +2.0kg; 下肢大复合 (深蹲/硬拉/腿举类) +5kg.
//   3. 最近两个训练日都在同重量上大幅掉次 (≥一半的组少 ≥2 次) → 建议 -10% deload.
//   4. 其余 (刚加过重/差一两次打满) → 不出声 (nil). 建议只在"挣到了"或"该退"时出现,
//      保持沉默的进步反馈, 不天天指手画脚.
//
// 呈现: 播放器动作信息区 "Last: 55 kg × 8" 下面一颗可点 chip "Try 57.5 kg (+2.5)",
// 点一下直接把当前动作的工作重量改过去 (走 updateCurrentStep, 跟手动编辑同一条路).
enum ProgressionEngine {

    struct Suggestion {
        /// 建议的下次工作重量 (kg, 已按 0.5 取整)
        let weightKg: Double
        /// 相对上次工作重量的增减 (kg, 负数 = deload)
        let deltaKg: Double
    }

    /// 30 分钟内的记录算"本场", 不算历史.
    private static let currentSessionWindow: TimeInterval = 1800

    static func suggestion(
        exerciseId: String,
        targetReps: Int?,
        sets: [SetRecord],
        exercise: Exercise?
    ) -> Suggestion? {
        let now = Date()
        // 该动作的带重量历史 (排除本场)
        let history = sets.filter {
            $0.exerciseId == exerciseId
                && ($0.weight ?? 0) > 0
                && $0.reps != nil
                && now.timeIntervalSince($0.performedAt) > currentSessionWindow
        }
        guard !history.isEmpty else { return nil }

        // 按训练日分组, 取最近两个训练日
        let cal = Calendar.current
        let byDay = Dictionary(grouping: history) { cal.startOfDay(for: $0.performedAt) }
        let sortedDays = byDay.keys.sorted(by: >)
        guard let lastDay = sortedDays.first, let lastRecords = byDay[lastDay] else { return nil }

        // 工作重量 = 该日出现次数最多的重量 (平手取更重的 — 热身组更轻且通常只有一组)
        guard let workingWeight = modeWeight(of: lastRecords) else { return nil }
        let workingSets = lastRecords.filter { abs(($0.weight ?? 0) - workingWeight) < 0.01 }
        guard !workingSets.isEmpty else { return nil }

        // 目标次数: plan 给的 targetReps 优先, 否则用该日工作组的众数次数
        let target = targetReps ?? modeReps(of: workingSets) ?? 8

        // 规则 2: 全部工作组打满 → 加重
        let allHit = workingSets.allSatisfy { ($0.reps ?? 0) >= target }
        if allHit {
            let inc = increment(for: exercise)
            let suggested = roundToHalf(workingWeight + inc)
            return Suggestion(weightKg: suggested, deltaKg: suggested - workingWeight)
        }

        // 规则 3: 最近两个训练日都在同重量大幅掉次 → deload 10%
        let badLast = isBadSession(workingSets, target: target)
        if badLast, sortedDays.count >= 2,
           let prevRecords = byDay[sortedDays[1]] {
            let prevWorking = prevRecords.filter { abs(($0.weight ?? 0) - workingWeight) < 0.01 }
            if !prevWorking.isEmpty, isBadSession(prevWorking, target: target) {
                let suggested = max(roundToHalf(workingWeight * 0.9), 0.5)
                if suggested < workingWeight {
                    return Suggestion(weightKg: suggested, deltaKg: suggested - workingWeight)
                }
            }
        }

        // 规则 4: 差一点打满 / 单日失手 → 沉默
        return nil
    }

    // MARK: - 规则细节

    /// "大幅掉次" = ≥一半的工作组比目标少 2 次以上
    private static func isBadSession(_ workingSets: [SetRecord], target: Int) -> Bool {
        guard !workingSets.isEmpty else { return false }
        let badCount = workingSets.filter { ($0.reps ?? 0) <= target - 2 }.count
        return badCount * 2 >= workingSets.count
    }

    /// 加重档位 — 按器械 + 是否下肢大复合
    private static func increment(for exercise: Exercise?) -> Double {
        guard let ex = exercise else { return 2.5 }
        let eq = (ex.equipment ?? "").lowercased()
        if eq.contains("dumbbell") { return 2.0 }   // 哑铃一对 +2 (每只 +1)
        // 下肢大复合 (深蹲/硬拉/腿举类): 杠铃或器械 → 大步进
        let lowerBody: Set<MuscleGroup> = [.quads, .glutes, .hamstrings]
        let isLowerCompound = !Set(ex.primaryMuscles).isDisjoint(with: lowerBody)
        if isLowerCompound, eq.contains("barbell") || eq.contains("machine") || eq.contains("smith") {
            return 5.0
        }
        return 2.5                                   // 杠铃 / 器械 / 龙门架默认
    }

    /// 该日出现次数最多的重量 (平手取更重)
    private static func modeWeight(of records: [SetRecord]) -> Double? {
        let counts = Dictionary(grouping: records.compactMap(\.weight)) { $0 }
            .mapValues(\.count)
        return counts.max { a, b in
            a.value != b.value ? a.value < b.value : a.key < b.key
        }?.key
    }

    private static func modeReps(of records: [SetRecord]) -> Int? {
        let counts = Dictionary(grouping: records.compactMap(\.reps)) { $0 }
            .mapValues(\.count)
        return counts.max { $0.value < $1.value }?.key
    }

    private static func roundToHalf(_ v: Double) -> Double {
        (v * 2).rounded() / 2
    }
}
