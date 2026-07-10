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

// MARK: - 底部液态光斑 (试验性视觉, 回退点 tag pre-liquid-glass)
//
// Canvas 双滤镜 metaball: blur 先融合各圆的 alpha 场, alphaThreshold 再把模糊场切回实体
// → 光斑靠近时像液体一样黏连融合. metaball 结果整体再叠一层大 blur + 极低透明度
// → "朦胧的光" 而非实体液滴边缘.
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
            // 滤镜作用顺序 = 注册的逆序: drawLayer 内容先被 blur 融合, 再被 threshold 凝固.
            context.addFilter(.alphaThreshold(min: 0.5, color: MasoColor.accent))
            context.addFilter(.blur(radius: 30))
            context.drawLayer { layer in
                for blob in Self.blobs {
                    let p = blob.position(at: t, in: size)
                    layer.fill(
                        Path(ellipseIn: CGRect(x: p.x - blob.radius, y: p.y - blob.radius,
                                               width: blob.radius * 2, height: blob.radius * 2)),
                        with: .color(.white))
                }
            }
        }
        .blur(radius: 28)          // metaball 整体再糊一层 → 朦胧光, 去掉液滴硬边
        .opacity(0.08)             // 克制: 第一眼几乎注意不到, 盯住才看到
        .mask(                     // 上缘渐隐到透明 → 与上方内容无缝衔接
            LinearGradient(stops: [.init(color: .clear, location: 0.0),
                                   .init(color: .black, location: 0.45)],
                           startPoint: .top, endPoint: .bottom))
        .allowsHitTesting(false)
    }

    // 4 个圆, 各自不同相位/周期 (25-45s) 的 sin/cos 轨迹极慢漂移;
    // 横向活动全宽, 纵向压在组件下半部. 位置/振幅均为 0-1 归一化.
    private struct Blob {
        let radius: CGFloat
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

    private static let blobs: [Blob] = [
        Blob(radius: 110, cx: 0.22, cy: 0.78, ax: 0.20, ay: 0.10, px: 41, py: 33, phase: 0.0),
        Blob(radius:  85, cx: 0.62, cy: 0.66, ax: 0.26, ay: 0.12, px: 29, py: 44, phase: 1.9),
        Blob(radius:  70, cx: 0.85, cy: 0.86, ax: 0.18, ay: 0.09, px: 36, py: 26, phase: 3.7),
        Blob(radius:  60, cx: 0.42, cy: 0.92, ax: 0.30, ay: 0.07, px: 25, py: 39, phase: 5.1),
    ]
}

// MARK: - 共享页面背景 — #121212 + 底部 ~40% 高度的液态光斑
//
// 三个 tab 屏 (Today 非 embedded / Coach / Progress) 的 .background 共用这一片,
// 替代原先各自的 MasoColor.background.ignoresSafeArea().
struct AppBackground: View {
    var body: some View {
        ZStack {
            MasoColor.background
            GeometryReader { geo in
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    LiquidGlowBackground()
                        .frame(height: geo.size.height * 0.4)
                }
            }
        }
        .ignoresSafeArea()
    }
}
