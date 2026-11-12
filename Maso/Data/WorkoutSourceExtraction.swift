import Foundation

/// Source extraction is not a request to design or rebalance a weekly program.
struct WorkoutSourceIntent: Equatable {
    let cardCount: Int?
    static func parse(_ text: String) -> Self? {
        // Only the request before the material may set cardinality. Quoted source is data.
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        if lines.count > 1, let first = lines.first, parse(first) == nil, let last = lines.last, let trailing = parse(last) { return trailing }
        let request = String(lines.first ?? text).lowercased()
        let cards = ["workout", "card", "routine", "训练", "訓練", "entraînement", "training", "entrenamiento", "allenamento", "treino", "трениров", "トレーニング", "운동", "تمرين", "carte", "karte", "tarjeta", "scheda", "schede", "cartão", "cartões", "ficha", "rotina", "карточ", "카드", "بطاق", "التمارين"]
        let extraction = ["these exercises", "following", "provided", "source", "video", "视频", "影片", "字幕", "以下", "下面", "资料", "資料", "素材", "from this", "extract", "import", "article", "transcript", "把这", "把這", "这些动作", "這些動作", "提取", "萃取", "导入", "匯入", "文章", "清单", "清單", "截图", "截圖", "image", "photo", "list", "extraire", "importer", "extrah", "importier", "extraer", "importar", "estrai", "извле", "取り込", "추출", "استخراج", "استخرج", "extrair", "импорт", "これら", "抽出"]
        guard cards.contains(where: request.contains), extraction.contains(where: request.contains) else { return nil }
        if ["同一个", "同一個", "一张", "一張", "single card", "one card", "one workout", "same card", "une seule", "ein einzig", "una sola", "1 card", "1张", "1張", "eine karte", "ein training", "una tarjeta", "un entrenamiento", "una scheda", "un allenamento", "um único", "um treino", "uma ficha", "одну", "один", "1枚", "一枚", "1つ", "一つ", "ひとつ", "同じ", "한 장", "한장", "하나", "같은", "واحدة", "واحد", "نفس"].contains(where: request.contains) { return .init(cardCount: 1) }
        let pattern = #"([1-7١-٧۱-۷一二两兩三四五六七])\s*(?:张|張|个|個|cards?|workouts?|routines?|cartes?|entraînements?|karten?|trainings?|tarjetas?|entrenamientos?|schede|allenamenti|cartões|treinos|карточ\p{L}*|трениров\p{L}*|枚|つ|장|개|카드|بطاقات|تمارين)"#
        if let range = request.range(of: pattern, options: .regularExpression) {
            let token = request[range].first!; let names: [Character:Int] = ["一":1,"二":2,"两":2,"兩":2,"三":3,"四":4,"五":5,"六":6,"七":7]
            return .init(cardCount: token.wholeNumberValue ?? names[token])
        }
        return .init(cardCount: nil)
    }
}

struct WorkoutSourceRow: Codable, Equatable {
    var sourceName: String
    var sourceQuote: String
    var exerciseID: String
    var sets: Int?
    var reps: Int?
    var weight: Double?
    var restSeconds: Int?
    var durationSeconds: Int?
}
struct WorkoutSourceGroup: Codable, Equatable {
    var title: String
    var rows: [WorkoutSourceRow]
    var sourceHeading: String? = nil
}
struct WorkoutSourceDocument: Codable {
    var groups: [WorkoutSourceGroup]
    var unreadable: Bool
}
struct WorkoutSourcePrepared: Codable {
    let plans: [Plan]
    let defaults: [String]
}

enum WorkoutSourceError: LocalizedError {
    case unreadable, grouping, evidence, unresolved(String)
    var errorDescription: String? {
        switch self {
        case .unreadable: NSLocalizedString("Source content could not be read. Paste the article, transcript or exercise list; no AI experience was used.", comment: "")
        case .grouping: NSLocalizedString("The source card count could not be confirmed. Nothing was saved and no AI experience was used.", comment: "")
        case .evidence: NSLocalizedString("Source exercises or parameters could not be verified. Nothing was substituted or saved.", comment: "")
        case .unresolved(let name): NSLocalizedString("Confirm an exact library match before importing:", comment: "") + " " + name
        }
    }
}

extension WorkoutSourceDocument {
    func prepare(intent: WorkoutSourceIntent, source: String?, library: [Exercise], settings: UserSettings, preserveSourcePrescriptions:Bool = true) throws -> WorkoutSourcePrepared {
        guard !unreadable, !groups.isEmpty, groups.count <= 7, groups.allSatisfy({ !$0.rows.isEmpty }), groups.reduce(0, { $0 + $1.rows.count }) <= 100 else { throw WorkoutSourceError.unreadable }
        var selected = groups
        if intent.cardCount == nil, groups.count > 1 {
            var cursor = source?.startIndex
            let grounded = groups.allSatisfy { group in
                guard let heading = group.sourceHeading, heading.count >= 2 else { return false }
                if let source, let start = cursor {
                    guard let header = source.range(of:heading,options:[.caseInsensitive,.diacriticInsensitive],range:start..<source.endIndex) else { return false }
                    var end = header.upperBound
                    for row in group.rows {
                        guard row.sourceQuote.count >= 2, let quote = source.range(of:row.sourceQuote,range:end..<source.endIndex) else { return false }
                        end = quote.upperBound
                    }
                    cursor = end
                }
                return true
            }
            if !grounded { selected = [.init(title:NSLocalizedString("Imported plan",comment:""),rows:groups.flatMap(\.rows))] }
        }
        if intent.cardCount == 1 { selected = [.init(title: groups.count == 1 ? groups[0].title : NSLocalizedString("Imported plan", comment:""), rows: groups.flatMap(\.rows))] }
        else if let count = intent.cardCount, selected.count != count { throw WorkoutSourceError.grouping }
        if preserveSourcePrescriptions, let source {
            let known = RoutineImageImporter.parseCandidates(source.components(separatedBy:.newlines),library:library,preserveRepeatedRows:true).filter { $0.confidence == .high }
            let rows = selected.flatMap(\.rows); var next = 0
            for native in known {
                guard let match = rows.indices.dropFirst(next).first(where: { rows[$0].exerciseID == native.exerciseId }) else { throw WorkoutSourceError.evidence }
                next = match + 1
            }
        }
        let lookup = Dictionary(library.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var plans: [Plan] = []; var defaults: [String] = []; var sourceCursor = source?.startIndex
        for group in selected {
            var steps: [PlanStep] = []
            for originalRow in group.rows {
                var row = originalRow
                // Native source prescriptions win over model suggestions; never rebalance them.
                if preserveSourcePrescriptions {
                    let nameWords = Set(exerciseSearchWords(row.sourceName))
                    guard !nameWords.isEmpty, nameWords.isSubset(of:Set(exerciseSearchWords(row.sourceQuote))) else { throw WorkoutSourceError.evidence }
                    let candidates = RoutineImageImporter.parseCandidates([row.sourceQuote],library:library)
                    if let exact = candidates.first(where: { $0.confidence == .high }), exact.exerciseId != row.exerciseID { throw WorkoutSourceError.evidence }
                    if let native = candidates.first(where: { $0.exerciseId == row.exerciseID }) {
                        if let sets = native.sets { row.sets = sets }; if let reps = native.reps { row.reps = reps }; if let weight = native.weight { row.weight = weight }
                    }
                }
                if let source, let cursor = sourceCursor {
                    guard row.sourceQuote.count >= 2,
                          let range = source.range(of: row.sourceQuote, options: [.caseInsensitive, .diacriticInsensitive], range: cursor..<source.endIndex) else { throw WorkoutSourceError.evidence }
                    sourceCursor = range.upperBound // Source order, not model's preferred weekly split.
                }
                guard let exercise = lookup[row.exerciseID],
                      CoachPhotoReview.imageWorkout(ids: [row.exerciseID], names: [row.sourceName], library: library, settings: settings) != nil else { throw WorkoutSourceError.unresolved(row.sourceName) }
                guard row.sets.map({ (1...20).contains($0) }) ?? true,
                      row.reps.map({ (1...1000).contains($0) }) ?? true,
                      row.restSeconds.map({ (0...600).contains($0) }) ?? true,
                      row.durationSeconds.map({ (1...3600).contains($0) }) ?? true,
                      row.weight.map({ $0.isFinite && (0...2000).contains($0) }) ?? true else { throw WorkoutSourceError.evidence }
                let timed = exercise.tempo == .isometric || [.cardio, .flexibility].contains(exercise.category.normalized)
                var missing: [String] = []
                if row.sets == nil { missing.append(NSLocalizedString("Sets", comment: "")) }
                if timed ? row.durationSeconds == nil : row.reps == nil { missing.append(NSLocalizedString(timed ? "Duration" : "Reps", comment: "")) }
                if row.restSeconds == nil { missing.append(NSLocalizedString("Rest", comment: "")) }
                if !missing.isEmpty { defaults.append(row.sourceName + ": " + missing.joined(separator: ", ")) }
                steps.append(PlanStep(id: UUID().uuidString, exerciseId: row.exerciseID, sets: row.sets ?? settings.defaultSetsPerExercise,
                    reps: timed ? row.reps : row.reps ?? settings.trainingGoal.defaultRepsForCompound(), weight: row.weight,
                    duration: timed ? row.durationSeconds ?? 30 : row.durationSeconds,
                    restBetweenSets: row.restSeconds ?? settings.defaultRestSeconds, rest: settings.defaultBetweenExerciseRestSeconds))
            }
            let now = Date()
            var plan = Plan(id: "plan-source-" + UUID().uuidString, name: group.title.isEmpty ? NSLocalizedString("Imported plan", comment: "") : group.title,
                steps: steps, createdAt: now, updatedAt: now, autoGenerated: true, source: .ai)
            plan.preservesExerciseVariants = true; plans.append(plan)
        }
        return .init(plans: plans, defaults: defaults)
    }
}
