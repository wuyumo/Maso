import SwiftUI

// 开屏 / Splash — 基于新一套 Maso brand SVG (5 层叠柱) 的入场.
//
// 设计意图:
//   - 5 根 path 按 **视觉 x 位置 从左到右** 依次 slide-in (从左侧 -40pt 滑入到位 + fade in)
//   - 形成 "logo 从左到右出现 / 扫过来" 的视觉效果, 像积木从左侧依次归位
//   - "Maso" 字样跟在 logo 落定后从下方淡入, 主从分明
//
// path 视觉 x 中心 (粗略, 用来定 stagger 时序):
//   BrandBar1  ≈ 96   ← 最左
//   BrandEcho2 ≈ 146
//   BrandBar2  ≈ 199
//   BrandEcho1 ≈ 229
//   BrandBar3  ≈ 265  ← 最右
//
// 动画节奏 (~2.5s):
//   t=0.00 — Bar1 (主柱, 最左) spring slide+fade
//   t=0.08 — Echo2 (中竖柱)
//   t=0.16 — Bar2 (中柱)
//   t=0.24 — Echo1 (右上斜柱)
//   t=0.32 — Bar3 (最右小柱)
//   t=0.85 — "Maso" 字样上浮
//   t=1.05 — Tagline 上浮
//   t=2.50 — 整组 fade out + 微缩, 转场到 RootView
//
// 5 个 path 都 internal in MasoBrandLogo.swift — 这里直接独立操控每根的进场状态.
struct SplashScreen: View {
    let onDone: () -> Void

    // 每根独立的进场状态 (opacityFactor, offsetY)
    // factor = 0 时 path 完全透明; factor = 1 时达到 SVG 的目标 opacity (e.g. Bar1=1.0, Echo=0.4)
    @State private var bar1Factor: Double = 0
    @State private var bar2Factor: Double = 0
    @State private var bar3Factor: Double = 0
    @State private var echo1Factor: Double = 0
    @State private var echo2Factor: Double = 0

    @State private var wordOn = false
    @State private var taglineOn = false
    @State private var opacity: Double = 1   // 整屏退场

    /// 把每个 path 的"进场系数" 0..1 映射到对应 SVG 目标 opacity.
    private var liveOpacities: [Double] {
        let target = MasoBrandLogo.defaultOpacities  // [Echo1, Echo2, Bar1, Bar2, Bar3]
        return [
            target[0] * echo1Factor,
            target[1] * echo2Factor,
            target[2] * bar1Factor,
            target[3] * bar2Factor,
            target[4] * bar3Factor,
        ]
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            // 整组品牌 mark — logo + wordmark + tagline 一个 VStack
            // 间距按 iOS HIG 8pt grid: logo→wordmark 32 (4×8), wordmark→tagline 8 (主从紧贴).
            // 垂直居中. 整组退场时微缩 0.97 + 整屏 fade out.
            VStack(spacing: 32) {
                logoLayer
                    // 160×160 — 占 iPhone 14/15 Pro 屏宽 (393pt) 的 ~40%, 跟 iOS 系统 launch
                    // image 规模一致 (Apple Fitness / Notes / Mail launch icon 大致这个尺寸).
                    .frame(width: 160, height: 160)
                VStack(spacing: 8) {
                    Text("Masso")
                        // 28pt bold — iOS HIG Title 1 字号. 比 Large Title (34pt) 小一档,
                        // 跟 logo 视觉比例更平衡, 不抢戏. tracking -0.3 收紧字距让 4 字母一体.
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.3)
                        .foregroundStyle(MasoColor.text)
                        .opacity(wordOn ? 1 : 0)
                        .offset(y: wordOn ? 0 : 12)
                    // Tagline — iOS HIG Subhead 字号 15pt regular. tracking 0.2 (略松)
                    // 提升"caption" 感. textDim 灰色 — 跟 wordmark 形成主从.
                    Text("My Personal AI Trainer")
                        .font(.system(size: 15, weight: .regular))
                        .tracking(0.2)
                        .foregroundStyle(MasoColor.textDim)
                        .opacity(taglineOn ? 1 : 0)
                        .offset(y: taglineOn ? 0 : 8)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)  // 整组绝对居中
            .scaleEffect(opacity < 1 ? 0.97 : 1)
        }
        .opacity(opacity)
        .onAppear { runIntro() }
    }

    /// Logo 层 — 5 个 path 各自从左侧 slide-in + fade-in.
    /// 每根独立 factor 控制 opacity 0→target; offset 从 -40/-28 (bar/echo) → 0 落位.
    /// 没用 MasoBrandLogo 的 opacities 数组 (那个是单帧静态), 而是用单 path 独立 view 串
    /// 让每根的 spring 起点不同.
    ///
    /// offset distance 分两档:
    ///   - 主柱 (Bar1/2/3): -42pt — 滑动距离大, 视觉重量感强
    ///   - Echo (Echo1/2):  -26pt — 装饰性, 滑动距离小, 显得"柔"
    @ViewBuilder
    private var logoLayer: some View {
        ZStack {
            // 跟 SVG path order 一致 — 底层在前.
            BrandEcho1()
                .fill(MasoColor.accent.opacity(MasoBrandLogo.defaultOpacities[0] * echo1Factor))
                .offset(x: echo1Factor > 0 ? 0 : -26)
            BrandEcho2()
                .fill(MasoColor.accent.opacity(MasoBrandLogo.defaultOpacities[1] * echo2Factor))
                .offset(x: echo2Factor > 0 ? 0 : -26)
            BrandBar1()
                .fill(MasoColor.accent.opacity(MasoBrandLogo.defaultOpacities[2] * bar1Factor))
                .offset(x: bar1Factor > 0 ? 0 : -42)
            BrandBar2()
                .fill(MasoColor.accent.opacity(MasoBrandLogo.defaultOpacities[3] * bar2Factor))
                .offset(x: bar2Factor > 0 ? 0 : -42)
            BrandBar3()
                .fill(MasoColor.accent.opacity(MasoBrandLogo.defaultOpacities[4] * bar3Factor))
                .offset(x: bar3Factor > 0 ? 0 : -42)
        }
        // 整组 logo 一层绿色 drop shadow, 跟 App Icon 上的发光感呼应
        .shadow(color: MasoColor.accent.opacity(0.25), radius: 28, y: 10)
    }

    private func runIntro() {
        // 整套用 spring — 节奏一致, 5 根都"弹"出位置.
        // response 0.55 = ~弹 0.55s; dampingFraction 0.72 微减振, 稍带一点弹性 overshoot.
        let spring = Animation.spring(response: 0.55, dampingFraction: 0.72)

        // ─── 5 根 path 按视觉 x 位置从左到右 slide-in ───
        // 主柱 1 (最左, x_center ≈ 96) — 先进场
        withAnimation(spring) { bar1Factor = 1 }
        // Echo2 (中竖柱, x_center ≈ 146)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            withAnimation(spring) { echo2Factor = 1 }
        }
        // 主柱 2 (中柱, x_center ≈ 199)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
            withAnimation(spring) { bar2Factor = 1 }
        }
        // Echo1 (右上斜柱, x_center ≈ 229)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24) {
            withAnimation(spring) { echo1Factor = 1 }
        }
        // 主柱 3 (最右小柱, x_center ≈ 265)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
            withAnimation(spring) { bar3Factor = 1 }
        }

        // ─── 文字 ───
        // "Maso" 字样 — logo 全部落定 (~0.32 + 0.55 = 0.87s) 后柔和淡入
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) {
            withAnimation(.easeOut(duration: 0.55)) { wordOn = true }
        }
        // Tagline 错峰 0.2s, 让用户先读完 brand 名再看 slogan
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
            withAnimation(.easeOut(duration: 0.5)) { taglineOn = true }
        }

        // ─── 退场 ───
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation(.easeOut(duration: 0.32)) { opacity = 0 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.34) {
                onDone()
            }
        }
    }
}

#Preview {
    SplashScreen { }
}
