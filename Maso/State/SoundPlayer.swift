import AVFoundation
import Foundation

/// 训练中的 UI 音效播放器 — set complete / skip rest 等节点用.
///
/// 2026-06-16: 应需求把音色对齐 Apple Watch —— watch 端这些动作用的是
/// `WKInterfaceDevice.play(.click)`, 一个简短的"咔哒"触觉音, 而不是 iPhone 旧版那种
/// do-mi-sol 和弦 / 上下行旋律. 这里改成合成一个同样简短轻柔的 click, 完成组 / 跳过休息
/// 都放这一声, 听感跟手表一致.
///
/// 关键约束: 不打断用户正在听的 Spotify / Music.
///   - AVAudioSession category = `.ambient` (UI 类音频, 不抢主播放权)
///   - options = `.mixWithOthers` (跟其它 app 的音轨叠加)
///
/// 音色是程序合成 (AVAudioEngine), 无 bundle 音频文件 — 包体积小, 调参即可改风格.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 短促"咔哒"click — 对齐 Apple Watch `.click` 触觉音的听感 (跳过/结束休息用).
    private var clickBuffer: AVAudioPCMBuffer?
    /// "完成动作组"的清单勾选感 chime — 两声上行小钟琴"叮-叮" (set complete 用).
    private var completeBuffer: AVAudioPCMBuffer?
    /// 极轻 tick — onboarding 拨盘吸附换值用 (比 click 小声, 连续滚动不刺耳).
    private var tickBuffer: AVAudioPCMBuffer?
    private var initialized = false

    private init() {}

    /// 真正启动 engine — 第一次调 play 才初始化, 避免 cold start 时无谓占音频会话.
    /// (用户可能刚开 app 就在听音乐, 我们不希望立刻去 set category 干扰它.)
    private func setupIfNeeded() {
        guard !initialized else { return }

        do {
            // .ambient + mixWithOthers — UI 音效, 跟用户的音乐叠加, 不会 ducking 或暂停.
            try AVAudioSession.sharedInstance().setCategory(
                .ambient, mode: .default,
                options: [.mixWithOthers]
            )
            try AVAudioSession.sharedInstance().setActive(true, options: [])
        } catch {
            // 设置失败也不 fatal — 音效不响就不响, 不影响训练流程.
            return
        }

        engine.attach(player)
        let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
        engine.connect(player, to: engine.mainMixerNode, format: format)

        clickBuffer = generateClick(format: format)
        tickBuffer = generateClick(format: format, gain: 0.11)   // 拨盘 tick — 更轻
        completeBuffer = generateComplete(format: format)

        do {
            try engine.start()
            initialized = true
        } catch {
            return
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

    /// 生成"完成动作组"的清单勾选感 chime — to-do 勾选那种"叮-叮"完成感.
    ///
    /// 设计 (参考通用 task-complete 音效: 简单两音 + 明亮上行 + 钟琴质感):
    ///   - 两声上行: G5 (784Hz) → D6 (1175Hz, 纯五度), 第二声晚 ~45ms 入 ("flam", 给俏皮的连击感)
    ///   - 每声 = 基频 + 八度泛音 + 十二度泛音 (递减) → 小钟琴 / 钢琴的玻璃亮质感, 不是干 click
    ///   - 软起手 ~4ms + 指数衰减 (第一声稍快收, 第二声 ring out 更长) → 收尾自然, 有"完成"余韵
    ///   - 总时长 ~340ms, 比 click 长、更"奖励感", 但仍短到不拖训练节奏; 音量适中 (奖励一下, 不刺耳)
    private func generateComplete(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.34
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount

        let chL = buf.floatChannelData![0]
        let chR = buf.floatChannelData![1]

        let f1 = 783.99    // G5
        let f2 = 1174.66   // D6 (上行纯五度) — 明亮、积极
        let off2 = 0.045   // 第二声 flam 延迟

        func voice(_ f: Double, _ t: Double, decay: Double) -> Double {
            guard t >= 0 else { return 0 }
            let env = exp(-t * decay) * min(1.0, t / 0.004)   // 4ms 软起手 + 指数衰减
            let h1 = sin(2 * .pi * f * t)
            let h2 = sin(2 * .pi * f * 2 * t) * 0.5
            let h3 = sin(2 * .pi * f * 3 * t) * 0.22
            return (h1 + h2 + h3) * env
        }

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            let n1 = voice(f1, t, decay: 9.5)          // 第一声稍快收
            let n2 = voice(f2, t - off2, decay: 6.5)   // 第二声 ring out 长一点
            let sample = Float((n1 * 0.5 + n2 * 0.62) * 0.3)
            chL[i] = sample
            chR[i] = sample
        }
        return buf
    }

    private func playComplete() {
        setupIfNeeded()
        guard let buf = completeBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    private func playClick() {
        setupIfNeeded()
        guard let buf = clickBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// Onboarding 拨盘吸附换值 — 一声极轻 tick (随静音开关静默, 不打断音乐).
    func playTick() {
        setupIfNeeded()
        guard let buf = tickBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// 通用按钮点击 — 清脆 click (比 tick 实, 给"按下/前进"的完成感; onboarding 各步按钮用).
    func playTap() { playClick() }

    /// 力量组完成 — 清单勾选感的上行"叮-叮" chime (比 click 更有"完成/奖励"感).
    /// 注: 仅 iPhone 端改成 chime; Apple Watch 完成组仍是 `.click` 触觉 (手表不走这套合成音).
    func playSetComplete() { playComplete() }

    /// 休息结束 / 跳过休息 — 一声 watch 风格的 click (保持简短, 不跟完成 chime 混淆).
    func playRestEnded() { playClick() }

    /// 进入休息 — 保持静默 (对齐 Apple Watch: 进休息只给触觉 `.stop`, 无独立提示音;
    /// 否则"完成组 click → 进休息又一声"会变成两声, 跟手表的单 click 不一致).
    /// 方法保留是为 call-site 兼容 (TrainingSession.advance 仍调它).
    func playEnterRest() {}
}
