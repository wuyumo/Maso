import SwiftUI

/// One symbol source for the Home overview and all Home Screen widget sizes.
enum OverviewMetric: String, CaseIterable {
    case workout, diet, sleep

    var title: String {
        switch self { case .workout: "Workout"; case .diet: "Diet"; case .sleep: "Sleep" }
    }
    var symbol: String {
        switch self { case .workout: "dumbbell"; case .diet: "fork.knife"; case .sleep: "moon" }
    }
}

/// The glow shares the symbol's exact center; it does not consume layout space.
struct OverviewMetricIcon: View {
    let metric: OverviewMetric
    let color: Color
    var glyphScale: CGFloat = 1

    var body: some View {
        Image(systemName: metric.symbol)
            .font(.footnote.weight(.semibold))
            .scaleEffect(glyphScale)
            .foregroundStyle(color)
            .background {
                Circle().fill(color.opacity(0.30))
                    .frame(width: 20, height: 20)
                    .blur(radius: 7)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}


/// Shared circle treatment for Home and Widget shortcuts.
struct OverviewActionIcon: View {
    static let diameter: CGFloat = 22
    let symbol: String
    let accent: Color
    var monochrome = false
    var symbolScale: Image.Scale = .medium
    var glyphScale: CGFloat = 1
    private var color: Color { monochrome ? .primary : accent }

    var body: some View {
        Image(systemName: symbol)
            .font(.caption.weight(.semibold))
            .imageScale(symbolScale)
            .scaleEffect(glyphScale)
            .foregroundStyle(color)
            .frame(width: Self.diameter, height: Self.diameter)
            .background(color.opacity(0.18), in: Circle())
    }
}

/// Semantic meal shortcut; appearance remains single-source with workout play.
struct MealAddIcon: View {
    static let diameter = OverviewActionIcon.diameter
    var monochrome = false
    var glyphScale: CGFloat = 1
    var body: some View { OverviewActionIcon(symbol: "plus", accent: .yellow, monochrome: monochrome, glyphScale: glyphScale) }
}
