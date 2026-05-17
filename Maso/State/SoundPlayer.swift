import AVFoundation
import Foundation

/// 训练中的 UI 音效播放器 — set complete / training complete 等高光节点用.
///
/// 关键约束: 不打断用户正在听的 Spotify / Music.
///   - AVAudioSession category = `.ambient` (UI 类音频, 不抢主播放权)
///   - options = `.mixWithOthers` (跟其它 app 的音轨叠加)
///   - 整体音量做了 -8dB 衰减让它"轻", 不抢戏
///
/// 音色是程序合成 (AVAudioEngine + sine wave 包络), 没有 bundle 音频文件 — 包体积小,
/// 调试 / 风格调整改参数即可.
@MainActor
final class SoundPlayer {
    static let shared = SoundPlayer()

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    /// 当前 setComplete 音色: "发送成功"风格上行二音 (G5 → D6, perfect fifth).
    /// 替代旧 chime (C6+G6+C7 钟形和声) — 钟声偏"任务完成", 上行音更像 iMessage send,
    /// 给用户"这一组发出去了"的语义感.
    private var setCompleteBuffer: AVAudioPCMBuffer?
    private var enterRestBuffer: AVAudioPCMBuffer?
    private var restEndedBuffer: AVAudioPCMBuffer?
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

        // set-complete: "发送成功"风格上行二音 (G5 → D6, perfect fifth, ~210ms).
        // 类似 iMessage send sound — 短上行 pitch sweep, 给"发出去了"的语义感.
        // 比旧 chime 更"前进感", 庆祝但不浮夸; 跟 rest-ended (E5→A5) 区分明显 (距离更大, 更亮).
        setCompleteBuffer = generateSendSuccess(format: format)

        // enter-rest: 比 set-complete 更柔, 给"该歇一歇"的氛围 — 下行小三度 (E5 → C5),
        // 长 attack 12ms 进音慢, 衰减 8 (中速).
        enterRestBuffer = generateDescend(format: format)

        // rest-ended: 短上行二音 (E5 → A5), 给"该回来练了"的提示感.
        // 比 enter-rest 更短促 (180ms), attack 更快 (3ms) — 切换 / 导航 性质而非"放下"性质.
        restEndedBuffer = generateAscend(format: format)

        do {
            try engine.start()
            initialized = true
        } catch {
            return
        }
    }

    /// 生成"发送成功"风格上行二音 — 类似 iMessage send sound.
    /// 设计意图: 给用户"这一组发出去了"的语义感, 而不是钟形"任务完成"感. 短上行音 + 干净.
    ///
    /// 频率:
    ///   - 起音 G5 (783.99 Hz) — 中音, 进音温和
    ///   - 终音 D6 (1174.66 Hz) — 上行 perfect fifth, 跳跃感明显
    ///   - 二倍泛音 (1.5×) — 提供"明亮"感, 但音量低 (0.15) 不抢主声
    ///
    /// 包络:
    ///   - attack 3ms (清晰但不刺耳)
    ///   - decay 12 (中速衰减, 200ms 内自然消失)
    ///
    /// blend:
    ///   - 前 50% 时间 G5 主导, 50% 转折点切到 D6
    ///   - 跟 rest-ended (E5→A5 perfect fourth) 区分明显: 距离更大, 终音更亮
    private func generateSendSuccess(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.21
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount

        let chL = buf.floatChannelData![0]
        let chR = buf.floatChannelData![1]

        let f1 = 783.99    // G5 (起音)
        let f2 = 1174.66   // D6 (终音, 上行 perfect fifth)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // attack 3ms 清晰起音, decay 12 中速衰减
            let attack = min(1.0, t / 0.003)
            let decay = exp(-t * 12)
            let env = attack * decay

            // f1 → f2 快速转折, 50% 处切换 (linear blend, 转折锐利, 听起来像"jump up"而非 sweep)
            let blend = min(1.0, t / durationSeconds / 0.5)
            let s1 = sin(2 * .pi * f1 * t) * (1 - blend) * 0.55
            let s2 = sin(2 * .pi * f2 * t) * blend * 0.55
            // 二倍泛音 — 给点"明亮"感, 跟着 f2 走 (前半静默, 后半带亮)
            let s3 = sin(2 * .pi * (f2 * 1.5) * t) * blend * 0.15

            let sample = Float((s1 + s2 + s3) * env * 0.4)
            chL[i] = sample
            chR[i] = sample
        }
        return buf
    }

    /// 生成"进入休息"的下行小三度 — 比 set-complete 更柔, 更"放下"感.
    /// E5 (659Hz) 主音前半, 后半下行到 C5 (523Hz). 长 attack 12ms 平滑入,
    /// 衰减 8 (中速, 比 chime 更长), 音量 0.28 (~-11dB) — 比 chime 更安静, 不抢戏.
    private func generateDescend(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.30
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount

        let chL = buf.floatChannelData![0]
        let chR = buf.floatChannelData![1]

        let f1 = 659.25  // E5
        let f2 = 523.25  // C5 (下行小三度 — "释放"感)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // 长 attack (12ms, 不刺耳) + 中速 exp 衰减 (8)
            let attack = min(1.0, t / 0.012)
            let decay = exp(-t * 8)
            let env = attack * decay
            // f1 前半主导, blend 到 f2 — 用 t/dur 的快线性曲线, 70% 时候转完
            let blend = min(1.0, t / durationSeconds / 0.7)
            let s1 = sin(2 * .pi * f1 * t) * (1 - blend) * 0.5
            let s2 = sin(2 * .pi * f2 * t) * blend * 0.5
            let sample = Float((s1 + s2) * env * 0.28)
            chL[i] = sample
            chR[i] = sample
        }
        return buf
    }

    /// 生成"休息结束"的上行二音 — E5 → A5, 短促, 给"切换 / 该练了"的提示感.
    /// 比 enterRest 更短 (180ms vs 300ms), attack 更快 (3ms vs 12ms) — 像"导航点击"而非"放下".
    /// 音量 0.32 (~-10dB) — 介于 chime 跟 enterRest 之间, 适中显眼但不抢戏.
    private func generateAscend(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.18
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount

        let chL = buf.floatChannelData![0]
        let chR = buf.floatChannelData![1]

        let f1 = 659.25  // E5
        let f2 = 880.0   // A5 (上行小四度 — 警觉感)

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            // 快 attack (3ms) + 中速衰减 (10)
            let attack = min(1.0, t / 0.003)
            let decay = exp(-t * 10)
            let env = attack * decay
            // f1 → f2 快速转音, 转点 50%
            let blend = min(1.0, t / durationSeconds / 0.5)
            let s1 = sin(2 * .pi * f1 * t) * (1 - blend) * 0.5
            let s2 = sin(2 * .pi * f2 * t) * blend * 0.5
            let sample = Float((s1 + s2) * env * 0.32)
            chL[i] = sample
            chR[i] = sample
        }
        return buf
    }

    /// 力量组完成 — "发送成功"风格上行二音 (~210ms, G5→D6 perfect fifth)
    func playSetComplete() {
        setupIfNeeded()
        guard let buf = setCompleteBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// 进入休息 — 一次轻下行音 (~300ms, E5→C5), 比 setComplete 柔和
    func playEnterRest() {
        setupIfNeeded()
        guard let buf = enterRestBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    /// 休息结束 — 上行二音 (~180ms, E5→A5), 提示"该练了"
    func playRestEnded() {
        setupIfNeeded()
        guard let buf = restEndedBuffer else { return }
        if !engine.isRunning { try? engine.start() }
        player.scheduleBuffer(buf, at: nil, options: [.interrupts], completionHandler: nil)
        if !player.isPlaying { player.play() }
    }
}
