import Foundation

// Bug reports stay in a local outbox until the central service accepts them.

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
    /// Prevent duplicate concurrent uploads.
    private(set) var isSending: Bool = false

    private static let storageKey = "maso.feedback.pending.v1"

    private init() {
        load()
    }

    /// Queue locally first, then upload. The server owns weekly batching and delivery.
    func submit(_ body: String) async -> Bool {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
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
        await tryUploadPending()
        return !pending.contains(where: { $0.id == item.id })
    }

    /// Upload any reports left over from offline or failed requests.
    func tryUploadPending() async {
        guard !pending.isEmpty, !isSending else { return }
        isSending = true
        defer { isSending = false }

        while let item = pending.first {
            guard await FeedbackTransport.send(item) else { break }
            pending.removeAll { $0.id == item.id }
            save()
        }
    }

    /// Let the report sheet retry immediately without enqueuing a duplicate report.
    func retryPending() async -> Bool {
        await tryUploadPending()
        return pending.isEmpty
    }

    // MARK: - Persistence

    private func save() {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(pending) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
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
