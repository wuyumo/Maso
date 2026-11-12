import Foundation
import Observation
import UIKit

// Coach tab (对话式生成) 的会话状态容器 — 批次 1 数据/AI 地基, 见 docs/coach-tab-design.md §1/§3.
//
// 为什么收归 DataStore 层而不是 view @State (工程评审钦点):
//   - 生成 45-60s 且无流式, 用户会切 tab / 锁屏; view 销毁 = @State 即丢, 回来一片空白.
//   - DataStore 持有 CoachSession + 生成 Task, 视图只渲染; 切走再回来, 等待清单/结果都还在.
// V1 刻意 in-memory (不落盘): 对话流是"工作台"不是"档案", 重启清空可接受;
// 真正的产物 (用户保存的 routine) 走 data.plans 持久化, 不受影响.

/// Proposed memory is never applied without an explicit user choice.
struct CoachMemoryProposal: Codable, Hashable {
    enum Decision: String, Codable { case pending, saved, declined }
    let note: String
    let sourceQuote: String
    var decision: Decision = .pending

    enum CodingKeys: String, CodingKey { case note, sourceQuote = "source_quote" }

    static func key(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    static func validated(_ proposed: Self?, userText: String?, existing: String, declined: Set<String>) -> Self? {
        guard let userText, !userText.isEmpty,
              let proposed = proposed ?? fromUserText(userText) else { return nil }
        let note = proposed.note.trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = proposed.sourceQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !note.isEmpty, note.count <= 220, quote.count >= 3, quote.count <= 500,
              userText.range(of: quote, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { return nil }
        // Both the saved claim and its user evidence must affect a concrete planning decision.
        // "Remember my preferences / recovery" is an instruction to the coach, not a preference.
        guard hasPlanningDetail(note), hasPlanningDetail(quote) else { return nil }
        let key = key(note)
        guard !key.isEmpty, !declined.contains(key), !declined.contains(Self.key(quote)),
              !Self.key(existing).contains(key) else { return nil }
        let temporary = ["today", "tonight", "this session", "this workout", "this week", "for now", "今天", "今晚", "这次", "本次", "这周", "暂时", "临时", "今天", "這次", "這週", "暫時", "heute", "hoy", "aujourd’hui", "aujourd'hui", "oggi", "hoje", "сегодня", "今日", "오늘", "اليوم"]
        guard !temporary.contains(where: { note.lowercased().contains($0) || quote.lowercased().contains($0) }) else { return nil }
        return .init(note: note, sourceQuote: quote)
    }

    /// Conservative offline guard, covering the app's 12 languages. Unknown details are
    /// left in chat rather than saving generic guidance or inventing a personal constraint.
    static func hasPlanningDetail(_ text: String) -> Bool {
        let targets = [
            "chest", "pec", "back", "lat", "shoulder", "delt", "bicep", "tricep", "core", "abs", "oblique", "quad", "hamstring", "glute", "calf", "calves", "leg", "knee", "wrist", "elbow",
            "dumbbell", "barbell", "kettlebell", "cable", "smith", "bodyweight", "resistance band", "pull-up", "push-up", "squat", "deadlift", "bench press", "overhead press", "no equipment",
            "gain muscle", "build muscle", "hypertrophy", "lose fat", "beginner", "增肌", "减脂", "減脂", "新手", "muskelaufbau", "musculación", "prise de muscle", "ipertrofia", "hipertrofia", "набор мышц", "筋肥大", "근비대", "بناء العضلات",
            "胸", "背", "肩", "腹", "腿", "臀", "二头", "二頭", "三头", "三頭", "后束", "後束", "哑铃", "啞鈴", "杠铃", "槓鈴", "弹力带", "彈力帶", "徒手", "深蹲", "硬拉", "膝", "腕", "肘",
            "brust", "rücken", "schulter", "hantel", "knie", "pecho", "espalda", "hombro", "mancuerna", "rodilla", "poitrine", "dos", "épaule", "haltère", "genou", "petto", "schiena", "spalla", "manubrio", "ginocchio",
            "peito", "costas", "ombro", "halter", "joelho", "грудь", "спина", "плечо", "гантел", "колен", "ダンベル", "バーベル", "自重", "膝", "가슴", "등", "어깨", "덤벨", "무릎", "صدر", "ظهر", "كتف", "دمبل", "ركبة"
        ]
        let folded = text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        for target in targets {
            let word = target.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            // Word boundaries prevent "back" matching "feedback" and "lat" matching "translate".
            let latin = word.unicodeScalars.allSatisfy { $0.value < 128 }
            let pattern = latin ? "(?<![a-z])" + NSRegularExpression.escapedPattern(for: word) + "s?(?![a-z])" : NSRegularExpression.escapedPattern(for: word)
            if folded.range(of: pattern, options: .regularExpression) != nil { return true }
        }
        let units = "minutes?|mins?|hours?|days?|times?|sessions?|分钟|分鐘|小时|小時|次|天|分|時間|분|시간|회|minuten|stunden|tage|minutos|horas|días|jours|heures|giorni|ore|dias|минут|час|дней|دقيقة|ساعة|أيام"
        return folded.range(of: "[0-9]+\\s*(?:" + units + ")", options: .regularExpression) != nil
    }

    private static func fromUserText(_ text: String) -> Self? {
        let durable = ["prefer", "usually", "always", "only have", "only use", "don't like", "dislike", "focus on", "focus more", "upper chest", "rear delt", "my gym", "喜欢", "不喜欢", "常用", "习惯", "只有", "只用", "侧重", "重点", "上胸", "后束"]
        for clause in text.components(separatedBy: CharacterSet(charactersIn: ".。;；\n")) {
            let trimmed = clause.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed.count <= 220,
               durable.contains(where: { trimmed.lowercased().contains($0) }) {
                return .init(note: trimmed, sourceQuote: trimmed)
            }
        }
        return nil
    }
}

/// A narrowly scoped, evidence-backed patch; confirmation never overwrites unrelated settings.
struct CoachPreferenceChange: Codable, Hashable {
    enum Field: String, Codable, CaseIterable {
        case weeklyTrainingDays, exercisesPerSession, defaultSetsPerExercise, trainingGoalKind
        case defaultRestSeconds, defaultBetweenExerciseRestSeconds, keepScreenAwakeDuringWorkout
        case coachMemory, wantStrengthen, availableEquipment
        var label: String {
            switch self {
            case .weeklyTrainingDays: "Days per week"
            case .exercisesPerSession: "Exercises per plan"
            case .defaultSetsPerExercise: "Default sets"
            case .trainingGoalKind: "Training goal"
            case .defaultRestSeconds: "Set rest"
            case .defaultBetweenExerciseRestSeconds: "Exercise rest"
            case .keepScreenAwakeDuringWorkout: "Keep screen awake during workouts"
            case .coachMemory: "Notes for your AI coach"
            case .wantStrengthen: "Muscles to focus"
            case .availableEquipment: "Equipment"
            }
        }
        func value(in s: UserSettings) -> [String] {
            switch self {
            case .weeklyTrainingDays: [String(s.weeklyTrainingDays)]
            case .exercisesPerSession: [String(s.exercisesPerSession)]
            case .defaultSetsPerExercise: [String(s.defaultSetsPerExercise)]
            case .trainingGoalKind: [s.trainingGoalKind.rawValue]
            case .defaultRestSeconds: [String(s.defaultRestSeconds)]
            case .defaultBetweenExerciseRestSeconds: [String(s.defaultBetweenExerciseRestSeconds)]
            case .keepScreenAwakeDuringWorkout: [String(s.keepScreenAwakeDuringWorkout)]
            case .coachMemory: [s.coachMemory]
            case .wantStrengthen: s.wantStrengthen.map(\.rawValue).sorted()
            case .availableEquipment: s.availableEquipment.sorted()
            }
        }
        func valid(_ values: [String]) -> Bool {
            switch self {
            case .wantStrengthen: return Set(values).count == values.count && values.allSatisfy { MuscleGroup(rawValue: $0) != nil }
            case .availableEquipment: return Set(values).count == values.count && values.allSatisfy { EquipmentCategory(rawValue: $0) != nil }
            default: guard values.count == 1 else { return false }
            }
            let v = values[0]
            switch self {
            case .weeklyTrainingDays: return Int(v).map { (1...7).contains($0) } ?? false
            case .exercisesPerSession: return Int(v).map { (1...8).contains($0) } ?? false
            case .defaultSetsPerExercise: return Int(v).map { (1...6).contains($0) } ?? false
            case .defaultRestSeconds: return Int(v).map { (15...300).contains($0) && $0 % 15 == 0 } ?? false
            case .defaultBetweenExerciseRestSeconds: return Int(v).map { (0...600).contains($0) && $0 % 15 == 0 } ?? false
            case .trainingGoalKind: return TrainingGoalKind(rawValue: v) != nil
            case .keepScreenAwakeDuringWorkout: return ["true", "false"].contains(v)
            case .coachMemory: return v.count <= 4000
            default: return false
            }
        }
        func display(_ values: [String]) -> String {
            if values.isEmpty { return NSLocalizedString("All", comment: "") }
            return values.map { value in
                switch self {
                case .trainingGoalKind: return TrainingGoalKind(rawValue: value)?.displayName ?? value
                case .wantStrengthen: return MuscleGroup(rawValue: value)?.displayName ?? value
                case .availableEquipment: return EquipmentCategory(rawValue: value).map { NSLocalizedString($0.displayName, comment: "") } ?? value
                case .keepScreenAwakeDuringWorkout: return NSLocalizedString(value == "true" ? "On" : "Off", comment: "")
                case .defaultRestSeconds, .defaultBetweenExerciseRestSeconds: return value + " s"
                default: return value.isEmpty ? "—" : value
                }
            }.joined(separator: ", ")
        }
    }
    let field: Field
    let values: [String]
    let sourceQuote: String
    var previous: [String] = []

    func apply(to s: inout UserSettings) {
        guard field.valid(values) else { return }
        switch field {
        case .weeklyTrainingDays: s.weeklyTrainingDays = Int(values[0])!
        case .exercisesPerSession: s.exercisesPerSession = Int(values[0])!
        case .defaultSetsPerExercise: s.defaultSetsPerExercise = Int(values[0])!
        case .trainingGoalKind:
            let rest = s.defaultRestSeconds
            s.trainingGoalKind = TrainingGoalKind(rawValue: values[0])!
            s.defaultRestSeconds = rest // Do not silently change a second preference.
        case .defaultRestSeconds: s.defaultRestSeconds = Int(values[0])!
        case .defaultBetweenExerciseRestSeconds: s.defaultBetweenExerciseRestSeconds = Int(values[0])!
        case .keepScreenAwakeDuringWorkout: s.keepScreenAwakeDuringWorkout = values[0] == "true"
        case .coachMemory: s.coachMemory = values[0]
        case .wantStrengthen: s.wantStrengthen = values.compactMap(MuscleGroup.init(rawValue:))
        case .availableEquipment: s.availableEquipment = values
        }
    }
}
/// Offline recognition of explicit weekly-frequency statements. Other preference
/// requests still use the multilingual extractor; nothing is saved before review.
enum WeeklyRoutineRequest {
    static func change(in text: String, settings: UserSettings) -> CoachPreferenceChange? {
        guard !text.contains("?"), !text.contains("？") else { return nil }
        let number = #"([\p{Nd}]+|一|二|两|兩|三|四|五|六|七|one|two|three|four|five|six|seven|ein|eins|zwei|drei|vier|fünf|sechs|sieben|un|une|deux|trois|quatre|cinq|six|sept|uno|una|dos|tres|cuatro|cinco|seis|siete|due|tre|quattro|cinque|sei|sette|um|uma|dois|duas|três|quatro|cinco|seis|sete|один|два|две|три|четыре|пять|шесть|семь|한|두|세|네|다섯|여섯|일곱|واحد|اثنتين|اثنين|ثلاث|ثلاثة|أربع|أربعة|خمس|خمسة|ست|ستة|سبع|سبعة)"#
        let patterns = [
            #"(?:每周|每週|一周|一週|每个星期|每個星期|每星期|每礼拜|每禮拜)\s*(?:训练|訓練|练|練|锻炼|鍛鍊)?\s*"# + number + #"\s*(?:次|天)"#,
            #"(?:週に?|毎週)\s*"# + number + #"\s*(?:回|日)"#,
            #"(?:주|일주일)에?\s*"# + number + #"\s*(?:회|번|일)"#,
            number + #"\s*(?:times?|days?|sessions?|workouts?)\s*(?:a|per|each|every)?\s*week"#,
            number + #"\s*(?:mal|Tage|Einheiten)\s*(?:pro|die|je)\s*Woche"#,
            number + #"\s*(?:fois|jours|séances)\s*par\s*semaine"#,
            number + #"\s*(?:veces|días|sesiones)\s*(?:por|a la)\s*semana"#,
            number + #"\s*(?:volte|giorni|sessioni)\s*(?:a|alla|per)\s*settimana"#,
            number + #"\s*(?:vezes|dias|sessões)\s*(?:por|na)\s*semana"#,
            number + #"\s*(?:раза?|дня|дней|тренировки?)\s*в\s*неделю"#,
            number + #"\s*(?:مرات|أيام)\s*(?:في الأسبوع|أسبوعيًا|أسبوعيا)"#
        ]
        let words: [[String]] = [
            ["一","one","ein","eins","un","une","uno","una","um","uma","один","한","واحد"],
            ["二","两","兩","two","zwei","deux","dos","due","dois","duas","два","две","두","اثنتين","اثنين"],
            ["三","three","drei","trois","tres","tre","três","три","세","ثلاث","ثلاثة"],
            ["四","four","vier","quatre","cuatro","quattro","quatro","четыре","네","أربع","أربعة"],
            ["五","five","fünf","cinq","cinco","cinque","пять","다섯","خمس","خمسة"],
            ["六","six","sechs","seis","sei","шесть","여섯","ست","ستة"],
            ["七","seven","sieben","sept","siete","sette","sete","семь","일곱","سبع","سبعة"]
        ]
        var matches: [(Int, String)] = []
        for clause in text.components(separatedBy: CharacterSet(charactersIn: ".。;；!！\n")) {
            let lower = clause.lowercased()
            if ["this week", "for now", "这周", "這週", "暂时", "暫時", "临时", "臨時", "if i", "如果", "假如"].contains(where: lower.contains) { continue }
            if ["don't", "do not", "not ", "nicht", "ne pas", "no quiero", "non voglio", "não quero", "не хочу", "不想每", "不要每", "不是每", "不想一周", "不要一周", "아니", "لا أريد"].contains(where: lower.contains) { continue }
            for pattern in patterns {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
                for m in regex.matches(in: clause, range: NSRange(clause.startIndex..., in: clause)) {
                    guard let r = Range(m.range(at: 1), in: clause), let full = Range(m.range, in: clause) else { continue }
                    let token = String(clause[r]).lowercased()
                    let digits = token.compactMap(\.wholeNumberValue).map(String.init).joined()
                    let count = Int(digits) ?? words.firstIndex(where: { $0.contains(token) }).map { $0 + 1 }
                    if let count, (1...7).contains(count) { matches.append((count, String(clause[full]))) }
                }
            }
        }
        guard Set(matches.map(\.0)).count == 1, let (count, quote) = matches.first,
              count != settings.weeklyTrainingDays else { return nil }
        return .init(field: .weeklyTrainingDays, values: [String(count)], sourceQuote: quote,
                     previous: [String(settings.weeklyTrainingDays)])
    }
}

struct CoachPreferenceProposal: Hashable {
    var changes: [CoachPreferenceChange]
    var feedback: String? = nil
    var photoData: Data? = nil
    var photoIsGoalComparison = false
    var decision: CoachMemoryProposal.Decision = .pending
}

/// 对话流里的一条消息. assistant 消息可携带一轮生成的 [Plan] —
/// UI 渲染成 DAY 1..N 卡组 (DAY 序号 = plans 数组下标 + 1, 不写进 plan.name).
/// Request-scoped context. Never written to Training Preferences or saved plans.
struct CoachSessionRequest: Codable, Hashable {
    var sourceQuote: String
    var durationMinutes: Int? = nil
    var focusMuscles: [MuscleGroup] = []
    var trainingType: String? = nil
    var equipmentOverride: [String]? = nil

    static func isWeekly(_ text: String) -> Bool {
        let lower = text.lowercased()
        return ["weekly", "per week", "a week", "my week", "each week", "每周", "每週", "一周", "一週", "周计划", "週計畫", "woche", "semaine", "semana", "settimana", "недел", "週間", "毎週", "주간", "매주", "أسبوع"].contains(where: lower.contains)
    }

    static func minutes(in text: String) -> Int? {
        let s = text.lowercased().map { c in c.wholeNumberValue.map(String.init) ?? String(c) }.joined()
        if ["一个半小时", "一個半小時", "1个半小时", "1個半小時"].contains(where: s.contains) { return 90 }
        if ["半小时", "半小時", "half an hour", "half-hour"].contains(where: s.contains) { return 30 }
        let patterns = [
            #"(\d{1,3})\s*[-–]?\s*(?:minutes?|mins?|分钟|分鐘|分間|分|분|minuten|minutos|minuti|минут\p{L}*|دقيقة|دقائق|min)(?![a-z])"#,
            #"(\d(?:[.,]\d+)?)\s*[-–]?\s*(?:hours?|hrs?|小时|小時|時間|시간|stunden|heures?|horas?|ore|час\p{L}*|ساعة|ساعات)(?![a-z])"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let re = try? NSRegularExpression(pattern: pattern),
                  let match = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
                  let range = Range(match.range(at: 1), in: s),
                  let n = Double(s[range].replacingOccurrences(of: ",", with: ".")) else { continue }
            let minutes = Int((n * (index == 0 ? 1 : 60)).rounded())
            if (5...180).contains(minutes) { return minutes }
        }
        return nil
    }

    /// Fast path for clear one-workout requests; the model handles other phrasing.
    static func local(in text: String) -> Self? {
        let lower = text.lowercased()
        guard !isWeekly(text),
              !["don't", "do not", "不想", "不要", "不练", "不練", "no quiero", "ne veux pas", "nicht", "non voglio", "não quero", "не хочу", "하지", "لا أريد"].contains(where: lower.contains),
              !["usually", "always", "prefer", "each session", "every session", "以后", "以後", "每次", "通常", "习惯", "習慣", "habituellement", "normalerweise", "обычно", "いつも", "보통", "عادة"].contains(where: lower.contains),
              !["why ", "enough", "is it safe", "为什么", "為什麼", "够不够", "足够", "suffisant", "ausreichend"].contains(where: lower.contains) else { return nil }
        let workoutWords = ["workout", "session", "train", "routine", "训练", "訓練", "练", "練", "entrenamiento", "séance", "entraînement", "training", "allenamento", "treino", "трениров", "トレーニング", "ワークアウト", "운동", "تمرين", "تدريب"]
        let temporary = ["today", "tonight", "right now", "one-off", "single workout", "今天", "今晚", "临时", "臨時", "这次", "這次", "hoy", "aujourd", "heute", "oggi", "hoje", "сегодня", "今日", "오늘", "اليوم"]
        let duration = minutes(in: text)
        guard workoutWords.contains(where: lower.contains), duration != nil || temporary.contains(where: lower.contains) else { return nil }
        var focus = LocalRoutineRules.parse(text).focusMuscles
        let sections: [(MuscleGroup, [String])] = [
            (.core, ["abs", "core", "腹", "核心", "abdominal", "abdos", "bauch", "addominal", "пресс", "복근", "코어", "بطن"]),
            (.chest, ["chest", "胸", "pecho", "poitrine", "brust", "petto", "peito", "груд", "가슴", "صدر"]),
            (.back, ["back", "背", "espalda", "dos", "rücken", "schiena", "costas", "спин", "등", "ظهر"]),
            (.shoulders, ["shoulder", "肩", "hombro", "épaule", "schulter", "spall", "ombro", "плеч", "어깨", "كتف"]),
            (.arms, ["arms", "手臂", "胳膊", "brazo", "bras", "arme", "bracci", "braço", "рук", "腕", "팔", "ذراع"]),
            (.legs, ["legs", "腿", "pierna", "jambes", "beine", "gambe", "pernas", "ног", "脚", "하체", "다리", "ساق"])
        ]
        if focus.isEmpty {
            for (muscle, words) in sections where words.contains(where: { word in
                if word == "dos" { return lower.range(of: #"(?<![a-z])dos(?![a-z])"#, options: .regularExpression) != nil }
                return lower.contains(word)
            }) { focus.insert(muscle) }
        }
        return .init(sourceQuote: text, durationMinutes: duration, focusMuscles: focus.sorted { $0.rawValue < $1.rawValue })
    }

    func matches(_ exercise: Exercise) -> Bool {
        if trainingType == "strength", ![ExerciseCategory.strength, .hypertrophyFocus, .calisthenics].contains(exercise.category.normalized) { return false }
        if trainingType == "cardio", exercise.category != .cardio { return false }
        if trainingType == "mobility", ![ExerciseCategory.mobility, .stretching].contains(exercise.category.normalized) { return false }
        if trainingType == "hiit", ![ExerciseCategory.cardio, .plyometric, .calisthenics].contains(exercise.category.normalized) { return false }
        return focusMuscles.isEmpty || focusMuscles.contains(.fullBody) || focusMuscles.contains { requested in
            exercise.primaryMuscles.contains { $0 == requested || ($0.section ?? $0) == requested }
        }
    }

    func exerciseCount(settings: UserSettings) -> Int {
        guard let durationMinutes else { return settings.exercisesPerSession }
        let sets = max(1, settings.defaultSetsPerExercise)
        let perExercise = sets * 45 + max(0, sets - 1) * settings.defaultRestSeconds + settings.defaultBetweenExerciseRestSeconds
        return max(1, min(8, Int((Double(durationMinutes * 60 + settings.defaultBetweenExerciseRestSeconds) / Double(max(60, perExercise))).rounded())))
    }
}

struct CoachRequestAnalysis {
    var changes: [CoachPreferenceChange] = []
    var session: CoachSessionRequest? = nil
    var startsWeeklyPlan = false
    var taskKind: CoachTaskKind? = nil
}

enum CoachPhotoKind: String, CaseIterable, Decodable, Sendable {
    case routine, body, meal, label, menu, equipment, records, bug, photo, unknown
    var titleKey: String {
        switch self {
        case .routine: "Training plan"
        case .body: "Body photo"
        case .meal: "Meal"
        case .label: "Nutrition label"
        case .menu: "Menu"
        case .equipment: "Equipment"
        case .records: "Training or health records"
        case .bug: "Report a bug"
        case .photo: "Share or exercise photo"
        case .unknown: "Choose image use"
        }
    }
}

struct CoachPhotoReview: Hashable {
    // Opaque in-memory identity keeps large image bytes out of message hashing.
    let id = UUID()
    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
    let jpeg: Data
    let caption: String?
    var kind: CoachPhotoKind
    var needsChoice = false
    var failed = false
    var possibleKinds: [CoachPhotoKind] = []
    var plans: [Plan] = []
    var candidates: [ImportCandidate] = []
    var meal: MealPhotoEstimate? = nil
    var exerciseIDs: [String] = []
    var exerciseNames: [String] = []
    var extractedText = ""
    var domain = ""

    var clarificationKinds: [CoachPhotoKind] {
        guard needsChoice, !failed else { return [] }
        var seen = Set<CoachPhotoKind>()
        let kinds = possibleKinds.filter { $0 != .unknown && seen.insert($0).inserted }
        return kinds.count >= 2 ? Array(kinds.prefix(3)) : []
    }

    private static func referenceWords(_ value: String) -> Set<String> {
        Set(exerciseSearchWords(value).filter { $0.count > 1 && Int($0) == nil }.map {
            $0.hasSuffix("s") && !$0.hasSuffix("ss") ? String($0.dropLast()) : $0
        })
    }

    /// Retrieval only: the vision model selects exact identities, not a fuzzy automatic import.
    static func catalogCandidates(ocr: String, library: [Exercise]) -> [Exercise] {
        let words = referenceWords
        let policy = ExerciseSelectionPolicy.shared
        var selected: [Exercise] = []
        var seen = Set<String>()
        for line in ocr.components(separatedBy: .newlines) {
            let query = words(line)
            let ranked = library.compactMap { exercise -> (Exercise, Int, Int, Bool)? in
                let name = words(exercise.name)
                let aliases = ((exercise.localizedName.map { Array($0.values) } ?? []) + (exercise.aliases ?? [])).reduce(name) { $0.union(words($1)) }
                let overlap = aliases.intersection(query).count
                guard overlap > 0 else { return nil }
                return (exercise, overlap, name.subtracting(query).count, !name.isEmpty && name.isSubset(of: query))
            }.sorted {
                if $0.3 != $1.3 { return $0.3 }
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                return policy.metadata(for: $0.0).defaultRank < policy.metadata(for: $1.0).defaultRank
            }
            for (exercise, _, _, _) in ranked.prefix(8) where seen.insert(exercise.id).inserted {
                selected.append(exercise)
            }
        }
        return Array(selected.prefix(96))
    }

    static func imageWorkout(ids: [String], names: [String], library: [Exercise], settings: UserSettings, sourceText: String = "") -> Plan? {
        let lookup = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard !ids.isEmpty, ids.count <= 12, ids.count == names.count else { return nil }
        // Missing IDs can be recovered from the existing importer's high-confidence name
        // match. Unknown nonempty IDs and incompatible equipment are never guessed away.
        let resolved = zip(ids, names).compactMap { id, name -> String? in
            let candidateID: String
            if id.isEmpty {
                let candidates = RoutineImageImporter.parseCandidates([name], library: ExerciseSelectionPolicy.shared.sorted(library, favoriteIDs: Set(settings.favoriteExerciseIds)))
                guard candidates.count == 1, candidates[0].confidence == .high,
                      let match = candidates[0].exerciseId else { return nil }
                candidateID = match
            } else { candidateID = id }
            guard let exercise = lookup[candidateID] else { return nil }
            let aliases = [exercise.name] + (exercise.aliases ?? []) + (exercise.localizedName.map { Array($0.values) } ?? [])
            let vocabulary = aliases.reduce(Set<String>()) { $0.union(referenceWords($1)) }
            let source = referenceWords(name)
            guard !source.isEmpty, source.isSubset(of: vocabulary) else { return nil }
            return candidateID
        }
        guard resolved.count == names.count, Set(resolved).count == resolved.count else { return nil }
        let prescriptions = RoutineImageImporter.parseCandidates(sourceText.components(separatedBy: .newlines), library: library)
        let now = Date()
        var plan = Plan(id: "plan-ai-image-" + UUID().uuidString,
                    name: NSLocalizedString("Single workout", comment: ""),
                    steps: resolved.map { id in
                        let exercise = lookup[id]!
                        let source = prescriptions.first { $0.exerciseId == id && $0.confidence == .high }
                        let timed = exercise.tempo == .isometric || [.cardio, .flexibility].contains(exercise.category.normalized)
                        return PlanStep(id: UUID().uuidString, exerciseId: id, sets: source?.sets ?? settings.defaultSetsPerExercise,
                                 reps: timed ? nil : source?.reps ?? (exercise.mechanic == .isolation ? settings.trainingGoal.defaultRepsForIsolation() : settings.trainingGoal.defaultRepsForCompound()),
                                 weight: source?.weight, duration: timed ? 30 : nil,
                                 restBetweenSets: settings.defaultRestSeconds, rest: settings.defaultBetweenExerciseRestSeconds)
                    }, createdAt: now, updatedAt: now, autoGenerated: true, source: .ai)
        plan.preservesExerciseVariants = true
        return safePlans([plan], lookup: lookup)?.first
    }

    static func planningContext(caption: String?, summary: String) -> String {
        // Plan from the report the user actually saw, not hidden vision suggestions
        // that might describe an unseen muscle as underdeveloped.
        [caption, summary, "Treat the visible appearance report as tentative context only. Do not assume unpictured muscles are weak, infer actual strength/recovery, or override saved constraints. Use current training preferences, permitted training history and recovery context; keep training balanced."].compactMap { $0 }.joined(separator: "\n")
    }

    static func safePlans(_ plans: [Plan], lookup: [String: Exercise]) -> [Plan]? {
        guard !plans.isEmpty, plans.count <= 20 else { return nil }
        let canonical = plans.map { ExerciseLibrary.canonicalPlan($0, using: lookup) }
        guard canonical.allSatisfy({ plan in
            !plan.steps.isEmpty && plan.steps.count <= 100 && plan.steps.allSatisfy { step in
                lookup[step.exerciseId]?.id == step.exerciseId && (1...20).contains(step.sets)
                    && (step.reps.map { (1...1000).contains($0) } ?? true)
                    && (step.weight.map { $0.isFinite && (0...5000).contains($0) } ?? true)
                    && (step.duration.map { (0...86400).contains($0) } ?? true)
            }
        }) else { return nil }
        return canonical
    }
}

enum BodyPhotoFocusAreas {
    static func muscles(_ values: [String]?) -> [MuscleGroup] {
        let allowed: [String: MuscleGroup] = ["chest": .chest, "back": .back, "shoulders": .shoulders,
                                              "arms": .arms, "core": .core, "legs": .legs]
        var seen = Set<MuscleGroup>()
        return Array((values ?? []).prefix(20).compactMap { value in
            allowed[value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()]
        }.filter { seen.insert($0).inserted }.prefix(3))
    }
}

struct CoachMessage: Identifiable, Hashable {
    var allowsTextActions = true
    enum Role: Hashable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var text: String
    /// assistant 专用 — 本轮生成的 routine 卡组 (nil = 纯文本消息).
    var plans: [Plan]? = nil
    /// 修订轮对应的上一版 routine, 用于在推荐卡片里标出具体变化.
    var previousPlans: [Plan]? = nil
    var isSingleWorkout = false
    var quotaRootID: String?
    var quotaGoalID: String?
    var photoData: Data? = nil
    /// 深链来源标签 (e.g. "FROM WEEKLY SUMMARY") — 用户气泡顶部的 kicker; nil = 普通消息.
    var sourceKicker: String? = nil
    var preferenceProposal: CoachPreferenceProposal? = nil
    var memoryProposal: CoachMemoryProposal? = nil
    /// Ephemeral report proposal; never changes saved preferences without confirmation.
    var photoReview: CoachPhotoReview? = nil
    var bodyPhotoPlanFocus: String? = nil
    var bodyPhotoFocusMuscles: [MuscleGroup] = []
    var bodyPhotoPlanDecision: Bool? = nil
    /// Set on the preview bubble. Buttons show only while this id is still pending.
    var equipmentSwapProposalId: String? = nil
    /// Set on the success bubble. Undo shows only while this id is still the undo record.
    var equipmentSwapUndoId: String? = nil
    let createdAt: Date

    init(role: Role, text: String, plans: [Plan]? = nil, previousPlans: [Plan]? = nil,
         sourceKicker: String? = nil, photoData: Data? = nil, memoryProposal: CoachMemoryProposal? = nil,
         isSingleWorkout: Bool = false) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
        self.plans = plans
        self.previousPlans = previousPlans
        self.isSingleWorkout = isSingleWorkout
        self.photoData = photoData
        self.memoryProposal = memoryProposal
        self.sourceKicker = sourceKicker
        self.createdAt = Date()
    }
}

/// Coach 对话状态 — DataStore 持有单例实例 (data.coachSession), 视图只读渲染 + 通过
/// DataStore 的 coach* 方法改写. ⚠️ 聊天文本属 PII: 任何字段都不许进 analytics (只报长度/次数/surface).
@MainActor
@Observable
final class CoachSession {
    var quickWorkoutDraft = CoachQuickWorkoutDraft()
    /// 对话流 (user / assistant 交替). "新对话" 清空.
    var messages: [CoachMessage] = []
    /// 生成中 — Composer 禁发 + 对话流尾部渲染诚实等待清单 (绝不做假打字机/假流式).
    var isGenerating = false
    var isAnalyzingImage = false
    /// 等待清单的渐进步骤 (0 上传 → 1 分析 → 2 生成; 最后一步等真实完成才落定).
    /// 文案键复用 AIGeneratingView 那套 ("Uploading your data" / "Analyzing your stats" / "Building your plan").
    var generationStep = 0
    /// 步骤总数 — UI 画清单用.
    static let generationStepCount = 3
    /// 离线/失败回落提示 (本地模板顶包 / 修订失败保留旧版时非 nil), 渲染在结果上方. 每轮开始时清空.
    var fallbackNote: String? = nil
    /// 每轮生成的 [Plan] 快照栈 — 本地版本历史, "捞回旧版"零 LLM 成本. 末尾 == currentRoutines.
    var versionStack: [[Plan]] = []
    /// 最新一轮的结果 — 修订轮以它为基 (CURRENT ROUTINES 块 + reconciliation 回填源). 空 = 还没生成过 (下一轮是首轮).
    var currentRoutines: [Plan] = []
    /// A chat workout has its own revision context; the weekly draft remains intact.
    var currentSessionPlan: Plan? = nil
    var currentSessionRequest: CoachSessionRequest? = nil
    var latestIsSingleWorkout = false
    /// 生成卡 plan.id → 已存副本 planId. 保存时记录; bookmark 态用它反查 —
    /// savePlan 存的是重 id 副本, 纯签名匹配在副本改名后会失灵 (工程评审要求 id 映射优先, 签名只作兜底).
    var savedIdMap: [String: String] = [:]
    /// QA修复①: 上一轮结果是否来自本地模板回落. 回落轮的 currentRoutines 不是 AI 认可的基线 —
    /// 下一轮 (含 Retry) 若按修订轮走, LLM 会被锚死在模板上原样复读却报"已更新".
    /// 约束: 回落轮置 true, 真 AI 成功轮置 false; 修订轮判定必须同时看它 (见 coachGenerate).
    var lastRoundUsedFallback = false
    /// QA修复③: 在途生成轮的身份 token — startCoachGenerate 每轮发新值, 任务收尾用它比对,
    /// 被取消的旧任务不许清掉新任务的句柄. 约束: 只在 startCoachGenerate / reset 里写.
    var quotaRootID: String?
    var quotaGoalID: String?
    var quotaKind: CoachTaskKind?
    var generationToken: UUID? = nil
    var declinedMemoryKeys: Set<String> = []
    /// Preview of a muscle/equipment replacement. Nothing is written until confirm.
    var pendingEquipmentSwap: CoachEquipmentSwap.Proposal?
    /// One-level undo of the last confirmed replacement. Cleared on a new conversation.
    var equipmentSwapUndo: CoachEquipmentSwap.UndoRecord?

    /// "新对话" — 清对话流/版本栈/回落提示, 不动 data.plans (已保存的 routine 是持久产物).
    /// savedIdMap 一并清: key 是旧对话里的生成卡 id, 新对话不会再引用.
    /// ⚠️ 调用方走 DataStore.resetCoachConversation() — 它负责先取消在途生成任务.
    func reset() {
        messages.removeAll()
        declinedMemoryKeys.removeAll()
        versionStack.removeAll()
        currentRoutines.removeAll()
        currentSessionPlan = nil
        currentSessionRequest = nil
        latestIsSingleWorkout = false
        savedIdMap.removeAll()
        fallbackNote = nil
        generationStep = 0
        isGenerating = false
        isAnalyzingImage = false
        lastRoundUsedFallback = false
        generationToken = nil
        quotaRootID = nil; quotaGoalID = nil; quotaKind = nil
        pendingEquipmentSwap = nil
        equipmentSwapUndo = nil
    }
}

// MARK: - DataStore + Coach 修订环 (one-shot, 不做真多轮 — 设计文档 §3)

extension DataStore {
    func rerouteCoachImage(messageID: String, kind: CoachPhotoKind) {
        guard !coachSession.isGenerating,
              let review = coachSession.messages.first(where: { $0.id == messageID })?.photoReview else { return }
        if let index = coachSession.messages.firstIndex(where: { $0.id == messageID }) {
            coachSession.messages[index].photoReview = nil
            coachSession.messages[index].bodyPhotoPlanFocus = nil
            coachSession.messages[index].bodyPhotoFocusMuscles = []
            coachSession.messages[index].bodyPhotoPlanDecision = false
        }
        startCoachGenerate(feedback: review.caption,
            displayText: NSLocalizedString(kind == .unknown ? "Retry" : kind.titleKey, comment: "image purpose"),
            photoData: review.jpeg, photoIntent: kind == .unknown ? nil : kind, skipPreferenceReview: true)
    }

    /// All side effects remain behind the existing destination's explicit confirmation.
    private struct ImageTaskOutput: Codable {
        let kind: CoachTaskKind
        let summary: String
        let plans: [Plan]
        let meal: MealPhotoEstimate?
        let extractedText: String
        let valid: Bool
    }

    func analyzeCoachImage(_ jpeg: Data, caption: String?, intent: CoachPhotoKind? = nil) async {
        let session = coachSession
        let before = session.messages
        let previousPlan = session.currentSessionPlan
        func work(_ resolved: CoachPhotoKind) async -> ImageTaskOutput {
            await analyzeCoachImageUnmetered(jpeg, caption: caption, intent: resolved)
            let last = session.messages.last; let review = last?.photoReview
            let kind: CoachTaskKind = switch review?.kind ?? resolved {
            case .body: .physiqueGoal
            case .meal, .label, .menu: .nutritionImage
            case .equipment: .equipmentImage
            case .records: .recordsImage
            default: .routineImage
            }
            let newPlan = session.currentSessionPlan != previousPlan ? session.currentSessionPlan : nil
            let recognized = review?.kind != .unknown && review?.kind != .photo && review?.kind != .bug
            let valid = DeviceAIExecution.trace?.requests != 0 && review?.needsChoice != true && review?.failed != true
                && (newPlan != nil || review?.meal?.isFood == true || review?.plans.isEmpty == false
                    || (recognized && kind != .routineImage && last?.text.isEmpty == false))
            return ImageTaskOutput(kind:kind, summary:last?.text ?? "", plans:newPlan.map { [$0] } ?? review?.plans ?? [], meal:review?.meal, extractedText:review?.extractedText ?? "", valid:valid)
        }
        func presentLocal(_ kind:CoachPhotoKind) {
            var message = CoachMessage(role:.assistant, text:NSLocalizedString("Review this image",comment:""))
            message.photoReview = CoachPhotoReview(jpeg:jpeg, caption:caption, kind:kind)
            session.messages.append(message); session.isGenerating = false; session.generationStep = 0
        }
        if let intent, [.photo,.bug].contains(intent) { presentLocal(intent); return }
        do {
            let evidence = await Task.detached(priority:.userInitiated) { UIImage(data:jpeg).map { RoutineImageImporter.evidence(from:$0) } }.value
            if (intent == .routine || (intent == nil && caption == nil)),
               CoachPhotoReview.safePlans(evidence?.plans ?? [], lookup:exById) != nil {
                await analyzeCoachImageUnmetered(jpeg, caption:caption, intent:.routine); return // local QR, no AI allowance
            }
            var resolved = intent
            if resolved == nil {
                guard await aiAccess.canClassifyImage(isPro:settings.isPro) else {
                    var message = CoachMessage(role:.assistant, text:NSLocalizedString("Choose image use",comment:""))
                    var review = CoachPhotoReview(jpeg:jpeg,caption:caption,kind:.unknown)
                    review.needsChoice = true; review.possibleKinds = [.photo,.bug,.routine]; message.photoReview = review
                    session.messages.append(message); session.isGenerating = false; session.generationStep = 0; return
                }
                // Routing alone returns no analysis/result; actual work must be admitted first.
                let classification = try await aiAccess.auxiliary {
                    try await AIWorkoutService.shared.understandCoachImage(jpeg, caption:caption, ocr:evidence?.text ?? "", hasPlanQR:false, forced:nil, library:userLibrary, classifyOnly:true)
                }
                resolved = classification.resolvedKind
                if !classification.needsClarification, [.photo,.bug].contains(classification.resolvedKind) { presentLocal(classification.resolvedKind); return }
                if classification.needsClarification || classification.resolvedKind == .unknown {
                    var review = CoachPhotoReview(jpeg:jpeg, caption:caption, kind:classification.resolvedKind)
                    review.needsChoice = true; review.possibleKinds = (classification.possibleKinds ?? []).compactMap(CoachPhotoKind.init(rawValue:))
                    var message = CoachMessage(role:.assistant, text:NSLocalizedString("Review this image", comment:"")); message.photoReview = review
                    session.messages.append(message); session.isGenerating = false; session.generationStep = 0; return
                }
            }
            guard let resolved else { throw WorkoutSourceError.unreadable }
            let kind: CoachTaskKind = switch resolved {
            case .body: .physiqueGoal
            case .meal, .label, .menu: .nutritionImage
            case .equipment: .equipmentImage
            case .records: .recordsImage
            default: .routineImage
            }
            let output: ImageTaskOutput = try await aiAccess.perform(kind:kind, isPro:settings.isPro,
                operationID:session.generationToken?.uuidString ?? UUID().uuidString, image:true,
                capacity:settings.isPro || kind != .routineImage || plans.count < Self.freeSavedPlansLimit,
                valid: { $0.valid }, summary: { $0.summary }) {
                    let output = await work(resolved)
                    if !output.plans.isEmpty && !canSaveImportedPlans(output.plans) { throw DeviceAIQuotaError.capacity }
                    return output
                }
            if output.valid {
                rememberCoachQuota(kind:kind)
                if let index = session.messages.indices.last, session.messages[index].bodyPhotoPlanFocus != nil {
                    session.messages[index].quotaRootID = session.quotaRootID
                    session.messages[index].quotaGoalID = session.quotaGoalID
                }
            }
        } catch {
            session.messages = before; session.currentSessionPlan = previousPlan; finishCoachAccessFailure(error)
        }
    }

    private func analyzeCoachImageUnmetered(_ jpeg: Data, caption: String?, intent: CoachPhotoKind? = nil) async {
        defer { if !Task.isCancelled { coachSession.isGenerating = false; coachSession.generationStep = 0 } }
        var review = CoachPhotoReview(jpeg: jpeg, caption: caption, kind: intent ?? .unknown)
        do {
            let evidence = await Task.detached(priority: .userInitiated) {
                UIImage(data: jpeg).map { RoutineImageImporter.evidence(from: $0) }
            }.value
            try Task.checkCancellation()
            let plans = evidence?.plans ?? []
            let ocr = evidence?.text ?? ""
            review.extractedText = ocr
            if evidence?.multiplePlanQRCodes == true, intent == nil || intent == .routine {
                review.needsChoice = true
                var message = CoachMessage(role: .assistant, text: NSLocalizedString("Several plan codes found. Upload one share card at a time.", comment: ""))
                message.photoReview = review; coachSession.messages.append(message); return
            }
            // Exact, locally decoded plan payloads need no paid vision guess unless a
            // caption specifies another use. Generic upload sends no synthetic body goal.
            if (intent == .routine || (intent == nil && caption == nil)),
               let safe = CoachPhotoReview.safePlans(plans, lookup: exById) {
                review.kind = .routine; review.plans = safe
                var message = CoachMessage(role: .assistant, text: NSLocalizedString("Training plans found. Review before adding.", comment: ""))
                message.photoReview = review; coachSession.messages.append(message)
                return
            }
            if intent == .body {
                let analysis = try await AIWorkoutService.shared.analyzeBodyPhoto(jpeg, goal: caption ?? "Balanced muscle development")
                try Task.checkCancellation()
                var message = CoachMessage(role: .assistant, text: analysis.summary)
                message.photoReview = review
                if analysis.canSuggestPlan {
                    message.bodyPhotoPlanFocus = CoachPhotoReview.planningContext(caption: caption, summary: analysis.summary)
                    message.bodyPhotoFocusMuscles = BodyPhotoFocusAreas.muscles(analysis.focusAreas)
                }
                coachSession.messages.append(message); return
            }
            if intent == .meal || intent == .label {
                let meal = try await AIWorkoutService.shared.analyzeMealPhoto(jpeg, language: LanguageManager.currentLanguageCode, caption: caption)
                try Task.checkCancellation()
                guard meal.isFood else { throw URLError(.cannotParseResponse) }
                review.meal = meal
                var message = CoachMessage(role: .assistant, text: meal.foods)
                message.photoReview = review; coachSession.messages.append(message); return
            }
            let result = try await AIWorkoutService.shared.understandCoachImage(jpeg, caption: caption, ocr: ocr,
                hasPlanQR: !plans.isEmpty, forced: intent, library: userLibrary)
            try Task.checkCancellation()
            review.kind = intent ?? result.resolvedKind
            review.needsChoice = result.needsClarification || review.kind == .unknown
            review.extractedText = result.extractedText?.isEmpty == false ? result.extractedText! : ocr
            review.domain = result.domain ?? ""
            review.exerciseIDs = result.exerciseIDs ?? []
            review.exerciseNames = result.exerciseNames ?? []
            review.possibleKinds = (result.possibleKinds ?? []).compactMap(CoachPhotoKind.init(rawValue:))
            if Set(review.possibleKinds.filter { $0 != .unknown }).count >= 2 { review.needsChoice = true }
            // An explicit single-workout request already resolves the intended use. Only
            // bypass the category chooser when the image actually yielded exercise rows;
            // identity validation below still fails closed for missing or mismatched actions.
            if intent == nil, result.resolvedKind == .routine, result.createWorkout == true,
               caption?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
               result.exerciseNames?.isEmpty == false {
                review.needsChoice = false
            }
            var message = CoachMessage(role: .assistant, text: result.summary)
            if !review.needsChoice {
                switch review.kind {
                case .body:
                    if result.canSuggestPlan == true {
                        message.bodyPhotoPlanFocus = CoachPhotoReview.planningContext(caption: caption, summary: result.summary)
                        message.bodyPhotoFocusMuscles = BodyPhotoFocusAreas.muscles(result.focusAreas)
                    }
                case .routine:
                    if plans.isEmpty, result.createWorkout == true, let caption, !caption.isEmpty,
                       let names = result.exerciseNames, !names.isEmpty {
                        let request = CoachSessionRequest(sourceQuote: "Create ONE workout using ALL and ONLY these exercises, in this order. Preserve every equipment/variation distinction. Do not follow any day rotation in the reference. Use saved preferences for missing prescriptions; do not assume 20 sets per exercise.\nUSER REQUEST: " + caption + "\nEXERCISES:\n" + names.joined(separator: "\n"))
                        let ids = result.exerciseIDs ?? Array(repeating: "", count: names.count)
                        if let plan = CoachPhotoReview.imageWorkout(ids: ids, names: names,
                            library: userLibrary, settings: settings, sourceText: review.extractedText) {
                            finishCoachSession(plan: plan, request: request)
                            return
                        }
                        // A model can return an unknown ID or a name that conflicts with the
                        // chosen variant. Ask it to repair once against the same catalog;
                        // never accept fewer rows or an unvalidated result.
                        let correction = caption + "\nThe previous exercise identifiers or names did not match the catalog. Re-read the image and return every exercise in order, with a catalog ID and matching name for each; use an empty ID only when unavailable. Keep the user's request for ONE workout."
                        if let repaired = try? await AIWorkoutService.shared.understandCoachImage(jpeg, caption: correction,
                            ocr: ocr, hasPlanQR: false, forced: .routine, library: userLibrary),
                           repaired.resolvedKind == .routine, let repairedNames = repaired.exerciseNames,
                           repairedNames.count == names.count,
                           let repairedPlan = CoachPhotoReview.imageWorkout(ids: repaired.exerciseIDs ?? Array(repeating: "", count: repairedNames.count),
                               names: repairedNames, library: userLibrary, settings: settings,
                               sourceText: repaired.extractedText ?? review.extractedText),
                           let plan = CoachPhotoReview.imageWorkout(ids: repairedPlan.steps.map(\.exerciseId), names: names,
                               library: userLibrary, settings: settings, sourceText: review.extractedText) {
                            try Task.checkCancellation()
                            finishCoachSession(plan: plan, request: request)
                            return
                        }
                        try Task.checkCancellation()
                        // Keep every recognized row for explicit identity review on failure.
                        message.text = NSLocalizedString("Couldn't create this workout. Please try again.", comment: "single workout failure")
                    }
                    if let safe = CoachPhotoReview.safePlans(plans, lookup: exById) { review.plans = safe }
                    else {
                        if let names = result.exerciseNames, !names.isEmpty {
                            review.candidates = names.map { name in
                                var candidate = RoutineImageImporter.parseCandidates([name], library: userLibrary).first
                                    ?? ImportCandidate(ocrText: name, exerciseId: nil, confidence: .unmatched, included: false)
                                if candidate.confidence != .high { candidate.included = false }
                                return candidate
                            }
                        } else {
                            review.candidates = RoutineImageImporter.parseCandidates(review.extractedText.components(separatedBy: .newlines), library: userLibrary).map { candidate in
                                var candidate = candidate
                                if candidate.confidence != .high { candidate.included = false }
                                return candidate
                            }
                        }
                        if review.candidates.isEmpty { review.failed = true }

                    }
                case .meal, .label:
                    review.meal = try await AIWorkoutService.shared.analyzeMealPhoto(jpeg, language: LanguageManager.currentLanguageCode, caption: caption)
                    guard review.meal?.isFood == true else { throw URLError(.cannotParseResponse) }
                    message.text = review.meal?.foods ?? result.summary
                case .equipment:
                    let candidates = RoutineImageImporter.parseCandidates(result.exerciseNames ?? [], library: userLibrary)
                    review.exerciseIDs = Array(Set(candidates.compactMap(\.exerciseId))).sorted().prefix(6).map { $0 }
                default: break
                }
            }
            try Task.checkCancellation()
            message.photoReview = review
            coachSession.messages.append(message)
        } catch {
            guard !Task.isCancelled else { return }
            review.needsChoice = true
            let evidenceError = AIWorkoutService.mealEvidenceError(error)
            review.failed = evidenceError == nil
            let messageText = error is CancellationError
                ? NSLocalizedString("AI permission wasn't granted. Your image wasn't sent.", comment: "")
                : evidenceError ?? NSLocalizedString("Image analysis is unavailable. Try again.", comment: "")
            var message = CoachMessage(role: .assistant, text: messageText)
            message.photoReview = review
            coachSession.messages.append(message)
        }
    }

    func resolveBodyPhotoPlan(messageID: String, accept: Bool) {
        guard !coachSession.isGenerating,
              let index = coachSession.messages.firstIndex(where: { $0.id == messageID }),
              coachSession.messages[index].bodyPhotoPlanDecision == nil,
              let focus = coachSession.messages[index].bodyPhotoPlanFocus else { return }
        coachSession.messages[index].bodyPhotoPlanDecision = accept
        guard accept else { return }
        coachSession.quotaRootID = coachSession.messages[index].quotaRootID
        coachSession.quotaGoalID = coachSession.messages[index].quotaGoalID
        coachSession.quotaKind = .physiqueGoal
        startCoachGenerate(feedback: focus, displayText: NSLocalizedString("Create a plan from these suggestions", comment: ""),
                           surface: "body_photo_report", skipPreferenceReview: true, forceRegeneration: true, explicitTaskKind:.physiqueGoal)
    }

    /// Coach 对话一轮生成的非 async 入口 — 任务由 DataStore 持有: 切 tab / 视图销毁不取消,
    /// 结果落回 coachSession (工程评审钦点). UI 一律调这个, 不要自己包 Task {}.
    /// - parameter feedback: 用户这轮说的话 (首轮 = 初始诉求, 修订轮 = 修改意见). nil/空 = 无言生成 (如深链自动触发).
    /// - parameter displayText: QA修复⑧ — 用户气泡显示的本地化短语; nil = 直接显示 feedback.
    ///   深链/建议 Apply 的 feedback 是英文 prompt 工程指令, 只进 prompt 不上屏.
    /// - parameter onlyModify: 定向修订目标 ("Day 2" / 动作名) — 长按动作行的引用式反馈传入.
    /// - parameter sourceKicker: 深链来源标签 (e.g. "FROM WEEKLY SUMMARY"), 渲染在用户气泡顶部.
    func startCoachGenerate(feedback: String? = nil,
                            displayText: String? = nil,
                            onlyModify: String? = nil,
                            sourceKicker: String? = nil,
                            surface: String = "coach_chat",
                            photoData: Data? = nil,
                            photoIsGoalComparison: Bool = false,
                            photoIntent: CoachPhotoKind? = nil,
                            skipPreferenceReview: Bool = false,
                            appendUserMessage: Bool = true,
                            forceRegeneration: Bool = false,
                            explicitSessionRequest: CoachSessionRequest? = nil,
                            explicitTaskKind: CoachTaskKind? = nil) {
        guard !coachSession.isGenerating else { return }
        // User-initiated requests pass through UpgradePrompt in their presenting
        // scene. Device-local admission below decides free experiences; existing paid rights have no experimental daily cap.
        // QA修复③: isGenerating 必须在进 Task 前同步置位 — 之前在 Task 体内才置 true,
        // 同一 runloop 双调用都能过上面的 guard, 两个生成任务并发互踩.
        coachSession.isGenerating = true
        let token = UUID()
        coachSession.generationToken = token
        coachGenerateTask = Task { [weak self] in
            await self?.coachGenerate(feedback: feedback, displayText: displayText,
                                      onlyModify: onlyModify,
                                      sourceKicker: sourceKicker, surface: surface,
                                      preflighted: true, photoData: photoData,
                                      photoIsGoalComparison: photoIsGoalComparison, photoIntent: photoIntent,
                                      skipPreferenceReview: skipPreferenceReview,
                                      appendUserMessage: appendUserMessage,
                                      forceRegeneration: forceRegeneration, explicitSessionRequest: explicitSessionRequest, explicitTaskKind: explicitTaskKind)
            await MainActor.run { [weak self] in
                // QA修复③: 身份比对 — 只有 token 仍是本轮的才清句柄;
                // 被取消的旧任务跑完 completion 时不许清掉新任务的句柄.
                guard let self, self.coachSession.generationToken == token else { return }
                self.coachGenerateTask = nil
            }
        }
    }

    /// "新对话" — 取消在途生成 + 清会话状态. 不动 data.plans.
    func resetCoachConversation() {
        coachGenerateTask?.cancel()
        coachGenerateTask = nil
        coachSession.reset()
    }

    /// 修订环核心 (async 本体):
    ///   - 首轮 (currentRoutines 空): 走既有 generateAIRoutines 管线 (count = weeklyTrainingDays 夹 1...7,
    ///     在它内部), feedback 作 focusNote 注入 PRIORITY 行; 失败回落本地模板 (usedFallback 语义沿用).
    ///   - 修订轮: AIWorkoutService.reviseRoutines (CURRENT ROUTINES + USER FEEDBACK [+ ONLY MODIFY]),
    ///     响应过 reconcileRevisedRoutines (缺天/多天对齐, 未提及的天用上一版回填) + applyScience 兜底;
    ///     失败 → 保留上一版原样 + fallbackNote (比换一批本地模板更不吓人).
    /// 每轮结束: push versionStack + append assistant 消息 (text = LLM rationale 或一句本地小结) + 清生成态.
    func coachGenerate(feedback: String?,
                       displayText: String? = nil,
                       onlyModify: String? = nil,
                       sourceKicker: String? = nil,
                       surface: String = "coach_chat",
                       preflighted: Bool = false,
                       photoData: Data? = nil,
                       photoIsGoalComparison: Bool = false,
                       photoIntent: CoachPhotoKind? = nil,
                       skipPreferenceReview: Bool = false,
                       appendUserMessage: Bool = true,
                       forceRegeneration: Bool = false,
                       explicitSessionRequest: CoachSessionRequest? = nil,
                       explicitTaskKind: CoachTaskKind? = nil) async {
        let session = coachSession
        session.isAnalyzingImage = photoData != nil
        defer { if !Task.isCancelled { session.isAnalyzingImage = false } }
        // QA修复③: startCoachGenerate 已同步置 isGenerating 再进 Task (preflighted=true),
        // 此时守卫要放行自己; 罕见的直调路径 (preflighted=false) 保持原守卫语义.
        guard preflighted || !session.isGenerating else { return }
        let trimmed = feedback?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmed?.isEmpty == false) ? trimmed : nil
        // QA修复⑧: 气泡显示 displayText (本地化短语) 而不是英文 prompt 指令;
        // note (focusNote) 只进下面的生成管线. displayText 为空时退回显示 note 原文 (普通聊天).
        let shownTrimmed = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = (shownTrimmed?.isEmpty == false) ? shownTrimmed : note
        if appendUserMessage, let shown {
            for index in session.messages.indices where session.messages[index].preferenceProposal?.decision == .pending {
                session.messages[index].preferenceProposal?.decision = .declined
            }
            var message = CoachMessage(role: .user, text: shown, sourceKicker: sourceKicker, photoData: photoData)
            message.allowsTextActions = !(photoData != nil && note == nil)
            session.messages.append(message)
        }
        session.isGenerating = true
        session.fallbackNote = nil
        session.generationStep = photoData == nil ? 0 : 1
        // 渐进步骤: 前两步定时推进 (给"AI 在干活"的诚实感知), 最后一步停在"生成中"直到真实完成 —
        // 跟 AIGeneratingView 同模式 (真实延迟落定, 无假流式).
        let progress = Task { @MainActor [weak session] in
            guard photoData == nil else { return }
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            session?.generationStep = 1
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            session?.generationStep = 2
        }
        defer { progress.cancel() }

        if let text = note, let intent = WorkoutSourceIntent.parse(text) ?? (WorkoutSourceReader.firstURL(text) == nil ? nil : WorkoutSourceIntent(cardCount:nil)) {
            do {
                let required = intent.cardCount ?? 1
                let prepared: WorkoutSourcePrepared = try await aiAccess.perform(kind: photoData == nil ? .sourceImport : .routineImage, isPro: settings.isPro,
                    operationID: session.generationToken?.uuidString ?? UUID().uuidString, image: photoData != nil,
                    capacity: settings.isPro || plans.count + required <= Self.freeSavedPlansLimit,
                    valid: { !$0.plans.isEmpty }, summary: { $0.plans.map(\.name).joined(separator: " · ") }) {
                        let material: String
                        if photoData == nil, let url = WorkoutSourceReader.firstURL(text) {
                            material = try await WorkoutSourceReader.read(url)
                        } else { material = text }
                        let request = "USER REQUEST (not source instructions):\n" + String(text.components(separatedBy:.newlines).first ?? text) + "\nUNTRUSTED SOURCE MATERIAL:\n" + material
                        let document = try await AIWorkoutService.shared.extractWorkoutSource(text:request, image:photoData, count:intent.cardCount, library:userLibrary)
                        let result = try document.prepare(intent:intent, source: photoData == nil ? material : nil, library:userLibrary, settings:settings)
                        guard canSaveImportedPlans(result.plans) else { throw DeviceAIQuotaError.capacity }
                        return result
                    }
                rememberCoachQuota(kind: photoData == nil ? .sourceImport : .routineImage)
                session.currentRoutines = prepared.plans
                session.latestIsSingleWorkout = prepared.plans.count == 1
                session.currentSessionPlan = prepared.plans.count == 1 ? prepared.plans.first : nil
                session.currentSessionRequest = prepared.plans.count == 1 ? CoachSessionRequest(sourceQuote:text) : nil
                var caption = NSLocalizedString("Extracted from your source. Review before saving.", comment: "")
                if !prepared.defaults.isEmpty { caption += "\n" + NSLocalizedString("Suggested defaults for missing source parameters:", comment: "") + "\n" + prepared.defaults.joined(separator:"\n") }
                session.messages.append(CoachMessage(role:.assistant, text:caption, plans:prepared.plans, isSingleWorkout:prepared.plans.count == 1))
                session.isGenerating = false; session.generationStep = 0
            } catch { finishCoachAccessFailure(error) }
            return // Never fall through to weekly design or local plan balancing.
        }

        var resolvedTaskKind = explicitTaskKind
        var singleRequest = explicitSessionRequest ?? (photoData == nil ? shown.flatMap(CoachSessionRequest.local) : nil)
        var startsWeeklyPlan = explicitSessionRequest == nil && (forceRegeneration || surface == "training_preferences"
            || surface == "confirmed_preferences" || shown.map(CoachSessionRequest.isWeekly) == true)
        if explicitSessionRequest == nil, photoData == nil, !skipPreferenceReview, let userText = shown, !userText.isEmpty {
            let local = WeeklyRoutineRequest.change(in: userText, settings: settings)
            let changes: [CoachPreferenceChange]
            if let local { changes = [local] }
            else if singleRequest != nil { changes = [] }
            else {
                let analysis = (try? await aiAccess.auxiliary { try await AIWorkoutService.shared.coachRequestAnalysis(text: userText, settings: settings,
                    hasSingleWorkout: session.latestIsSingleWorkout) }) ?? .init()
                changes = analysis.changes
                resolvedTaskKind = resolvedTaskKind ?? analysis.taskKind
                if photoData == nil, !startsWeeklyPlan { singleRequest = analysis.session }
                startsWeeklyPlan = startsWeeklyPlan || analysis.startsWeeklyPlan
            }
            guard !Task.isCancelled else { return }
            if !changes.isEmpty {
                var message = CoachMessage(role: .assistant, text: NSLocalizedString("Update Training Preferences?", comment: ""))
                message.preferenceProposal = .init(changes: changes, feedback: note, photoData: photoData,
                                                   photoIsGoalComparison: photoIsGoalComparison)
                session.messages.append(message)
                session.generationStep = 0
                session.isGenerating = false
                return // Confirmation must precede both preference writes and generation.
            }
        }
        guard !Task.isCancelled else { return }

        // Follow-up edits stay attached to the single workout, independently of the weekly draft.
        let revisingSingle = singleRequest == nil && session.latestIsSingleWorkout && !startsWeeklyPlan
        if revisingSingle, photoData == nil, var previous = session.currentSessionRequest {
            if let note {
                previous.sourceQuote = String((previous.sourceQuote + "\nLATEST EDIT: " + note).suffix(6000))
                previous.durationMinutes = CoachSessionRequest.minutes(in: note) ?? previous.durationMinutes
                let focus = LocalRoutineRules.parse(note)
                if !focus.focusMuscles.isEmpty { previous.focusMuscles = Array(focus.focusMuscles) }
                else if !focus.focusSections.isEmpty { previous.focusMuscles = Array(focus.focusSections) }
            }
            singleRequest = previous
        }
        if photoData == nil, !startsWeeklyPlan, let request = singleRequest {
            var payload = buildAIPayload()
            payload.focusNote = request.sourceQuote
            if let equipment = request.equipmentOverride {
                payload.selectionEquipment = equipment
                payload.trainingEnvironment = TrainingEnvironment.forEquipmentOverride(equipment, current: settings.trainingEnvironment)
                if equipment == ["body_only"] { payload.trainingEnvironment = .bodyweight }
            }
            payload.trainingSessionMinutes = request.durationMinutes ?? settings.trainingSessionMinutes
            payload.sessionTransitionRestSeconds = settings.defaultBetweenExerciseRestSeconds
            payload.sessionSetRestSeconds = settings.defaultRestSeconds
            let previous = revisingSingle ? session.currentSessionPlan : nil
            let continuing = revisingSingle && session.quotaRootID != nil
            let kind = continuing ? (session.quotaKind ?? .singleWorkout) : (resolvedTaskKind ?? .singleWorkout)
            let sourceRevision = continuing && previous?.preservesExerciseVariants == true && (kind == .sourceImport || kind == .routineImage)
            let plan: Plan?
            do {
                plan = try await aiAccess.perform(kind: kind, isPro: settings.isPro,
                    operationID: session.generationToken?.uuidString ?? UUID().uuidString,
                    goalID: continuing ? session.quotaGoalID : nil, parentID: continuing ? session.quotaRootID : nil,
                    capacity: settings.isPro || previous != nil || plans.count < Self.freeSavedPlansLimit,
                    valid: { $0?.steps.isEmpty == false && (sourceRevision ? $0?.steps != previous?.steps : $0 != previous) }, summary: { $0?.name ?? "" }) {
                        if sourceRevision, let previous {
                            return try await AIWorkoutService.shared.reviseImportedWorkout(previous,feedback:note ?? "",library:userLibrary,settings:settings)
                        }
                        return await AIWorkoutService.shared.generateToday(payload: payload, library: userLibrary,
                            maxExercises: request.exerciseCount(settings: settings), surface: "coach_single_workout",
                            sessionRequest: request, previousSession: previous, onlyModify: onlyModify)
                    }
                if sourceRevision, plan?.steps == previous?.steps { finishUnchangedRevision(memorySource:nil); return }
                rememberCoachQuota(kind: kind)
            } catch { finishCoachAccessFailure(error); return }
            guard !Task.isCancelled else { return }
            finishCoachSession(plan: plan, request: request, previous: previous)
            return
        }

        if let photoData, !photoIsGoalComparison {
            await analyzeCoachImage(photoData, caption: note, intent: photoIntent)
            return
        }
        if let photoData {
            do {
                let analysis = try await aiAccess.perform(kind: .physiqueGoal, isPro: settings.isPro,
                    operationID: session.generationToken?.uuidString ?? UUID().uuidString, image: true,
                    valid: { $0.canSuggestPlan }, summary: { $0.summary }) {
                        try await AIWorkoutService.shared.analyzeBodyPhoto(photoData,
                            goal: note ?? "Balanced muscle development", compareToGoalReference: photoIsGoalComparison)
                    }
                guard !Task.isCancelled else { return }
                rememberCoachQuota(kind:.physiqueGoal)
                var report = CoachMessage(role: .assistant, text: analysis.summary)
                report.quotaRootID = session.quotaRootID; report.quotaGoalID = session.quotaGoalID
                if analysis.canSuggestPlan {
                    report.bodyPhotoPlanFocus = CoachPhotoReview.planningContext(caption: note, summary: analysis.summary)
                    report.bodyPhotoFocusMuscles = BodyPhotoFocusAreas.muscles(analysis.focusAreas)
                }
                session.messages.append(report)
                session.isGenerating = false
                session.generationStep = 0
                return // The report never starts plan generation without an explicit Yes.
            } catch {
                guard !Task.isCancelled else { return }
                let message = NSLocalizedString(error is CancellationError
                    ? "AI permission wasn't granted. Your image wasn't sent."
                    : "Couldn't analyze this photo. Your routines are unchanged. Please try again.", comment: "")
                session.messages.append(CoachMessage(role: .assistant, text: message))
                session.fallbackNote = message
                session.isGenerating = false
                session.generationStep = 0
                return
            }
        }

        // QA修复①: 回落轮的结果只是本地模板顶包, 不是 AI 认可的基线 — 上一轮回落时下一轮
        // (含 Retry 原参重发) 必须重走首轮生成管线, 否则修订轮会把 LLM 锚死在模板上原样复读.
        let isRevision = !forceRegeneration && !startsWeeklyPlan && surface != "training_preferences"
            && session.currentRoutines.count == max(1, min(7, settings.weeklyTrainingDays))
            && !session.currentRoutines.isEmpty && !session.lastRoundUsedFallback
        if !isRevision {
            let kind = resolvedTaskKind ?? .weeklyPlan
            let photoContinuation = surface == "body_photo_report" && kind == .physiqueGoal && session.quotaRootID != nil
            let (plans, usedFallback) = await generateAIRoutines(focusNote: note, surface: surface,
                taskKind: kind, operationID: session.generationToken?.uuidString ?? UUID().uuidString,
                goalID:photoContinuation ? session.quotaGoalID : nil, parentID:photoContinuation ? session.quotaRootID : nil)
            guard !Task.isCancelled else { return }
            if plans.isEmpty, let notice = aiAccess.notice { finishCoachAccessFailure(DeviceAITextError(message: notice)); return }
            if !usedFallback { rememberCoachQuota(kind: kind) }
            finishCoachRound(plans: plans, usedFallback: usedFallback, isRevision: false, memorySource: skipPreferenceReview ? nil : feedback)
        } else {
            let previous = session.currentRoutines
            let kind = session.quotaKind ?? resolvedTaskKind ?? .weeklyPlan
            do {
                let revised: [Plan]? = try await aiAccess.perform(kind: kind, isPro: settings.isPro,
                    operationID: session.generationToken?.uuidString ?? UUID().uuidString,
                    goalID: session.quotaGoalID, parentID: session.quotaRootID,
                    capacity: settings.isPro || previous.allSatisfy { isCoachPlanSaved($0) } || previous.count <= max(0, Self.freeSavedPlansLimit - plans.count),
                    valid: { $0?.isEmpty == false && $0 != previous }, summary: { $0?.map(\.name).joined(separator: " · ") ?? "" }) {
                        guard let raw = await AIWorkoutService.shared.reviseRoutines(payload: buildAIPayload(), library: userLibrary,
                            current: previous, feedback: note ?? "", onlyModify: onlyModify,
                            maxExercises: settings.exercisesPerSession, surface: surface), !raw.isEmpty else { return nil }
                        var reconciled = DataStore.reconcileRevisedRoutines(raw, previous: previous).map { applyScienceToCoachPlan($0) }
                        let focus = LocalRoutineRules.parse([settings.coachMemory, note ?? ""].joined(separator: "\n"))
                        if !focus.focusMuscles.isEmpty {
                            let indices = reconciled.indices.filter { reconciled[$0] != previous[$0] }
                            let targeted = LocalRoutineRules.apply(to: indices.map { reconciled[$0] }, intent: focus, settings: settings, exById: exById)
                            for (index, plan) in zip(indices, targeted) { reconciled[index] = plan }
                        }
                        return reconciled
                    }
                guard !Task.isCancelled else { return }
                if let revised, revised != previous {
                    rememberCoachQuota(kind: kind)
                    finishCoachRound(plans: revised, usedFallback: false, isRevision: true, memorySource: skipPreferenceReview ? nil : feedback)
                } else { finishUnchangedRevision(memorySource: skipPreferenceReview ? nil : feedback) }
            } catch { finishCoachAccessFailure(error) }
        }
    }

    private func rememberCoachQuota(kind: CoachTaskKind) {
        guard let saved = aiAccess.lastSuccessful else { return }
        coachSession.quotaRootID = saved.parentID ?? saved.jobID
        coachSession.quotaGoalID = saved.goalID ?? saved.jobID
        coachSession.quotaKind = kind
    }

    private func finishCoachAccessFailure(_ error: Error) {
        coachSession.messages.append(CoachMessage(role: .assistant, text: error.localizedDescription))
        coachSession.isGenerating = false; coachSession.generationStep = 0
    }

    /// Ready to start, but not saved. Keep weekly drafts, preferences and save quota untouched.
    func finishCoachSession(plan: Plan?, request: CoachSessionRequest, previous: Plan? = nil) {
        let session = coachSession
        defer { session.isGenerating = false; session.generationStep = 0 }
        guard var plan, !plan.steps.isEmpty,
              plan.steps.allSatisfy({ step in exById[step.exerciseId].map(request.matches) == true }) else {
            let message = NSLocalizedString("Couldn't create this workout. Please try again.", comment: "single workout failure")
            session.messages.append(CoachMessage(role: .assistant, text: message))
            session.fallbackNote = message
            return
        }
        // A focused session intentionally permits more than two movements for one muscle.
        // Do not run the weekly full-body balancing pass here.
        if session.quotaKind != .sourceImport && session.quotaKind != .routineImage {
            plan.steps = plan.steps.map { suggestingMissingParameters(for:$0) }
        }
        var constraints = plan.constraints ?? []
        if let minutes = request.durationMinutes {
            constraints.removeAll { $0.kind == .duration }
            constraints.append(.init(kind: .duration, value: String(minutes),
                label: String(format: NSLocalizedString("About %d min", comment: "approximate workout target"), minutes)))
        }
        if !constraints.isEmpty { plan.constraints = constraints }
        Task { await ExerciseDemoService.shared.prefetch(plan.steps.map(\.exerciseId), priority: true) }
        session.currentSessionPlan = plan
        session.currentSessionRequest = request
        session.latestIsSingleWorkout = true
        session.fallbackNote = nil
        session.messages.append(CoachMessage(role: .assistant,
            text: NSLocalizedString("Your workout is ready.", comment: "single workout ready"),
            plans: [plan], previousPlans: previous.map { [$0] }, isSingleWorkout: true))
    }

    /// 修订轮"没有实际变化"的收尾 (QA修复⑦) — 修订失败 与 reconcile 后跟上一版全等 共用:
    /// 保留上一版原样, 不 push versionStack (没有新版本), assistant 消息诚实说明"没改动".
    /// 约束: 不新增 Localizable key — 复用既有 fallbackNote 文案 (语义 = 计划保持原样).
    private func finishUnchangedRevision(memorySource: String? = nil) {
        let session = coachSession
        let unchanged = NSLocalizedString("Couldn't reach the AI coach — your plan is unchanged.",
                                          comment: "coach chat — revision round failed, previous plan kept")
        session.messages.append(CoachMessage(role: .assistant, text: unchanged,
                                             memoryProposal: CoachMemoryProposal.validated(nil, userText: memorySource,
                                                                                           existing: settings.coachMemory,
                                                                                           declined: session.declinedMemoryKeys)))
        session.fallbackNote = unchanged
        session.generationStep = 0
        session.isGenerating = false
    }

    /// 回落时给用户看的一句话 —— 带上**为什么**, 而不是一律说"连不上".
    /// service 的 .failure 里已经是 AIError.userMessage (network/api/parse 的具体描述,
    /// 或 "AI returned no matching exercises"), 直接拼在通用句后面, 不新增本地化 key。
    private static func fallbackNote(from state: AIWorkoutService.State) -> String {
        let generic = NSLocalizedString("Couldn't reach the AI coach — showing templates instead.",
                                        comment: "coach chat fallback when LLM unreachable")
        guard case .failure(let detail) = state else { return generic }
        let d = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !d.isEmpty else { return generic }
        return "\(generic) (\(d))"
    }

    func resolveCoachPreferences(messageID: String, accept: Bool) {
        guard let index = coachSession.messages.firstIndex(where: { $0.id == messageID }),
              var proposal = coachSession.messages[index].preferenceProposal,
              proposal.decision == .pending, !coachSession.isGenerating else { return }
        // A later manual edit or another accepted proposal must not be overwritten.
        guard !accept || proposal.changes.allSatisfy({ $0.field.value(in: settings) == $0.previous }) else {
            proposal.decision = .declined
            coachSession.messages[index].text = NSLocalizedString("Preferences changed. Please ask again to review the latest values.", comment: "")
            coachSession.messages[index].preferenceProposal = proposal
            return
        }
        if accept {
            for change in proposal.changes { change.apply(to: &settings) }
            flushSave()
        }
        proposal.decision = accept ? .saved : .declined
        coachSession.messages[index].preferenceProposal = proposal
        if accept {
            startCoachGenerate(feedback: proposal.feedback, surface: "confirmed_preferences",
                               photoData: proposal.photoData, photoIsGoalComparison: proposal.photoIsGoalComparison,
                               skipPreferenceReview: true, appendUserMessage: false, forceRegeneration: true)
        }
    }

    func resolveCoachMemory(messageID: String, accept: Bool) {
        guard let index = coachSession.messages.firstIndex(where: { $0.id == messageID }),
              coachSession.messages[index].role == .assistant,
              var proposal = coachSession.messages[index].memoryProposal,
              proposal.decision == .pending else { return }
        if accept {
            guard CoachMemoryProposal.hasPlanningDetail(proposal.note),
                  CoachMemoryProposal.hasPlanningDetail(proposal.sourceQuote) else {
                proposal.decision = .declined
                coachSession.messages[index].memoryProposal = proposal
                return
            }
            appendCoachNote(proposal.note)
            flushSave()
            proposal.decision = .saved
        } else {
            coachSession.declinedMemoryKeys.insert(CoachMemoryProposal.key(proposal.note))
            coachSession.declinedMemoryKeys.insert(CoachMemoryProposal.key(proposal.sourceQuote))
            proposal.decision = .declined
        }
        coachSession.messages[index].memoryProposal = proposal
    }

    /// 一轮收尾 (成功 / 首轮模板回落) — push 版本栈 / 写 currentRoutines / 追加 assistant 消息 / 清生成态.
    /// text: 首轮优先 LLM 给的 rationale (让用户看出"真 AI"); 修订轮固定用本地小结 —
    /// 修订后 Day 1 可能是回填的旧天, 它的 rationale 描述的不是这次修改, 用了反而误导.
    private func finishCoachRound(plans: [Plan], usedFallback: Bool, isRevision: Bool, memorySource: String? = nil) {
        let session = coachSession
        if let first = plans.first {
            Task {
                await ExerciseDemoService.shared.prefetch(first.steps.map(\.exerciseId), priority: true)
                await ExerciseDemoService.shared.prefetch(plans.dropFirst().flatMap { $0.steps.map(\.exerciseId) })
            }
        }
        let previousPlans = isRevision ? session.currentRoutines : nil
        session.versionStack.append(plans)
        session.currentRoutines = plans
        session.latestIsSingleWorkout = false
        let rationale = plans.first?.rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if isRevision {
            text = NSLocalizedString("Updated your plan.", comment: "coach chat — assistant summary after a revision round")
        } else if let rationale, !rationale.isEmpty {
            text = rationale
        } else {
            text = NSLocalizedString("Your plan is ready", comment: "coach chat — assistant fallback summary")
        }
        session.messages.append(CoachMessage(role: .assistant, text: text, plans: plans,
                                             previousPlans: previousPlans,
                                             memoryProposal: CoachMemoryProposal.validated(
                                                usedFallback ? nil : AIWorkoutService.shared.takeMemoryProposal(for: plans),
                                                userText: memorySource, existing: settings.coachMemory,
                                                declined: session.declinedMemoryKeys)))
        // QA修复①: 记录本轮是否回落 — 回落轮之后的下一轮重走首轮生成管线 (见 coachGenerate 的 isRevision).
        session.lastRoundUsedFallback = usedFallback
        // ⚠️ 回落**不等于**连不上. 这一句以前不管什么原因都写"Couldn't reach the AI coach",
        //    结果是: 网络明明通 (设置里的自检绿的), 用户在这儿还是读到"够不到 AI", 我也没法定位.
        //    真实原因 service 早就算出来了 (AIError.userMessage → state.failure), 这里带出来:
        //    网络失败 / 上游报错 / JSON 解析失败 / LLM 给的动作名一个都没匹配上库.
        session.fallbackNote = usedFallback ? Self.fallbackNote(from: AIWorkoutService.shared.state) : nil
        session.generationStep = 0
        session.isGenerating = false
    }

    /// 修订响应 ↔ 上一版的对齐 (风险② reconciliation). 目标天数恒 = 上一版天数 (修订不改周分化结构):
    ///   ① 名称相同 (不区分大小写) 优先 — LLM 通常保留没被要求改的天名;
    ///   ② 否则取同序号的响应天;
    ///   ③ 都对不上 (LLM 漏了这天) → 用上一版原数据回填.
    /// 响应里多出来的天 (LLM 幻觉) 直接丢弃, 不进结果.
    static func reconcileRevisedRoutines(_ revised: [Plan], previous: [Plan]) -> [Plan] {
        guard !previous.isEmpty else { return revised }
        var remaining = Array(revised.enumerated())   // (原响应序号, plan)
        var out: [Plan] = []
        for (i, prev) in previous.enumerated() {
            if let byName = remaining.firstIndex(where: {
                $0.element.name.caseInsensitiveCompare(prev.name) == .orderedSame
            }) {
                out.append(remaining.remove(at: byName).element)
            } else if revised.count == previous.count,
                      let byOrder = remaining.firstIndex(where: { $0.offset == i }) {
                // 序号对齐只在"响应天数 = 上一版天数"时可信 — 定向修订现在只返回改动的天
                // (部分响应), 此时按序号硬套会把改名后的 Day2 错塞进 Day1 槽位.
                out.append(remaining.remove(at: byOrder).element)
            } else {
                out.append(prev)
            }
        }
        return out
    }

    // MARK: - 书签态 (savedIdMap 优先, 签名兜底 — 设计文档 §2)

    /// Coach 结果卡的保存 — savePlan + 记录 生成卡 id → 已存副本 id 映射 (bookmark 态反查).
    /// 幂等: 已存 → 直接成功. 返回 false = 撞免费上限 (调用方弹 paywall).
    @discardableResult
    func saveCoachPlan(_ plan: Plan) -> Bool {
        if isCoachPlanSaved(plan) { return true }
        guard let copy = savePlanReturningCopy(plan) else { return false }
        coachSession.savedIdMap[plan.id] = copy.id
        return true
    }

    /// 一键替换 — 清空 Today 现有的已存 routines, 换成这一轮 coach 生成的全部 (owner).
    /// 逐张走 saveCoachPlan, 所以 savedIdMap / analytics / 免费上限口径跟单张保存完全一致.
    /// ⚠️ **调用方负责免费上限判断** (newPlans 多于 freeSavedPlansLimit 时先弹 paywall) ——
    ///    这里不静默截断: 清空后 plans=0, 免费档最多只吃得下 3 张, 第 4 张会被 savePlan 丢掉.
    /// 返回实际存入张数, 调用方可校验 (正常 == newPlans.count).
    @discardableResult
    func replaceSavedPlans(withCoach newPlans: [Plan]) -> Int {
        guard !newPlans.isEmpty else { return 0 }
        let removedCount = plans.count
        plans.removeAll()
        // 映射整体作废 —— 旧副本已经不存在, 留着会让 isCoachPlanSaved 对旧卡误报已存.
        coachSession.savedIdMap.removeAll()
        for p in newPlans { _ = saveCoachPlan(p) }
        Analytics.shared.track("routines_replace_all", [
            "removed": .int(removedCount),
            "added": .int(plans.count),
        ])
        save()
        return plans.count
    }

    /// 生成卡是否已存 — savedIdMap 反查优先 (副本改名后签名会漂移, id 不会), 签名匹配兜底
    /// (老对话恢复 / map 里没记录过的卡). 映射指向的副本已被删 → 视为未存 (陈旧映射无害, 不在读路径清理).
    func areCoachPlansSaved(_ plans: [Plan]) -> Bool {
        !plans.isEmpty && plans.allSatisfy { isCoachPlanSaved($0) }
    }

    func isCoachPlanSaved(_ plan: Plan) -> Bool {
        if let savedId = coachSession.savedIdMap[plan.id],
           plans.contains(where: { $0.id == savedId }) {
            return true
        }
        return isPlanSaved(plan)
    }

    /// applyScience 的 coach 修订轮出口 — 私有 applyScience 在 DataStore.swift 里, 这里包一层
    /// (extension 跨文件访问不到 private). 语义完全一致: enforceScience + lastSet 负重兜底.
    private func applyScienceToCoachPlan(_ plan: Plan) -> Plan {
        var p = plan
        p.steps = DataStore.enforceScience(p.steps, exById: exById)
        p.steps = p.steps.map { step in
            var s = step
            s = suggestingMissingParameters(for: s)
            return s
        }
        return p
    }
}

// MARK: - Equipment swap (local tool, not an LLM rewrite)

extension DataStore {
    /// Returns true when the utterance is a muscle/equipment replacement and the chat
    /// already has a preview, clarification, or empty result. False leaves the normal
    /// generate path untouched.
    @discardableResult
    func handleEquipmentSwapUtterance(_ text: String, onlyModify: String?, focusedPlanId: String?) -> Bool {
        if handleEquipmentSwapFollowUp(text) { return true }
        let lang = LanguageManager.currentLanguageCode
        var conversationIds: [String] = []
        for plan in coachSession.currentRoutines where plans.contains(where: { $0.id == plan.id }) {
            conversationIds.append(plan.id)
        }
        for saved in coachSession.savedIdMap.values where plans.contains(where: { $0.id == saved }) {
            conversationIds.append(saved)
        }
        var seenLibrary = Set<String>()
        let library = exById.values.filter { seenLibrary.insert($0.id).inserted }
        let context = CoachEquipmentSwap.Context(
            plans: plans,
            library: library,
            candidates: userLibrary,
            availableEquipment: settings.availableEquipment,
            focusedPlanId: focusedPlanId,
            conversationPlanIds: conversationIds,
            onlyModifyName: onlyModify,
            languageCode: lang)
        let outcome = CoachEquipmentSwap.interpret(text, context: context)
        if case .notHandled = outcome { return false }

        coachSession.messages.append(CoachMessage(role: .user, text: text))
        switch outcome {
        case .notHandled:
            return false
        case .preview(let proposal):
            if coachSession.pendingEquipmentSwap?.id == proposal.id {
                coachSession.messages.append(CoachMessage(
                    role: .assistant,
                    text: lang.hasPrefix("zh")
                        ? "还是刚才那份预览, 确认后才会写入. 我没有再改一次."
                        : "That’s the same preview as before. Nothing is written until you apply it."))
            } else {
                coachSession.pendingEquipmentSwap = proposal
                var message = CoachMessage(
                    role: .assistant,
                    text: CoachEquipmentSwap.text(for: outcome, languageCode: lang))
                message.equipmentSwapProposalId = proposal.id
                coachSession.messages.append(message)
            }
            Analytics.shared.track("coach_equipment_swap", [
                "phase": .string("preview"),
                "steps": .int(proposal.lines.count),
                "routines": .int(Set(proposal.lines.map(\.planId)).count),
            ])
        default:
            coachSession.pendingEquipmentSwap = nil
            coachSession.messages.append(CoachMessage(
                role: .assistant,
                text: CoachEquipmentSwap.text(for: outcome, languageCode: lang)))
            Analytics.shared.track("coach_equipment_swap", [
                "phase": .string("clarify"),
                "steps": .int(0),
                "routines": .int(0),
            ])
        }
        return true
    }

    /// Confirm, cancel, or undo from the chat itself. Buttons call the same methods.
    /// A reply that is not one of these, and not a new replacement request, returns false
    /// so the normal coach path still runs.
    private func handleEquipmentSwapFollowUp(_ text: String) -> Bool {
        guard let follow = CoachEquipmentSwap.chatFollowUp(text) else { return false }
        switch follow {
        case .confirm:
            guard let id = coachSession.pendingEquipmentSwap?.id else { return false }
            coachSession.messages.append(CoachMessage(role: .user, text: text))
            confirmEquipmentSwap(proposalId: id)
        case .cancel:
            guard let id = coachSession.pendingEquipmentSwap?.id else { return false }
            coachSession.messages.append(CoachMessage(role: .user, text: text))
            cancelEquipmentSwap(proposalId: id)
        case .undo:
            if let id = coachSession.pendingEquipmentSwap?.id {
                coachSession.messages.append(CoachMessage(role: .user, text: text))
                cancelEquipmentSwap(proposalId: id)
            } else if let undo = coachSession.equipmentSwapUndo {
                coachSession.messages.append(CoachMessage(role: .user, text: text))
                undoEquipmentSwap(id: undo.id)
            } else {
                return false
            }
        }
        return true
    }

    func confirmEquipmentSwap(proposalId: String) {
        guard let proposal = coachSession.pendingEquipmentSwap, proposal.id == proposalId else { return }
        let beforePlans = plans
        let lang = LanguageManager.currentLanguageCode
        let allowed = Set(userLibrary.map(\.id))
        let applied = CoachEquipmentSwap.applyTransaction(
            plans: plans, sets: sets, aiTodayPlan: aiTodayPlan,
            proposal: proposal, allowedExerciseIds: allowed
        ) { [weak self] newPlans in
            guard let self else { return false }
            let previous = self.plans
            self.plans = newPlans
            let ok = self.saveEquipmentSwapNow()
            if !ok {
                self.plans = previous
                // The failed write cancelled the debounce. Reschedule so unrelated
                // in-memory edits (history, settings) are not dropped with the rollback.
                // A test override already replaced the write; do not also touch shared storage.
                if self.equipmentSwapSaveOverride == nil { self.save() }
            }
            return ok
        }
        plans = applied.plans
        let routineCount = Set(proposal.lines.map(\.planId)).count
        let cleared = proposal.lines.contains { $0.clearsWeight }
        switch applied.result {
        case .applied:
            coachSession.pendingEquipmentSwap = nil
            let undo = CoachEquipmentSwap.UndoRecord(
                id: "undo-\(proposal.id)", proposalId: proposal.id,
                previousPlans: applied.previousPlans ?? beforePlans)
            coachSession.equipmentSwapUndo = undo
            refreshCoachEmbeddedPlans()
            var message = CoachMessage(
                role: .assistant,
                text: CoachEquipmentSwap.textApplied(
                    stepCount: proposal.lines.count, routineCount: routineCount,
                    clearedWeight: cleared, languageCode: lang))
            message.equipmentSwapUndoId = undo.id
            coachSession.messages.append(message)
            Analytics.shared.track("coach_equipment_swap", [
                "phase": .string("applied"),
                "steps": .int(proposal.lines.count),
                "routines": .int(routineCount),
            ])
        case .alreadyApplied:
            coachSession.pendingEquipmentSwap = nil
            coachSession.messages.append(CoachMessage(
                role: .assistant,
                text: CoachEquipmentSwap.textAlready(languageCode: lang)))
        case .failed(.persist):
            plans = beforePlans
            coachSession.messages.append(CoachMessage(
                role: .assistant,
                text: CoachEquipmentSwap.textPersistFailed(languageCode: lang)))
        case .failed:
            plans = beforePlans
            coachSession.pendingEquipmentSwap = nil
            coachSession.messages.append(CoachMessage(
                role: .assistant,
                text: CoachEquipmentSwap.textConflict(languageCode: lang)))
        }
    }

    func cancelEquipmentSwap(proposalId: String) {
        guard coachSession.pendingEquipmentSwap?.id == proposalId else { return }
        coachSession.pendingEquipmentSwap = nil
        coachSession.messages.append(CoachMessage(
            role: .assistant,
            text: CoachEquipmentSwap.textCancelled(languageCode: LanguageManager.currentLanguageCode)))
    }

    func undoEquipmentSwap(id: String) {
        guard let undo = coachSession.equipmentSwapUndo, undo.id == id else { return }
        let current = plans
        let undone = CoachEquipmentSwap.undoTransaction(
            plans: plans, sets: sets, aiTodayPlan: aiTodayPlan, previousPlans: undo.previousPlans
        ) { [weak self] restored in
            guard let self else { return false }
            let previous = self.plans
            self.plans = restored
            let ok = self.saveEquipmentSwapNow()
            if !ok {
                self.plans = previous
                if self.equipmentSwapSaveOverride == nil { self.save() }
            }
            return ok
        }
        plans = undone.plans
        guard undone.saved else {
            plans = current
            coachSession.messages.append(CoachMessage(
                role: .assistant,
                text: CoachEquipmentSwap.textUndoFailed(languageCode: LanguageManager.currentLanguageCode)))
            return
        }
        coachSession.equipmentSwapUndo = nil
        refreshCoachEmbeddedPlans()
        coachSession.messages.append(CoachMessage(
            role: .assistant,
            text: CoachEquipmentSwap.textUndone(languageCode: LanguageManager.currentLanguageCode)))
    }

    private func refreshCoachEmbeddedPlans() {
        let byId = Dictionary(plans.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
        for index in coachSession.currentRoutines.indices {
            if let updated = byId[coachSession.currentRoutines[index].id] {
                coachSession.currentRoutines[index] = updated
            }
        }
        if let current = coachSession.currentSessionPlan, let updated = byId[current.id] {
            coachSession.currentSessionPlan = updated
        }
        for index in coachSession.messages.indices {
            guard var embedded = coachSession.messages[index].plans else { continue }
            var changed = false
            for stepIndex in embedded.indices {
                if let updated = byId[embedded[stepIndex].id] {
                    embedded[stepIndex] = updated
                    changed = true
                }
            }
            if changed { coachSession.messages[index].plans = embedded }
        }
    }
}

/// One-off draft; never writes saved Training Preferences.
struct CoachQuickWorkoutDraft {
    var kind = "auto"
    var minutes = 20
    var intensity = "moderate"
    var equipment = "saved"
    var requirements = ""
    static let kinds = ["auto", "strength", "cardio", "hiit", "mobility"]
    static let kindKeys = ["auto": "Let AI recommend", "strength": "Strength training", "cardio": "Cardio", "hiit": "HIIT", "mobility": "Mobility & stretching"]
    static let intensityKeys = ["easy": "Easy", "moderate": "Moderate", "hard": "High intensity"]
    static let equipmentKeys = ["saved": "Use saved equipment", "bodyweight": "Bodyweight", "dumbbell": "Dumbbells", "bands": "Resistance bands"]
    var request: CoachSessionRequest {
        let text = "Create exactly one new workout for today, about \(minutes) minutes INCLUDING rests. Training type: \(kind). Intensity: \(intensity). This is a one-off request; do not update saved preferences or revise previous plans. For HIIT specify timed work intervals; retain the user's configured rest settings and explain their effect on total time. Additional requirements: \(requirements)"
        return CoachSessionRequest(sourceQuote: text, durationMinutes: minutes, trainingType: kind,
            equipmentOverride: equipment == "saved" ? nil : [equipment == "bodyweight" ? "body_only" : equipment])
    }
    var displayText: String {
        [NSLocalizedString("AI Quick Workout", comment: ""),
         NSLocalizedString(Self.kindKeys[kind]!, comment: ""),
         String(format: NSLocalizedString("%lld min", comment: ""), minutes),
         NSLocalizedString(Self.intensityKeys[intensity]!, comment: ""),
         NSLocalizedString(Self.equipmentKeys[equipment]!, comment: ""), requirements]
            .filter { !$0.isEmpty }.joined(separator: " · ")
    }
}
