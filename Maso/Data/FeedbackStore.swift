import Foundation

// 用户反馈 — 本地暂存 + 按天汇总发送
//
// 设计:
//   - 用户每次提交反馈 → 本地 append 进 pending 队列 + 立刻尝试 send (机会式发送)
//   - 每次 app 启动 / 回前台 → 检查 pending: 上次 send 成功时间 ≥24h 就 batch send
//   - send 成功后清掉已发送的 id (期间新加的保留, 不丢)
//   - send 失败就保留 pending, 下次启动 / app resume 再试
//
// 为什么没有真正的"每天定时"?
//   - iOS 后台无法保证定时唤醒 app, 除非用 BGAppRefreshTask. 那要 entitlement, 不稳定.
//   - "用户每次打开 app 都检查一次"已经足够 — 跨天就发, 没跨天先攒着.
//
// 传输方案: FormSubmit (formsubmit.co)
//   - 零注册, POST 到 https://formsubmit.co/<email> 就行
//   - 首次发送会触发激活邮件给收件邮箱, 收件人确认后该 endpoint 才正式可用
//   - 在 `_captcha=false` 下可程序化发送
//   - 见 FeedbackTransport.swift

@MainActor
@Observable
final class FeedbackStore {
    static let shared = FeedbackStore()

    struct Item: Codable, Identifiable, Hashable {
        let id: UUID
        let date: Date
        let body: String
        // 设备 / 语言 信息 — 帮助定位用户场景
        let appVersion: String
        let osVersion: String
        let language: String
    }

    /// 还没发送出去的 feedback. 按提交顺序排列.
    private(set) var pending: [Item] = []
    /// 最近一次 digest 成功发送的时间. nil = 从未成功过.
    private(set) var lastDigestSentAt: Date?
    /// 正在 send 中 — 防并发重复发
    private(set) var isSending: Bool = false

    private static let storageKey = "maso.feedback.pending.v1"
    private static let lastSentKey = "maso.feedback.lastDigestSentAt.v1"

    /// 至少间隔多久才会再次自动 send digest (秒). 24h.
    static let digestInterval: TimeInterval = 24 * 60 * 60

    private init() {
        load()
    }

    /// 用户提交一条反馈 — 入队, 立即试 send (force=true 跳过 24h 间隔).
    func submit(_ body: String) {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let item = Item(
            id: UUID(),
            date: Date(),
            body: trimmed,
            appVersion: Self.appVersionString,
            osVersion: Self.osVersionString,
            language: Locale.preferredLanguages.first ?? "en"
        )
        pending.append(item)
        save()
        Task { await trySendDigest(force: true) }
    }

    /// 检查是否需要 daily digest — 入口在 RootView / scenePhase 切换时.
    /// - force=true: 跳过 24h 间隔判断 (用户主动 send 时用)
    func trySendDigest(force: Bool = false) async {
        guard !pending.isEmpty, !isSending else { return }
        if !force, let last = lastDigestSentAt,
           Date().timeIntervalSince(last) < Self.digestInterval {
            return
        }
        isSending = true
        defer { isSending = false }

        let snapshot = pending
        let ok = await FeedbackTransport.sendDigest(items: snapshot)
        if ok {
            let sentIds = Set(snapshot.map { $0.id })
            pending.removeAll { sentIds.contains($0.id) }
            lastDigestSentAt = Date()
            save()
        }
    }

    // MARK: - Persistence

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        if let last = lastDigestSentAt {
            UserDefaults.standard.set(last, forKey: Self.lastSentKey)
        }
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey) {
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            if let items = try? dec.decode([Item].self, from: data) {
                self.pending = items
            }
        }
        if let last = UserDefaults.standard.object(forKey: Self.lastSentKey) as? Date {
            self.lastDigestSentAt = last
        }
    }

    // MARK: - Device info

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
