import SwiftUI

// Maso 品牌 logo — 5 根斜柱叠层版 (5th iteration, 2026-05-16).
// 直接从 `Maso Green.svg` / `Maso Black.svg` / `Maso white.svg` 解析的 path, viewBox 320×320.
//
// 这一版的视觉重点是"前后景错位 + 双向内阴影 3D":
//   - 5 个 path 各自有不同 opacity, 营造前后层次
//   - 主柱 (Bar1/2/3) 额外加 2 层内阴影:
//       上左侧 10% 黑 → 暗面
//       下右侧 10% 白 → 亮面
//     仿照 SVG 里的 feOffset + feGaussianBlur + feComposite inner shadow filter
//
//   path 3 (BrandBar1) — 最显眼的主柱, opacity 1.0 + 双内阴影
//   path 4 (BrandBar2) — 主柱右后侧, opacity 0.85 + 双内阴影
//   path 5 (BrandBar3) — 最右小柱, opacity 0.7 + 双内阴影
//   path 1 (BrandEcho1) — 右上斜柱 echo, opacity 0.4 (无内阴影, 纯平)
//   path 2 (BrandEcho2) — 中竖圆角柱 echo, opacity 0.5 (无内阴影, 纯平)
//
// 跟 `MasoMarkIcon.swift` 共享同一套 Shape — 两个组件视觉表面一致,
// 只在调用点的 frame 上区分 hero 大小. 不再分维护两份 path 数据.
//
// `BrandBar1/2/3` + `BrandEcho1/2` 是 internal Shape, 外部可单独取用做分柱动画
// (SplashScreen 的入场就是 5 层独立 spring 进场).
struct MasoBrandLogo: View {
    var color: Color = MasoColor.accent
    /// 5 个 path 的 opacity. 默认是 SVG 出图的层次, caller 通常不用改.
    /// 顺序: [Echo1(右上斜柱), Echo2(中竖柱), Bar1(主柱), Bar2(中柱), Bar3(右小柱)]
    var opacities: [Double] = MasoBrandLogo.defaultOpacities

    /// 2026-05-24 v7 — 跟新一版 `Maso Green.svg` / `Maso Black.svg` / `Maso white.svg` 对齐.
    /// 整体形态变了 (更高瘦的"柱阵", 头部上提, 底部对齐), path 全部重画过. opacity 维持 v6 节奏.
    static let defaultOpacities: [Double] = [0.4, 0.4, 1.0, 0.85, 0.7]

    var body: some View {
        ZStack {
            // 跟 SVG path order 一致, ZStack first = 底层. Echo 平的, Bar 带内阴影 3D.
            BrandEcho1().fill(color.opacity(opacities[0]))
            BrandEcho2().fill(color.opacity(opacities[1]))
            innerShadowedBar(BrandBar1(), opacity: opacities[2])
            innerShadowedBar(BrandBar2(), opacity: opacities[3])
            innerShadowedBar(BrandBar3(), opacity: opacities[4])
        }
        .aspectRatio(1, contentMode: .fit)
    }

    /// 主柱带 SVG 同款双向内阴影 (top-left 暗 + bottom-right 亮 → 3D 突起感).
    ///
    /// 实现细节:
    ///   - 用 GeometryReader 拿到当前渲染尺寸, 跟 SVG viewBox 320 算 scale —
    ///     这样 2pt 偏移 / 1pt blur 在大尺寸是明显的, 小尺寸 (e.g. TabBar 22pt) 自动缩到几乎不可见,
    ///     视觉上保持一致 "纸感", 不会在小图上变成肉眼可见的描边.
    ///   - 内阴影的标准 SwiftUI 套路: `Shape.stroke(...).blur(...).offset(...).mask(Shape.fill(.black))`
    ///     stroke 创建边缘, blur 软化, offset 推方向, mask 把它裁回形状内部.
    ///   - 整体再套 .opacity(...) 对齐 SVG 里 <g opacity="..."> 的语义.
    @ViewBuilder
    private func innerShadowedBar<S: Shape>(_ shape: S, opacity: Double) -> some View {
        GeometryReader { geo in
            let scale = min(geo.size.width, geo.size.height) / BrandSVGScale.viewBox
            ZStack {
                // 1) 实色填充 — accent / black / white 视 caller 而定
                shape.fill(color)
                // 2) 暗面: top-left 10% 黑内阴影
                shape
                    .stroke(Color.black.opacity(0.5), lineWidth: 4 * scale)
                    .blur(radius: 1 * scale)
                    .offset(x: -2 * scale, y: -2 * scale)
                    .mask(shape.fill(Color.black))
                // 3) 亮面: bottom-right 10% 白内阴影
                shape
                    .stroke(Color.white.opacity(0.5), lineWidth: 4 * scale)
                    .blur(radius: 1 * scale)
                    .offset(x: 2 * scale, y: 2 * scale)
                    .mask(shape.fill(Color.black))
            }
            .opacity(opacity)
        }
    }
}

// MARK: - SVG 缩放 helper (viewBox 320×320)

struct BrandSVGScale {
    static let viewBox: CGFloat = 320
    static func map(_ rect: CGRect) -> (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        let s = min(rect.width, rect.height) / viewBox
        let dx = (rect.width - viewBox * s) / 2
        let dy = (rect.height - viewBox * s) / 2
        return (s, dx, dy)
    }
}

private extension Path {
    /// Absolute move-to (SVG M, 已应用 viewBox 映射)
    mutating func _move(_ x: CGFloat, _ y: CGFloat,
                        _ c: (scale: CGFloat, dx: CGFloat, dy: CGFloat)) {
        move(to: CGPoint(x: c.dx + x * c.scale, y: c.dy + y * c.scale))
    }
    /// Absolute line-to (SVG L)
    mutating func _line(_ x: CGFloat, _ y: CGFloat,
                        _ c: (scale: CGFloat, dx: CGFloat, dy: CGFloat)) {
        addLine(to: CGPoint(x: c.dx + x * c.scale, y: c.dy + y * c.scale))
    }
    /// Cubic bezier — SVG C 的 (c1x c1y, c2x c2y, ex ey) 三对坐标
    mutating func _curve(to end: (CGFloat, CGFloat),
                         c1: (CGFloat, CGFloat),
                         c2: (CGFloat, CGFloat),
                         _ c: (scale: CGFloat, dx: CGFloat, dy: CGFloat)) {
        addCurve(
            to: CGPoint(x: c.dx + end.0 * c.scale, y: c.dy + end.1 * c.scale),
            control1: CGPoint(x: c.dx + c1.0 * c.scale, y: c.dy + c1.1 * c.scale),
            control2: CGPoint(x: c.dx + c2.0 * c.scale, y: c.dy + c2.1 * c.scale)
        )
    }
}

// MARK: - 5 个 Shape (SVG path #1-#5, 从 SVG XML 顺序映射)

/// SVG path #1 — 右上 echo 柱 (opacity 0.4). v7 改成跟 path #4 一对的高瘦柱 echo, 不再是小角斜柱.
struct BrandEcho1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(203.085, 79.9764, c)
        p._curve(to: (212.214, 74.2783), c1: (202.59, 75.0274), c2: (207.985, 71.6598), c)
        p._line(234.775, 88.2497, c)
        p._curve(to: (244.206, 104.002), c1: (240.285, 91.6621), c2: (243.801, 97.5332), c)
        p._line(252.696, 239.426, c)
        p._curve(to: (244.342, 247.918), c1: (252.994, 244.178), c2: (249.1, 248.137), c)
        p._line(230.982, 247.3, c)
        p._curve(to: (218.647, 235.607), c1: (224.539, 247.002), c2: (219.288, 242.025), c)
        p._line(203.085, 79.9764, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #2 — 中竖向 echo 柱 (opacity 0.4). v7 拉成跟 BrandBar1 同节奏的高瘦柱.
struct BrandEcho2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(124.511, 25.7485, c)
        p._curve(to: (136.374, 18.6297), c1: (124.424, 19.6096), c2: (130.998, 15.6643), c)
        p._line(168.916, 36.5794, c)
        p._curve(to: (181.319, 57.1019), c1: (176.416, 40.7166), c2: (181.143, 48.5378), c)
        p._line(185.67, 269.074, c)
        p._curve(to: (173.898, 279.121), c1: (185.8, 275.389), c2: (180.115, 280.241), c)
        p._line(140.16, 273.04, c)
        p._curve(to: (127.823, 258.491), c1: (133.097, 271.767), c2: (127.925, 265.668), c)
        p._line(124.511, 25.7485, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #3 — 最大主柱 (左) (opacity 1.0 in SVG). v7 整体拉高 + 顶部前倾.
struct BrandBar1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(118.745, 23.2059, c)
        p._curve(to: (135.29, 18.0316), c1: (121.781, 17.0855), c2: (129.308, 14.7317), c)
        p._line(168.547, 36.3755, c)
        p._curve(to: (175.621, 56.4591), c1: (175.664, 40.3012), c2: (178.707, 48.9394), c)
        p._line(91.9959, 260.267, c)
        p._curve(to: (73.5369, 269.77), c1: (89.0122, 267.539), c2: (81.1888, 271.566), c)
        p._line(19.1963, 257.014, c)
        p._curve(to: (11.1891, 239.998), c1: (11.6683, 255.246), c2: (7.75241, 246.925), c)
        p._line(118.745, 23.2059, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #4 — 中等主柱 (opacity 0.85 in SVG). v7 起点上移、终点下移 → 高度跟 Bar1 同 scale.
struct BrandBar2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(197.668, 79.4321, c)
        p._curve(to: (212.33, 74.3505), c1: (199.838, 73.4715), c2: (206.937, 71.0109), c)
        p._line(234.375, 88.002, c)
        p._curve(to: (240.387, 104.016), c1: (239.786, 91.3529), c2: (242.256, 97.9322), c)
        p._line(189.567, 269.421, c)
        p._curve(to: (173.701, 279.087), c1: (187.486, 276.193), c2: (180.674, 280.344), c)
        p._line(139.682, 272.955, c)
        p._curve(to: (132.059, 259.694), c1: (133.578, 271.855), c2: (129.937, 265.522), c)
        p._line(197.668, 79.4321, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #5 — 最右小柱 (opacity 0.7 in SVG). v7 改成跟 Bar2 同形态的细柱, 不再是斜角小三角.
struct BrandBar3: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(244.777, 151.503, c)
        p._curve(to: (256.162, 146.414), c1: (246.075, 146.559), c2: (251.613, 144.084), c)
        p._line(267.541, 152.243, c)
        p._curve(to: (273.717, 165.812), c1: (272.5, 154.784), c2: (275.058, 160.404), c)
        p._line(255.622, 238.778, c)
        p._curve(to: (243.421, 247.877), c1: (254.245, 244.332), c2: (249.137, 248.141), c)
        p._line(229.643, 247.24, c)
        p._curve(to: (222.274, 237.217), c1: (224.557, 247.005), c2: (220.982, 242.142), c)
        p._line(244.777, 151.503, c)
        p.closeSubpath()
        return p
    }
}

#Preview("Accent on black") {
    HStack(spacing: 24) {
        MasoBrandLogo()
            .frame(width: 120, height: 120)
        MasoBrandLogo(color: .white)
            .frame(width: 60, height: 60)
        MasoBrandLogo(color: .black)
            .frame(width: 40, height: 40)
            .background(MasoColor.accent)
    }
    .padding(40)
    .background(Color.black)
}
