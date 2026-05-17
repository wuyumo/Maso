import SwiftUI

// Maso M 标志 — 小尺寸版本.
// 新一套素材 (2026-05) 取消了 BrandLogo (大) vs MarkIcon (小) 的 path 数据差异 —
// 两个组件都用同一套 320×320 path (`MasoBrandLogo.swift` 里的 BrandBar1/2/3 + BrandEcho1/2),
// 只是 caller 控制 frame 不同.
//
// 这个 wrapper 保留是为 caller API 兼容 (TabBar / Settings / Paywall 等).
struct MasoMarkIcon: View {
    let color: Color
    /// 5 个 path 的 opacity — 默认跟 SVG 出图一致.
    /// 顺序: [Echo1, Echo2, Bar1, Bar2, Bar3]
    var opacities: [Double] = MasoBrandLogo.defaultOpacities

    var body: some View {
        // 直接复用 BrandLogo, opacities 透传
        MasoBrandLogo(color: color, opacities: opacities)
    }
}

#Preview("On dark bg") {
    HStack(spacing: 24) {
        MasoMarkIcon(color: .white).frame(width: 64, height: 64)
        MasoMarkIcon(color: .white).frame(width: 32, height: 32)
        MasoMarkIcon(color: .white).frame(width: 20, height: 20)
    }
    .padding(40)
    .background(Color.black)
}

#Preview("On accent bg") {
    HStack(spacing: 24) {
        MasoMarkIcon(color: .black).frame(width: 64, height: 64)
        MasoMarkIcon(color: .black).frame(width: 36, height: 36)
    }
    .padding(40)
    .background(MasoColor.accent)
}
