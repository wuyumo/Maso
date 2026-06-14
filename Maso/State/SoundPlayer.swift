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
    /// 当前 setComplete 音色: "任务完成 / 打钩"感的上行大三和弦琶音 (C6 → E6 → G6, do-mi-sol).
    /// 三音快速上行后收在最高音 (G6) 并多响一会 = "解决/收束"感; 每音叠一层八度泛音给钟铃微光.
    /// 比旧的 iMessage 单跳 (G5→D6) 更有"✓ 这组搞定了"的成就/收尾感.
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

        // set-complete: "任务完成 / 打钩"感的上行大三和弦琶音 (C6→E6→G6, ~340ms).
        // do-mi-sol 快速上行收在 G6 = 明确的"解决/收尾"感; 比旧 iMessage 单跳更有成就感.
        setCompleteBuffer = generateTaskComplete(format: format)

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

    /// 生成"任务完成 / 打钩"感的上行大三和弦琶音 — do-mi-sol (C6→E6→G6).
    /// 设计意图: 三个音快速错峰上行、最后收在最高音 (G6) 并多 ring 一会 → 明确的"解决/收尾"感,
    /// 就是"完成任务打个钩"的成就声. 每音叠一层八度泛音 (×2) 给钟铃般的微光.
    ///
    /// 结构:
    ///   - 3 个音错峰起音 (0 / 55ms / 110ms), 后音在前音还在响时切入 → 琶音上行感 + 末尾叠成和弦
    ///   - 末音 G6 衰减更慢 (decay 7 vs 11) → 多 ring 一会, 给"落定"感
    ///   - 每音: 基频 + 八度泛音 (0.18 音量, 钟铃亮度), 快 attack 4ms (清脆不刺)
    ///   - 总时长 ~340ms — 比旧单跳 (210ms) 略长但有"完成"分量, 单组重复也不腻
    private func generateTaskComplete(format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let sampleRate = format.sampleRate
        let durationSeconds = 0.34
        let frameCount = AVAudioFrameCount(sampleRate * durationSeconds)
        guard let buf = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else { return nil }
        buf.frameLength = frameCount

        let chL = buf.floatChannelData![0]
        let chR = buf.floatChannelData![1]

        // C 大三和弦琶音 (do-mi-sol), 落在 G6 = 明亮稳定的收束.
        struct Note { let freq: Double; let start: Double; let decay: Double }
        let notes = [
            Note(freq: 1046.50, start: 0.000, decay: 11),  // C6 (do)
            Note(freq: 1318.51, start: 0.055, decay: 11),  // E6 (mi)
            Note(freq: 1567.98, start: 0.110, decay: 7),   // G6 (sol) — 落定, ring 更长
        ]

        for i in 0..<Int(frameCount) {
            let t = Double(i) / sampleRate
            var s = 0.0
            for n in notes {
                let lt = t - n.start          // 该音的本地时间 (相位从 0 起, 起音干净)
                guard lt >= 0 else { continue }
                let attack = min(1.0, lt / 0.004)
                let decay = exp(-lt * n.decay)
                let env = attack * decay
                let fund = sin(2 * .pi * n.freq * lt)
                let oct  = sin(2 * .pi * n.freq * 2 * lt) * 0.18   // 八度泛音 — 钟铃微光
                s += (fund + oct) * env * 0.5
            }
            let sample = Float(s * 0.42)
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

    /// 力量组完成 — "任务完成/打钩"感的上行大三和弦琶音 (~340ms, C6→E6→G6 do-mi-sol)
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
