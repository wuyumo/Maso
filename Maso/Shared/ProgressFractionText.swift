import SwiftUI

/// Calorie progress remains yellow through the goal, then changes continuously
/// with the actual/target ratio. The displayed bar itself still caps at 100%.
enum DietProgressColor {
    static func components(for fraction: Double?) -> (Double, Double, Double) {
        guard let fraction, fraction.isFinite, fraction > 1 else { return (1, 1, 0) }
        let stops: [(Double, (Double, Double, Double))] = [
            (1.0, (1, 1, 0)), (1.3, (1, 0.584, 0)),
            (1.6, (1, 0.231, 0.188)), (1.9, (0.686, 0.322, 0.87))
        ]
        guard fraction < 1.9 else { return stops[3].1 }
        for index in 1..<stops.count where fraction <= stops[index].0 {
            let a = stops[index - 1], b = stops[index]
            let t = (fraction - a.0) / (b.0 - a.0)
            return (a.1.0 + (b.1.0 - a.1.0) * t,
                    a.1.1 + (b.1.1 - a.1.1) * t,
                    a.1.2 + (b.1.2 - a.1.2) * t)
        }
        return stops[3].1
    }
    static func color(for fraction: Double?) -> Color {
        guard let fraction, fraction.isFinite, fraction > 1 else { return .yellow }
        let (r, g, b) = components(for: fraction)
        return Color(red: r, green: g, blue: b)
    }
}

/// Parse only bare numeric values in dedicated metric slots. Prose and unit ratios stay untouched.
struct NumericFractionParts: Equatable {
    let numerator: String
    let denominator: String
    let separator: String
    init?(value: String) {
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let first = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let second = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
        func numeric(_ part: String) -> Bool {
            let punctuation = Set(".,٬٫’' +−-\u{00a0}\u{202f}")
            return part.contains(where: { $0.isNumber }) && part.allSatisfy { $0.isNumber || punctuation.contains($0) }
        }
        guard numeric(first), numeric(second) else { return nil }
        numerator = first; denominator = second
        separator = parts[0].last?.isWhitespace == true || parts[1].first?.isWhitespace == true ? " / " : "/"
    }
}

/// Actual value stays prominent; the slash, goal and trailing unit use secondary emphasis.
/// Text interpolation preserves one wrapping/baseline/accessibility element and inherited sizing.
struct ProgressFractionText: View {
    let numerator: String
    let denominator: String?
    var suffix = ""
    var separator = " / "
    var numeratorColor: Color = .primary
    var denominatorColor: Color = .secondary
    var numeratorWeight: Font.Weight = .semibold
    var numeratorFont: Font? = nil
    var denominatorFont: Font? = nil
    var body: some View {
        let actual = Text(verbatim: numerator).font(numeratorFont).fontWeight(numeratorWeight)
            .foregroundColor(numerator == "—" ? denominatorColor : numeratorColor)
        let goal = Text(verbatim: (denominator.map { separator + $0 } ?? "") + suffix)
            .font(denominatorFont).fontWeight(.regular).foregroundColor(denominatorColor)
        Text("\(actual)\(goal)").monospacedDigit()
    }
}

/// For existing generic numeric slots only; does not search or modify surrounding text.
struct MetricValueText: View {
    let value: String
    var numeratorColor: Color = .primary
    var denominatorColor: Color = .secondary
    var numeratorWeight: Font.Weight = .semibold
    var numeratorFont: Font? = nil
    var denominatorFont: Font? = nil
    var body: some View {
        if let ratio = NumericFractionParts(value: value) {
            ProgressFractionText(numerator: ratio.numerator, denominator: ratio.denominator,
                                 separator: ratio.separator, numeratorColor: numeratorColor,
                                 denominatorColor: denominatorColor, numeratorWeight: numeratorWeight,
                                 numeratorFont: numeratorFont, denominatorFont: denominatorFont)
        } else { Text(verbatim: value).foregroundColor(numeratorColor) }
    }
}
