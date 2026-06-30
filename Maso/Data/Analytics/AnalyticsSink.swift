import Foundation

// 分析事件出口 (sink) — 可插拔, 让后端选型 (见 docs/analytics-design.md §5) 不动 call-site.
//
// Phase 0 (本 PR): 默认 NoOpSink —— 事件只在设备本地缓冲, 永不离开设备 (= 隐私零负担,
//   App Review 安全, 隐私清单不用改). 配本地 AnalyticsInspectorScreen 即可在自己机器上看事件.
// Phase 1 (后续 PR, 需 owner 的 App ID): 换 TelemetryDeckSink → 跨用户漏斗/留存看板.

/// 一个分析后端 —— Analytics 服务把缓冲批量交给它发送.
protocol AnalyticsSink: Sendable {
    /// 发送一批事件 + 共享信封. 返回 true 表示后端已接收 (缓冲可丢弃这批);
    /// 返回 false → Analytics 保留缓冲, 下次启动 / 回前台 / 攒够阈值再重试.
    func send(_ batch: [AnalyticsEvent], envelope: AnalyticsEnvelope) async -> Bool
}

/// 空出口 —— 什么都不发, 直接"成功". Phase 0 默认值: 事件只活在本地缓冲 (供调试查看器读),
/// 没有任何数据离开设备. 因 send 总返回 true, 缓冲会被正常清空 (避免无限增长).
struct NoOpSink: AnalyticsSink {
    func send(_ batch: [AnalyticsEvent], envelope: AnalyticsEnvelope) async -> Bool {
        true
    }
}
