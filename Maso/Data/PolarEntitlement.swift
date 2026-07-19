import Foundation
import StoreKit

// Polar license key 校验 — 无账号外部付费的解锁凭证.
//
// 流程: 用户在 Polar 网页买 → 拿到 license key (深链自动带回 或 手动输入) → app 把 key
// 发给自家 Cloudflare Worker /pro/validate (org token 藏在 Worker, 不进 binary) →
// Worker 调 Polar /v1/license-keys/validate → 返回归一化的 {active, status, expiresAt}.
//
// 门: 只有美区 storefront 走这套判定 (见 UserSettings.isPro). 其他区免费全解锁.
enum PolarEntitlement {

    struct Result {
        let active: Bool
        let status: String
        let expiresAt: Date?
    }

    /// 离线宽限窗 — 网络挂了但上次校验过且在这个窗内, 保留上次 active 状态.
    static let offlineGrace: TimeInterval = 7 * 86400

    private static var workerBase: String {
        (Bundle.main.object(forInfoDictionaryKey: "MasoAIProxyURL") as? String ?? "")
            .trimmingCharacters(in: .whitespaces)
    }
    private static var clientToken: String {
        Bundle.main.object(forInfoDictionaryKey: "MasoClientToken") as? String ?? ""
    }
    static var isConfigured: Bool { !workerBase.isEmpty && !clientToken.isEmpty }

    /// 校验一个 license key. 网络/配置失败抛错 (caller 决定是否保留旧状态).
    /// 成功返回归一化结果 (含 not-active 的情况 — Polar 对无效 key 也算成功返回 active=false).
    static func validate(key: String) async throws -> Result {
        guard isConfigured, let url = URL(string: "\(workerBase)/pro/validate") else {
            throw PolarError.notConfigured
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(clientToken, forHTTPHeaderField: "X-Maso-Client-Token")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["key": key])
        req.timeoutInterval = 15

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PolarError.server
        }
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let active = obj["active"] as? Bool ?? false
        let status = obj["status"] as? String ?? "unknown"
        let expiresAt: Date? = (obj["expiresAt"] as? String).flatMap {
            ISO8601DateFormatter.parsePolar($0)
        }
        return Result(active: active, status: status, expiresAt: expiresAt)
    }

    /// 当前 App Store storefront 的国家码 (alpha-3, 如 "USA"). 拿不到返回 nil.
    static func currentStorefrontCountry() async -> String? {
        await Storefront.current?.countryCode
    }
}

enum PolarError: Error { case notConfigured, server }

private extension ISO8601DateFormatter {
    /// Polar 的 expires_at 可能带小数秒, 两种格式都试.
    static func parsePolar(_ s: String) -> Date? {
        let f1 = ISO8601DateFormatter()
        f1.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f1.date(from: s) { return d }
        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s)
    }
}
