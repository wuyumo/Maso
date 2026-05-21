import SwiftUI

// 配色系统 — 跟 Web App 1:1 对齐
// Web 端的 CSS 变量定义在 :root, 这里直接给出对应 Color
enum MasoColor {
    // 强调色 — Spotify 风格的绿
    static let accent = Color(red: 30.0 / 255, green: 215.0 / 255, blue: 96.0 / 255)        // #1ED760

    // 文本色阶 (暗主题)
    static let text = Color(red: 1.0, green: 1.0, blue: 1.0)                                // #FFFFFF
    static let textDim = Color(red: 0.706, green: 0.706, blue: 0.706)                       // #B3B3B3
    static let textFaint = Color(red: 0.682, green: 0.682, blue: 0.682)                     // #AEAEAE
    static let textSoft = Color(red: 0.796, green: 0.796, blue: 0.796)                      // #CBCBCB

    // 背景层级 (暗主题 — 越靠前色越浅, 制造深度)
    static let background = Color(red: 18.0 / 255, green: 18.0 / 255, blue: 18.0 / 255)     // #121212
    static let surface = Color(red: 25.0 / 255, green: 25.0 / 255, blue: 25.0 / 255)        // #191919
    static let surfaceHi = Color(red: 38.0 / 255, green: 38.0 / 255, blue: 38.0 / 255)      // #262626

    // 边框 / 分隔线
    static let borderSoft = Color.white.opacity(0.08)

    // 警告色 — 取消等危险操作
    static let negative = Color(red: 243.0 / 255, green: 114.0 / 255, blue: 127.0 / 255)    // 柔和的红粉

    // 训练播放器底层渐变
    static let playerBgTop = Color.black.opacity(0.0)
    static let playerBgBottom = Color.black.opacity(0.85)
}

// 常用的圆角 / 阴影 / 尺寸常量 — 跟 DESIGN.md §2.4 对齐
// 所有屏 / 组件都从这里取值, 杜绝 magic number 散落各处
enum MasoMetrics {
    // 圆角
    static let cornerRadiusSmall: CGFloat = 8
    static let cornerRadiusMedium: CGFloat = 16
    static let cornerRadiusLarge: CGFloat = 24
    static let cornerRadiusPill: CGFloat = 999

    // Page (主屏) 边距
    /// 页面左右安全距 — 所有屏 ScrollView 内容统一 16
    static let pagePaddingHorizontal: CGFloat = 16
    /// 页面顶部留白 — 标题不顶状态栏 (NavigationStack 下不需要, 主屏用)
    static let pagePaddingTop: CGFloat = 56
    /// 页面底部 spacer — 避开 78 高的 TabBar
    static let pageBottomInset: CGFloat = 80

    // 卡片
    /// 卡片内 padding — surface bg + corner 16 用这个
    static let cardPadding: CGFloat = 20
    /// 列表行 padding
    static let rowPaddingH: CGFloat = 12
    static let rowPaddingV: CGFloat = 8

    // TabBar — pill 高度. 缩了一圈, 78 → 62 (上下各减 8)
    static let bottomNavHeight: CGFloat = 62
    static let pillWidthActive: CGFloat = 248

    // BodyHint 在各场景的高度 — 同类场景全局一致
    /// Home 大卡片里的 body hint
    static let bodyHintLarge: CGFloat = 260
    /// History 7-day 整身视图
    static let bodyHintHistory: CGFloat = 240
    /// PlanPlayer 动作信息行 (用 square 模式, 锁定 slot)
    static let bodyHintPlayer: CGFloat = 72
    /// Plans 列表行 (用 square 模式, 锁定 slot)
    static let bodyHintListRow: CGFloat = 56
}
