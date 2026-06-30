import Foundation

// 产品分析 — 事件模型 (无 PII).
//
// 设计原则 (见 docs/analytics-design.md §3/§4):
//   - props 只允许标量 (String/Int/Double/Bool) —— 用 `AnyCodableScalar` 这个封闭类型从
//     **编译期**杜绝把动作名 / 计划标题 / 自由文本塞进事件. 没有任何代码路径能附 PII.
//   - 年龄 / 体重在 call-site 先**分桶** (banded), planId 用 SHA256 前 8 位**哈希**, 不可逆回标题.
//   - 信封 (anon_id / app_version / os_version / language) 由 Analytics 服务统一附加,
//     不在每个 call-site 重复传 —— 见 AnalyticsEnvelope.

/// 单条分析事件 — 名称 + 时间戳 + 标量属性. Codable 落盘到 Documents/maso-analytics.json.
struct AnalyticsEvent: Codable, Sendable {
    let name: String
    let ts: Date                          // encode 时走 iso8601
    let props: [String: AnyCodableScalar] // 仅标量 — 编译期约束

    init(name: String, ts: Date = Date(), props: [String: AnyCodableScalar] = [:]) {
        self.name = name
        self.ts = ts
        self.props = props
    }
}

/// 事件属性的**唯一**允许值类型 —— 标量 only (String / Int / Double / Bool).
/// 没有 `.array` / `.dict` / `.data` case, 故无法承载任意结构或自由文本块;
/// 这是"无 PII"的编译期保证 (call-site 想塞 [Exercise] 或 Plan 根本无法构造).
enum AnyCodableScalar: Codable, Sendable, Hashable, ExpressibleByStringLiteral,
                       ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral,
                       ExpressibleByBooleanLiteral {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)

    // 字面量构造 — 让 call-site 直接写 ["surface": "onboarding", "count": 4, "ok": true].
    init(stringLiteral value: String) { self = .string(value) }
    init(integerLiteral value: Int) { self = .int(value) }
    init(floatLiteral value: Double) { self = .double(value) }
    init(booleanLiteral value: Bool) { self = .bool(value) }

    // MARK: - Codable (扁平编码 — JSON 里就是裸标量, 不带 case 包装)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        throw DecodingError.dataCorruptedError(in: c, debugDescription: "Unsupported analytics scalar")
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let s): try c.encode(s)
        case .int(let i): try c.encode(i)
        case .double(let d): try c.encode(d)
        case .bool(let b): try c.encode(b)
        }
    }

    /// 调试 / 本地查看器用的可读字符串.
    var displayValue: String {
        switch self {
        case .string(let s): return s
        case .int(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "true" : "false"
        }
    }
}

/// 事件信封 — 所有事件共享的非 PII 上下文, 由 Analytics 服务在发送时统一附加 (不进每条 event).
struct AnalyticsEnvelope: Codable, Sendable {
    let anonId: String      // 每安装一个 UUID (UserSettings.anonymousId), 删除重装即重置
    let appVersion: String  // e.g. "1.5 (11)"
    let osVersion: String   // e.g. "iOS 18.0.0"
    let language: String    // e.g. "zh-Hans"
}
