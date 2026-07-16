import Foundation

// 共享 "肌肉状态" 计算 — 累计 volume + 时间衰减模型.
//
// 2026-05-24 改: 之前只看"上次训练时间", 用户反馈 "练 1 组" 和 "练 5 组" 在状态卡上长得一样,
// 这是不科学的. 现在改成累计 volume + 指数衰减:
//   1. 每条 SetRecord 贡献 stress — primary 肌肉 1.0 / synergist 0.4
//   2. stress 随时间指数衰减, 半衰期 24h
//        - 24h → 50%, 48h → 25%, 72h → 12.5%, 5天外 ~6% 直接忽略
//   3. 总 stress → fatigue (0..1) 通过饱和指数:
//        fatigue = 1 - exp(-stress / 2)
//
// 例子:
//   - 今天 1 组腿 (primary): stress 1.0 → fatigue 0.39 (Recovering 起步)
//   - 24h 后:                 stress 0.5 → fatigue 0.22 (Mostly recovered)
//   - 今天 5 组腿:             stress 5.0 → fatigue 0.92 (Fatigued)
//   - 24h 后:                 stress 2.5 → fatigue 0.71 (Fatigued)
//
// 用法 (典型 SwiftUI):
//   let fatigueMap = MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById)
//   BodyHint(
//       muscles: [],
//       heatStyleFor: { m in MasoColor.recoveryHeatStyle(muscle: m, fatigueMap: fatigueMap) }
//   )
//
// 阈值 (跟 MuscleStatusOverviewCard legend 对齐):
//   ≥ 0.65 → 1.0 (Fatigued)
//   ≥ 0.35 → 0.6 (Recovering)
//   ≥ 0.12 → 0.3 (Mostly recovered)
//   < 0.12 → nil (Fresh, 走默认灰底)
enum MuscleStatusCompute {

    // MARK: - 模型常数

    /// 24h 半衰期 — 训练 24h 后 stress 衰减一半
    private static let halfLifeSeconds: Double = 24 * 3600

    /// fatigue 饱和参数 — 控制几组算"完全疲劳".
    /// 2.0 → 5 set primary 后 fatigue ≈ 0.92 (基本到顶)
    private static let saturation: Double = 2.0

    /// primary 肌肉每组 stress
    private static let primaryStressPerSet: Double = 1.0
    /// 协同肌肉每组 stress (~40% of primary)
    private static let synergistStressPerSet: Double = 0.4

    /// 5 天以外的 set 直接跳过 (decay 已到 ~6%, 算了也是噪音)
    private static let maxAgeSeconds: Double = 5 * 86400

    // MARK: - 主计算

    /// 每个 anatomy 肌肉 → 当前 fatigue 值 (0..1, 1=完全疲劳, 0=完全恢复).
    /// 用 expandAnatomyMuscles 展开 — 训练动作的 .chest 自动点亮所有 sub-chest.
    static func muscleFatigueMap(
        sets: [SetRecord],
        exById: [String: Exercise]
    ) -> [MuscleGroup: Double] {
        let now = Date()
        let lambda = log(2.0) / halfLifeSeconds

        var stressByMuscle: [MuscleGroup: Double] = [:]
        for s in sets {
            guard let ex = exById[s.exerciseId] else { continue }
            let elapsed = now.timeIntervalSince(s.performedAt)
            guard elapsed > 0, elapsed < maxAgeSeconds else { continue }
            let decay = exp(-lambda * elapsed)

            // 区分 primary / synergist — primary 肌肉吃 full stress, synergist 吃 40%
            let primarySet = Set(ex.primaryMuscles)
            let allSet = Set(ex.muscleGroups)
            let synergistSet = allSet.subtracting(primarySet)

            for m in primarySet {
                let expanded = expandAnatomyMuscles([m])
                for em in expanded {
                    stressByMuscle[em, default: 0] += primaryStressPerSet * decay
                }
            }
            for m in synergistSet {
                let expanded = expandAnatomyMuscles([m])
                for em in expanded {
                    stressByMuscle[em, default: 0] += synergistStressPerSet * decay
                }
            }
        }

        // stress → fatigue (saturating exponential, 0..1)
        var result: [MuscleGroup: Double] = [:]
        for (m, stress) in stressByMuscle {
            result[m] = 1.0 - exp(-stress / saturation)
        }
        return result
    }

    /// 恢复四档 — 阈值跟 opacity 映射一致, 输出语义档位而非透明度.
    /// 颜色/透明度由视图层决定 (MasoColor.recoveryHeatStyle):
    /// 绿=练过点亮 (越累越亮), 灰=没点亮=该去练 (owner 二轮拍板, 反转试过后撤回).
    enum RecoveryTier {
        case fresh              // < 0.12 (或无记录) — 可以练
        case mostlyRecovered    // 0.12 ..< 0.35     — 快恢复了
        case recovering         // 0.35 ..< 0.65     — 恢复中
        case fatigued           // ≥ 0.65            — 疲劳
    }

    static func tierFor(muscle m: MuscleGroup, fatigueMap: [MuscleGroup: Double]) -> RecoveryTier {
        guard let fatigue = fatigueMap[m], fatigue >= 0.12 else { return .fresh }
        if fatigue >= 0.65 { return .fatigued }
        if fatigue >= 0.35 { return .recovering }
        return .mostlyRecovered
    }

    // MARK: - 时间维度 (给 "Train the gaps" 等"老久没练"判断用)

    /// 每个 anatomy 肌肉 → 最近一次被训练的时间. 跟 fatigue map 解耦 —
    /// fatigue 看"练了多少 + 多久衰减", 这个看"上次什么时候碰过".
    /// "Train the gaps" 按钮判断"3 天没碰" 用这个, 不用 fatigue.
    static func muscleLastTrainedMap(
        sets: [SetRecord],
        exById: [String: Exercise]
    ) -> [MuscleGroup: Date] {
        var map: [MuscleGroup: Date] = [:]
        for s in sets {
            guard let ex = exById[s.exerciseId] else { continue }
            let expanded = expandAnatomyMuscles(ex.muscleGroups)
            for m in expanded {
                if let prev = map[m], prev > s.performedAt { continue }
                map[m] = s.performedAt
            }
        }
        return map
    }
}
