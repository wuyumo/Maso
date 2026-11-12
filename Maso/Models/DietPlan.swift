import Foundation

/// Small, offline food table: approximate composition per 100 g edible portion.
/// Cooked meat/starches/vegetables; dry oats; packaged yogurt/tofu; peeled fruit.
/// Sources and conventions: docs/diet-page-proposal.md.
struct DietFood: Identifiable, Sendable {
    enum Group: Sendable { case protein, starch, produce }
    let id: String
    let name: String
    let icon: String
    let group: Group
    let protein: Double
    let carbs: Double
    var plant: Bool = true
    var allergen: String? = nil
    static let all: [DietFood] = [
        .init(id: "chicken", name: "Chicken breast", icon: "🍗", group: .protein, protein: 31, carbs: 0, plant: false),
        .init(id: "beef", name: "Lean beef", icon: "🥩", group: .protein, protein: 29, carbs: 0, plant: false),
        .init(id: "tofu", name: "Firm tofu", icon: "◻️", group: .protein, protein: 15, carbs: 3, allergen: "Soy"),
        .init(id: "eggs", name: "Eggs", icon: "🥚", group: .protein, protein: 13, carbs: 1, plant: false, allergen: "Egg"),
        .init(id: "yogurt", name: "Plain Greek yogurt", icon: "🥣", group: .protein, protein: 10, carbs: 4, plant: false, allergen: "Milk"),
        .init(id: "rice", name: "Rice", icon: "🍚", group: .starch, protein: 2.7, carbs: 28),
        .init(id: "potato", name: "Potatoes", icon: "🥔", group: .starch, protein: 2, carbs: 20),
        .init(id: "oats", name: "Oats", icon: "🌾", group: .starch, protein: 13, carbs: 68),
        .init(id: "broccoli", name: "Broccoli", icon: "🥦", group: .produce, protein: 2.4, carbs: 7),
        .init(id: "greens", name: "Leafy greens", icon: "🥬", group: .produce, protein: 2, carbs: 4),
        .init(id: "tomato", name: "Tomatoes", icon: "🍅", group: .produce, protein: 0.9, carbs: 4),
        .init(id: "berries", name: "Blueberries", icon: "🫐", group: .produce, protein: 0.7, carbs: 14)
    ]
}

struct DietPreferences: Codable, Equatable, Sendable {
    var includesSnack = false // Legacy 3-meal / 3-meal-plus-snack preference.
    var mealsPerDay: Int? = nil
    /// nil = flexible; otherwise a 12, 10, or 8 hour eating window.
    var eatingWindowHours: Int? = nil
    var windowStartMinutes: Int? = nil
    var mealCount: Int { min(5, max(2, mealsPerDay ?? (includesSnack ? 4 : 3))) }
    var windowHours: Int? { eatingWindowHours.flatMap { [12, 10, 8].contains($0) ? $0 : nil } }
    var startMinutes: Int {
        let defaultStart = windowHours == 8 ? 12 * 60 : (windowHours == 10 ? 10 * 60 : 8 * 60)
        return ((windowStartMinutes ?? defaultStart) % 1440 + 1440) % 1440
    }
    var endMinutes: Int? { windowHours.map { (startMinutes + $0 * 60) % 1440 } }
    func scheduledMinute(at index: Int) -> Int? {
        guard let hours = windowHours else { return nil }
        let spacing = Double(hours * 60 - 30) / Double(mealCount - 1)
        let offset = Int((Double(index) * spacing / 5).rounded()) * 5
        return (startMinutes + offset) % 1440
    }
    var plantBased = false
    var excludedFoods: Set<String> = []
    var allergens: Set<String> = []
    /// User-adjustable fixed daily macro targets. Older profiles decode these as nil
    /// and continue to use the profile-derived starting point.
    var proteinTarget: Int? = nil
    var carbohydrateTarget: Int? = nil
    var fatTarget: Int? = nil
    func allows(_ food: DietFood) -> Bool {
        (!plantBased || food.plant) && !excludedFoods.contains(food.id)
            && (food.allergen.map { !allergens.contains($0) } ?? true)
    }
}

struct DietPortion: Identifiable, Codable, Equatable, Sendable {
    let id: String
    var foodID: String
    /// Keep original nutrient budget so repeated swaps do not compound rounding errors.
    let referenceFoodID: String
    let referenceGrams: Double
    var food: DietFood { DietFood.all.first { $0.id == foodID }! }
    var grams: Double {
        Self.convert(referenceGrams, from: DietFood.all.first { $0.id == referenceFoodID }!, to: food)
    }
    static func convert(_ grams: Double, from: DietFood, to: DietFood) -> Double {
        let ratio: Double
        switch from.group {
        case .protein: ratio = from.protein / to.protein
        case .starch: ratio = from.carbs / to.carbs
        case .produce: ratio = 1
        }
        return max(5, (grams * ratio / 5).rounded() * 5)
    }
}

struct DietMeal: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let title: String
    var portions: [DietPortion]
    var scheduledMinute: Int? = nil
}

struct DailyDietPlan: Codable, Sendable {
    let day: Date
    let profileKey: String
    var meals: [DietMeal]
    static func profileKey(settings: UserSettings, preferences: DietPreferences) -> String {
        "meal-balance-v5|\(settings.weight ?? 0)|\(settings.age ?? 0)|\(settings.weeklyTrainingDays)|\(settings.trainingGoalKind.rawValue)|\(preferences.mealCount)|\(preferences.windowHours ?? 0)|\(preferences.startMinutes)|\(preferences.proteinTarget ?? 0)|\(preferences.carbohydrateTarget ?? 0)|\(preferences.fatTarget ?? 0)|\(preferences.plantBased)|\(preferences.excludedFoods.sorted())|\(preferences.allergens.sorted())"
    }
    static func build(settings: UserSettings, preferences: DietPreferences, now: Date = Date()) -> DailyDietPlan {
        let weight = settings.weight ?? 75
        let protein = Double(DietNutritionTargets.build(settings: settings)?.protein ?? 120)
        let carbsPerKg = weight > 0
            ? Double(DietNutritionTargets.build(settings: settings)?.carbohydrate ?? Int(weight * 4)) / weight
            : 4
        func meal(_ id: String, _ title: String, proteinFood: String, starch: String, produce: String, produceGrams: Double) -> DietMeal {
            let p = DietFood.all.first { $0.id == proteinFood }!
            let c = DietFood.all.first { $0.id == starch }!
            let v = DietFood.all.first { $0.id == produce }!
            let proteinBudget = max(0, protein * proteinFraction(id, mealCount: preferences.mealCount) - v.protein * produceGrams / 100)
            let carbBudget = max(0, weight * carbsPerKg * carbohydrateFraction(id, mealCount: preferences.mealCount) - v.carbs * produceGrams / 100)
            // Include starch protein and protein-food carbohydrate in both budgets.
            let determinant = p.protein * c.carbs - c.protein * p.carbs
            let proteinGrams = max(5, 100 * (proteinBudget * c.carbs - carbBudget * c.protein) / determinant)
            let starchGrams = max(5, 100 * (carbBudget * p.protein - proteinBudget * p.carbs) / determinant)
            let items = [(p, proteinGrams), (c, starchGrams), (v, produceGrams)]
            let portions = items.enumerated().compactMap { index, item -> DietPortion? in
                let reference = item.0
                let choices = DietFood.all.filter { $0.group == reference.group && preferences.allows($0) }
                guard let selected = choices.first(where: { $0.id == reference.id }) ?? choices.first else { return nil }
                return DietPortion(id: "\(id)-\(index)", foodID: selected.id, referenceFoodID: reference.id, referenceGrams: item.1)
            }
            return DietMeal(id: id, title: title, portions: portions)
        }
        let specifications: [(id: String, title: String, protein: String, starch: String, produce: String, grams: Double)]
        switch preferences.mealCount {
        case 2:
            specifications = [("lunch", "Meal 1", "chicken", "rice", "broccoli", 200), ("dinner", "Meal 2", "beef", "potato", "greens", 200)]
        case 4:
            specifications = [("breakfast", "Breakfast", "yogurt", "oats", "berries", 100), ("lunch", "Lunch", "chicken", "rice", "broccoli", 200), ("snack", "Snack", "yogurt", "oats", "berries", 50), ("dinner", "Dinner", "beef", "potato", "greens", 200)]
        case 5:
            specifications = [("breakfast", "Breakfast", "yogurt", "oats", "berries", 100), ("snack-morning", "Morning snack", "yogurt", "oats", "berries", 50), ("lunch", "Lunch", "chicken", "rice", "broccoli", 200), ("snack", "Afternoon snack", "yogurt", "oats", "berries", 50), ("dinner", "Dinner", "beef", "potato", "greens", 200)]
        default:
            specifications = [("breakfast", "Breakfast", "yogurt", "oats", "berries", 100), ("lunch", "Lunch", "chicken", "rice", "broccoli", 200), ("dinner", "Dinner", "beef", "potato", "greens", 200)]
        }
        let meals = specifications.enumerated().map { index, item in
            let title = preferences.windowHours == nil ? item.title : "Meal \(index + 1)"
            var result = meal(item.id, title, proteinFood: item.protein, starch: item.starch, produce: item.produce, produceGrams: item.grams)
            result.scheduledMinute = preferences.scheduledMinute(at: index)
            return result
        }
        return .init(day: now, profileKey: profileKey(settings: settings, preferences: preferences), meals: meals)
    }
    /// Practical allocations that sum to one; meal timing never changes daily targets.
    static func proteinFraction(_ id: String, mealCount: Int) -> Double {
        1 / Double(min(5, max(2, mealCount)))
    }
    static func carbohydrateFraction(_ id: String, mealCount: Int) -> Double {
        if mealCount == 2 { return id == "lunch" ? 0.45 : 0.55 }
        if id == "snack" { return mealCount == 5 ? 0.10 : 0.15 }
        if id == "snack-morning" { return 0.10 }
        let mainFraction = id == "breakfast" ? 0.25 : (id == "lunch" ? 0.35 : 0.40)
        return mainFraction * (mealCount == 5 ? 0.8 : (mealCount == 4 ? 0.85 : 1))
    }

}

/// Fixed planning targets, derived only from profile inputs the app actually collects.
/// They are not a clinical prescription or a measured energy requirement.
struct DietNutritionTargets {
    let protein: Int
    let carbohydrate: Int
    let fat: Int
    static func build(settings: UserSettings) -> DietNutritionTargets? {
        guard let weight = settings.weight, weight.isFinite, (20...350).contains(weight) else { return nil }
        let proteinFactor: Double
        switch settings.trainingGoalKind {
        case .buildMuscle, .getStronger: proteinFactor = 1.6
        case .loseFat: proteinFactor = 1.8
        case .generalFitness, .endurance: proteinFactor = 1.4
        }
        // Older adults often benefit from a higher protein target; keep the adjustment
        // conservative because health status and kidney function are not collected.
        let ageAdjustedProteinFactor = (settings.age ?? 0) >= 65 ? max(proteinFactor, 1.6) : proteinFactor
        let trainingDays = Double(min(7, max(0, settings.weeklyTrainingDays)))
        let carbohydrateFactor: Double
        switch settings.trainingGoalKind {
        case .buildMuscle: carbohydrateFactor = 3.0 + 0.30 * trainingDays
        case .getStronger: carbohydrateFactor = 3.0 + 0.25 * trainingDays
        case .loseFat: carbohydrateFactor = 2.0 + 0.20 * trainingDays
        case .generalFitness: carbohydrateFactor = 2.5 + 0.20 * trainingDays
        case .endurance: carbohydrateFactor = 3.0 + 0.40 * trainingDays
        }
        func roundedToFive(_ value: Double) -> Int { max(5, Int((value / 5).rounded() * 5)) }
        let protein = roundedToFive(weight * ageAdjustedProteinFactor)
        // 130 g/day is the adult carbohydrate RDA; avoid setting a lower default.
        let carbohydrate = max(130, roundedToFive(weight * min(5, carbohydrateFactor)))
        // A simple weight-based fixed target avoids inventing a calorie requirement
        // without height, body composition or reliable total-activity data.
        let fat = roundedToFive(weight * 0.8)
        return .init(protein: protein, carbohydrate: carbohydrate, fat: fat)
    }

    static func build(settings: UserSettings, preferences: DietPreferences) -> DietNutritionTargets? {
        guard let base = build(settings: settings) else { return nil }
        return .init(
            protein: preferences.proteinTarget ?? base.protein,
            carbohydrate: preferences.carbohydrateTarget ?? base.carbohydrate,
            fat: preferences.fatTarget ?? base.fat
        )
    }

    static func preset(_ preset: DietTargetPreset, settings: UserSettings) -> DietNutritionTargets? {
        guard let weight = settings.weight, weight.isFinite, (20...350).contains(weight) else { return nil }
        if preset == .profileGoal { return build(settings: settings) }
        let proteinFactor: Double
        let carbohydrateFactor: Double
        let fatFactor: Double = 0.8
        switch preset {
        case .profileGoal:
            return build(settings: settings)
        case .gainMuscle:
            proteinFactor = 1.8; carbohydrateFactor = 4.0
        case .maintain:
            proteinFactor = 1.6; carbohydrateFactor = 3.0
        case .loseFat:
            proteinFactor = 2.0; carbohydrateFactor = 2.5
        case .custom:
            return build(settings: settings)
        }
        func roundedToFive(_ value: Double) -> Int { max(5, Int((value / 5).rounded() * 5)) }
        return .init(protein: roundedToFive(weight * proteinFactor),
                     carbohydrate: max(130, roundedToFive(weight * carbohydrateFactor)),
                     fat: roundedToFive(weight * fatFactor))
    }
}

enum DietTargetPreset: String, CaseIterable, Identifiable, Hashable {
    case profileGoal, gainMuscle, maintain, loseFat, custom
    var id: String { rawValue }
    var title: String {
        switch self {
        case .profileGoal: "Based on my goal"
        case .gainMuscle: "Build muscle"
        case .maintain: "Maintain"
        case .loseFat: "Lose fat"
        case .custom: "Custom"
        }
    }
}

/// Conservative planning adjustments, not an exercise-calorie or sleep-debt estimate.
struct DietDailyGuidance {
    let targets: DietNutritionTargets
    let carbohydrateAdjustment: Int
    let trainedToday: Bool
    let highVolume: Bool
    let recovering: Bool
    let shortSleep: Bool

    var subtitleKey: String {
        if shortSleep {
            return trainedToday ? "Training today and short sleep: fuel your workout and prioritize recovery" : "Short sleep last night: keep protein steady and prioritize recovery"
        }
        if carbohydrateAdjustment == 0 { return "Daily nutrition targets" }
        if highVolume { return "More training today: extra carbs support recovery" }
        if trainedToday { return "Training today: carbs adjusted, protein stays steady" }
        if recovering { return "Recovery day: keep protein steady while muscles recover" }
        return "No workout logged today: carbs follow your lighter activity"
    }

    static func build(settings: UserSettings, sets: [SetRecord], exById: [String: Exercise],
                      sleptMinutes: Double? = nil, now: Date = Date()) -> Self? {
        let preferences = settings.dietPreferences ?? DietPreferences()
        guard let base = DietNutritionTargets.build(settings: settings), let targets = DietNutritionTargets.build(settings: settings, preferences: preferences), let weight = settings.weight else { return nil }
        let calendar = settings.calendar
        let day = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: day) ?? day
        let today = sets.filter { calendar.isDate($0.performedAt, inSameDayAs: day) }
        let strength = today.filter { [.strength, .hypertrophyFocus, .calisthenics].contains($0.category) && ($0.reps ?? 0) > 0 }
        var groups: [MuscleGroup: Int] = [:]
        for record in strength {
            let primary = Set((exById[record.exerciseId]?.primaryMuscles ?? []).map { $0.section ?? $0 })
            for muscle in primary { groups[muscle, default: 0] += 1 }
        }
        let trained = !today.isEmpty
        let high = strength.count >= 18 || groups.values.contains { $0 >= 10 }
        let frequency = Double(min(7, max(0, settings.weeklyTrainingDays))) / 7
        // Training/rest offsets balance around the existing weekly-average target.
        // 0.5 g/kg day modulation and the high-volume 0.3 g/kg add-on are Masso's
        // cautious heuristics, not exact doses prescribed by the referenced studies.
        let offset = weight * (0.5 * ((trained ? 1 : 0) - frequency) + (high ? 0.3 : 0))
        let bounded = min(50, max(-50, offset))
        let dynamicBaseCarbs = max(130, Int(((Double(base.carbohydrate) + bounded) / 5).rounded()) * 5)
        // Saved gram targets are an explicit choice, not a baseline for further modulation.
        let carbs = preferences.carbohydrateTarget ?? dynamicBaseCarbs
        return .init(targets: .init(protein: targets.protein, carbohydrate: carbs, fat: targets.fat),
                     carbohydrateAdjustment: carbs - targets.carbohydrate, trainedToday: trained, highVolume: high,
                     recovering: !trained && sets.contains { calendar.isDate($0.performedAt, inSameDayAs: yesterday) },
                     shortSleep: sleptMinutes.map { $0.isFinite && $0 > 0 && $0 < 420 } ?? false)
    }
}

struct MealNutrition: Codable, Equatable, Sendable {
    var protein: Double = 0
    var carbs: Double = 0
    var fat: Double = 0
    var valid: Bool { [protein, carbs, fat].allSatisfy { $0.isFinite && $0 >= 0 && $0 <= 1000 } }
    /// General 4/4/9 estimate from stored macros; not an independently measured energy value.
    /// Computed so legacy meals and historical targets keep their original data.
    var estimatedCalories: Double? {
        guard [protein, carbs, fat].allSatisfy({ $0.isFinite && $0 >= 0 }) else { return nil }
        let result = protein * 4 + carbs * 4 + fat * 9
        return result.isFinite ? result : nil
    }
    static func + (lhs: Self, rhs: Self) -> Self { .init(protein: lhs.protein + rhs.protein, carbs: lhs.carbs + rhs.carbs, fat: lhs.fat + rhs.fat) }
}
struct MealPhotoEstimate: Codable, Sendable {
    var foods: String
    var nutrition: MealNutrition
    var isFood: Bool
    var analysis: MealNutritionAnalysis? = nil
}
struct MealCheckIn: Codable, Identifiable, Sendable {
    var id: String { "\(day.timeIntervalSince1970)-\(mealID)" }
    let day: Date
    var mealID: String
    let title: String
    var photoFilename: String
    var foods: String
    var nutrition: MealNutrition
    let confirmedAt: Date
    var originalDescription: String? = nil
    var analysis: MealNutritionAnalysis? = nil
    /// Actual eating time; old records retain their previously displayed timestamp.
    var consumedAt: Date? = nil
    var mealTime: Date { consumedAt ?? confirmedAt }
}
/// Whole-ten intake percentages; over-target intake remains visible.
struct DietNutritionScore {
    let protein: Int
    let carbs: Int
    let fat: Int
    let overall: Int
    static func points(_ fraction: Double) -> Int {
        guard fraction.isFinite else { return 0 }
        return Int(floor(max(0, fraction) * 10 + 0.0000001)) * 10
    }
    static func calculate(actual: MealNutrition, targets: MealNutrition) -> Self? {
        guard actual.valid, [targets.protein, targets.carbs, targets.fat].allSatisfy({ $0.isFinite && $0 > 0 }) else { return nil }
        let p = actual.protein / targets.protein
        let c = actual.carbs / targets.carbs
        let f = actual.fat / targets.fat
        return Self(protein: points(p), carbs: points(c), fat: points(f),
                    overall: points((20 * p + 10 * c + 5 * f) / 35))
    }
}

/// One meal's weighted contribution toward the full daily macro targets, shown as a percentage (not a score).
struct DietNutritionProgress {
    static func dailyTargetContribution(actual: MealNutrition, goal: DailyWellnessGoal?) -> Int? {
        guard let goal,
              actual.valid,
              goal.protein > 0, goal.carbsMinimum > 0, goal.fatMinimum > 0 else { return nil }
        let protein = actual.protein / Double(goal.protein)
        let carbs = actual.carbs / Double(goal.carbsMinimum)
        let fat = actual.fat / Double(goal.fatMinimum)
        let contribution = (20 * protein + 10 * carbs + 5 * fat) / 35
        guard contribution.isFinite else { return nil }
        return Int((contribution * 100).rounded())
    }
}

/// Target adherence from confirmed intake, kept separate from health or food-quality claims.
struct DietIntakeProgress {
    let percent: Int
    let fraction: Double
    let score: Int
    let complete: Bool
    static func calculate(goal: DailyWellnessGoal?, meals: [MealCheckIn]) -> Self? {
        guard let goal, goal.protein > 0, goal.carbsMinimum > 0, goal.fatMinimum > 0 else { return nil }
        let latest = Dictionary(grouping: meals, by: \.mealID).values.compactMap { $0.max(by: { $0.confirmedAt < $1.confirmedAt }) }
        guard !latest.isEmpty, latest.allSatisfy({ $0.nutrition.valid }) else { return nil }
        let total = latest.reduce(MealNutrition()) { $0 + $1.nutrition }
        func ratio(_ value: Double, _ target: Int) -> Double { value / Double(target) }
        let value = (20 * ratio(total.protein, goal.protein) + 10 * ratio(total.carbs, goal.carbsMinimum) + 5 * ratio(total.fat, goal.fatMinimum)) / 35
        return Self(percent: Int((value * 100).rounded()), fraction: value, score: DietNutritionScore.points(value),
                    complete: goal.mealsComplete(latest))
    }
}

/// Calorie actual/target for overview surfaces. Keep the separate nutrition score intact.
struct DietEnergyProgress {
    let actual: Double?
    let target: Double?
    var fraction: Double? {
        guard let actual, let target, actual.isFinite, target.isFinite, actual >= 0, target > 0 else { return nil }
        return actual / target
    }
    static func calculate(goal: DailyWellnessGoal?, meals: [MealCheckIn]) -> Self {
        let latest = Dictionary(grouping: meals, by: \.mealID).values.compactMap { $0.max(by: { $0.confirmedAt < $1.confirmedAt }) }
        let actual = !latest.isEmpty && latest.allSatisfy({ $0.nutrition.valid })
            ? latest.reduce(MealNutrition()) { $0 + $1.nutrition }.estimatedCalories : nil
        let target = goal.flatMap { value -> Double? in
            guard value.protein > 0, value.carbsMinimum > 0, value.fatMinimum > 0 else { return nil }
            return MealNutrition(protein: Double(value.protein), carbs: Double(value.carbsMinimum), fat: Double(value.fatMinimum)).estimatedCalories
        }
        return .init(actual: actual, target: target)
    }
}

struct DailyWellnessGoal: Codable, Sendable {
    var trainingSets: Int? // nil = no explicit plan; 0 = planned rest
    var planID: String?
    var protein: Int
    var carbsMinimum: Int
    var fatMinimum: Int
    var sleepMinutes: Int
    var mealIDs: [String]
    var perMealTargets: MealNutrition? {
        let count = Set(mealIDs).count
        guard count > 0, protein > 0, carbsMinimum > 0, fatMinimum > 0 else { return nil }
        return .init(protein: Double(protein) / Double(count), carbs: Double(carbsMinimum) / Double(count), fat: Double(fatMinimum) / Double(count))
    }
    /// Meal count is a planning reference, not a fixed breakfast/lunch/dinner identity.
    func mealsComplete(_ records: [MealCheckIn]) -> Bool {
        !mealIDs.isEmpty && Set(records.map(\.mealID)).count >= Set(mealIDs).count
    }
}
struct DailyWellnessScore {
    let training: Double?
    let nutrition: Double?
    let sleep: Double?
    var total: Int? {
        guard let training, let nutrition, let sleep else { return nil }
        return Int((training + nutrition + sleep).rounded())
    }
    var allMet: Bool { training == 40 && nutrition == 35 && sleep == 25 }
    static func calculate(goal: DailyWellnessGoal?, sets: [SetRecord], meals: [MealCheckIn], slept: Double?) -> Self {
        guard let goal else { return .init(training: nil, nutrition: nil, sleep: nil) }
        let training: Double? = goal.trainingSets.map { target in
            if target == 0 { return 40 }
            let done = sets.filter { (goal.planID == nil || $0.planId == goal.planID) && (($0.reps ?? 0) > 0 || ($0.duration ?? 0) > 0) }.count
            return 40 * min(1, Double(done) / Double(max(1, target)))
        }
        let totals = meals.reduce(MealNutrition()) { $0 + $1.nutrition }
        let complete = goal.mealsComplete(meals)
        func ratio(_ value: Double, _ target: Int) -> Double { min(1, max(0, value) / Double(max(1, target))) }
        let nutrition: Double? = complete ? 20 * ratio(totals.protein, goal.protein) + 10 * ratio(totals.carbs, goal.carbsMinimum) + 5 * ratio(totals.fat, goal.fatMinimum) : nil
        let sleep = slept.flatMap { value -> Double? in
            guard value.isFinite, value >= 0, goal.sleepMinutes > 0 else { return nil }
            return 25 * ratio(value, goal.sleepMinutes)
        }
        return .init(training: training, nutrition: nutrition, sleep: sleep)
    }
}

/// Fourteen calendar days ending today. Missing intake/sleep stays unknown, never zero.
struct LifestyleDayProgress: Identifiable, Sendable {
    enum Kind { case diet, sleep }
    var id: Date { day }
    let day: Date
    let fraction: Double?
    let usesCurrentTarget: Bool
    static func build(kind: Kind, settings: UserSettings, healthSleep: [Date: Double] = [:], now: Date = Date()) -> [Self] {
        let calendar = settings.calendar
        let today = calendar.startOfDay(for: now)
        let snapshot = PerformanceCalendarSnapshot.lifestyle(kind: kind == .diet ? .diet : .sleep, settings: settings, healthSleep: healthSleep)
        return (-13...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return .init(day: day, fraction: snapshot.progress[day], usesCurrentTarget: !snapshot.savedTargetDays.contains(day))
        }
    }
}

/// Shared actual-record snapshot for compact and complete performance calendars.
struct PerformanceCalendarSnapshot {
    enum Kind: String { case workout, diet, sleep }
    let kind: Kind
    let progress: [Date: Double]
    var savedTargetDays: Set<Date> = []
    var dietCalorieFractions: [Date: Double] = [:]
    var earliestDay: Date? { progress.keys.min() }
    static func workout(_ days: Set<Date>, calendar: Calendar) -> Self {
        .init(kind: .workout, progress: Dictionary(days.map { (calendar.startOfDay(for: $0), 1.0) }, uniquingKeysWith: { _, value in value }))
    }
    /// Context only: never add these days to workout progress or counts.
    func recoveryFraction(on date: Date, calendar: Calendar, now: Date = Date()) -> Double? {
        guard kind == .workout else { return nil }
        let day = calendar.startOfDay(for: date)
        guard day <= calendar.startOfDay(for: now), progress[day] == nil else { return nil }
        for (offset, fraction) in [(1, 0.6), (2, 0.3)] {
            if let previous = calendar.date(byAdding: .day, value: -offset, to: day), progress[previous] != nil {
                return fraction
            }
        }
        return nil
    }
    static func lifestyle(kind: Kind, settings: UserSettings, healthSleep: [Date: Double] = [:]) -> Self {
        let calendar = settings.calendar
        var values: [Date: Double] = [:]
        var savedDays = Set<Date>()
        func record(_ day: Date, value: Double, target: Int?, saved: Bool) {
            guard value.isFinite, value >= 0, let target, target > 0 else { return }
            values[day] = min(1, value / Double(target))
            if saved { savedDays.insert(day) }
        }
        if kind == .diet {
            let meals = Dictionary(grouping: settings.mealCheckIns ?? []) { calendar.startOfDay(for: $0.day) }
            let targets = DietNutritionTargets.build(
                settings: settings,
                preferences: settings.dietPreferences ?? DietPreferences()
            )
            for (day, records) in meals {
                let key = SleepPreferences.dayKey(day, calendar: calendar)
                var goal = settings.wellnessGoals?[key]
                if goal != nil { savedDays.insert(day) }
                if goal == nil, let targets {
                    goal = .init(protein: targets.protein, carbsMinimum: targets.carbohydrate,
                                 fatMinimum: targets.fat, sleepMinutes: 480, mealIDs: [])
                }
                if let result = DietIntakeProgress.calculate(goal: goal, meals: records) { values[day] = result.fraction }
            }
        } else if kind == .sleep {
            var nights: [Date: Double] = [:]
            for (key, minutes) in settings.sleepRecords ?? [:] {
                let parts = key.split(separator: "-").compactMap { Int($0) }
                guard parts.count == 3, let day = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { continue }
                nights[calendar.startOfDay(for: day)] = minutes
            }
            for (day, minutes) in healthSleep { nights[calendar.startOfDay(for: day)] = minutes }
            for (day, minutes) in nights {
                let key = SleepPreferences.dayKey(day, calendar: calendar)
                let saved = settings.sleepPreferences?.recordedGoals[key] ?? settings.wellnessGoals?[key]?.sleepMinutes
                record(day, value: minutes, target: saved ?? (settings.sleepPreferences ?? SleepPreferences()).targetMinutes, saved: saved != nil)
            }
        }
        return .init(kind: kind, progress: values, savedTargetDays: savedDays)
    }
}

/// Seven actual-record days, using saved targets where available. Empty days stay unknown.
struct TargetWeekProgress {
    static func build(kind: PerformanceCalendarSnapshot.Kind, settings: UserSettings,
                      workoutDates: Set<Date> = [], healthSleep: [Date: Double] = [:], now: Date = Date()) -> [LifestyleDayProgress] {
        let calendar = settings.calendar
        let today = calendar.startOfDay(for: now)
        let snapshot: PerformanceCalendarSnapshot
        if kind == .workout {
            return workoutStrip(workoutDates: workoutDates, calendar: calendar, dayCount: 7, now: now)
        } else if kind == .sleep {
            snapshot = .lifestyle(kind: .sleep, settings: settings, healthSleep: healthSleep)
        } else {
            var recorded = settings
            recorded.mealCheckIns = settings.mealCheckIns?.filter { $0.day <= now && $0.confirmedAt <= now && $0.mealTime <= now }
            snapshot = .lifestyle(kind: .diet, settings: recorded)
        }
        return (-6...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return .init(day: day, fraction: snapshot.progress[day], usesCurrentTarget: !snapshot.savedTargetDays.contains(day))
        }
    }

    /// Logged day = full green; the following two calendar days fade through recovering / ready.
    /// Recovery tint is contextual only and never counts as a workout toward the weekly target.
    static func workoutStrip(workoutDates: Set<Date>, calendar: Calendar, dayCount: Int, now: Date = Date()) -> [LifestyleDayProgress] {
        let today = calendar.startOfDay(for: now)
        let recordedDays = Set(workoutDates.filter { $0 <= now }.map { calendar.startOfDay(for: $0) })
        let startOffset = -(max(1, dayCount) - 1)
        return (startOffset...0).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            let fraction: Double?
            if recordedDays.contains(day) {
                fraction = 1
            } else if let previous = recordedDays.filter({ $0 < day }).max(),
                      let daysSince = calendar.dateComponents([.day], from: previous, to: day).day {
                switch daysSince {
                case 1: fraction = 0.6   // Recovering
                case 2: fraction = 0.3   // Ready
                default: fraction = nil
                }
            } else {
                fraction = nil
            }
            return .init(day: day, fraction: fraction, usesCurrentTarget: false)
        }
    }
}

/// Visual bands are app UI thresholds, not medical cutoffs.
enum GoalCompletionAppearance {
    static func workoutOpacity(_ fraction: Double) -> Double {
        if fraction >= 1 { return 1 }
        if fraction >= 0.6 { return 0.6 }
        return 0.3
    }

    static func opacity(_ fraction: Double) -> Double {
        if fraction >= 1 { return 1 }
        if fraction >= 0.8 { return 0.75 }
        if fraction >= 0.5 { return 0.5 }
        return 0.25
    }
}

/// Export scope follows calendar days, excludes future/invalid samples, and never fills missing days.
enum PerformanceShareSummary {
    static func entries(_ snapshot: PerformanceCalendarSnapshot, start: Date, end: Date,
                        calendar: Calendar, now: Date = Date()) -> [Date: Double] {
        guard start <= end, start <= now else { return [:] }
        let first = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: min(end, now))
        var result: [Date: Double] = [:]
        for (date, progress) in snapshot.progress where date <= now && progress.isFinite && progress >= 0 {
            let day = calendar.startOfDay(for: date)
            guard day >= first, day <= last else { continue }
            result[day] = max(result[day] ?? 0, progress)
        }
        return result
    }
}
