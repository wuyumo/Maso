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
        p._move(202.245, 81.3876, c)
        p._curve(to: (212.144, 76.6644), c1: (202.103, 76.188), c2: (208.192, 73.2824), c)
        p._line(234.265, 95.5946, c)
        p._curve(to: (241.238, 109.83), c1: (238.451, 99.1768), c2: (240.973, 104.327), c)
        p._line(247.044, 230.653, c)
        p._curve(to: (242.804, 237.425), c1: (247.184, 233.575), c2: (245.494, 236.275), c)
        p._line(224.529, 245.24, c)
        p._curve(to: (206.422, 233.644), c1: (216.092, 248.848), c2: (206.674, 242.816), c)
        p._line(202.245, 81.3876, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #2 — 中竖向 echo 柱 (opacity 0.4). v7 拉成跟 BrandBar1 同节奏的高瘦柱.
struct BrandEcho2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(127.238, 57.0463, c)
        p._curve(to: (169.751, 35.1531), c1: (127.16, 35.1314), c2: (151.956, 22.3621), c)
        p._curve(to: (180.927, 57.1607), c1: (176.828, 40.2399), c2: (180.995, 48.4456), c)
        p._line(179.337, 260.524, c)
        p._curve(to: (169.434, 270.445), c1: (179.294, 265.978), c2: (174.889, 270.393), c)
        p._line(143.09, 270.701, c)
        p._curve(to: (127.945, 255.755), c1: (134.77, 270.782), c2: (127.975, 264.075), c)
        p._line(127.238, 57.0463, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #3 — 最大主柱 (左) (opacity 1.0 in SVG). v7 整体拉高 + 顶部前倾.
struct BrandBar1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(121.633, 19.3457, c)
        p._curve(to: (139.914, 13.706), c1: (124.353, 11.8734), c2: (133.457, 9.06477), c)
        p._line(171.193, 36.1897, c)
        p._curve(to: (176.89, 54.654), c1: (177.014, 40.3736), c2: (179.341, 47.9181), c)
        p._line(100.36, 264.918, c)
        p._curve(to: (84.1274, 275.401), c1: (97.9081, 271.654), c2: (91.2756, 275.937), c)
        p._line(45.7137, 272.518, c)
        p._curve(to: (35.3353, 256.448), c1: (37.7841, 271.923), c2: (32.6156, 263.92), c)
        p._line(121.633, 19.3457, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #4 — 中等主柱 (opacity 0.85 in SVG). v7 起点上移、终点下移 → 高度跟 Bar1 同 scale.
struct BrandBar2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(196.939, 81.4358, c)
        p._curve(to: (212.838, 77.2582), c1: (199.327, 74.8748), c2: (207.533, 72.7186), c)
        p._line(233.452, 94.8993, c)
        p._curve(to: (237.505, 110.324), c1: (237.886, 98.6937), c2: (239.501, 104.84), c)
        p._line(182.578, 261.235, c)
        p._curve(to: (169.558, 270.446), c1: (180.582, 266.719), c2: (175.394, 270.39), c)
        p._line(142.427, 270.71, c)
        p._curve(to: (132.934, 257.29), c1: (135.446, 270.777), c2: (130.546, 263.851), c)
        p._line(196.939, 81.4358, c)
        p.closeSubpath()
        return p
    }
}

/// SVG path #5 — 最右小柱 (opacity 0.7 in SVG). v7 改成跟 Bar2 同形态的细柱, 不再是斜角小三角.
struct BrandBar3: Shape {
    func path(in rect: CGRect) -> Path {
        let c = BrandSVGScale.map(rect)
        var p = Path()
        p._move(244.409, 149.832, c)
        p._curve(to: (259.064, 148.955), c1: (246.804, 143.251), c2: (255.901, 142.706), c)
        p._line(268.186, 166.977, c)
        p._curve(to: (268.756, 176.5), c1: (269.684, 169.936), c2: (269.891, 173.383), c)
        p._line(249.055, 230.629, c)
        p._curve(to: (242.497, 237.558), c1: (247.92, 233.746), c2: (245.546, 236.254), c)
        p._line(223.925, 245.5, c)
        p._curve(to: (213.262, 235.408), c1: (217.485, 248.253), c2: (210.866, 241.989), c)
        p._line(244.409, 149.832, c)
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
