import Foundation

/// A Health workout stays separate from strength sets and saved workout plans.
struct ExternalWorkout: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let activity: Kind
    let startedAt: Date
    let endedAt: Date
    let duration: Double
    let distanceMeters: Double?
    let kilocalories: Double?
    let sourceBundleID: String
    let sourceName: String

    enum Kind: String, Codable, Sendable {
        case walking, cycling, running, swimming, hiking, yoga, strength, other
        var title: String {
            switch self {
            case .walking: "Walking"
            case .cycling: "Cycling"
            case .running: "Running"
            case .swimming: "Swimming"
            case .hiking: "Hiking"
            case .yoga: "Yoga"
            case .strength: "Strength training"
            case .other: "Other workout"
            }
        }
        var icon: String {
            switch self {
            case .walking: "figure.walk"
            case .cycling: "figure.outdoor.cycle"
            case .running: "figure.run"
            case .swimming: "figure.pool.swim"
            case .hiking: "figure.hiking"
            case .yoga: "figure.yoga"
            case .strength: "dumbbell"
            case .other: "figure.mixed.cardio"
            }
        }
    }
    var isMassoSource: Bool {
        let bundle = sourceBundleID.lowercased()
        return bundle == "com.yumowu.maso" || bundle.hasPrefix("com.yumowu.maso.")
    }
    func isRecorded(by now: Date) -> Bool {
        !id.isEmpty && !isMassoSource && startedAt < endedAt && endedAt <= now && duration.isFinite && duration > 0
    }
    static func normalized(_ records: [ExternalWorkout], now: Date = Date()) -> [ExternalWorkout] {
        var unique: [String: ExternalWorkout] = [:]
        for record in records where record.isRecorded(by: now) { unique[record.id] = record }
        return unique.values.sorted { $0.startedAt == $1.startedAt ? $0.id < $1.id : $0.startedAt > $1.startedAt }
    }
}
