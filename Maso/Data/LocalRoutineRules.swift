import Foundation

// AI 不可用时的**本地规则引擎** — 把用户在 Coach 里打的原话解析成结构化意图,
// 叠加到现成的本地生成管线上. 全程不联网.
//
// 为什么需要: `*.workers.dev` / `*.vercel.app` 在中国大陆都可能被 DNS 污染 → 有相当一部分
// 用户**长期**碰不到 AI. 原来的兜底 (DataStore.tunedRecommendedPlans) 只读 Settings 里的
// 结构化偏好, **完全无视用户打的字** —— 用户说"多练胸/只用哑铃/45 分钟内", 兜底一个字不看,
// 出来的计划跟他的要求无关, 体感就是"AI 挂了 = 这功能废了".
//
// 这里只做"解析 + 叠加", **不重写选动作逻辑** —— 裁剪/器械替换/重量折算/enforceScience
// 全部复用 DataStore 已有的那套 (它们已经过实战). 加的是"听懂用户这次要什么".
//
// ⚠️ 刻意不做自然语言理解: 就是关键词匹配. 本地没有模型, 假装聪明只会更糟 ——
//    匹配不到就退回纯 Settings 行为 (跟改动前一致), 不会更差.
enum LocalRoutineRules {

    /// 从用户原话里能提取出来的意图. 全空 = 没匹配到任何东西 → 调用方按原逻辑走.
    struct Intent: Equatable {
        /// 想多练的大肌群区 (chest/back/shoulders/arms/core/legs)
        var focusSections: Set<MuscleGroup> = []
        /// 想少练/避开的大肌群区 — 优先级高于 focus (用户明说不练就别塞)
        var avoidSections: Set<MuscleGroup> = []
        /// 限定器械 (EquipmentCategory.rawValue); 空 = 不限制
        var equipment: Set<String> = []
        /// 徒手 — 特殊态: 不是"限定某器械", 而是"什么器械都别用"
        var bodyweightOnly: Bool = false
        /// 时长换算出的动作数上限
        var maxExercises: Int? = nil

        var isEmpty: Bool {
            focusSections.isEmpty && avoidSections.isEmpty && equipment.isEmpty
                && !bodyweightOnly && maxExercises == nil
        }
    }

    // MARK: - 词表

    /// 大肌群区 → 中英关键词. 全小写匹配; 中文不分词, 直接子串命中.
    private static let sectionWords: [(MuscleGroup, [String])] = [
        (.chest,     ["chest", "pec", "胸"]),
        (.back,      ["back", "lat", "row", "背", "阔背", "引体"]),
        (.shoulders, ["shoulder", "delt", "肩", "三角肌"]),
        (.arms,      ["arm", "bicep", "tricep", "curl", "臂", "手臂", "二头", "三头"]),
        (.core,      ["core", "ab ", "abs", "腹", "核心"]),
        (.legs,      ["leg", "quad", "hamstring", "glute", "squat", "腿", "臀", "深蹲", "股四头"]),
    ]

    /// 器械关键词 → EquipmentCategory.rawValue
    private static let equipmentWords: [(String, [String])] = [
        ("dumbbell",  ["dumbbell", "db ", "哑铃"]),
        ("barbell",   ["barbell", "bb ", "杠铃"]),
        ("cable",     ["cable", "龙门", "绳索", "拉索"]),
        ("machine",   ["machine", "器械"]),
        ("smith",     ["smith", "史密斯"]),
        ("kettlebell",["kettlebell", "壶铃"]),
        ("bands",     ["band", "弹力带", "阻力带"]),
        ("pullupBar", ["pull-up bar", "pullup bar", "单杠", "引体架"]),
    ]

    /// 徒手 / 无器械
    private static let bodyweightWords = [
        "bodyweight", "body weight", "no equipment", "no gear", "calisthenic",
        "徒手", "自重", "无器械", "没有器械", "不用器械", "在家",
    ]

    /// "少练 / 避开" 的否定前缀 — 出现在肌群词附近时把 focus 翻成 avoid
    private static let avoidWords = ["less ", "no ", "skip ", "avoid ", "without ",
                                     "少练", "不练", "别练", "避开", "跳过"]

    // MARK: - 解析

    /// 把用户原话解析成 Intent. nil / 空串 / 匹配不到 → 返回 isEmpty 的 Intent.
    static func parse(_ note: String?) -> Intent {
        guard let raw = note?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return Intent()
        }
        let s = raw.lowercased()
        var intent = Intent()

        // 肌群: **按标点切句后逐句判**, 句内出现否定词 → 该句命中的都记 avoid, 否则 focus.
        // ⚠️ 不能用"往回看 N 个字符"的近邻窗口 —— 实测「不练腿，多练肩」里"肩"会扫到前半句的
        //    "不练", 把肩也误判成 avoid. 中文短句之间没有空格, 只有标点是可靠的边界.
        let clauses = s.split(whereSeparator: { ",，.。;；!！?？、\n".contains($0) })
        for clause in clauses {
            let negated = avoidWords.contains(where: { clause.contains($0) })
            for (section, words) in sectionWords where words.contains(where: { clause.contains($0) }) {
                if negated { intent.avoidSections.insert(section) }
                else { intent.focusSections.insert(section) }
            }
        }
        // 明说避开的, 从 focus 里剔掉 (同一句里两边都命中时以 avoid 为准)
        intent.focusSections.subtract(intent.avoidSections)

        // 徒手优先级最高 — 说了徒手就不再收集具体器械
        if bodyweightWords.contains(where: { s.contains($0) }) {
            intent.bodyweightOnly = true
        } else {
            for (raw, words) in equipmentWords where words.contains(where: { s.contains($0) }) {
                intent.equipment.insert(raw)
            }
        }

        intent.maxExercises = parseDurationToExerciseCount(s)
        return intent
    }

    /// "45 分钟" / "under 45 min" / "1 小时" → 动作数上限.
    /// 换算: 每个动作按 ~10 分钟算 (3 组 × (做 ~40s + 歇 ~90s) ≈ 6.5min, 加换器械/热身余量),
    /// 再减 5 分钟热身. 夹到 2...8 —— 低于 2 不成计划, 高于 8 超出 UI 上限.
    private static func parseDurationToExerciseCount(_ s: String) -> Int? {
        let patterns = [
            #"(\d{1,3})\s*(?:min|minute|minutes|分钟|分)"#,
            #"(\d{1,2})\s*(?:h|hr|hour|hours|小时)"#,
        ]
        for (i, p) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: p),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let r = Range(m.range(at: 1), in: s),
                  let n = Int(s[r]) else { continue }
            let minutes = i == 0 ? n : n * 60
            guard minutes >= 10, minutes <= 300 else { continue }   // 明显不是时长, 忽略
            return min(8, max(2, (minutes - 5) / 10))
        }
        return nil
    }

    // MARK: - Intent → 可展示的契约

    /// 把解析出的意图翻成"生成依据"chip. 生成那一刻本地化并存进 Plan.constraints,
    /// 用户在计划页上就能核对: 我说的每一条, app 到底认没认。
    static func constraints(from intent: Intent) -> [PlanConstraint] {
        var out: [PlanConstraint] = []
        if intent.bodyweightOnly {
            out.append(.init(kind: .equipment, value: "bodyweight",
                             label: NSLocalizedString("Bodyweight only", comment: "plan constraint")))
        } else {
            for e in intent.equipment.sorted() {
                let name = NSLocalizedString(e.capitalized, comment: "equipment name")
                out.append(.init(kind: .equipment, value: e,
                                 label: String(format: NSLocalizedString("%@ only", comment: "plan constraint — equipment"), name)))
            }
        }
        if let cap = intent.maxExercises {
            // 反算回分钟 (parseDurationToExerciseCount 的逆) —— 给用户看分钟, 不是"动作数"这种内部量.
            let minutes = cap * 10 + 5
            out.append(.init(kind: .duration, value: "\(minutes)",
                             label: String(format: NSLocalizedString("Under %d min", comment: "plan constraint — duration"), minutes)))
        }
        for m in intent.avoidSections.sorted(by: { $0.rawValue < $1.rawValue }) {
            out.append(.init(kind: .avoid, value: m.rawValue,
                             label: String(format: NSLocalizedString("No %@", comment: "plan constraint — avoided muscle"), m.displayName)))
        }
        for m in intent.focusSections.sorted(by: { $0.rawValue < $1.rawValue }) {
            out.append(.init(kind: .focus, value: m.rawValue,
                             label: String(format: NSLocalizedString("More %@", comment: "plan constraint — focused muscle"), m.displayName)))
        }
        return out
    }

    // MARK: - 叠加到已生成的计划上

    /// 把 Intent 应用到本地模板产出上. 复用 DataStore 现成的器械替换 + 科学化,
    /// 这里只负责"按用户这次说的话重新挑/裁动作".
    ///
    /// - avoid: 直接剔掉该区动作 (剔空了就保留原样 —— 宁可不听话也不给空计划)
    /// - focus: 命中的动作排前面, 裁剪时优先保留
    /// - 器械 / 徒手: 覆盖 settings.availableEquipment 走同一套替换逻辑
    /// - maxExercises: 覆盖 exercisesPerSession 的裁剪上限
    @MainActor
    static func apply(
        to plans: [Plan],
        intent: Intent,
        settings: UserSettings,
        exById: [String: Exercise]
    ) -> [Plan] {
        guard !intent.isEmpty else { return plans }

        // 器械约束: 用 intent 覆盖出一份临时 settings, 复用 applyEquipmentPreference.
        var effective = settings
        if intent.bodyweightOnly {
            effective.availableEquipment = []          // 空 = 不限制, 所以徒手单独在下面过滤
        } else if !intent.equipment.isEmpty {
            effective.availableEquipment = Array(intent.equipment)
        }

        func section(of step: PlanStep) -> MuscleGroup? {
            guard let ex = exById[step.exerciseId] else { return nil }
            return ex.primaryMuscles.first.flatMap { $0.section ?? $0 }
        }
        func isBodyweight(_ step: PlanStep) -> Bool {
            guard let ex = exById[step.exerciseId] else { return false }
            let e = (ex.equipment ?? "").lowercased()
            return e.isEmpty || e.contains("body") || e.contains("none")
        }

        return plans.map { plan -> Plan in
            var p = plan
            var steps = p.steps

            // 1. 徒手: 只留自重动作 (全滤没了就放弃这条约束, 不给空计划)
            if intent.bodyweightOnly {
                let bw = steps.filter(isBodyweight)
                if !bw.isEmpty { steps = bw }
            } else if !intent.equipment.isEmpty {
                steps = DataStore.applyEquipmentPreference(steps, settings: effective, exById: exById)
            }

            // 2. avoid: 剔掉明确不想练的区 (剔空则保留)
            if !intent.avoidSections.isEmpty {
                let kept = steps.filter { s in
                    guard let sec = section(of: s) else { return true }
                    return !intent.avoidSections.contains(sec)
                }
                if !kept.isEmpty { steps = kept }
            }

            // 3. focus: 命中的排前面 (稳定 — 同类保持原相对顺序)
            if !intent.focusSections.isEmpty {
                steps = steps.enumerated().sorted { a, b in
                    let fa = section(of: a.element).map { intent.focusSections.contains($0) } ?? false
                    let fb = section(of: b.element).map { intent.focusSections.contains($0) } ?? false
                    return fa == fb ? a.offset < b.offset : fa
                }.map(\.element)
            }

            // 4. 时长 → 动作数上限
            if let cap = intent.maxExercises, steps.count > cap {
                steps = Array(steps.prefix(cap))
            }

            // 5. 重新过一遍科学化 (复合优先 / 同区 ≤2 / push≥pull) —— 上面动过顺序和成员
            p.steps = DataStore.enforceScience(steps, exById: exById)
            return p
        }
    }
}
