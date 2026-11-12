import Foundation

struct WorkoutCompletion: Codable, Sendable {
    let sessionID: String
    let planID: String
    let finishedAt: Date
}

/// Selection never changes the stored card order. Completion is scoped to the
/// user's calendar week; the next candidate follows the latest finished plan.
struct WorkoutRotation {
    let completedPlanIDs: Set<String>
    let todayPlanID: String?
    let defaultPlanID: String?

    init(plans: [Plan], completions: [WorkoutCompletion], calendar: Calendar, now: Date) {
        let ids = plans.filter { !$0.steps.isEmpty }.map(\.id)
        let valid = Set(ids)
        let records = completions.filter { valid.contains($0.planID) && $0.finishedAt <= now }
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let completed = Set(records.filter { $0.finishedAt >= weekStart }.map(\.planID))
        completedPlanIDs = completed
        let latest = records.max { $0.finishedAt < $1.finishedAt }?.planID
        let start = latest.flatMap { ids.firstIndex(of: $0) }.map { ($0 + 1) % max(1, ids.count) } ?? 0
        todayPlanID = ids.indices.lazy.map { ids[($0 + start) % ids.count] }
            .first { !completed.contains($0) }
        defaultPlanID = todayPlanID ?? latest ?? ids.first
    }
}
