import Foundation
import Observation

// 产品分析服务 — 单例, 仿 AIWorkoutService.shared (静态 config + 单例) + FeedbackStore (离线 outbox).
// 见 docs/analytics-design.md §4.
//
// 关键性质:
//   - track() 是 **nonisolated 非阻塞** 的: call-site 同步调用 → 立即返回, 内部 hop 到 main 入队,
//     永不卡 UI; 真正的网络发送 (sink.send) 在 sink 内部 async, 不占 main actor.
//   - 缓冲落自己的 JSON 文件 Documents/maso-analytics.json (不挤进 maso-data.json, 避免给主快照
//     每次写盘增负), 用 PersistenceController 同款 atomic write.
//   - 门控: MasoFlags.analyticsEnabled (编译期总开关) && !optOut (用户开关) && 非 MASO_SHOWCASE
//     (截图流水线零事件). #if DEBUG 下默认只 print 不缓冲 (本机调试看控制台).
//   - 无 PII: props 是 [String: AnyCodableScalar] (仅标量), 没有路径能附名字/标题/自由文本.
@MainActor
@Observable
final class Analytics {
    static let shared = Analytics()

    /// 内存 + 落盘缓冲 (newest appended). 本地查看器读这个 (newest-first 由 UI 反转).
    private(set) var buffer: [AnalyticsEvent] = []
    private var lastFlushAt: Date?

    /// 攒够这么多条就机会式 flush 一次.
    private let flushThreshold = 20
    /// 缓冲硬上限 — 超过就丢最旧的, 避免 sink 长期失败时无限占盘.
    private let bufferCap = 1000

    /// 当前出口 — boot 时 configure(sink:) 注入. 默认 NoOpSink (Phase 0: 不离开设备).
    private var sink: AnalyticsSink = NoOpSink()

    /// 门控 / 信封上下文 — DataStore 在 boot 时注入 (闭包读 settings.anonymousId / analyticsOptOut).
    /// 没注入前 (理论上不会发生) optOut 视为 false, anonId 空.
    @ObservationIgnored private var contextProvider: (() -> Context)?

    /// 本次前台会话已记录的事件数 — app_background 的 session_event_count 用. 回前台时清零.
    @ObservationIgnored private var sessionEventCount = 0
    /// 进后台的时刻 — app_foreground 的 seconds_backgrounded 用.
    @ObservationIgnored private var backgroundedAt: Date?

    /// Analytics 运行所需的最小上下文 — 由 DataStore 提供, 不让 Analytics 依赖 DataStore 类型.
    struct Context {
        var anonymousId: String
        var optOut: Bool
    }

    private init() {
        load()
    }

    // MARK: - Boot wiring

    /// boot 时调一次 (MasoApp .task): 注入出口 + 读 settings 的上下文闭包.
    func configure(sink: AnalyticsSink, context: @escaping () -> Context) {
        self.sink = sink
        self.contextProvider = context
    }

    // MARK: - 唯一对外 API (call-site 只用这个)

    /// 记录一条事件 — **非阻塞**. call-site 在任意 actor 同步调用, 内部 hop 到 main 入队.
    /// props 只能是标量字面量 (AnyCodableScalar) → 无法塞 PII.
    nonisolated func track(_ name: String, _ props: [String: AnyCodableScalar] = [:]) {
        Task { @MainActor in self.enqueue(name, props) }
    }

    // MARK: - 入队 / 门控

    private func enqueue(_ name: String, _ props: [String: AnyCodableScalar]) {
        // 截图流水线: 永远零事件 (verify-app 据此确认 showcase gate 生效).
        guard ProcessInfo.processInfo.environment["MASO_SHOWCASE"] == nil,
              ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] != "1" else { return }
        // 编译期总开关 + 用户 opt-out.
        guard MasoFlags.analyticsEnabled, !currentContext().optOut else { return }

        #if DEBUG
        // 本机调试: 控制台直接看事件 (本地查看器也读缓冲, 故仍入缓冲).
        print("📊 analytics: \(name) \(props.mapValues { $0.displayValue })")
        #endif

        buffer.append(AnalyticsEvent(name: name, props: props))
        sessionEventCount += 1
        if buffer.count > bufferCap { buffer.removeFirst(buffer.count - bufferCap) }
        persist()
        if buffer.count >= flushThreshold { Task { await flush() } }
    }

    // MARK: - 生命周期 (MasoApp scenePhase 单一站点调用, 不跟 RootView 的 scenePhase handler 重复)

    /// 回前台 — 报 app_foreground (带离开后台时长), 清零前台会话事件计数, 并机会式 flush 一次.
    func handleForeground() {
        let secs = backgroundedAt.map { Int(Date().timeIntervalSince($0)) } ?? 0
        backgroundedAt = nil
        sessionEventCount = 0
        track("app_foreground", ["seconds_backgrounded": .int(max(0, secs))])
        Task { await flush() }
    }

    /// 进后台 — 报 app_background (带本次前台会话事件数), 记下进后台时刻, 并 flush 落地这批.
    func handleBackground() {
        backgroundedAt = Date()
        track("app_background", ["session_event_count": .int(sessionEventCount)])
        Task { await flush() }
    }

    // MARK: - Flush

    /// 把缓冲整批交给 sink. 成功 → 清掉已发的; 失败 → 留着下次重试 (FeedbackStore digest 同款).
    /// Phase 0 sink = NoOpSink (总成功 → 缓冲被清空, 但什么都没离开设备).
    func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        let ok = await sink.send(batch, envelope: makeEnvelope())
        if ok {
            buffer.removeFirst(min(batch.count, buffer.count))
            lastFlushAt = Date()
            persist()
        }
        // 失败 → 保留缓冲, 下次 launch / foreground / 阈值触发再试.
    }

    private func currentContext() -> Context {
        contextProvider?() ?? Context(anonymousId: "", optOut: false)
    }

    private func makeEnvelope() -> AnalyticsEnvelope {
        AnalyticsEnvelope(
            anonId: currentContext().anonymousId,
            appVersion: Self.appVersionString,
            osVersion: Self.osVersionString,
            language: LanguageManager.shared.effectiveLanguage.rawValue
        )
    }

    /// 本地查看器用 — 当前匿名 ID (信封里的 anon_id).
    var anonymousId: String { currentContext().anonymousId }

    // MARK: - Persistence (Documents/maso-analytics.json, atomic write — 同 PersistenceController)

    private var fileURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("maso-analytics.json")
    }

    private func persist() {
        guard let url = fileURL else { return }
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = []
            let data = try enc.encode(buffer)
            try data.write(to: url, options: [.atomic])
        } catch {
            // 静默 — 下次 enqueue 会再写一次.
        }
    }

    private func load() {
        guard let url = fileURL,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else { return }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        if let events = try? dec.decode([AnalyticsEvent].self, from: data) {
            buffer = events
        }
    }

    // MARK: - Device info (同 FeedbackStore)

    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let ver = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(ver) (\(build))"
    }

    private static var osVersionString: String {
        let p = ProcessInfo.processInfo.operatingSystemVersion
        return "iOS \(p.majorVersion).\(p.minorVersion).\(p.patchVersion)"
    }
}
