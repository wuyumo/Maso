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
}
