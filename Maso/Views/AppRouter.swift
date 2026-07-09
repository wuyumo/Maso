import SwiftUI

// 跨 sheet / 跨 view 的导航请求 — 解决 "Settings sheet 内点 row 想切到 Plans tab" 这种
// 需要 dismiss 一个 sheet 之外再让 RootView 改 tab 的场景.
//
// 用法:
//   - Settings tap "Plans" → AppRouter.shared.requestedTab = .plans + dismiss()
//   - RootView .onChange(of: router.requestedTab) → tab = new; 重置成 nil
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    private init() {}

    /// 待切到的 tab. nil = 没请求.
    var requestedTab: RootTab? = nil

    /// AI 小结卡"Apply to routine"发起的待处理侧重 — 跨 tab 把用户带到 AI Routines 页 + 用这个
    /// focusNote 触发重生成 (复用 startGenerateRoutines). 用法: caller 同时置 requestedTab = .plans
    /// + pendingSummaryFocus = focusNote; PlansScreen .onChange 消费后置 nil. nil = 没请求.
    var pendingSummaryFocus: String? = nil

    /// Today 侧 All sheet 优化卡 Apply 发起的待处理 focusNote — 同 pendingSummaryFocus 管道,
    /// 但 CoachScreen 消费时用 "FROM OPTIMIZE" kicker + surface "optimize" (语义跟 Coach 侧
    /// All sheet 的 onOptimize 一致). Pro gate 由发起方 (TodayScreen) 过闸后才置值.
    var pendingOptimizeFocus: String? = nil
}
