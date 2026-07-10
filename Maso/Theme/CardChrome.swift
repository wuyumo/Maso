import SwiftUI

// 共享卡片外壳 — padding 14 + surface 填充 + corner medium (16).
// 原本私有在 AISummaryCard.swift, 抽成 internal 让 AI Coach Summary 卡 (Progress) 跟
// Training Preferences 卡 (Routines) 共用同一片壳, 保证两张卡颜色/圆角/内边距逐像素一致.
// (跟 InsightsChartsView 其它卡也一致.)
extension View {
    func cardChrome() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }

    /// 液态玻璃卡底 (试验性, 回退点 tag pre-liquid-glass; owner 拍板: 全部卡片用 iOS 原生
    /// Liquid Glass, 跟按钮/导航胶囊同一套系统材质 — 带边缘折光, 不是普通磨砂).
    /// 只换"底", 布局/描边由调用处照旧; cornerRadius 需与调用处 clipShape 一致 (玻璃按形状折光).
    /// ⚠️ 材质跟随系统 colorScheme — app 根已挂 .preferredColorScheme(.dark) (MasoApp.swift).
    @ViewBuilder
    func glassCardBackground(cornerRadius: CGFloat = MasoMetrics.cornerRadiusMedium) -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.tint(MasoColor.accent.opacity(0.04)),
                             in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // iOS <26 回退: ultraThinMaterial + 压暗 + accent tint (v2 的磨砂方案).
            self.background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.30)
                    MasoColor.accent.opacity(0.03)
                }
            }
        }
    }
}
