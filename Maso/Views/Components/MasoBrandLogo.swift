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

    static let defaultOpacities: [Double] = [0.4, 0.5, 1.0, 0.85, 0.7]

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

/// SVG path #1 — 右上小斜柱 echo (opacity 0.4 in SVG)
struct BrandEcho1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(192.446, 106.265, c)
        p._curve(to: (200.695, 99.0393), c1: (190.904, 101.299), c2: (195.977, 96.8563), c)
        p._line(242.97, 118.597, c)
        p._curve(to: (254.214, 132.982), c1: (248.816, 121.301), c2: (253.001, 126.656), c)
        p._line(268.326, 206.572, c)
        p._curve(to: (265.279, 213.751), c1: (268.861, 209.362), c2: (267.657, 212.198), c)
        p._line(245.794, 226.479, c)
        p._curve(to: (227.772, 219.992), c1: (239.123, 230.836), c2: (230.135, 227.601), c)
        p._line(192.446, 106.265, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #2 — 中竖向圆角柱 echo (opacity 0.5 in SVG)
struct BrandEcho2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(95.7204, 104.655, c)
        p._curve(to: (138.48, 64.7968), c1: (87.2144, 78.589), c2: (113.074, 54.4835), c)
        p._curve(to: (157.682, 87.0822), c1: (148.095, 68.7003), c2: (155.243, 76.9953), c)
        p._line(195.949, 245.317, c)
        p._curve(to: (188.061, 257.498), c1: (197.296, 250.888), c2: (193.695, 256.448), c)
        p._line(160.959, 262.549, c)
        p._curve(to: (143.951, 252.456), c1: (153.561, 263.927), c2: (146.286, 259.61), c)
        p._line(95.7204, 104.655, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #3 — 最大主柱 (左) (opacity 1.0 in SVG)
struct BrandBar1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(72.1364, 54.0457, c)
        p._curve(to: (88.5432, 44.525), c1: (73.1808, 46.2736), c2: (81.2772, 41.5754), c)
        p._line(141.211, 65.9056, c)
        p._curve(to: (150.798, 84.2624), c1: (148.47, 68.8523), c2: (152.527, 76.6216), c)
        p._line(110.374, 262.876, c)
        p._curve(to: (96.3601, 275.265), c1: (108.854, 269.59), c2: (103.21, 274.58), c)
        p._line(56.7851, 279.221, c)
        p._curve(to: (43.6983, 265.682), c1: (49.0749, 279.992), c2: (42.6664, 273.362), c)
        p._line(72.1364, 54.0457, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #4 — 中等主柱 (opacity 0.85 in SVG)
struct BrandBar2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(185.631, 105.3, c)
        p._curve(to: (199.564, 98.5161), c1: (187.082, 99.1388), c2: (193.819, 95.8586), c)
        p._line(240.168, 117.3, c)
        p._curve(to: (247.261, 135.273), c1: (246.95, 120.438), c2: (250.072, 128.349), c)
        p._line(201.307, 248.474, c)
        p._curve(to: (190.9, 256.971), c1: (199.513, 252.895), c2: (195.59, 256.097), c)
        p._line(163.113, 262.149, c)
        p._curve(to: (151.548, 250.026), c1: (156.011, 263.473), c2: (149.891, 257.059), c)
        p._line(185.631, 105.3, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #5 — 最右小柱 (opacity 0.7 in SVG)
struct BrandBar3: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(262.055, 164.846, c)
        p._curve(to: (275.831, 163.149), c1: (264.45, 159.149), c2: (272.125, 158.204), c)
        p._line(287.469, 178.679, c)
        p._curve(to: (286.272, 194.44), c1: (291.075, 183.491), c2: (290.563, 190.228), c)
        p._line(270.057, 210.353, c)
        p._curve(to: (268.215, 211.835), c1: (269.493, 210.907), c2: (268.876, 211.403), c)
        p._line(246.16, 226.241, c)
        p._curve(to: (238.816, 220.117), c1: (242.031, 228.938), c2: (236.905, 224.663), c)
        p._line(262.055, 164.846, c)
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
