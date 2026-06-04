import SwiftUI

// MARK: - ProBanner — 付费展示位 (Today tab 顶部, Pro 用户隐藏)
//
// 设计思路 (参考 Strava / Hevy / Apple 自家 App 顶部的 promotional cell):
//   - 整张可点的卡片, 视觉跟普通内容卡明显区分:
//     · accent 绿色细描边
//     · 内嵌 accent 色 Maso 标志, 像 logo 卡
//     · 顶部 radial 微辉光, 制造 premium 感
//   - 信息层次清楚:
//     · kicker "MASO PRO" + "FROM <价>/MO" 并排小字 (价格 StoreKit 实时算, accent 绿, 大字距)
//     · 主标题 "Unlock everything" (白字大字, 17pt bold)
//     · 副标题 1 行总结主要价值 (淡灰)
//     · 右侧 chevron 暗示可进
//   - Pro 用户看不到这张卡 — 由 caller 用 `if !data.settings.isPro { ProBanner... }` 守门
struct ProBanner: View {
    /// "起步价"/月 — 由 caller 从 StoreKit yearly product 现算 (年价 ÷ 12, locale-aware).
    /// nil = product 还没 load → 不显示价格段, 只留 "MASO PRO" kicker (不写死假价格).
    var fromPrice: String? = nil
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                // 跟 Settings 页面的 logo 完全一致 — 40×40 MasoMarkIcon, accent 色, 无 shadow.
                MasoMarkIcon(color: MasoColor.accent)
                    .frame(width: 40, height: 40)

                // 中间文字栈 — kicker 行把"MASO PRO"和"FROM $2.50/mo"并排放, 节省纵向空间
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("MASO PRO")
                            .font(.system(size: 10, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                        if let fromPrice {
                            Circle()
                                .fill(MasoColor.accent.opacity(0.6))
                                .frame(width: 3, height: 3)
                            // "FROM $2.50/MO" — 价格走 StoreKit 实时算 (年价÷12), 不写死.
                            Text(String(format: NSLocalizedString("FROM %@/MO", comment: ""), fromPrice))
                                .font(.system(size: 10, weight: .heavy))
                                .tracking(1)
                                .foregroundStyle(MasoColor.accent)
                        }
                    }
                    Text("Unlock everything")
                        // 跟 WorkoutCard / PlanRow 对齐, iOS HIG Headline 17pt bold
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                    Text("Unlimited plans · Full history · Custom moves")
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 右侧 — 仅一个 chevron, 不再占文字宽度
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .heavy))
                    .foregroundStyle(MasoColor.accent)
            }
            .padding(MasoMetrics.cardPadding - 2)
            .background(
                ZStack {
                    MasoColor.surface
                    // 顶左微辉光, 让卡片有"高级感", 不是死的色块
                    RadialGradient(
                        colors: [MasoColor.accent.opacity(0.20), .clear],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 240
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            .overlay(
                RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                    .stroke(MasoColor.accent.opacity(0.30), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}
