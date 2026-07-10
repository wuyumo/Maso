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

    /// 磨砂玻璃卡底 (试验性, 回退点 tag pre-liquid-glass) —
    /// .ultraThinMaterial + 一点点 MasoColor.accent tint. 只换"底",
    /// 圆角/描边/布局仍由调用处照旧负责 (跟原 .background(MasoColor.surface) 等位替换).
    /// ⚠️ 材质跟随系统 colorScheme — app 根已挂 .preferredColorScheme(.dark) (MasoApp.swift).
    func glassCardBackground() -> some View {
        self.background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                MasoColor.accent.opacity(0.03)
            }
        }
    }
}
