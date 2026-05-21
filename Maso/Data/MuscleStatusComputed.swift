import Foundation

// 共享 "肌肉状态" 计算 — 把 HistoryScreen 顶部 Muscle Status 卡片用的两个核心函数
// (`muscleLastTrainedMap` + `opacityFor`) 提到一个公共文件, 让其他 view 也能用同款衰减.
//
// 用法 (典型 SwiftUI):
//   let lastMap = MuscleStatusCompute.muscleLastTrainedMap(sets: data.sets, exById: data.exById)
//   BodyHint(
//       muscles: [],
//       opacityFor: { m in MuscleStatusCompute.opacityFor(muscle: m, lastMap: lastMap) }
//   )
//
// 之前两份逻辑分别在 HistoryScreen 顶部 + SessionDetailSheet 里复制一份, 这次又要给
// QuickMuscleStep "显示肌肉状态" 开关用 — 第 3 处. 集中到这里避免代码漂移.
//
// 衰减档位 (跟 HistoryScreen legend 对齐):
//   - 0..1 d → 1.0 (Fatigued, 满色)
//   - 1..2 d → 0.6 (Recovering, 中色)
//   - 2..3 d → 0.3 (Almost fresh, 浅色)
//   - ≥ 3 d → nil  (Ready to train, 默认灰底)
enum MuscleStatusCompute {
    /// 每个 anatomy 肌肉 → 最近一次被训练的时间.
    /// 用于 BodyHint opacityFor — 跟 web 端 muscleLastTrained 同义.
    ///
    /// 用 expandAnatomyMuscles 展开 — 训练动作的 .chest 自动点亮
    /// .upperChest / .midChest / .lowerChest 三个 sub 的 lastTrained 时间.
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

    /// 衰减映射 — 间距加大让三档对比明显:
    /// 0..1 d → 1.0 (满色); 1..2 d → 0.6; 2..3 d → 0.3; ≥ 3 d → nil (默认灰).
    /// 之前 1.0/0.7/0.4 三档视觉差异不够明显 (人眼对低 alpha 差异不敏感),
    /// 现在 0.4 + 0.3 + 0.3 间隔, 整体更分明.
    static func opacityFor(muscle m: MuscleGroup, lastMap: [MuscleGroup: Date]) -> Double? {
        guard let last = lastMap[m] else { return nil }
        let days = Date().timeIntervalSince(last) / 86400
        if days < 1 { return 1.0 }
        if days < 2 { return 0.6 }
        if days < 3 { return 0.3 }
        return nil
    }
}
