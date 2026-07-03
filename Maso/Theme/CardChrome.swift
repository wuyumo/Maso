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
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}
