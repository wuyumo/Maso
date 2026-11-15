import SwiftUI
import Observation

/// AI Coach and Classics share the same native confirmation and saving rules.
@MainActor
@Observable
final class WorkoutSaveFlow {
    var candidate: [Plan]?
    var confirmationAnchorID: String?

    func request(_ plans: [Plan], anchorID: String? = nil, data: DataStore, onLimit: () -> Void) {
        guard !plans.isEmpty, !data.areCoachPlansSaved(plans) else { return }
        confirmationAnchorID = anchorID
        if data.plans.isEmpty {
            commit(plans, replacing: false, data: data, onLimit: onLimit)
        } else {
            candidate = plans
        }
    }

    func commit(_ plans: [Plan], replacing: Bool, data: DataStore, onLimit: () -> Void) {
        guard !plans.isEmpty else { return }
        // Match the store's signature deduplication before checking the whole batch.
        var seen: Set<String> = []
        let unique = plans.filter { seen.insert($0.name + "\u{1}" + $0.steps.map(\.exerciseId).joined(separator: ",")).inserted }
        let additions = replacing ? unique : unique.filter { !data.isCoachPlanSaved($0) }
        let resultingCount = (replacing ? 0 : data.plans.count) + additions.count
        guard data.settings.isPro || resultingCount <= DataStore.freeSavedPlansLimit else {
            candidate = nil
            confirmationAnchorID = nil
            onLimit()
            return
        }
        if replacing {
            data.replaceSavedPlans(withCoach: unique)
        } else {
            for plan in additions { _ = data.saveCoachPlan(plan) }
        }
        candidate = nil
        confirmationAnchorID = nil
        if !additions.isEmpty { Haptics.tap() }
    }
}

private struct WorkoutSaveConfirmation: ViewModifier {
    @Environment(DataStore.self) private var data
    @Bindable var flow: WorkoutSaveFlow
    var anchorID: String?
    let onLimit: () -> Void

    private var presented: Binding<Bool> {
        Binding(get: { flow.candidate != nil && flow.confirmationAnchorID == anchorID },
                set: { visible in
                    if !visible, flow.confirmationAnchorID == anchorID {
                        flow.candidate = nil
                        flow.confirmationAnchorID = nil
                    }
                })
    }
    func body(content: Content) -> some View {
        content.confirmationDialog("Save to My Routines", isPresented: presented, titleVisibility: .hidden) {
            let plans = flow.candidate ?? []
            Button("Add to existing routines") { commit(plans, replacing: false) }
                .accessibilityIdentifier("routine.save.add")
            Button("Replace all routines", role: .destructive) { commit(plans, replacing: true) }
                .accessibilityIdentifier("routine.save.replace")
            Button("Cancel", role: .cancel) { presented.wrappedValue = false }
                .accessibilityIdentifier("routine.save.cancel")
        }
    }

    private func commit(_ plans: [Plan], replacing: Bool) {
        flow.commit(plans, replacing: replacing, data: data, onLimit: onLimit)
    }

}

extension View {
    func workoutSaveConfirmation(flow: WorkoutSaveFlow, anchorID: String? = nil, onLimit: @escaping () -> Void) -> some View {
        modifier(WorkoutSaveConfirmation(flow: flow, anchorID: anchorID, onLimit: onLimit))
    }
}
