import SwiftUI

// MARK: - RoutineOptimizeCard — 数据驱动优化建议卡 (Pro feature ②)
//
// 浮在 Saved routines 页顶部, 仅当 data.routineSuggestion() != nil (练够 ~2 周 + 诊断出问题) 才显示.
// 卡上: accent kicker "OPTIMIZE" + 诊断 title + detail + "Optimize with AI" 按钮.
// 点按钮 (Pro) → 上抛 suggestion 给 PlansScreen, 它切到 AI 标签 + 把诊断的 focusNote 注进
// generateAIRoutines(focusNote:) 重生成一批偏向修复的 routine. 非 Pro → 弹 paywall.
// 卡本身对所有人可见 (teaser), 动作才 gate.
struct RoutineOptimizeCard: View {
    let suggestion: DataStore.RoutineSuggestion
    /// 点 "Optimize with AI" 的回调 — parent (TodayScreen) 接管 Pro gating + 拉起 chat / paywall.
    let onOptimize: (DataStore.RoutineSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // kicker
            HStack(spacing: 6) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 10, weight: .heavy))
                Text("OPTIMIZE")
                    .font(.system(size: 10, weight: .heavy)).tracking(1.5)
            }
            .foregroundStyle(MasoColor.accent)

            Text(suggestion.title)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)

            Text(suggestion.detail)
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                Haptics.tap()
                onOptimize(suggestion)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles").font(.system(size: 13, weight: .heavy))
                    Text("Optimize with AI").font(.system(size: 14, weight: .heavy))
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 22)
                // 次级胶囊钮 (owner 映射表②点名): iOS 26 = accent 低浓度玻璃 + accent 字;
                // 旧系统保留改动前的实心 accent + 黑字.
                .foregroundStyle(systemGlassAvailable ? MasoColor.accent : .black)
                .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25), fallback: MasoColor.accent)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(MasoMetrics.cardPadding - 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(
            RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium)
                .stroke(MasoColor.borderHero, lineWidth: 0.5)
        )
    }
}
