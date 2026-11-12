import SwiftUI

/// Local coaching advice and summary recommendations share one dismissible card deck.
struct AISummaryCard: View {
    let data: DataStore
    let localSuggestion: DataStore.RoutineSuggestion?
    var onUnlock: () -> Void = {}
    var onApply: (AISummaryAction) -> Bool = { _ in false }
    var onApplyLocal: (DataStore.RoutineSuggestion) -> Bool = { _ in false }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var swipeOffset: CGFloat = 0
    @State private var departureOpacity: Double = 1
    @State private var isCycling = false
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selectedID = ""
    @State private var lastDismissedID: String?
    @State private var isGenerating = false
    @State private var errorNote: String?
    @State private var lastRefresh: Date?

    private var allCards: [CoachAdvice] {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASO_SHOWCASE"] == "coach_advice" {
            return [
                CoachAdvice(title: "Give your legs more attention", detail: "Your recent sessions focus on upper body. Add a little more leg work to balance your routine.", action: .regenerateRoutines(focusNote: "Add more leg work"), source: .summary),
                CoachAdvice(title: "Keep sessions manageable", detail: "Try shorter sessions that are easier to fit into your week.", action: .addCoachNote(note: "Prefer shorter sessions"), source: .summary),
                CoachAdvice(title: "Make room for recovery", detail: "Spread demanding sessions across your week to leave time between them.", action: .regenerateRoutines(focusNote: "Spread sessions across the week"), source: .summary)
            ]
        }
        #endif
        var cards = CoachAdvice.merged(local: localSuggestion, summary: data.cachedSummary,
                                       isPro: data.settings.isPro)
        if !data.settings.isPro && data.summaryMinDataMet {
            cards.append(CoachAdvice(title: NSLocalizedString("AI Coach Summary", comment: ""),
                                     detail: NSLocalizedString("Unlock your AI coach summary with Pro", comment: ""),
                                     action: .none, source: .upgrade))
        }
        return cards
    }

    private var cards: [CoachAdvice] {
        let dismissed = Set(data.settings.dismissedCoachSuggestionIDs ?? [])
        let visible = allCards.filter { !dismissed.contains($0.id) }
        guard let index = visible.firstIndex(where: { $0.id == selectedID }) else { return visible }
        return Array(visible[index...]) + Array(visible[..<index])
    }
    private var currentID: String { cards.contains { $0.id == selectedID } ? selectedID : cards.first?.id ?? "" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !cards.isEmpty {
                ZStack(alignment: .top) {
                    ForEach(Array(cards.enumerated()), id: \.element.id) { index, card in
                        adviceCard(card)
                            .scaleEffect(1 - CGFloat(min(index, 2)) * 0.03, anchor: .top)
                            .offset(x: index == 0 && !reduceMotion ? swipeOffset : 0,
                                    y: -CGFloat(min(index, 2)) * 8)
                            .opacity(index >= 3 ? 0 : (index == 0 ? departureOpacity : 1))
                            .zIndex(-Double(index))
                            .allowsHitTesting(index == 0 && !isCycling)
                            .accessibilityElement(children: index == 0 ? .contain : .ignore)
                            .accessibilityHidden(index != 0)
                            .accessibilityIdentifier(index == 0 ? "coach.adviceDeck" : "coach.adviceDeck.back")
                            .simultaneousGesture(DragGesture(minimumDistance: 16)
                                .onChanged { value in
                                    guard index == 0, cards.count > 1, !isCycling,
                                          abs(value.translation.width) > abs(value.translation.height) * 1.2 else { return }
                                    swipeOffset = value.translation.width
                                }
                                .onEnded { value in
                                    guard index == 0, !isCycling else { return }
                                    let horizontal = abs(value.translation.width) > abs(value.translation.height) * 1.2
                                    if horizontal && (abs(value.translation.width) > 50 ||
                                        (abs(value.translation.width) > 16 && abs(value.predictedEndTranslation.width) > 120)) {
                                        cycleAdvice(direction: value.translation.width < 0 ? -1 : 1)
                                    } else {
                                        withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.9)) { swipeOffset = 0 }
                                    }
                                })
                    }
                }
                .padding(.top, CGFloat(min(2, max(0, cards.count - 1))) * 8)
            }
            if isGenerating {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Updating suggestions…").font(.caption).foregroundStyle(MasoColor.textDim)
                }
            }
            if let errorNote {
                Text(errorNote).font(.caption).foregroundStyle(MasoColor.textDim)
            }
            if lastDismissedID != nil {
                HStack {
                    Text("Suggestion removed").font(.caption).foregroundStyle(MasoColor.textDim)
                    Spacer(minLength: 8)
                    Button("Undo", action: undoDismiss)
                        .font(.footnote.weight(.semibold))
                        .frame(minWidth: 44, minHeight: 44)
                }
            }
        }
        .onChange(of: cards.map(\.id), initial: true) { _, ids in
            if !ids.contains(selectedID) { selectedID = ids.first ?? "" }
        }
        .task(id: data.settings.isPro) {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MASO_SHOWCASE"] == "coach_advice" { return }
            #endif
            if data.settings.isPro && data.summaryMinDataMet && data.shouldRegenerateSummary() {
                await refresh()
            }
        }
    }

    private func cycleAdvice(direction: CGFloat = 1) {
        guard cards.count > 1, !isCycling else { return }
        let nextID = cards[1].id
        if reduceMotion {
            selectedID = nextID
            swipeOffset = 0
            Haptics.selection()
            return
        }
        isCycling = true
        withAnimation(.easeOut(duration: 0.18), completionCriteria: .logicallyComplete) {
            swipeOffset = direction * max(420, abs(swipeOffset) + 180)
            departureOpacity = 0
        } completion: {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                if cards.contains(where: { $0.id == nextID }) { selectedID = nextID }
                swipeOffset = 0
                departureOpacity = 1
                isCycling = false
            }
            Haptics.selection()
        }
    }

    private func adviceCard(_ card: CoachAdvice) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AI suggestion", systemImage: "sparkles")
                .accessibilityAction(named: Text("Next")) { cycleAdvice() }
                .font(.caption.weight(.semibold))
                .foregroundStyle(MasoColor.accent)
            VStack(alignment: .leading, spacing: 6) {
                Text(card.title).font(.subheadline.weight(.bold)).foregroundStyle(MasoColor.text)
                Text(card.detail).font(.footnote).foregroundStyle(MasoColor.textDim)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            Group {
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) { adviceActions(card) }
                } else {
                    HStack(alignment: .center, spacing: 12) { adviceActions(card) }
                }
            }
        }
        .padding(14)
        .background {
            MasoColor.background.overlay(MasoColor.accent.opacity(0.10))
        }
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(MasoColor.accent.opacity(0.14), lineWidth: 0.5).allowsHitTesting(false)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func adviceActions(_ card: CoachAdvice) -> some View {
        if card.source == .upgrade {
            matchingRowButton("View Pro", prominent: true, action: onUnlock)
                .accessibilityIdentifier("coach.applyAdvice")
        } else if card.action != .none {
            matchingRowButton("Apply", prominent: true) {
                let accepted: Bool
                if card.source == .suggestion, let localSuggestion {
                    accepted = onApplyLocal(localSuggestion)
                } else {
                    accepted = onApply(card.action)
                }
                if accepted { dismiss(card, allowsUndo: false) }
            }
            .accessibilityIdentifier("coach.applyAdvice")
        }
        matchingRowButton("Skip") { dismiss(card) }
            .accessibilityIdentifier("coach.skipAdvice")
    }

    /// Apply stays accent glass; Skip stays neutral. Vertical padding 8 captured
    /// about 34pt, above the run15 suggestion pill (about 30pt), so this uses 6.
    /// The 44pt frame is the hit target outside the glass.
    private func matchingRowButton(_ title: LocalizedStringKey, prominent: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(prominent ? Color.black : MasoColor.text)
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassCapsuleButtonBackground(
                    tint: prominent ? MasoColor.accent.opacity(0.85) : nil,
                    fallback: prominent ? MasoColor.accent : MasoColor.surfaceHi)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: true)
    }

    private func dismiss(_ card: CoachAdvice, allowsUndo: Bool = true) {
        let next = CoachAdvice.selection(afterRemoving: card.id, from: cards.map(\.id))
        var ids = data.settings.dismissedCoachSuggestionIDs ?? []
        if !ids.contains(card.id) { ids.append(card.id) }
        selectedID = next ?? ""
        data.settings.dismissedCoachSuggestionIDs = ids
        lastDismissedID = allowsUndo ? card.id : nil
        data.save()
        Haptics.tap()
    }

    private func undoDismiss() {
        guard let id = lastDismissedID else { return }
        data.settings.dismissedCoachSuggestionIDs?.removeAll { $0 == id }
        selectedID = id
        lastDismissedID = nil
        data.save()
    }

    @MainActor private func refresh() async {
        guard data.settings.isPro, data.summaryMinDataMet, !isGenerating else { return }
        guard data.shouldRegenerateSummary() else {
            errorNote = NSLocalizedString("Already up to date", comment: "")
            return
        }
        guard lastRefresh.map({ Date().timeIntervalSince($0) >= 30 }) ?? true else { return }
        lastRefresh = Date()
        isGenerating = true
        errorNote = nil
        let result = await data.generateSummary()
        isGenerating = false
        if result == nil { errorNote = NSLocalizedString("AI summary unavailable — Retry", comment: "") }
    }
}
