import SwiftUI

/// Shared by Home and Widget horizontal tracks and three-part calendar rings.
enum OverviewProgressMetrics {
    static let thickness: CGFloat = 4
    // Matches the native accessoryCircular Gauge at the 62pt Lock Screen size.
    static let lockScreenThickness: CGFloat = 5.5
}

/// The calendar's three arcs: workout at top, diet lower-left, sleep lower-right.
/// Shared with Lock Screen accessories so segment order, gaps and missing values stay identical.
struct DailyProgressRing: View {
    let progress: [Double?]
    let colors: [Color]
    let lineWidth: CGFloat
    let dietCalorieFraction: Double?
    init(progress: [Double?], colors: [Color], lineWidth: CGFloat = OverviewProgressMetrics.thickness, dietCalorieFraction: Double? = nil) {
        self.progress = progress
        self.colors = colors
        self.lineWidth = lineWidth
        self.dietCalorieFraction = dietCalorieFraction
    }
    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                let start = Double([0, 2, 1][index]) / 3 + 0.033
                let span = 1.0 / 3 - 0.066
                let value = progress.indices.contains(index) ? progress[index].flatMap { $0.isFinite && $0 >= 0 ? min($0, 1) : nil } ?? 0 : 0
                Circle().trim(from: start, to: start + span)
                    .stroke(Color.secondary.opacity(0.22), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                if value > 0 {
                    Circle().trim(from: start, to: start + span * value)
                        .stroke(index == 1 && dietCalorieFraction != nil ? DietProgressColor.color(for: dietCalorieFraction) : colors[index], style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
        .rotationEffect(.degrees(-150))
        .padding(3)
        .accessibilityHidden(true)
    }
}
