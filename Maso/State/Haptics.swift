import UIKit

// 触觉反馈 — DESIGN 7 iOS native 要求接到关键节点
// 跟 web 端 navigator.vibrate 等价 (web 端在 advance() / completed 时已经触发)
enum Haptics {
    /// 组完成 — 力量段点 ✓ 时. 改 .soft + 70% intensity, 比之前 .medium 更柔, 不打扰用户的练举感.
    static func setComplete() {
        let g = UIImpactFeedbackGenerator(style: .soft)
        g.prepare()
        g.impactOccurred(intensity: 0.7)
    }

    /// 休息结束 — 倒计时归零自动 advance 时
    static func restEnded() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }

    /// 训练完成 — 所有段走完
    static func trainingComplete() {
        let g = UINotificationFeedbackGenerator()
        g.notificationOccurred(.success)
    }

    /// 按钮点击 (轻量)
    static func tap() {
        let g = UIImpactFeedbackGenerator(style: .light)
        g.impactOccurred()
    }
}
