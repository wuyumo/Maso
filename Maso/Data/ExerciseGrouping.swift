import Foundation

// MARK: - ExerciseGrouping
//
// 把"同基础动作 + 不同器械变种"折叠成一个 group, 让 picker 列表不至于被 5 种 Bench Press
// (machine / dumbbell / smith / decline / incline) 挤爆.
//
// Rule (跟用户原话对齐):
//   - 带括号的动作 → 基础名 = 括号前的部分. "Bench Press (Machine)" → base "Bench Press"
//   - 没括号的动作 → 基础名 = 自身. "Bench Press" → base "Bench Press"
//   - 同 base 的动作收到同一 group. Group 里 name 跟 base 完全相等的那个 = "canonical"
//     (默认推荐); 其它都是 variant.
//   - 关键反例: "Speed Bench Press" 的 base = "Speed Bench Press" (它自己), 不收进
//     "Bench Press" group — 因为它本身不带括号, base 就是它自己, 跟 "Bench Press" 是两组.
//
// UI 用法:
//   - picker 默认渲染每组 canonical 那一项 (折叠态)
//   - 有 variants → 行右侧带"+N 变种" disclosure
//   - 用户 tap row 直接选 canonical; tap disclosure 展开看每个变种 (各自带 equipment icon)

/// 一组"同基础动作"的 exercise 集合.
/// canonical: 这个 group 推荐默认的那一项. 永远非 nil — 即使没有跟 base 同名的 exercise (e.g.
/// 整组都带括号 / 没有"裸基础名"那一项), 也会拿 group 里第一个当 canonical.
struct ExerciseGroup: Hashable, Identifiable {
    let baseName: String  // "Bench Press"
    let canonical: Exercise
    let variants: [Exercise]  // 不含 canonical

    var id: String { baseName + "|" + canonical.id }

    /// 全部 exercise: canonical + variants. 顺序: canonical 第一.
    var all: [Exercise] { [canonical] + variants }

    /// 这个组有多少个 exercise (含 canonical).
    var count: Int { 1 + variants.count }

    /// 是不是单 exercise 组 (没变种). UI 用这个决定要不要显 disclosure.
    var isSingleton: Bool { variants.isEmpty }
}

enum ExerciseGrouping {
    /// 从 exercise.name 提取"基础名": 第一个 "(" 之前的部分.
    /// "Bench Press" → "Bench Press"
    /// "Bench Press (Machine)" → "Bench Press"
    /// "Bench Press (Dumbbell, Decline)" → "Bench Press"
    /// "Speed Bench Press" → "Speed Bench Press" (无括号 → 整名当 base)
    static func baseName(of exercise: Exercise) -> String {
        let n = exercise.name
        if let paren = n.firstIndex(of: "(") {
            // 截到 "(" 前, trim 末尾空白
            return n[..<paren].trimmingCharacters(in: .whitespaces)
        }
        return n.trimmingCharacters(in: .whitespaces)
    }

    /// 把一组 exercise 折叠成 ExerciseGroup 列表.
    /// 顺序: 跟 input 一致 (拿每组第一次出现的 exercise 决定 group 顺序).
    /// 同 group 内 variants 顺序: input 顺序 (除去 canonical).
    static func group(_ exercises: [Exercise]) -> [ExerciseGroup] {
        var orderedKeys: [String] = []
        var buckets: [String: [Exercise]] = [:]
        for ex in exercises {
            let key = baseName(of: ex)
            if buckets[key] == nil {
                orderedKeys.append(key)
                buckets[key] = []
            }
            buckets[key]?.append(ex)
        }
        return orderedKeys.compactMap { key -> ExerciseGroup? in
            guard let items = buckets[key], !items.isEmpty else { return nil }
            // canonical 选取:
            //   1. name 严格等于 base 的那一项 (没括号 → 真正的"基础动作")
            //   2. 没有裸基础名 (orphan group, ~10% 的组) → 按器械/机制优先级挑, 不是随机 items[0],
            //      否则会出现 "Calf Raise (Band)" / "Bicep Curl (Band)" 当默认推荐的怪象 (P1-4).
            let canonical = items.first(where: { $0.name == key })
                ?? items.min(by: { a, b in
                    let ra = canonicalRank(a), rb = canonicalRank(b)
                    return ra != rb ? ra < rb : a.name < b.name  // 同 rank 按名字定序, 不依赖 JSON 顺序
                })
                ?? items[0]
            // P1-8: 去掉跟 canonical 完全同 displayName 的"幽灵变种" (DB 里 17 对重名动作),
            // 否则展开会看到两行一模一样的名字 + "+N" 计数虚高.
            var seenNames = Set([canonical.displayName])
            let variants = items.filter { v -> Bool in
                guard v.id != canonical.id else { return false }
                return seenNames.insert(v.displayName).inserted
            }
            return ExerciseGroup(baseName: key, canonical: canonical, variants: variants)
        }
    }

    /// orphan group 选 canonical 用的优先级 (越小越优先). 偏好"自由重量 / 自重 / 复合"作为默认,
    /// 把 band / machine / 专项器械往后排. 同 rank 再按 name 字母序保证确定性 (不依赖 JSON 顺序).
    private static func canonicalRank(_ ex: Exercise) -> Int {
        let eq = ex.equipment ?? ""
        let base: Int
        switch eq {
        case "body_only":            base = 0
        case "barbell":              base = 1
        case "dumbbell":             base = 2
        case "cable":                base = 3
        case "machine", "smith_machine": base = 4
        case "kettlebell":           base = 5
        case "band", "resistance_band": base = 8   // band 往后 — 不该当默认
        default:                     base = 6
        }
        // compound 比 isolation 略优先 (基础动作通常是复合)
        let mech = ex.mechanic == .compound ? 0 : 1
        return base * 2 + mech
    }
}
