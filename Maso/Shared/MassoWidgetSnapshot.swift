import Foundation

/// Native, language-aware duration formatting shared by the App and its widgets.
enum MassoDurationFormatter {
    static func sleep(_ minutes: Double, locale: Locale) -> String {
        guard minutes.isFinite, minutes >= 0, minutes < Double(Int.max / 60) else { return "—" }
        let value = Int(minutes)
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = locale
        formatter.calendar = calendar
        formatter.allowedUnits = value < 60 ? [.minute] : [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: Double(value) * 60) ?? "—"
    }
}

/// Small, versioned App Group contract. Widgets never load the App database or HealthKit.
struct MassoWidgetSnapshot: Codable, Equatable, Sendable {
    static let schemaVersion = 1
    var version = schemaVersion
    var generatedAt: Date
    var language: String
    var timeZone: String
    var dietEnabled: Bool
    var sleepEnabled: Bool
    var moments: [Moment]

    struct TrainedMuscle: Codable, Equatable, Sendable {
        let id: String
        let name: String
        let sets: Int
    }

    struct CalendarDay: Codable, Equatable, Sendable {
        let date: Date
        let workout: Double?
        let diet: Double?
        let sleep: Double?
        var dietCalorieFraction: Double? = nil
    }

    struct Moment: Codable, Equatable, Sendable {
        var date: Date
        var workoutDays: Int
        var workoutTarget: Int
        var protein: Double?
        var proteinTarget: Int?
        var dietProgress: Double?
        var sleepMinutes: Double?
        var sleepTarget: Int?
        var sleepProgress: Double?
        var musclesTrained: [TrainedMuscle]? = nil
        var calendarDays: [CalendarDay]? = nil
        // Optional for existing App Group snapshots: never interpret an old nutrition score as energy.
        var calories: Double? = nil
        var calorieTarget: Double? = nil
        var calorieProgress: Double? {
            guard let calories, let calorieTarget, calories.isFinite, calorieTarget.isFinite,
                  calories >= 0, calorieTarget > 0 else { return nil }
            return calories / calorieTarget
        }
    }

    func moment(at date: Date) -> Moment? {
        // Never present an old meal, sleep night or recovery picture indefinitely.
        guard version == Self.schemaVersion, date >= generatedAt.addingTimeInterval(-300),
              date < generatedAt.addingTimeInterval(25 * 3600) else { return nil }
        return moments.filter { $0.date <= date }.max { $0.date < $1.date }
    }
}

enum MassoWidgetDestination: String, CaseIterable, Sendable {
    case home, workout, diet, sleep, recovery, start, coach, addMeal, playWorkout
    var url: URL { URL(string: "maso://widget/\(rawValue)")! }
    init?(url: URL) {
        guard url.scheme == "maso", url.host == "widget", url.query == nil,
              let value = Self(rawValue: url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else { return nil }
        self = value
    }
}

enum MassoWidgetStore {
    static let groupID = "group.com.yumowu.masso.widgets"
    static var directory: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID)?
            .appendingPathComponent("Widgets", isDirectory: true)
    }
    static func read(from directory: URL? = Self.directory) -> MassoWidgetSnapshot? {
        guard let directory, let data = try? Data(contentsOf: directory.appendingPathComponent("snapshot.json")),
              let value = try? JSONDecoder().decode(MassoWidgetSnapshot.self, from: data),
              value.version == MassoWidgetSnapshot.schemaVersion else { return nil }
        return value
    }
    static func write(_ value: MassoWidgetSnapshot, to directory: URL? = Self.directory) throws {
        guard let directory else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: directory.appendingPathComponent("snapshot.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}

/// A calendar date opens the existing daily records sheet, including cold launches.
enum MassoWidgetDayLink {
    static func url(for day: Date) -> URL {
        URL(string: "maso://widget/day?date=\(Int(day.timeIntervalSince1970))")!
    }
    static func day(from url: URL, now: Date = Date()) -> Date? {
        guard url.scheme == "maso", url.host == "widget", url.path == "/day",
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              items.count == 1, items[0].name == "date", let raw = items[0].value,
              let seconds = Double(raw), seconds.isFinite, seconds >= 0,
              seconds <= now.timeIntervalSince1970 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }
}
