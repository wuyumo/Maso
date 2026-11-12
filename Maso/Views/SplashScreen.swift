import SwiftUI

/// Approved splash-lab export. Preview language never overrides the App language.
struct SplashMotionConfiguration: Decodable {
    struct Motion: Decodable {
        var logoSize: Double = 160
        var wordSize: Double = 28
        var tagSize: Double = 16
        var logoGap: Double = 56
        var textGap: Double = 8
        var verticalOffset: Double = -40
        var response: Double = 0.45
        var damping: Double = 0.92
        var stagger: Double = 0.035
        var travel: Double = 18
        var wordDelay: Double = 0.22
        var wordTime: Double = 0.32
        var tagDelay: Double = 0.62
        var tagTime: Double = 0.36
        var textTravel: Double = 6
        var exitAt: Double = 1.55
        var exitTime: Double = 0.22
        var logoMode: String = "slide"
        var wordMode: String = "fade"
        var tagMode: String = "rise"
    }
    var schema = "masso.splash-motion"
    var version = 1
    var preset = "F"
    var motion = Motion()

    static let approved: Self = {
        guard let url = Bundle.main.url(forResource: "SplashMotion", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let value = try? JSONDecoder().decode(Self.self, from: data),
              value.schema == "masso.splash-motion", value.version == 1,
              value.motion.logoMode == "slide", value.motion.wordMode == "fade", value.motion.tagMode == "rise",
              value.motion.response > 0, (0.01...1).contains(value.motion.damping) else {
            // A packaging failure must never prevent the App from opening.
            return Self()
        }
        return value
    }()

    var exitStart: Double {
        max(motion.exitAt, max(0.4, motion.response * 2) + 4 * motion.stagger,
            motion.wordDelay + motion.wordTime + 0.1, motion.tagDelay + motion.tagTime + 0.1)
    }
    func duration(reducedMotion: Bool) -> Double { reducedMotion ? 0.53 : exitStart + motion.exitTime }
    func exitStart(reducedMotion: Bool) -> Double { reducedMotion ? 0.35 : exitStart }

    func layer(_ index: Int, at time: Double, reducedMotion: Bool) -> (opacity: Double, x: Double) {
        let order = [2, 1, 3, 0, 4]
        let delay = reducedMotion ? 0 : Double(order.firstIndex(of: index) ?? 0) * motion.stagger
        let elapsed = max(0, time - delay)
        let progress = min(elapsed, max(0.4, motion.response * 2))
        let x = reducedMotion ? 0 : -motion.travel * (1 - spring(progress))
        let alpha = min(1, elapsed / (reducedMotion ? 0.18 : 0.24))
        return (MasoBrandLogo.defaultOpacities[index] * alpha, x)
    }
    func wordOpacity(at time: Double, reducedMotion: Bool) -> Double {
        fraction(time, start: reducedMotion ? 0 : motion.wordDelay, duration: reducedMotion ? 0.18 : motion.wordTime)
    }
    func tag(at time: Double, reducedMotion: Bool) -> (opacity: Double, y: Double) {
        let q = fraction(time, start: reducedMotion ? 0.08 : motion.tagDelay, duration: reducedMotion ? 0.18 : motion.tagTime)
        return (min(1, q * (reducedMotion ? 1 : 2)), reducedMotion ? 0 : motion.textTravel * pow(1 - q, 3))
    }
    func exit(at time: Double, reducedMotion: Bool) -> Double {
        let q = fraction(time, start: exitStart(reducedMotion: reducedMotion), duration: reducedMotion ? 0.18 : motion.exitTime)
        return 1 - pow(1 - q, 3)
    }
    private func fraction(_ time: Double, start: Double, duration: Double) -> Double {
        min(1, max(0, (time - start) / duration))
    }
    private func spring(_ time: Double) -> Double {
        let w = 2 * Double.pi / motion.response, z = motion.damping
        if z >= 1 { return 1 - (1 + w * time) * exp(-w * time) }
        let wd = w * sqrt(1 - z * z)
        return 1 - exp(-z * w * time) * (cos(wd * time) + z * w / wd * sin(wd * time))
    }
}

/// Pure sampled frame, shared by live playback and native visual validation.
struct SplashMotionFrame: View {
    let time: Double
    var reducedMotion = false
    var configuration = SplashMotionConfiguration.approved
    @ScaledMetric(relativeTo: .title) private var wordScale = 1.0
    @ScaledMetric(relativeTo: .subheadline) private var tagScale = 1.0

    var body: some View {
        let motion = configuration.motion
        let exit = configuration.exit(at: time, reducedMotion: reducedMotion)
        let tag = configuration.tag(at: time, reducedMotion: reducedMotion)
        ZStack {
            Color.black
            VStack(spacing: motion.logoGap) {
                logo.frame(width: motion.logoSize, height: motion.logoSize)
                    .background {
                        RadialGradient(stops: [
                            .init(color: MasoColor.accent.opacity(0.22), location: 0),
                            .init(color: MasoColor.accent.opacity(0.14), location: 0.28),
                            .init(color: MasoColor.accent.opacity(0.05), location: 0.60),
                            .init(color: MasoColor.accent.opacity(0), location: 1)
                        ], center: .center, startRadius: 0, endRadius: motion.logoSize * 1.1)
                        .frame(width: motion.logoSize * 2.2, height: motion.logoSize * 2.2)
                        // Use the first logo layer's existing reveal; no extra timer or layout space.
                        .opacity(configuration.layer(2, at: time, reducedMotion: reducedMotion).opacity)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                VStack(spacing: motion.textGap) {
                    Text(verbatim: "Masso")
                        .font(.system(size: motion.wordSize * wordScale, weight: .bold))
                        .tracking(-0.3).foregroundStyle(MasoColor.text)
                        .frame(minHeight: motion.wordSize * wordScale * 1.2)
                        .opacity(configuration.wordOpacity(at: time, reducedMotion: reducedMotion))
                    Text(MasoBrand.splashSlogan)
                        .font(.system(size: motion.tagSize * tagScale))
                        .tracking(0.2).foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3 * tagScale)
                        .padding(.horizontal, 16)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(minHeight: motion.tagSize * tagScale * 1.4)
                        .opacity(tag.opacity).offset(y: tag.y)
                }
            }
            .scaleEffect(reducedMotion ? 1 : 1 - 0.03 * exit)
            .offset(y: motion.verticalOffset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .opacity(1 - exit)
        .ignoresSafeArea()
    }
    private var logo: some View {
        ZStack {
            layer(BrandEcho1(), index: 0)
            layer(BrandEcho2(), index: 1)
            layer(BrandBar1(), index: 2)
            layer(BrandBar2(), index: 3)
            layer(BrandBar3(), index: 4)
        }
        .environment(\.layoutDirection, .leftToRight)
        .accessibilityLabel("Masso")
    }
    private func layer<S: Shape>(_ shape: S, index: Int) -> some View {
        let state = configuration.layer(index, at: time, reducedMotion: reducedMotion)
        return shape.fill(MasoColor.accent)
            .opacity(state.opacity).offset(x: state.x)
    }
}

struct SplashScreen: View {
    /// Optional preview/test injection; production always follows the system preference.
    var reducedMotionOverride: Bool? = nil
    var onPrepare: () -> Void = {}
    var onExit: () -> Void = {}
    let onDone: () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var startedAt: Date?
    @State private var prepared = false
    @State private var exitStartedAt: Date?
    @State private var exitNotified = false
    @State private var completed = false
    private let configuration = SplashMotionConfiguration.approved
    private var reducedMotion: Bool { reducedMotionOverride ?? systemReduceMotion }
    private var playbackID: Int { scenePhase == .active ? (reducedMotion ? 2 : 1) : 0 }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: completed || scenePhase != .active)) { context in
            let elapsed = startedAt.map { max(0, context.date.timeIntervalSince($0)) } ?? 0
            let exitStart = configuration.exitStart(reducedMotion: reducedMotion)
            let frameTime = exitStartedAt.map { exitStart + max(0, context.date.timeIntervalSince($0)) }
                ?? min(elapsed, exitStart)
            SplashMotionFrame(time: frameTime, reducedMotion: reducedMotion, configuration: configuration)
        }
        .task(id: playbackID) {
            guard scenePhase == .active, !completed else { return }
            if startedAt == nil { startedAt = Date() }
            guard let start = startedAt else { return }
            do {
                if !prepared {
                    // Build the home behind the fully visible splash, before its fade begins.
                    let prepareAt = reducedMotion ? 0.18 : 1.05
                    let remaining = max(0, prepareAt - Date().timeIntervalSince(start))
                    try await Task.sleep(for: .seconds(remaining))
                    try Task.checkCancellation()
                    prepared = true
                    onPrepare()
                    // Give SwiftUI time to mount the home before beginning the exit.
                    try await Task.sleep(for: .seconds(reducedMotion ? 0.17 : 0.5))
                    try Task.checkCancellation()
                }
                if !exitNotified {
                    let remaining = max(0, configuration.exitStart(reducedMotion: reducedMotion) - Date().timeIntervalSince(start))
                    try await Task.sleep(for: .seconds(remaining))
                    try Task.checkCancellation()
                    exitNotified = true
                    exitStartedAt = Date()
                    onExit()
                }
                let exitDuration = configuration.duration(reducedMotion: reducedMotion) - configuration.exitStart(reducedMotion: reducedMotion)
                let remaining = max(0, exitDuration - Date().timeIntervalSince(exitStartedAt ?? Date()))
                try await Task.sleep(for: .seconds(remaining))
                try Task.checkCancellation()
                completed = true
                onDone()
            } catch { /* Leaving or backgrounding cancels pending callbacks. */ }
        }
    }
}

#Preview { SplashScreen { } }
