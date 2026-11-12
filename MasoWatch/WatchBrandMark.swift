import SwiftUI

// Masso 品牌 M 标 — watch 端自包含版 (跟 iOS `MasoBrandLogo` 同一套 320×320 path).
// 纯平填充, 5 个 path 各带 opacity, 跟 `Maso Green/Black/white.svg` 1:1 (无 3D 内阴影).
// 单独一份是因为 iOS 那份依赖 MasoColor / 在 Maso target, 不便跨 target 共享; watch 这份
// 不依赖任何 iOS 主题, 只吃一个 color 参数 (默认品牌绿 #1ED760).
struct WatchBrandMark: View {
    var color: Color = Color(red: 30 / 255, green: 215 / 255, blue: 96 / 255)
    /// path opacity 顺序: [Echo1, Echo2, Bar1, Bar2, Bar3] — 跟 SVG 出图一致.
    private let opacities: [Double] = [0.4, 0.4, 1.0, 0.85, 0.7]

    var body: some View {
        ZStack {
            WatchMarkEcho1().fill(color.opacity(opacities[0]))
            WatchMarkEcho2().fill(color.opacity(opacities[1]))
            WatchMarkBar1().fill(color.opacity(opacities[2]))
            WatchMarkBar2().fill(color.opacity(opacities[3]))
            WatchMarkBar3().fill(color.opacity(opacities[4]))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

// MARK: - SVG 缩放 (viewBox 320×320) + Path helpers

private enum WatchMarkScale {
    static let viewBox: CGFloat = 320
    static func map(_ rect: CGRect) -> (scale: CGFloat, dx: CGFloat, dy: CGFloat) {
        let s = min(rect.width, rect.height) / viewBox
        return (s, (rect.width - viewBox * s) / 2, (rect.height - viewBox * s) / 2)
    }
}

private extension Path {
    mutating func _m(_ x: CGFloat, _ y: CGFloat, _ c: (scale: CGFloat, dx: CGFloat, dy: CGFloat)) {
        move(to: CGPoint(x: c.dx + x * c.scale, y: c.dy + y * c.scale))
    }
    mutating func _l(_ x: CGFloat, _ y: CGFloat, _ c: (scale: CGFloat, dx: CGFloat, dy: CGFloat)) {
        addLine(to: CGPoint(x: c.dx + x * c.scale, y: c.dy + y * c.scale))
    }
    mutating func _c(_ ex: CGFloat, _ ey: CGFloat, _ c1x: CGFloat, _ c1y: CGFloat,
                     _ c2x: CGFloat, _ c2y: CGFloat, _ c: (scale: CGFloat, dx: CGFloat, dy: CGFloat)) {
        addCurve(
            to: CGPoint(x: c.dx + ex * c.scale, y: c.dy + ey * c.scale),
            control1: CGPoint(x: c.dx + c1x * c.scale, y: c.dy + c1y * c.scale),
            control2: CGPoint(x: c.dx + c2x * c.scale, y: c.dy + c2y * c.scale)
        )
    }
}

// MARK: - 5 个 Shape (SVG path #1–#5)

private struct WatchMarkEcho1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = WatchMarkScale.map(rect); var p = Path()
        p._m(196.939, 81.4358, c)
        p._c(212.838, 77.2582, 199.327, 74.8748, 207.533, 72.7186, c)
        p._l(233.452, 94.8993, c)
        p._c(237.505, 110.324, 237.886, 98.6937, 239.501, 104.84, c)
        p._l(247.044, 230.653, c)
        p._c(242.497, 237.558, 247.184, 233.575, 245.546, 236.254, c)
        p._l(223.925, 245.5, c)
        p._c(213.262, 235.408, 217.485, 248.253, 210.866, 241.989, c)
        p._l(196.939, 81.4358, c)
        p.closeSubpath(); return p
    }
}

private struct WatchMarkEcho2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = WatchMarkScale.map(rect); var p = Path()
        p._m(121.633, 19.3457, c)
        p._c(139.914, 13.706, 124.353, 11.8734, 133.457, 9.06477, c)
        p._l(171.193, 36.1897, c)
        p._c(176.89, 54.654, 177.014, 40.3736, 179.341, 47.9181, c)
        p._l(182.578, 261.235, c)
        p._c(169.558, 270.446, 180.582, 266.719, 175.394, 270.39, c)
        p._l(142.427, 270.71, c)
        p._c(132.934, 257.29, 135.446, 270.777, 130.546, 263.851, c)
        p._l(121.633, 19.3457, c)
        p.closeSubpath(); return p
    }
}

private struct WatchMarkBar1: Shape {
    func path(in rect: CGRect) -> Path {
        let c = WatchMarkScale.map(rect); var p = Path()
        p._m(121.633, 19.3457, c)
        p._c(139.914, 13.706, 124.353, 11.8734, 133.457, 9.06477, c)
        p._l(171.193, 36.1897, c)
        p._c(176.89, 54.654, 177.014, 40.3736, 179.341, 47.9181, c)
        p._l(100.36, 264.918, c)
        p._c(84.1274, 275.401, 97.9081, 271.654, 91.2756, 275.937, c)
        p._l(45.7137, 272.518, c)
        p._c(35.3353, 256.448, 37.7841, 271.923, 32.6156, 263.92, c)
        p._l(121.633, 19.3457, c)
        p.closeSubpath(); return p
    }
}

private struct WatchMarkBar2: Shape {
    func path(in rect: CGRect) -> Path {
        let c = WatchMarkScale.map(rect); var p = Path()
        p._m(196.939, 81.4358, c)
        p._c(212.838, 77.2582, 199.327, 74.8748, 207.533, 72.7186, c)
        p._l(233.452, 94.8993, c)
        p._c(237.505, 110.324, 237.886, 98.6937, 239.501, 104.84, c)
        p._l(182.578, 261.235, c)
        p._c(169.558, 270.446, 180.582, 266.719, 175.394, 270.39, c)
        p._l(142.427, 270.71, c)
        p._c(132.934, 257.29, 135.446, 270.777, 130.546, 263.851, c)
        p._l(196.939, 81.4358, c)
        p.closeSubpath(); return p
    }
}

private struct WatchMarkBar3: Shape {
    func path(in rect: CGRect) -> Path {
        let c = WatchMarkScale.map(rect); var p = Path()
        p._m(244.409, 149.832, c)
        p._c(259.064, 148.955, 246.804, 143.251, 255.901, 142.706, c)
        p._l(268.186, 166.977, c)
        p._c(268.756, 176.5, 269.684, 169.936, 269.891, 173.383, c)
        p._l(249.055, 230.629, c)
        p._c(242.497, 237.558, 247.92, 233.746, 245.546, 236.254, c)
        p._l(223.925, 245.5, c)
        p._c(213.262, 235.408, 217.485, 248.253, 210.866, 241.989, c)
        p._l(244.409, 149.832, c)
        p.closeSubpath(); return p
    }
}
