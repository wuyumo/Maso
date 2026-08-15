import Foundation

// Phase 1 出口 —— 把缓冲的事件批量发到 TelemetryDeck.
//
// 为什么现在做 (2026-08-15): 在此之前 sink 是 NoOpSink, 事件生成完直接丢 ——
// **我们对自己 app 里发生的一切一无所知**。所有产品判断只能靠竞品的公开评论,
// 那是别人的用户不是我们的。装了这个才知道: 多少人走完引导、AI 生成成功率多少、哪一步流失。
//
// 为什么不用官方 SDK: v2 ingest 就是一个 POST + JSON 数组, 十几行的事。
// 加 SPM 依赖要动 project.yml、拖慢构建、多一个供应链面, 不值当。
//
// 隐私: 只发 AnalyticsEvent 允许的标量 props (AnyCodableScalar 从编译期挡死自由文本/PII),
// clientUser = 每安装一个随机 UUID (删除重装即重置, 不可回溯到人), TelemetryDeck 还会再哈希一次。
struct TelemetryDeckSink: AnalyticsSink {
    let appID: String
    /// Debug 构建发到 Test Mode —— 开发时的点点点不该污染真实漏斗。
    var isTestMode: Bool = {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }()

    private static let endpoint = URL(string: "https://nom.telemetrydeck.com/v2/")!

    func send(_ batch: [AnalyticsEvent], envelope: AnalyticsEnvelope) async -> Bool {
        guard !batch.isEmpty, !appID.isEmpty else { return true }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        let signals: [[String: Any]] = batch.map { e in
            var payload: [String: String] = [
                // 信封放进 payload —— TelemetryDeck 侧就能按版本/系统/语言切分.
                "appVersion": envelope.appVersion,
                "osVersion": envelope.osVersion,
                "language": envelope.language,
            ]
            for (k, v) in e.props { payload[k] = v.stringForAnalytics }
            return [
                "appID": appID,
                "clientUser": envelope.anonId,
                "sessionID": envelope.anonId,
                "type": e.name,
                "receivedAt": iso.string(from: e.ts),
                "isTestMode": isTestMode ? "true" : "false",
                "payload": payload,
            ]
        }

        var req = URLRequest(url: Self.endpoint)
        req.httpMethod = "POST"
        req.timeoutInterval = 20
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        guard let body = try? JSONSerialization.data(withJSONObject: signals) else { return true }
        // ↑ 序列化失败返回 true: 这批数据本身有问题, 留着重试也永远发不出去, 丢掉比无限堆积好.
        req.httpBody = body

        do {
            let (_, resp) = try await URLSession.shared.data(for: req)
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            // 只有 2xx 才算收下. 其余 (含 5xx / 断网) 返回 false → Analytics 保留缓冲下次重试.
            // ⚠️ 4xx 也返回 false 是刻意的: 格式错了我要在缓冲堆积上看得见, 而不是静默吞掉。
            return (200..<300).contains(code)
        } catch {
            return false
        }
    }
}

private extension AnyCodableScalar {
    /// TelemetryDeck 的 payload 值是字符串; 标量在这里统一转字符串.
    var stringForAnalytics: String {
        switch self {
        case .string(let s): return s
        case .int(let i):    return String(i)
        case .double(let d): return String(format: "%g", d)
        case .bool(let b):   return b ? "true" : "false"
        }
    }
}
