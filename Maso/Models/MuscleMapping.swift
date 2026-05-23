import Foundation
import MuscleMap

// MARK: - Maso.MuscleGroup ↔ MuscleMap.Muscle 桥接
//
// Maso 内部用 MuscleGroup (52 个 case, 含 sub-muscle) 表达"哪块肌肉".
// MuscleMap SDK 用它自己的 Muscle (35 个 case). 这文件是双向映射.
//
// 设计:
//   - 一个 MuscleGroup 映射到 1-N 个 MuscleMap.Muscle (e.g. .chest → [.chest, .upperChest, .lowerChest]
//     让"选胸"高亮三个 sub).
//   - MuscleMap.Muscle 反向映射回单个 MuscleGroup (用户点 sub-muscle 时 callback 还原).
//   - MuscleMap 没原生支持的 MuscleGroup (e.g. .lats / .rhomboids 单独 polygon) → 走 .upperBack
//     proxy. 跟之前 BodyHint 的 proxyAnatomy 类似但表更短.

extension MuscleGroup {
    /// 把一个 Maso MuscleGroup 展开成 MuscleMap.Muscle 列表 (用于 BodyView.highlight).
    /// 主肌群展开到所有 sub. Sub 直接返回自己 (单点高亮).
    var mmMuscles: [Muscle] {
        switch self {
        // 胸
        case .chest:           return [.chest, .upperChest, .lowerChest]
        case .upperChest:      return [.upperChest]
        case .midChest:        return [.chest]                                  // sternocostal head = main
        case .lowerChest:      return [.lowerChest]

        // 背
        case .back:            return [.upperBack, .lowerBack]
        case .lats:            return [.upperBack]                              // proxy
        case .upperLats:       return [.upperBack]
        case .lowerLats:       return [.upperBack]
        case .upperTraps:      return [.upperTrapezius]
        case .midTraps:        return [.trapezius]                              // proxy
        case .lowerTraps:      return [.lowerTrapezius]
        case .rhomboids:       return [.rhomboids]
        case .teres:           return [.upperBack]                              // proxy
        case .lowerBack:       return [.lowerBack]

        // 肩
        case .shoulders:       return [.deltoids, .frontDeltoid, .rearDeltoid]
        case .frontDelts:      return [.frontDeltoid]
        case .sideDelts:       return [.deltoids]                               // proxy: 中束没独立 polygon
        case .rearDelts:       return [.rearDeltoid]
        case .rotatorCuff:     return [.rotatorCuff]

        // 二头 (Maso 还细分长 / 短 / 肱肌; MuscleMap 只有 biceps + brachialis 没有)
        case .biceps:          return [.biceps]
        case .bicepsLong:      return [.biceps]
        case .bicepsShort:     return [.biceps]
        case .brachialis:      return [.biceps]                                 // proxy
        case .brachioradialis: return [.forearm]                                // proxy: 肱桡肌靠近前臂

        // 三头
        case .triceps:         return [.triceps]
        case .tricepsLong:     return [.triceps]
        case .tricepsLateral:  return [.triceps]
        case .tricepsMedial:   return [.triceps]

        // 前臂
        case .forearms:        return [.forearm]
        case .forearmFlexors:  return [.forearm]
        case .forearmExtensors: return [.forearm]

        // 手臂聚合 — 同时高亮二头 + 三头 + 前臂
        case .arms:            return [.biceps, .triceps, .forearm]

        // 核心
        case .core:            return [.abs, .upperAbs, .lowerAbs, .obliques]
        case .abs:             return [.abs, .upperAbs, .lowerAbs]
        case .upperAbs:        return [.upperAbs]
        case .lowerAbs:        return [.lowerAbs]
        case .obliques:        return [.obliques]
        case .serratus:        return [.serratus]
        case .neck:            return [.neck]

        // 腿 (聚合) — 高亮 quad + hamstring + glute + calf
        case .legs:            return [.quadriceps, .hamstring, .gluteal, .calves,
                                       .innerQuad, .outerQuad, .adductors]

        // 股四头
        case .quads:           return [.quadriceps, .innerQuad, .outerQuad]
        case .rectusFemoris:   return [.quadriceps]                             // 股直肌 = 中间, 用主 quad
        case .vastusLateralis: return [.outerQuad]                              // 股外肌 = 外侧
        case .vastusMedialis:  return [.innerQuad]                              // 股内肌 = 内侧

        // 腘绳肌
        case .hamstrings:      return [.hamstring]
        case .bicepsFemoris:   return [.hamstring]
        case .semitendinosus:  return [.hamstring]

        // 臀
        case .glutes:          return [.gluteal]
        case .gluteusMaximus:  return [.gluteal]
        case .gluteusMedius:   return [.gluteal]                                // proxy: med 没独立

        // 小腿
        case .calves:          return [.calves]
        case .gastrocnemius:   return [.calves]
        case .soleus:          return [.calves]
        case .tibialisAnterior: return [.tibialis]
        case .adductors:       return [.adductors]

        // 全身 / fallback
        case .fullBody:        return []
        }
    }
}

extension Muscle {
    /// 反向: MuscleMap.Muscle → Maso MuscleGroup. 用于 onMuscleSelected callback 把
    /// 用户点的肌肉传回 caller.
    var masoMuscleGroup: MuscleGroup {
        switch self {
        // 胸
        case .chest:           return .midChest
        case .upperChest:      return .upperChest
        case .lowerChest:      return .lowerChest

        // 背
        case .upperBack:       return .lats
        case .lowerBack:       return .lowerBack
        case .upperTrapezius:  return .upperTraps
        case .lowerTrapezius:  return .lowerTraps
        case .trapezius:       return .midTraps
        case .rhomboids:       return .rhomboids

        // 肩
        case .deltoids:        return .sideDelts
        case .frontDeltoid:    return .frontDelts
        case .rearDeltoid:     return .rearDelts
        case .rotatorCuff:     return .rotatorCuff

        // 臂
        case .biceps:          return .biceps
        case .triceps:         return .triceps
        case .forearm:         return .forearms

        // 核心
        case .abs:             return .abs
        case .upperAbs:        return .upperAbs
        case .lowerAbs:        return .lowerAbs
        case .obliques:        return .obliques
        case .serratus:        return .serratus
        case .neck:            return .neck

        // 腿
        case .quadriceps:      return .quads
        case .innerQuad:       return .vastusMedialis
        case .outerQuad:       return .vastusLateralis
        case .hamstring:       return .hamstrings
        case .gluteal:         return .glutes
        case .calves:          return .calves
        case .tibialis:        return .tibialisAnterior
        case .adductors:       return .adductors
        case .hipFlexors:      return .legs                                    // 没独立 enum, 归 legs

        // 没用上的
        case .feet, .hands, .head, .knees, .ankles:
            return .fullBody
        }
    }
}
