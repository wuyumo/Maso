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
    @State private var pendingLimit = false

    private var presented: Binding<Bool> {
        Binding(get: { flow.candidate != nil && flow.confirmationAnchorID == anchorID },
                set: { visible in
                    if !visible, flow.confirmationAnchorID == anchorID {
                        flow.candidate = nil
                        flow.confirmationAnchorID = nil
                    }
                })
    }
    private var message: String {
        String(format: NSLocalizedString("Choose whether to replace your %lld saved routines or add these %lld routines alongside them.", comment: ""), data.plans.count, flow.candidate?.count ?? 0)
    }

    @ViewBuilder func body(content: Content) -> some View {
        if anchorID != nil {
            content.popover(isPresented: presented, attachmentAnchor: .rect(.bounds), arrowEdge: .bottom) {
                ViewThatFits(in: .vertical) {
                    choices
                    ScrollView { choices }.scrollBounceBehavior(.basedOnSize)
                }
                .frame(idealWidth: 280, maxWidth: 280, alignment: .leading)
                .padding(16)
                .presentationCompactAdaptation(.popover)
                .onDisappear {
                    if pendingLimit { pendingLimit = false; onLimit() }
                }
            }
        } else {
            // Deferred saves from a closed detail sheet keep their native dialog;
            // there is no longer a visible source button to anchor to.
            content.confirmationDialog("Save to My Routines", isPresented: presented, titleVisibility: .visible) {
                Button("Add to existing routines") { commit(replacing: false, anchored: false) }
                Button("Replace all routines", role: .destructive) { commit(replacing: true, anchored: false) }
                Button("Cancel", role: .cancel) { presented.wrappedValue = false }
            } message: { Text(message) }
        }
    }

    private var choices: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save to My Routines").font(.headline)
            Text(message).font(.subheadline).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { commit(replacing: false, anchored: true) } label: {
                Text("Add to existing routines").frame(maxWidth: .infinity, alignment: .leading)
            }.nativeGlassButtonStyle().accessibilityIdentifier("routine.save.add")
            Button(role: .destructive) { commit(replacing: true, anchored: true) } label: {
                Text("Replace all routines").frame(maxWidth: .infinity, alignment: .leading)
            }.nativeGlassButtonStyle().accessibilityIdentifier("routine.save.replace")
            Button("Cancel", role: .cancel) { presented.wrappedValue = false }
                .frame(maxWidth: .infinity).accessibilityIdentifier("routine.save.cancel")
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("routine.save.choices")
    }

    private func commit(replacing: Bool, anchored: Bool) {
        let plans = flow.candidate ?? []
        flow.commit(plans, replacing: replacing, data: data) {
            if anchored { pendingLimit = true } else { onLimit() }
        }
    }
}

extension View {
    func workoutSaveConfirmation(flow: WorkoutSaveFlow, anchorID: String? = nil, onLimit: @escaping () -> Void) -> some View {
        modifier(WorkoutSaveConfirmation(flow: flow, anchorID: anchorID, onLimit: onLimit))
    }
}
