import Foundation

// FormSubmit 传输层 — 把 N 条 FeedbackStore.Item 打包成 1 封邮件发给收件人.
//
// FormSubmit 工作机制 (https://formsubmit.co):
//   1. 首次 POST 到 https://formsubmit.co/<email>, 它会发激活邮件到 <email>
//   2. 收件人点击邮件里的 "Activate" 链接后, 该 endpoint 才正式可用
//   3. 之后所有 POST 会被 forward 成邮件到 <email>
//   4. 默认开 captcha; 程序化发送必须传 _captcha=false
//   5. 可用 _subject / _template 等保留字段控制邮件格式
//
// 收件人是硬编码的 Maso 开发者邮箱. 想换收件人就改 recipient.
enum FeedbackTransport {

    /// 反馈收件邮箱
    static let recipient = "wuyumoawuyumo@gmail.com"

    /// 把 items 拼成一封"daily digest"邮件 POST 到 FormSubmit.
    /// 成功 → true; 网络失败 / 4xx / 5xx → false.
    ///
    /// 两个 endpoint 都试一次:
    ///   1) AJAX (`/ajax/<email>`) — 程序化用法, 返回 JSON. 优先.
    ///   2) Regular (`/<email>`) — HTML form fallback, 返回 redirect/html. 当 ajax 521/down 时备胎.
    /// 任一成功就算成功. 失败时 store 保留 pending, 下次启动再 retry.
    static func sendDigest(items: [FeedbackStore.Item]) async -> Bool {
        guard !items.isEmpty else { return true }
        let payload = buildPayload(items: items)

        // 1) AJAX endpoint
        if await postFormUrlEncoded(
            url: URL(string: "https://formsubmit.co/ajax/\(recipient)")!,
            payload: payload
        ) {
            return true
        }
        // 2) Regular endpoint fallback (FormSubmit 普通 form action)
        if await postFormUrlEncoded(
            url: URL(string: "https://formsubmit.co/\(recipient)")!,
            payload: payload
        ) {
            return true
        }
        return false
    }

    // MARK: - private

    /// 拼邮件 payload — 普通 form 字段, 不嵌 JSON.
    /// FormSubmit 把每个 key 当成 form field 渲染到邮件里, `_subject` 等下划线开头是控制字段.
    private static func buildPayload(items: [FeedbackStore.Item]) -> [String: String] {
        let local = DateFormatter()
        local.dateFormat = "yyyy-MM-dd HH:mm"
        local.locale = Locale(identifier: "en_US_POSIX")

        let body = items.enumerated().map { (idx, f) -> String in
            """
            [#\(idx + 1)] \(local.string(from: f.date))
            \(f.body)

            -- ver: \(f.appVersion) · \(f.osVersion) · \(f.language)
            """
        }.joined(separator: "\n\n────────────────\n\n")

        let today = DateFormatter()
        today.dateFormat = "yyyy-MM-dd"
        today.locale = Locale(identifier: "en_US_POSIX")
        let plural = items.count > 1 ? "s" : ""

        return [
            "_subject": "[Masso] Feedback Digest — \(today.string(from: Date())) (\(items.count) item\(plural))",
            "_template": "box",
            "_captcha": "false",
            "count": "\(items.count)",
            "feedbacks": body,
        ]
    }

    /// 用 form-urlencoded POST. 大部分 form 服务对 form-urlencoded 比 JSON 容忍度高
    /// (绕开某些 WAF 规则 / Cloudflare 521 时的 origin 解析问题).
    private static func postFormUrlEncoded(url: URL, payload: [String: String]) async -> Bool {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        // FormSubmit 默认会拒绝空 User-Agent — 给一个标准的避免 521 / 403.
        req.setValue("Maso-iOS/1.0", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let bodyStr = payload.map { (k, v) -> String in
            let ek = k.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? k
            let ev = v.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? v
            return "\(ek)=\(ev)"
        }.joined(separator: "&")
        req.httpBody = bodyStr.data(using: .utf8)

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { return false }
            // 200..299 = success; FormSubmit 普通 endpoint 也可能 302 跳转
            return (200...299).contains(http.statusCode) || http.statusCode == 302
        } catch {
            return false
        }
    }
}
