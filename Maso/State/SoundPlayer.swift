import AVFoundation
import Foundation

/// One policy for silent demos, feedback and optional speech. Configure before
/// constructing/preparing any player: even a muted AVPlayer can activate the
/// default soloAmbient session. Ambient implicitly mixes without ducking.
@MainActor
enum AppAudioSession {
    private static var tutorialPlaybackActive = false

    static func beginTutorialPlayback() {
        tutorialPlaybackActive = true
        _ = activateForFeedback()
    }

    static func endTutorialPlayback() {
        guard tutorialPlaybackActive else { return }
        tutorialPlaybackActive = false
        _ = configure()
    }

    @discardableResult
    static func configure() -> Bool {
        let session = AVAudioSession.sharedInstance()
        do {
            if tutorialPlaybackActive {
                if session.category != .playback || session.mode != .moviePlayback {
                    try session.setCategory(.playback, mode: .moviePlayback, options: [.mixWithOthers])
                }
                return true
            }
            let disruptiveOptions: AVAudioSession.CategoryOptions = [.duckOthers, .interruptSpokenAudioAndMixWithOthers]
            if session.category != .ambient || session.mode != .default ||
                !session.categoryOptions.intersection(disruptiveOptions).isEmpty {
                // Ambient enables mixWithOthers itself; do not request a
                // playback-only option or activate audio merely by opening App.
                try session.setCategory(.ambient, mode: .default, options: [])
            }
            return true
        } catch {
            #if DEBUG
            print("[Audio] Could not configure noninterrupting playback: \(error)")
            #endif
            return false
        }
    }

    static func activateForFeedback() -> Bool {
        guard configure() else { return false }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            return true
        } catch { return false }
    }
}

/// Shared training feedback: synthesized click/tick, approved glass completion cue,
/// and the user's level-up WAV for the celebration. Ambient audio respects silent
/// mode and mixes with Music/Spotify; it never ducks or interrupts their playback.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 短促"咔哒"click — 对齐 Apple Watch `.click` 触觉音的听感 (跳过/结束休息用).
    private var clickBuffer: AVAudioPCMBuffer?
    enum CompletionAsset: String {
        case exercise = "masso-celebration-glass"
        case workout = "masso-celebration-levelup"
    }
    private var assetPlayers: [CompletionAsset: AVAudioPlayer] = [:]
    /// 极轻 tick — onboarding 拨盘吸附换值用 (比 click 小声, 连续滚动不刺耳).
    private var tickBuffer: AVAudioPCMBuffer?
    private var initialized = false

    private init() {}

    /// 真正启动 engine — 第一次调 play 才初始化, 避免 cold start 时无谓占音频会话.
    /// (用户可能刚开 app 就在听音乐, 我们不希望立刻去 set category 干扰它.)
    private func setupIfNeeded() -> Bool {
        // Recheck even after engine initialization (e.g. after returning from
        // a system media presentation). Failure means skip our sound.
        guard AppAudioSession.activateForFeedback() else { return false }
        if initialized {
            do {
                if !engine.isRunning { try engine.start() }
                return true
            } catch { return false }
        }

        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        if player.engine == nil {
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }

        clickBuffer = generateClick(format: format)
        tickBuffer = generateClick(format: format, gain: 0.11)   // 拨盘 tick — 更轻

        do {
            try engine.start()
            initialized = true
            return true
        } catch {
            return false
        }
    }

    /// 生成一个简短轻柔的"咔哒"click — 听感对齐 Apple Watch `.click`.
    ///
    /// 设计: 不用乐音 (旧版那种和弦/旋律太"演出"), 改成一个短促打击感的 tick.
    ///   - 极短 (~38ms), 极快 attack (~0.3ms) → 干脆利落, 不拖泥带水
    ///   - 一个中频"tock"主体 (~620Hz, 快衰减) + 一个高频亮 transient (~1900Hz, 更快衰减)
    ///     两层叠出"哒"的木感, 而非单频"哔"
    ///   - 起手 ~几ms 叠一点确定性噪声 → 给"咔"的颗粒感 (taptic 那种机械 click 感)
    ///   - 音量压低 → 跟手表那一下一样轻, 不抢戏
    private func generateClick(format: AVAudioFormat, gain: Double = 0.22) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.038
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount

        let chL = buf.floatChannelData![0]
        let chR = buf.floatChannelData![1]

        // 确定性伪随机 (LCG) — 给起手的"咔"颗粒, 不依赖系统 RNG, 每次生成一致.
        var seed: UInt32 = 0x9E3779B9
        func noise() -> Double {
            seed = seed &* 1664525 &+ 1013904223
            return Double(seed) / Double(UInt32.max) * 2 - 1   // [-1, 1]
        }

        let fBody = 620.0     // 中频"tock"主体
        let fTick = 1900.0    // 高频亮 transient

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let attack = min(1.0, t / 0.0003)
            // 三层包络: 噪声起手最快灭, body 中速, tick 较快
            let nEnv = exp(-t * 420)
            let bodyEnv = exp(-t * 95)
            let tickEnv = exp(-t * 190)
            let n = noise() * nEnv * 0.30
            let body = sin(2 * .pi * fBody * t) * bodyEnv * 0.6
            let tick = sin(2 * .pi * fTick * t) * tickEnv * 0.35
            let sample = Float((n + body + tick) * attack * gain)
            chL[i] = sample
            chR[i] = sample
        }
        return buf
    }

    private func playClick() {
        guard setupIfNeeded(), let buf = clickBuffer else { return }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Onboarding 拨盘吸附换值 — 一声极轻 tick (随静音开关静默, 不打断音乐).
    func playTick() {
        guard setupIfNeeded(), let buf = tickBuffer else { return }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// 通用按钮点击 — 清脆 click (比 tick 实, 给"按下/前进"的完成感; onboarding 各步按钮用).
    func playTap() { playClick() }

    /// Preload before the celebration clock begins; WAV already includes the approved 0.38 gain.
    func prepareCelebration() {
        guard AppAudioSession.activateForFeedback() else { return }
        _ = assetPlayer(.workout)
    }

    private func assetPlayer(_ asset: CompletionAsset) -> AVAudioPlayer? {
        if let cached = assetPlayers[asset] { return cached }
        guard let url = WorkoutCelebrationConfiguration.resource(asset.rawValue, extension: "wav"),
              let audio = try? AVAudioPlayer(contentsOf: url) else { return nil }
        audio.volume = 1 // Do not apply the exported gain twice.
        audio.prepareToPlay()
        assetPlayers[asset] = audio
        return audio
    }

    private func playAsset(_ asset: CompletionAsset) {
        // prepareToPlay() can activate the session, so policy MUST come first.
        guard AppAudioSession.activateForFeedback() else { return }
        guard let audio = assetPlayer(asset) else { return }
        if initialized { player.stop() }
        for other in assetPlayers.values { other.stop() }
        audio.currentTime = 0
        audio.play()
    }

    func playCelebration() { playAsset(.workout) }
    func stopCelebration() { assetPlayers[.workout]?.stop() }
    func playSetComplete() { playAsset(.exercise) }

    /// 休息结束 / 跳过休息 — 一声 watch 风格的 click (保持简短, 不跟完成 chime 混淆).
    func playRestEnded() { playClick() }

    /// 进入休息 — 保持静默 (对齐 Apple Watch: 进休息只给触觉 `.stop`, 无独立提示音;
    /// 否则"完成组 click → 进休息又一声"会变成两声, 跟手表的单 click 不一致).
    /// 方法保留是为 call-site 兼容 (TrainingSession.advance 仍调它).
    func playEnterRest() {}
}
