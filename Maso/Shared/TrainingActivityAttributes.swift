import ActivityKit
import Foundation

// 跟 widget extension target 共享的 ActivityAttributes 定义.
// 不能放在 main app 私有 source 里 — widget extension 要 import 同款 schema.
// project.yml 里两个 target 都 source 这个文件.
//
// 设计:
//   - Attributes (immutable): planName / planId — start 时 set, 训练全程不变
//   - ContentState (mutable): segmentLabel / setProgress / endsAt 等 — 每次 segment 切换 update
//
// 倒计时用 `Date.distantPast...endsAt` 配合 SwiftUI Text(timerInterval:) — Live Activity
// 自带 timer 渲染, 不需要 app 在 background 频繁 push.

public struct TrainingActivityAttributes: ActivityAttributes {
    public typealias TrainingState = ContentState

    public struct ContentState: Codable, Hashable {
        /// 当前段的主标签 — 力量段 = 动作名 ("Bench Press"); rest 段 = "Rest" 或 "Switching"
        public var segmentLabel: String
        /// 力量段的组进度 "2/5". rest 段 = ""
        public var setProgress: String
        /// 倒计时目标时刻. nil = 无倒计时 (力量段等用户点完成).
        /// 给 SwiftUI `Text(timerInterval: ...)` 用, Live Activity 自动每秒刷新不需 push.
        public var endsAt: Date?
        /// 是否休息段 — 决定 widget UI 风格 (rest = accent 颜色 / 倒计时 prominent)
        public var isRest: Bool
        /// rest 段下一动作名提示 ("Next: Squat"). 非 rest 段 nil.
        public var nextExerciseName: String?

        public init(
            segmentLabel: String,
            setProgress: String,
            endsAt: Date? = nil,
            isRest: Bool = false,
            nextExerciseName: String? = nil
        ) {
            self.segmentLabel = segmentLabel
            self.setProgress = setProgress
            self.endsAt = endsAt
            self.isRest = isRest
            self.nextExerciseName = nextExerciseName
        }
    }

    /// 训练计划名 — Live Activity 卡片顶部 kicker 用
    public var planName: String

    public init(planName: String) {
        self.planName = planName
    }
}
