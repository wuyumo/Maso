import CoreGraphics
import SwiftUI

// Watch training layout.
//
// The exercise and rest stacks are top-aligned inside the system safe area.
// Their minimum height (kicker + up to two title lines + detail + countdown +
// a full-width button + vitals) is what overflows the smallest watchOS 11
// screen. There is no extra top padding in the view — the empty band above
// the title is the clock safe area, and the heart-rate row plus the bottom
// control are the views that fall past the bottom edge.
//
// Presets are chosen from the live content box (GeometryReader size minus
// the safe-area insets the reader reports). Roomy keeps the previous point
// sizes when that box is tall enough. Compact is only used when roomy and
// medium do not fit. Text is not scaled down below the chosen preset at the
// default Dynamic Type size. Larger-than-default type scrolls instead of
// being squeezed onto one screen.

enum WatchTrainingPage: Equatable {
    case exerciseManual
    case exerciseTimed
    case rest
}

struct WatchTrainingChrome: Equatable {
    var spacing: CGFloat
    var horizontalPadding: CGFloat
    var kicker: CGFloat
    var title: CGFloat
    var detail: CGFloat
    var countdown: CGFloat
    var buttonHeight: CGFloat
    var footer: CGFloat
    /// 1 at the default size and below. Larger Dynamic Type multiplies text
    /// and the button, and the page scrolls.
    var drawScale: CGFloat
    var scrollFallback: Bool
}

struct WatchDeviceSpec: Equatable {
    var name: String
    var screenWidth: CGFloat
    var screenHeight: CGFloat
    var safeTop: CGFloat
    var safeBottom: CGFloat
    var safeLeading: CGFloat
    var safeTrailing: CGFloat

    var contentWidth: CGFloat { screenWidth - safeLeading - safeTrailing }
    var contentHeight: CGFloat { screenHeight - safeTop - safeBottom }
}

enum WatchDeviceSpecs {
    /// 40 / 41 / 44 / 45 mm insets are the published SwiftUI safe areas for
    /// those case sizes. Series 10/11 and Ultra insets are conservative
    /// estimates (about 0.15 of the screen height) so a fit here still fits
    /// if the real inset is smaller. Runtime layout uses the live safe area,
    /// not this table.
    static let all: [WatchDeviceSpec] = [
        WatchDeviceSpec(name: "40mm", screenWidth: 162, screenHeight: 197, safeTop: 28, safeBottom: 28, safeLeading: 0.5, safeTrailing: 0.5),
        WatchDeviceSpec(name: "41mm", screenWidth: 176, screenHeight: 215, safeTop: 34, safeBottom: 34, safeLeading: 1, safeTrailing: 1),
        WatchDeviceSpec(name: "44mm", screenWidth: 184, screenHeight: 224, safeTop: 31, safeBottom: 31, safeLeading: 0.5, safeTrailing: 0.5),
        WatchDeviceSpec(name: "42mm", screenWidth: 187, screenHeight: 223, safeTop: 34, safeBottom: 34, safeLeading: 1, safeTrailing: 1),
        WatchDeviceSpec(name: "45mm", screenWidth: 198, screenHeight: 242, safeTop: 35, safeBottom: 35, safeLeading: 1, safeTrailing: 1),
        WatchDeviceSpec(name: "49mm", screenWidth: 205, screenHeight: 251, safeTop: 36, safeBottom: 36, safeLeading: 1, safeTrailing: 1),
        WatchDeviceSpec(name: "46mm", screenWidth: 208, screenHeight: 248, safeTop: 36, safeBottom: 36, safeLeading: 1, safeTrailing: 1),
        WatchDeviceSpec(name: "49mm-ultra3", screenWidth: 211, screenHeight: 257, safeTop: 37, safeBottom: 37, safeLeading: 1, safeTrailing: 1),
    ]

    static var minimum: WatchDeviceSpec {
        all.min { $0.contentHeight < $1.contentHeight } ?? all[0]
    }
}

private struct WatchLayoutPreset {
    var spacing: CGFloat
    var horizontalPadding: CGFloat
    var kicker: CGFloat
    var title: CGFloat
    var detail: CGFloat
    var countdownExercise: CGFloat
    var countdownRest: CGFloat
    var buttonManual: CGFloat
    var buttonOther: CGFloat
    var footer: CGFloat
    var lineFactor: CGFloat
    var countdownFactor: CGFloat
}

enum WatchTrainingLayout {
    // Full-width capsules. 44pt is kept when the safe area allows it.
    // 36pt is the floor: the control still spans the content width.
    static let minimumButtonHeight: CGFloat = 36

    private static let roomy = WatchLayoutPreset(
        spacing: 6, horizontalPadding: 6,
        kicker: 11, title: 17, detail: 13,
        countdownExercise: 24, countdownRest: 40,
        buttonManual: 44, buttonOther: 36, footer: 11,
        lineFactor: 1.25, countdownFactor: 1.10
    )
    private static let medium = WatchLayoutPreset(
        spacing: 3, horizontalPadding: 5,
        kicker: 11, title: 15, detail: 13,
        countdownExercise: 20, countdownRest: 30,
        buttonManual: 40, buttonOther: 36, footer: 11,
        lineFactor: 1.25, countdownFactor: 1.12
    )
    private static let compact = WatchLayoutPreset(
        spacing: 2, horizontalPadding: 4,
        kicker: 11, title: 14, detail: 11,
        countdownExercise: 16, countdownRest: 32,
        buttonManual: 38, buttonOther: 36, footer: 11,
        lineFactor: 1.25, countdownFactor: 1.05
    )

    private static let presets = [roomy, medium, compact]

    static func typeScale(_ size: DynamicTypeSize) -> CGFloat {
        switch size {
        case .xSmall: return 0.82
        case .small: return 0.88
        case .medium: return 0.94
        case .large: return 1
        case .xLarge: return 1.12
        case .xxLarge: return 1.26
        case .xxxLarge: return 1.40
        case .accessibility1: return 1.64
        case .accessibility2: return 1.92
        case .accessibility3: return 2.20
        case .accessibility4: return 2.48
        case .accessibility5: return 2.76
        @unknown default: return 1
        }
    }

    /// `includeFooter` is always true for the fit check so a heart-rate
    /// sample arriving later cannot push the button past the bezel.
    /// Whether the footer is drawn still follows the existing conditions.
    static func resolve(
        contentWidth: CGFloat,
        contentHeight: CGFloat,
        page: WatchTrainingPage,
        showsDetail: Bool,
        showsNext: Bool,
        typeScale: CGFloat
    ) -> WatchTrainingChrome {
        if typeScale <= 1 {
            for preset in presets {
                let needed = estimatedHeight(
                    preset, page: page,
                    showsDetail: showsDetail, showsNext: showsNext,
                    includeFooter: true, typeScale: 1
                )
                if needed <= contentHeight && contentWidth > 0 {
                    return chrome(from: preset, page: page, drawScale: 1, scrollFallback: false)
                }
            }
        }
        return chrome(from: compact, page: page, drawScale: max(typeScale, 1), scrollFallback: true)
    }

    private static func chrome(
        from preset: WatchLayoutPreset,
        page: WatchTrainingPage,
        drawScale: CGFloat,
        scrollFallback: Bool
    ) -> WatchTrainingChrome {
        let countdown: CGFloat
        let button: CGFloat
        switch page {
        case .exerciseManual:
            countdown = preset.countdownExercise
            button = preset.buttonManual
        case .exerciseTimed:
            countdown = preset.countdownExercise
            button = preset.buttonOther
        case .rest:
            countdown = preset.countdownRest
            button = preset.buttonOther
        }
        return WatchTrainingChrome(
            spacing: preset.spacing,
            horizontalPadding: preset.horizontalPadding,
            kicker: preset.kicker,
            title: preset.title,
            detail: preset.detail,
            countdown: countdown,
            buttonHeight: max(minimumButtonHeight, button),
            footer: preset.footer,
            drawScale: drawScale,
            scrollFallback: scrollFallback
        )
    }

    private static func estimatedHeight(
        _ preset: WatchLayoutPreset,
        page: WatchTrainingPage,
        showsDetail: Bool,
        showsNext: Bool,
        includeFooter: Bool,
        typeScale: CGFloat
    ) -> CGFloat {
        func line(_ size: CGFloat) -> CGFloat { size * preset.lineFactor * typeScale }
        var rows: [CGFloat] = [line(preset.kicker)]
        switch page {
        case .exerciseManual, .exerciseTimed:
            rows.append(line(preset.title) * 2)
            if showsDetail { rows.append(line(preset.detail)) }
            if page == .exerciseTimed {
                rows.append(preset.countdownExercise * preset.countdownFactor * typeScale)
            }
            rows.append(page == .exerciseManual ? preset.buttonManual : preset.buttonOther)
        case .rest:
            rows.append(preset.countdownRest * preset.countdownFactor * typeScale)
            if showsNext {
                rows.append(line(10) + 1 + line(13))
            }
            rows.append(preset.buttonOther)
        }
        if includeFooter { rows.append(line(preset.footer)) }
        let gaps = preset.spacing * CGFloat(max(0, rows.count - 1))
        return rows.reduce(0, +) + gaps
    }
}
