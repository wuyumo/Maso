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

    /// 这个 exercise 是不是"动作差异变种" (Variation), 区别于"器械差异变种" (Equipment).
    /// 两条任一成立即算动作差异, 否则算器械差异:
    ///   1. 名字带执行方式前缀 (Seated / Single-Arm / Close-Grip …) → 动作差异 (沿用主库逻辑).
    ///   2. 跟 canonical 用同一器械 → 区别只能在执行方式/体位/握法/动作模式 — 尤其括号内的 niche 变种
    ///      (Standing / Single-Leg / Lean-Forward / Alternating Waves …) → 动作差异.
    /// 器械不同 (且无执行方式前缀) → 器械差异.
    /// UI 用这个把展开的变种拆成 "Variation"(动作) / "Equipment"(器械) 两段.
    func isModifierVariant(_ exercise: Exercise) -> Bool {
        if ExerciseGrouping.extractedModifier(of: exercise) != nil { return true }
        return ExerciseGrouping.sameEquipment(exercise, canonical)
    }

    /// 返回这个 exercise 的执行方式修饰标签, e.g. "Seated" / "Single-Arm" / "Close-Grip".
    /// 纯器械变种返回 nil.
    func modifierLabel(for exercise: Exercise) -> String? {
        ExerciseGrouping.extractedModifier(of: exercise)
    }

    /// 动作差异变种的"区别"短标签 — 优先执行方式前缀 (主库); 否则取括号内容并去掉与器械相关的词 (niche).
    /// e.g. "Hip Abduction (Machine, Single-Leg)" → "Single-Leg"; "Battle Rope (Double Waves)" → "Double Waves";
    ///      "Seated Lateral Raise" → "Seated".
    func variationLabel(for exercise: Exercise) -> String {
        if let m = ExerciseGrouping.extractedModifier(of: exercise) { return m }
        if let detail = ExerciseGrouping.parenDetail(of: exercise) { return detail }
        return exercise.displayName
    }

    /// 展开时归到 "Variation"(动作) section 的变种 — 执行方式差异 (Seated / Single-Leg / 括号内动作细节 …).
    var movementVariants: [Exercise] { variants.filter { isModifierVariant($0) } }

    /// 展开时归到 "Equipment"(器械) section 的变种 — 器械差异 (Dumbbell / Machine / Swiss Ball …).
    var equipmentVariants: [Exercise] { variants.filter { !isModifierVariant($0) } }
}

enum ExerciseGrouping {
    /// 从 exercise.name 提取"基础名": 第一个 "(" 之前的部分.
    /// "Bench Press" → "Bench Press"
    /// "Bench Press (Machine)" → "Bench Press"
    /// "Bench Press (Dumbbell, Decline)" → "Bench Press"
    /// "Speed Bench Press" → "Speed Bench Press" (无括号 → 整名当 base)
    static func baseName(of exercise: Exercise) -> String {
        let n = exercise.name
        // 1. 截到第一个 "(" 前 — 括号里的器械/grip 变种归到同 base (现有逻辑).
        let beforeParen: String
        if let paren = n.firstIndex(of: "(") {
            beforeParen = String(n[..<paren]).trimmingCharacters(in: .whitespaces)
        } else {
            beforeParen = n.trimmingCharacters(in: .whitespaces)
        }
        // 2. 先删器械词 ("Dumbbell Bench Press" → "Bench Press"; "Landmine Front Raise" → "Front Raise").
        let noEquip = stripEquipmentWords(beforeParen)
        // 3. 再删运动修饰词 ("Seated Lateral Raise" → "Lateral Raise";
        //    "Incline/Decline Bench Press" → "Bench Press"; "Dive Bomber Push-Up" → "Push-Up").
        //    仍保留 Romanian/Sumo 等真正独立的动作 (见 movementModifierTokens 的注释).
        return stripMovementModifiers(noEquip)
    }

    /// 名字里的器械词 — 整词、大小写不敏感地删掉. 多词词条放前面 (正则 alternation 从左到右,
    /// 所以 "with bands" 必须排在 "bands" 前面才不会被单独的 "bands" 抢先匹配掉).
    private static let equipmentNameTokens: [String] = [
        // accommodating resistance / 负重道具 — 当成器械变体收折到基础动作:
        //   "Bench Press with Bands/Chains" → Bench Press; "Med Ball Push-Up" → Push-Up.
        "with bands", "with band", "with chains", "with chain",
        "medicine ball", "med ball", "med-ball",
        "smith machine", "resistance band", "ez curl bar", "ez-bar", "ez bar",
        "trap bar", "leverage machine", "body only",
        "dumbbells", "dumbbell", "barbells", "barbell", "kettlebells", "kettlebell",
        "cables", "cable", "machine", "smith", "bands", "band", "bodyweight",
        "landmine", "sled", "weighted", "plate",
    ]

    private static let equipmentRegex: NSRegularExpression = {
        let pat = "\\b(?:" + equipmentNameTokens.joined(separator: "|") + ")\\b"
        return try! NSRegularExpression(pattern: pat, options: [.caseInsensitive])
    }()

    /// 删器械词 + 收敛空白. 大小写不敏感匹配但保留其余词的原始大小写 (在原串上替换).
    /// 全被删空 (动作名本身就叫 "Dumbbell" 之类) → 回退原串, 不强行归并出空 base.
    private static func stripEquipmentWords(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        var out = equipmentRegex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        out = out.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                 .trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? s : out
    }

    // MARK: - Movement modifier (执行方式) stripping

    /// "执行方式"修饰词 — 改的是怎么做(站/坐/单侧/握法/节奏/范围)而不是换了个动作.
    /// 判定规则 (跟用户对齐): 动作名 = "<修饰词> <某个真实基础动作>" 且修饰词只是"怎么做"
    ///   → 收折到基础动作 (e.g. "Feet-Elevated Bench Dip" → Bench Dip, "Dead-Stop Barbell Row" → Row).
    /// 用户最新口径 (2026-06): Incline / Decline (角度) 也算同一动作的变体 → 收折
    ///   ("Incline/Decline Bench Press" → Bench Press; "Incline/Decline Chest Fly" → Chest Fly).
    /// 仍然排除以下"独立动作" —— 它们是不同动作, 不是同一动作的执行变体, 不该被合并:
    ///   - 限定 ROM / 轨迹 / 模态的不同动作: Floor / Behind-the-Neck / Speed / Romanian / Sumo
    ///   - 独立的下肢花式: Pistol / Sissy / Hack / Zercher / Bulgarian / Cossack / Split / Curtsy …
    ///   - 独立的自重技巧: Diamond / Pike / Handstand / Archer / Commando / Typewriter …
    ///     (Dive Bomber / Med Ball 这两类用户要求收进 Push-Up; 其余自重花式暂留, 待用户确认是否一起收.)
    static let movementModifierTokens: [String] = [
        // 角度 (用户要求收折: Incline/Decline 视作同一动作的角度变体)
        "incline", "decline",
        // 动作模式 (执行花式 — 当前只收用户点名的两类自重 push-up)
        "dive bomber", "dive-bomber",
        // 方向/角度
        "low-to-high", "high-to-low",
        // 单侧 / 双侧
        "single-arm", "one-arm", "single arm", "one arm",
        "single-leg", "one-leg", "single leg", "one leg",
        "one-side", "one side", "unilateral", "alternating",
        "two-arm", "two arm", "two-handed", "two handed",
        // 体位 / 支撑 (注意: 不含 floor — Floor Press 是独立动作)
        "seated", "standing", "lying", "prone", "supine",
        "kneeling", "half-kneeling", "half kneeling",
        "chest-supported", "chest supported", "feet-elevated", "feet elevated",
        // 握法
        "wide-grip", "close-grip", "neutral-grip", "reverse-grip",
        "wide grip", "close grip", "neutral grip", "reverse grip",
        "overhand", "underhand", "pronated", "supinated",
        "hammer-grip", "hammer grip", "crush-grip", "crush grip",
        "snatch-grip", "snatch grip", "iso-lateral", "iso lateral",
        // 节奏 / 强度技巧 (同一动作的执行变体)
        "paused", "tempo", "eccentric", "iso-hold", "iso hold",
        "21s", "drop-set", "drop set", "drag",
        // 范围 / 起停
        "deficit", "dead-stop", "dead stop",
        // 路径 / 倾身 (常见于侧平举 / 弯举的执行变体)
        "cross-body", "cross body", "behind-the-back", "behind the back",
        "behind-the-head", "behind the head", "lean-in", "lean in", "leaning", "egyptian",
    ]

    static let movementModifierRegex: NSRegularExpression = {
        // 多词词条放前 (regex alternation 左优先)
        let sorted = movementModifierTokens.sorted { $0.count > $1.count }
        let pat = "(?i)\\b(?:" + sorted.joined(separator: "|") + ")\\b"
        return try! NSRegularExpression(pattern: pat, options: [.caseInsensitive])
    }()

    /// 删运动修饰词 + 收敛空白. 只收敛空格, 不动连字符 (Multi-Joint 等专名保持原样).
    private static func stripMovementModifiers(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        var out = movementModifierRegex.stringByReplacingMatches(in: s, options: [], range: range, withTemplate: " ")
        out = out.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
                 .trimmingCharacters(in: .whitespaces)
        return out.isEmpty ? s : out
    }

    /// 从 exercise name 提取执行方式修饰标签 (在同 group 内区分变种用).
    ///
    /// 例:
    ///   "Seated Lateral Raise (Dumbbell)"  →  "Seated"
    ///   "Single-Arm Cable Row"             →  "Single-Arm"
    ///   "Close-Grip Bench Press (Smith)"   →  "Close-Grip"
    ///   "Lateral Raise (Dumbbell)"         →  nil  (没有修饰词)
    static func extractedModifier(of exercise: Exercise) -> String? {
        let n = exercise.name
        // 截掉括号部分
        let beforeParen: String
        if let paren = n.firstIndex(of: "(") {
            beforeParen = String(n[..<paren]).trimmingCharacters(in: .whitespaces)
        } else {
            beforeParen = n.trimmingCharacters(in: .whitespaces)
        }
        // 删器械词
        let noEquip = stripEquipmentWords(beforeParen)
        // 删修饰词得到 base
        let baseOnly = stripMovementModifiers(noEquip).trimmingCharacters(in: .whitespaces)
        guard !baseOnly.isEmpty, noEquip.trimmingCharacters(in: .whitespaces) != baseOnly else { return nil }
        // 从 noEquip 中去掉 base 字符串, 剩下的就是修饰词部分
        let noEquipTrimmed = noEquip.trimmingCharacters(in: .whitespaces)
        if let r = noEquipTrimmed.range(of: baseOnly, options: [.caseInsensitive]) {
            var mod = String(noEquipTrimmed[..<r.lowerBound])
                    + String(noEquipTrimmed[r.upperBound...])
            // 只收敛空格, 保留连字符 (Single-Arm 不能变 Single Arm)
            mod = mod.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
                     .trimmingCharacters(in: .whitespaces)
            return mod.isEmpty ? nil : mod
        }
        return nil
    }

    // MARK: - 器械比较 + 括号内容提取 (Variation / Equipment 分段用)

    /// equipment 归一: nil / 空 / "none" 都视作 "other", 大小写不敏感.
    static func normalizedEquipment(_ equipment: String?) -> String {
        let s = (equipment ?? "").lowercased().trimmingCharacters(in: .whitespaces)
        return (s.isEmpty || s == "none") ? "other" : s
    }

    /// 两个动作是否用同一器械 — 判定变种是"动作差异"还是"器械差异"的核心.
    static func sameEquipment(_ a: Exercise, _ b: Exercise) -> Bool {
        normalizedEquipment(a.equipment) == normalizedEquipment(b.equipment)
    }

    /// 取名字第一个 "(" 到最后一个 ")" 之间的内容 (去首尾空白). 无括号 → nil.
    static func parenContent(_ name: String) -> String? {
        guard let o = name.firstIndex(of: "("), let c = name.lastIndex(of: ")"),
              name.index(after: o) < c else { return nil }
        return String(name[name.index(after: o)..<c]).trimmingCharacters(in: .whitespaces)
    }

    /// 括号内容去掉器械词 (Machine / Cable / Smith …) + 清理逗号空白 — 得到"执行方式"短标签.
    /// "Machine, Single-Leg" → "Single-Leg"; "Double Waves" → "Double Waves" (无器械词原样保留).
    static func parenDetail(of exercise: Exercise) -> String? {
        guard let p = parenContent(exercise.name) else { return nil }
        var s = stripEquipmentWords(p)              // 删器械词 (全删空会回退原串)
        s = s.replacingOccurrences(of: " +", with: " ", options: .regularExpression)
        s = s.trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return s.isEmpty ? p : s
    }

    /// 器械前缀删除后的基础名 (不删运动修饰词) — 用于判断"某动作是否有无修饰词的同名变种".
    private static func equipmentOnlyBase(of exercise: Exercise) -> String {
        let n = exercise.name
        let beforeParen: String
        if let paren = n.firstIndex(of: "(") {
            beforeParen = String(n[..<paren]).trimmingCharacters(in: .whitespaces)
        } else {
            beforeParen = n.trimmingCharacters(in: .whitespaces)
        }
        return stripEquipmentWords(beforeParen)
    }

    /// 把一组 exercise 折叠成 ExerciseGroup 列表.
    /// 顺序: 跟 input 一致 (拿每组第一次出现的 exercise 决定 group 顺序).
    /// 同 group 内 variants 顺序: input 顺序 (除去 canonical).
    ///
    /// 运动修饰词折叠策略 (J-session 新增):
    ///   "Seated Lateral Raise" 和 "Single-Arm Rear Delt Fly" 这类带修饰词的动作,
    ///   只在目标 base 已有"无修饰词变种"时才并入 — 这样 "Lateral Raise (Dumbbell)" 存在 →
    ///   "Seated Lateral Raise" 合法并入 "Lateral Raise" 组; 而 "Alternating Dumbbell Curl"
    ///   没有无修饰词的 "Curl" 变种 → 保持在自己的器械只 base "Alternating Curl" 里, 不强行并入.
    static func group(_ exercises: [Exercise]) -> [ExerciseGroup] {
        // 1. 先算所有"纯器械 base" (不删修饰词) — 用于检测 "目标 base 是否有无修饰词成员".
        let equipBasesSet = Set(exercises.map { equipmentOnlyBase(of: $0) })

        // 2. 为每个 exercise 确定最终 key:
        //    fullBase = modifier-stripped base; equipBase = equipment-only base.
        //    只有当 fullBase 出现在 equipBasesSet 里 (即有真正的"无修饰词"变种存在), 才采用 fullBase;
        //    否则回退 equipBase.
        func contextualKey(_ ex: Exercise) -> String {
            let eBase = equipmentOnlyBase(of: ex)
            let fBase = baseName(of: ex)      // strips both equipment + modifiers
            if fBase != eBase && equipBasesSet.contains(fBase) {
                return fBase
            }
            return eBase
        }

        var orderedKeys: [String] = []
        var buckets: [String: [Exercise]] = [:]
        for ex in exercises {
            let key = contextualKey(ex)
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
