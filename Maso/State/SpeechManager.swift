import AVFoundation
import Observation

// 系统级 TTS 包装 — 给 "How to do it" 之类的说明文本朗读用.
//
// 用 iOS 原生 AVSpeechSynthesizer:
//   - 离线 (不依赖网络)
//   - 免费 (没 API quota)
//   - 12+ 语言全覆盖 (跟 Maso i18n 完美对接)
//   - Siri Voice / Enhanced voice 自动升级路径 — 用户在 Settings → Accessibility →
//     Spoken Content → Voices 下载高质量声音后, 这里自动用上, 不用改代码
//
// 跟其他第三方 TTS (OpenAI / ElevenLabs) 比, system AVSpeechSynthesizer 在 fitness app 这个
// 场景下是最对的选择 — 低 latency / 离线 / 多语言 / 隐私本地.
//
// 单 instance — `shared`. 全 app 共用一个 synthesizer, 避免多 sheet 同时播音叠播.
// `currentSource: String?` 用 caller 传的 source id (e.g. exercise.id) 跟踪"谁在播",
// view 用 `manager.currentSource == self.exercise.id && manager.isSpeaking` 来决定按钮态.

@Observable
@MainActor
final class SpeechManager: NSObject {
    static let shared = SpeechManager()

    private let synthesizer = AVSpeechSynthesizer()

    /// 当前是否在朗读. 由 delegate (didFinish / didCancel) 维护. View 可 observe 切换按钮 icon.
    private(set) var isSpeaking: Bool = false

    /// 当前朗读源的 id — caller 传 (e.g. exercise.id). nil = 没有在播.
    /// 让 view 判断"我是不是当前播放源" — 多个 sheet 共存时各自按钮态正确.
    private(set) var currentSource: String? = nil

    override init() {
        super.init()
        synthesizer.delegate = self
        configureAudioSession()
    }

    /// 配置 AVAudioSession — .playback 类别让 app 后台仍能继续朗读 (e.g. 用户切到锁屏).
    /// .duckOthers + .mixWithOthers 让背景音乐变小但不停, 跟 iOS 系统 TTS 行为一致.
    private func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(
                .playback,
                mode: .spokenAudio,
                options: [.duckOthers, .mixWithOthers]
            )
        } catch {
            print("[Speech] AVAudioSession setup failed: \(error)")
        }
    }

    /// 朗读一组步骤 (内部拼接成一段, 用 ". " 分隔让 TTS 在句号处自然停顿模拟"步骤分隔").
    /// - parameter steps: 简化版 instructions 或任何 [String]
    /// - parameter locale: BCP-47 voice locale (e.g. "en-US"). nil = 用系统当前语言
    /// - parameter source: 标识 caller (e.g. exercise.id) — view 用它判断按钮态
    func speak(steps: [String], locale: String? = nil, source: String) {
        // 先停旧的 — 不管谁触发的, 防叠播
        synthesizer.stopSpeaking(at: .immediate)
        currentSource = source

        let text = steps
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ". ")
        guard !text.isEmpty else { return }

        let utterance = AVSpeechUtterance(string: text)
        let voiceLocale = locale ?? Locale.current.identifier
        utterance.voice = bestVoice(for: voiceLocale)
        // 0.95 × 默认速率 — instructions 比对话需要听清楚, 稍慢一点
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 0.95
        utterance.pitchMultiplier = 1.0
        utterance.volume = 1.0
        utterance.postUtteranceDelay = 0.0

        // 激活 audio session — 不激活的话锁屏 / 切 app 后会停
        try? AVAudioSession.sharedInstance().setActive(true)
        synthesizer.speak(utterance)
        isSpeaking = true
    }

    /// 立即停止朗读. 用户主动 tap stop / sheet dismiss / 切换语言 时调用.
    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // isSpeaking / currentSource 由 delegate 的 didCancel 重置, 但为了 UI 立即响应, 这里也 set.
        isSpeaking = false
        currentSource = nil
    }

    /// 拿"最好的"语音 — 优先 Enhanced / Premium 质量声 (Siri voice 系列), fallback default.
    ///
    /// iOS 16+ Enhanced / Premium 声音需要用户在 Settings → Accessibility → Spoken Content
    /// → Voices 下载. 没下载时 default 是标准合成声 (能听清). 已下载时这里自动用上 — 不用让用户
    /// 在 app 内额外配置.
    private func bestVoice(for localeId: String) -> AVSpeechSynthesisVoice? {
        let voiceLocale = Self.mapToVoiceLocale(localeId)
        let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == voiceLocale }
        // 优先 premium → enhanced → default
        if let premium = voices.first(where: { $0.quality == .premium }) {
            return premium
        }
        if let enhanced = voices.first(where: { $0.quality == .enhanced }) {
            return enhanced
        }
        return AVSpeechSynthesisVoice(language: voiceLocale)
    }

    /// LanguageManager 用的 BCP-47 → AVSpeechSynthesisVoice 用的完整 BCP-47.
    /// AVSpeechSynthesisVoice 需要 region 后缀 (e.g. "en-US" 而不是 "en").
    /// 单 language code → 默认 region; zh-Hans → zh-CN, zh-Hant → zh-TW.
    static func mapToVoiceLocale(_ code: String) -> String {
        // 已经带 region 的直接用
        if code.contains("-") {
            switch code {
            case "zh-Hans": return "zh-CN"
            case "zh-Hant": return "zh-TW"
            default: return code  // "pt-BR" 等
            }
        }
        // 单 language code → 默认 region
        switch code.prefix(2).lowercased() {
        case "en": return "en-US"
        case "zh": return "zh-CN"
        case "ja": return "ja-JP"
        case "ko": return "ko-KR"
        case "es": return "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "it": return "it-IT"
        case "pt": return "pt-BR"
        case "ru": return "ru-RU"
        case "ar": return "ar-SA"
        default:   return code  // 兜底原值
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate (driven from synthesizer thread, marshal to MainActor)

extension SpeechManager: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentSource = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
            self.currentSource = nil
        }
    }
}
