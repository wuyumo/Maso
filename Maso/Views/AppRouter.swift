import SwiftUI

// Cross-screen requests from sheets and insight actions.
// RootView consumes the destination and opens it from Today.
@MainActor
@Observable
final class AppRouter {
    static let shared = AppRouter()
    private init() {}

    /// Pending destination; nil means there is no navigation request.
    var requestedDestination: AppDestination? = nil
    var pendingWidgetDestination: MassoWidgetDestination? = nil
    var pendingWidgetDay: Date? = nil
    var pendingHomeQuickAction: HomeQuickAction.Request? = nil
    var homeQuickActionsReady = false
    /// Update confirmed from Training Preferences outside the Coach page.
    var pendingTrainingPreferencesUpdate = false

    /// Muscle recovery action opens an editable draft, never an automatic send.
    var pendingMuscleTraining: MuscleGroup? = nil

    static func muscleTrainingPrompt(for muscle: MuscleGroup) -> String {
        String(format: NSLocalizedString("Adjust my saved workouts to train %@ more. Keep my training preferences, equipment, available time and recovery in mind. Show which exercises and sets you would change. If I have no saved workouts, create a suitable plan.", comment: "muscle recovery — editable Coach request"), muscle.displayName)
    }

    /// AI 小结卡"Apply to routine"发起的待处理侧重 — 跨 tab 把用户带到 AI Routines 页 + 用这个
    /// focusNote 触发重生成 (复用 startGenerateRoutines). 用法: caller 同时置 requestedDestination = .plans
    /// + pendingSummaryFocus = focusNote; PlansScreen .onChange 消费后置 nil. nil = 没请求.
    var pendingSummaryFocus: String? = nil

    /// Today 侧 All sheet 优化卡 Apply 发起的待处理 focusNote — 同 pendingSummaryFocus 管道,
    /// 但 CoachScreen 消费时用 "FROM OPTIMIZE" kicker + surface "optimize" (语义跟 Coach 侧
    /// All sheet 的 onOptimize 一致). Pro gate 由发起方 (TodayScreen) 过闸后才置值.
    var pendingOptimizeFocus: String? = nil
}
