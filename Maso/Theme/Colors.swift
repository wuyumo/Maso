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
    /// "Hero 卡" 描边 — 比 borderSoft 强一档, 0.18 白. 用在没底色透到页面背景的卡片上
    /// (MuscleStatusOverviewCard / PlanRationaleCard / TRAINING PREFERENCES). 这类卡靠
    /// 描边唯一界定边界, borderSoft 在 NavigationStack 渐变区会被洗淡到几乎不可见.
    static let borderHero = Color.white.opacity(0.18)

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

// MARK: - 全屏液态光斑 (试验性视觉, 回退点 tag pre-liquid-glass)
//
// v2 (owner 调整): ① 不再只压屏底 — 铺满整个 UI 分层的最底层 (整屏背景动效);
// ② 不再单色 — 绿→白之间取多档色调, 各光斑颜色不同, 大半径 blur 让交叠处的颜色
// 互相溶合出中间调 (动态融合), .screen 混合让交叠读作"光的相加"而非色块.
// (v1 的 alphaThreshold 单色 metaball 撤掉 — 多色融合与单色凝固互斥, 朦胧光场不需要硬边.)
struct LiquidGlowBackground: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if reduceMotion {
            glow(at: 0)   // Reduce Motion → 静止帧, 不驱动 Timeline
        } else {
            TimelineView(.animation(minimumInterval: 1.0 / 20.0)) { timeline in
                glow(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func glow(at t: TimeInterval) -> some View {
        Canvas { context, size in
            // 大半径 blur — 各色光斑边缘互溶, 交界处混出绿白中间调 (colors mixing).
            context.addFilter(.blur(radius: 55))
            context.drawLayer { layer in
                for blob in Self.blobs {
                    let p = blob.position(at: t, in: size)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: p.x - blob.radius, y: p.y - blob.radius,
                                               width: blob.radius * 2, height: blob.radius * 2)),
                        with: .color(blob.color))
                }
            }
        }
        .blur(radius: 22)          // 整体再糊一层 → 朦胧光场
        .blendMode(.screen)        // 发光式叠加: 深底上只加亮不压暗, 交叠 = 光的相加
        .opacity(0.70)             // 光斑亮一点 → 对比度更高 (owner: 拉开跟底色的差)
        .allowsHitTesting(false)
    }

    // 5 个圆铺满全屏, 各自不同相位/周期 (25-45s) 的 sin/cos 轨迹极慢漂移;
    // 颜色 = 从 Accent 衍生的五色 (黄绿/品牌绿/青绿/青 + 互补玫瑰). 位置/振幅均为 0-1 归一化.
    private struct Blob {
        let radius: CGFloat
        let color: Color
        let cx, cy: CGFloat
        let ax, ay: CGFloat
        let px, py: Double
        let phase: Double
        func position(at t: TimeInterval, in size: CGSize) -> CGPoint {
            CGPoint(
                x: (cx + ax * CGFloat(sin(t * 2 * .pi / px + phase))) * size.width,
                y: (cy + ay * CGFloat(cos(t * 2 * .pi / py + phase * 1.7))) * size.height)
        }
    }

    // 光斑配色 = 从品牌 Accent #1ED760 (HSB 141°, ≈ Spotify 绿) 衍生的色相和谐 (owner 指定基于 accent 衍生):
    // 一条 analogous 类似色冷主轴 绿→青绿→青 (141°±) 紧扣品牌 + 一颗 complementary 互补色 (~330°) 玫瑰做暖点缀.
    // 全部提亮、饱和降到柔和光场档; 融合处混出高级中间调, 但整体是"品牌绿的一家人", 不再是随意的 pastel.
    private static let glowLime  = Color(red: 0.466, green: 0.920, blue: 0.386)  // #77EB62 类似色 -30° (偏黄绿)
    private static let glowGreen = Color(red: 0.360, green: 0.900, blue: 0.549)  // #5CE68C 品牌绿 141° 柔化
    private static let glowTeal  = Color(red: 0.450, green: 0.900, blue: 0.833)  // #73E6D4 类似色 +30° (青绿)
    private static let glowCyan  = Color(red: 0.506, green: 0.844, blue: 0.920)  // #81D7EB 类似色 +50° (青)
    private static let glowRose  = Color(red: 0.920, green: 0.552, blue: 0.736)  // #EB8CBC 互补色 ~330° (玫瑰暖点缀)

    private static let blobs: [Blob] = [
        Blob(radius: 170, color: glowGreen, cx: 0.20, cy: 0.80, ax: 0.22, ay: 0.12, px: 41, py: 33, phase: 0.0),
        Blob(radius: 130, color: glowTeal,  cx: 0.75, cy: 0.62, ax: 0.24, ay: 0.16, px: 29, py: 44, phase: 1.9),
        Blob(radius: 150, color: glowLime,  cx: 0.35, cy: 0.30, ax: 0.26, ay: 0.14, px: 36, py: 26, phase: 3.7),
        Blob(radius: 100, color: glowCyan,  cx: 0.82, cy: 0.14, ax: 0.18, ay: 0.12, px: 25, py: 39, phase: 5.1),
        Blob(radius: 120, color: glowRose,  cx: 0.55, cy: 0.90, ax: 0.30, ay: 0.08, px: 45, py: 31, phase: 2.6),
    ]
}

// MARK: - 共享页面背景 — #121212 + 全屏液态光斑 (UI 分层最底)
//
// 三个 tab 屏 (Today 非 embedded / Coach / Progress) 的 .background 共用这一片,
// 替代原先各自的 MasoColor.background.ignoresSafeArea().
struct AppBackground: View {
    var body: some View {
        ZStack {
            MasoColor.background
            // 底色回到纯 #121212 (owner 要更黑) — 不再叠提亮白, 页面背景 = MasoColor.background 本体.
            LiquidGlowBackground()
        }
        .ignoresSafeArea()
    }
}
