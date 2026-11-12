import SwiftUI
import CoreHaptics
import AVFoundation

/// The approved web export is the source of truth; metadata/recipes are not executed.
struct WorkoutCelebrationConfiguration: Decodable {
    struct Motion: Decodable {
        var enterDelay = 0.0, size = 104.0, startScale = 0.16, peakScale = 1.55, growTime = 0.36
        var response = 0.4, damping = 0.3, springVelocity = 0.0
        var turns = 1.9, spinTime = 1.05, spinPower = 3.1, direction = 1.0
        var checkDelay = 0.0, checkTime = 0.26, checkStart = 0.55, checkResponse = 0.3, checkDamping = 0.65, stroke = 8.0
        var titleDelay = 0.14, titleTime = 0.3
    }
    struct Confetti: Decodable {
        var confettiOffset = 0.0, count = 150, life = 2.6, speed = 850.0, gravity = 900.0, spread = 70.0, drag = 0.75
        var pieceSize = 6.0, flutter = 1.2, emission = 0.12, origin = 0.65, mode = "sides", seed: UInt32 = 42
        var colors = ["#15ce59", "#f4c544", "#399dff", "#f26c74", "#ffffff"]
    }
    struct Sound: Decodable {
        var sound = "levelup", volume = 0.38, transpose = 0.0, audioTempo = 1.0, tail = 1.0, audioOffset = 0.0
    }
    struct Haptic: Decodable {
        var haptic = true, intensity = 0.65, sharpness = 0.5, hapticCount = 2, hapticGap = 0.09
    }
    var motion = Motion(), confetti = Confetti(), sound = Sound(), haptics = Haptic()
    static let approved: Self = {
        guard let url = resource("WorkoutCelebration", extension: "json"),
              let data = try? Data(contentsOf: url),
              let config = try? JSONDecoder().decode(Self.self, from: data) else { return .init() }
        return config
    }()
    static func resource(_ name: String, extension ext: String) -> URL? {
        Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Celebration")
    }
    var anchor: Double { motion.enterDelay + motion.growTime + motion.checkDelay }
    var duration: Double {
        max(motion.enterDelay + motion.spinTime + 0.3,
            anchor + confetti.confettiOffset + confetti.life + confetti.emission + 0.3,
            anchor + sound.audioOffset + 2.4 * sound.tail / sound.audioTempo,
            anchor + motion.titleDelay + motion.titleTime + 0.5,
            motion.enterDelay + motion.growTime + 6 * motion.response / max(1, 8 * motion.damping))
    }
    static func unit(_ value: Double) -> Double { min(1, max(0, value)) }
    static func spring(_ time: Double, from: Double, to: Double, response: Double, damping: Double, velocity: Double = 0) -> Double {
        guard time > 0 else { return from }
        let w = 2 * Double.pi / response, x = from - to
        if damping >= 0.999 { return to + (x + (velocity + w * x) * time) * exp(-w * time) }
        let wd = w * sqrt(1 - damping * damping), b = (velocity + damping * w * x) / wd
        return to + exp(-damping * w * time) * (x * cos(wd * time) + b * sin(wd * time))
    }
    struct Frame {
        let scale: Double, angle: Double, opacity: Double, checkOpacity: Double, checkScale: Double, checkStroke: Double, titleOpacity: Double
    }
    func frame(at time: Double, reducedMotion: Bool = false) -> Frame {
        let m = motion, elapsed = time - m.enterDelay, q = time - anchor
        let u = Self.unit(elapsed / m.growTime)
        let scale: Double
        if elapsed < 0 { scale = m.startScale }
        else if elapsed < m.growTime { scale = m.startScale + (m.peakScale - m.startScale) * (1 - pow(1 - u, 3)) }
        else { scale = Self.spring(elapsed - m.growTime, from: m.peakScale, to: 1, response: m.response, damping: m.damping, velocity: m.springVelocity) }
        return .init(scale: reducedMotion ? 1 : scale,
                     angle: reducedMotion ? 0 : -m.direction * m.turns * 360 * pow(1 - Self.unit(elapsed / m.spinTime), m.spinPower),
                     opacity: Self.unit(elapsed / 0.12), checkOpacity: Self.unit(q / min(m.checkTime, 0.12)),
                     checkScale: reducedMotion ? 1 : Self.spring(max(0, q), from: m.checkStart, to: 1, response: m.checkResponse, damping: m.checkDamping),
                     checkStroke: reducedMotion ? Self.unit(q / 0.15) : 1 - pow(1 - Self.unit(q / m.checkTime), 3),
                     titleOpacity: Self.unit((q - m.titleDelay) / m.titleTime))
    }
}

/// Separate layers: the check never rotates with the seal.
struct WorkoutCelebrationSymbol: View {
    let configuration: WorkoutCelebrationConfiguration
    let frame: WorkoutCelebrationConfiguration.Frame
    var body: some View {
        ZStack {
            CelebrationSeal().fill(MasoColor.accent)
                .scaleEffect(frame.scale).rotationEffect(.degrees(frame.angle)).opacity(frame.opacity)
            CelebrationCheck().trim(from: 0, to: frame.checkStroke)
                .stroke(MasoColor.background, style: StrokeStyle(lineWidth: configuration.motion.stroke * configuration.motion.size / 120,
                                                                lineCap: .round, lineJoin: .round))
                .scaleEffect(frame.checkScale).opacity(frame.checkOpacity)
        }.frame(width: configuration.motion.size, height: configuration.motion.size)
            .accessibilityHidden(true)
    }
}
private struct CelebrationSeal: Shape {
    func path(in rect: CGRect) -> Path {
        let points = (0..<16).map { index -> CGPoint in
            let angle = Double(index) * .pi / 8 - .pi / 2, radius = index % 2 == 0 ? 59.0 : 48.0
            return CGPoint(x: (60 + cos(angle) * radius) / 120 * rect.width, y: (60 + sin(angle) * radius) / 120 * rect.height)
        }
        func mid(_ a: CGPoint, _ b: CGPoint) -> CGPoint { .init(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2) }
        var path = Path(); path.move(to: mid(points[15], points[0]))
        for index in 0..<16 { path.addQuadCurve(to: mid(points[index], points[(index + 1) % 16]), control: points[index]) }
        path.closeSubpath(); return path
    }
}
private struct CelebrationCheck: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: .init(x: rect.width * 37 / 120, y: rect.height * 61 / 120))
        path.addLine(to: .init(x: rect.width * 53 / 120, y: rect.height * 78 / 120))
        path.addLine(to: .init(x: rect.width * 85 / 120, y: rect.height * 40 / 120)); return path
    }
}

struct CelebrationParticle {
    let side: Int, xRandom: Double, vx: Double, vy: Double, delay: Double, size: Double, rotation: Double, angular: Double, phase: Double
    static func make(_ config: WorkoutCelebrationConfiguration.Confetti) -> [Self] {
        var state = config.seed
        func random() -> Double {
            state &+= 0x6D2B79F5
            var t = state; t = (t ^ (t >> 15)) &* (t | 1)
            t ^= t &+ ((t ^ (t >> 7)) &* (t | 61))
            return Double(t ^ (t >> 14)) / 4_294_967_296
        }
        return (0..<config.count).map { index in
            let side = index % 2
            let angle = (-90 + (random() - 0.5) * config.spread + (config.mode == "sides" ? (side == 1 ? -32 : 32) : 0)) * .pi / 180
            let speed = config.speed * (0.65 + random() * 0.5)
            let x = config.mode == "rain" ? random() : 0
            return .init(side: side, xRandom: x, vx: config.mode == "rain" ? (random() - 0.5) * 160 : cos(angle) * speed,
                         vy: config.mode == "rain" ? speed * 0.24 : sin(angle) * speed,
                         delay: random() * config.emission, size: config.pieceSize * (0.65 + random() * 0.7),
                         rotation: random() * .pi * 2, angular: (random() - 0.5) * 12, phase: random() * 6.28)
        }
    }
    func position(at elapsed: Double, config: WorkoutCelebrationConfiguration.Confetti, size canvas: CGSize) -> (point: CGPoint, angle: Double, alpha: Double)? {
        let t = elapsed - delay
        guard t >= 0, t <= config.life else { return nil }
        let k = config.drag, decay = k > 0 ? (1 - exp(-k * t)) / k : t, scale = canvas.width / 390
        let originX = config.mode == "sides" ? (side == 1 ? canvas.width + 6 * scale : -6 * scale) : config.mode == "center" ? canvas.width / 2 : xRandom * canvas.width
        let originY = config.mode == "rain" ? -15 * scale : config.mode == "center" ? canvas.height * 0.39 : canvas.height * config.origin
        let y = k > 0 ? (vy - config.gravity / k) * decay + config.gravity * t / k : vy * t + 0.5 * config.gravity * t * t
        return (.init(x: originX + (vx * decay + sin(t * 6 + phase) * config.flutter * 7 * t) * scale, y: originY + y * scale),
                rotation + angular * t, 1 - WorkoutCelebrationConfiguration.unit((t - config.life * 0.62) / (config.life * 0.38)))
    }
}
struct WorkoutCelebrationConfetti: View {
    let configuration: WorkoutCelebrationConfiguration
    let elapsed: Double
    private static let particles = CelebrationParticle.make(WorkoutCelebrationConfiguration.approved.confetti)
    private static let palette = WorkoutCelebrationConfiguration.approved.confetti.colors.map { hex -> Color in
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0x15ce59
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
    var body: some View {
        Canvas { context, canvas in
            let c = configuration.confetti, local = elapsed - configuration.anchor - c.confettiOffset, scale = canvas.width / 390
            for (index, p) in Self.particles.enumerated() {
                guard let state = p.position(at: local, config: c, size: canvas) else { continue }
                var copy = context; copy.opacity = state.alpha
                copy.translateBy(x: state.point.x, y: state.point.y); copy.rotate(by: .radians(state.angle))
                let width = p.size * max(0.18, abs(cos(local * 7 + p.phase))) * scale
                copy.fill(Path(CGRect(x: -width / 2, y: -p.size * scale, width: width, height: p.size * 1.8 * scale)),
                          with: .color(Self.palette[index % Self.palette.count]))
            }
        }.allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// Prepared before the visual clock starts, then fired at the common success anchor.
@MainActor
final class WorkoutCelebrationFeedback {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private var haptic = WorkoutCelebrationConfiguration.Haptic()
    func prepare(_ configuration: WorkoutCelebrationConfiguration) {
        SoundPlayer.shared.prepareCelebration()
        haptic = configuration.haptics
        guard haptic.haptic, CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            guard AppAudioSession.configure() else { return }
            let engine = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
            engine.playsHapticsOnly = true; engine.isAutoShutdownEnabled = true
            try engine.start()
            let events = (0..<haptic.hapticCount).map { index in
                CHHapticEvent(eventType: .hapticTransient, parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(haptic.intensity)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(haptic.sharpness))
                ], relativeTime: Double(index) * haptic.hapticGap)
            }
            player = try engine.makePlayer(with: CHHapticPattern(events: events, parameters: [])); self.engine = engine
        } catch { player = nil; engine = nil }
    }
    func play() {
        SoundPlayer.shared.playCelebration()
        guard haptic.haptic else { return }
        if let engine, let player {
            do { try engine.start(); try player.start(atTime: CHHapticTimeImmediate); return } catch {}
        }
        Haptics.trainingComplete()
    }
    func cancel() {
        try? player?.stop(atTime: CHHapticTimeImmediate)
        SoundPlayer.shared.stopCelebration()
    }
}
