import SwiftUI

// 3-tab 底部栏 — 跟 web 端 BottomNav.tsx 对齐 (但不再 morph)
//
// 当前布局 (左 → 中 → 右):
//   - 左:   今日训练 (大圆 + Maso 标志, 主入口 + primary action)
//   - 中:   训练计划 (side icon — 两横杠, 跟 Plans 列表视觉同源)
//   - 右:   肌肉状态 (clock icon)
//
// 设计哲学:
//   - 左侧 big circle = "今日训练" — 是用户最频繁触发的动作 (开始今日推荐).
//     选中状态再点 = 直接开练 (跳过详情 sheet), 提供 quick-start muscle memory.
//   - 中间 side icon = Plans hub, 让用户切到训练计划列表浏览/编辑/新建.
//     新建 plan 入口在 Plans tab 的标题行 "+" 按钮 (不在 TabBar 上做长按 menu).
//   - 右侧 side icon = Muscle Status, 显示 7 天肌群活跃度 + 训练记录.
//   - 训练中状态不在 TabBar 内体现 — 由独立的 TrainingMiniBar 浮在 TabBar 上方.
struct TabBarView: View {
    @Binding var selection: RootTab

    /// 点大圆按钮 (Today) → 主流程 (handleCenterPrimary in RootView):
    ///   - 不在 Today tab → 切到 Today
    ///   - 已在 Today + 训练中 → 拉 PlanPlayer
    ///   - 已在 Today + 没训练 + quickStart 开 → 直接开练今日推荐
    let onCenterPrimary: () -> Void

    var body: some View {
        let isTodayActive = (selection == .today)
        HStack(spacing: 36) {
            // ─── 左: 今日训练 (大圆 + Maso M, primary action) ───
            Button(action: onCenterPrimary) {
                ZStack {
                    Circle()
                        .fill(isTodayActive ? MasoColor.accent : Color.black)
                        .overlay(
                            Circle()
                                .stroke(.white.opacity(isTodayActive ? 0 : 0.1), lineWidth: 1)
                        )
                        .shadow(color: isTodayActive
                                ? MasoColor.accent.opacity(0.45)
                                : .black.opacity(0.55),
                                radius: 12, x: 0, y: 8)
                    MasoMarkIcon(color: isTodayActive ? .black : Color(red: 0.945, green: 1.0, blue: 0.965))
                        .frame(width: 32, height: 32)
                }
                .frame(width: 56, height: 56)
                // active 切换时颜色/阴影平滑过渡, 而不是硬切
                .animation(.easeOut(duration: 0.22), value: isTodayActive)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey("Today")))

            // ─── 中: 训练计划 (side icon — 两横杠) ───
            SideTab(
                label: "Plans",
                active: selection == .plans,
                icon: { IconPlans(active: selection == .plans) }
            ) { selection = .plans }
            .frame(width: 56)

            // ─── 右: 肌肉状态 (side icon — clock) ───
            SideTab(
                label: "Muscle Status",
                active: selection == .history,
                icon: { IconHistory(active: selection == .history) }
            ) { selection = .history }
            .frame(width: 56)
        }
        // 胶囊内边距 — 跟着胶囊缩一圈 (左右各减 8pt). 3pt = (62 胶囊高 - 56 大圆) / 2,
        // 大圆距上下左边都等距 (3pt)
        .padding(.horizontal, 3)
        .frame(height: MasoMetrics.bottomNavHeight)
        // fixedSize 横向 = 胶囊不再撑满, 宽度收紧到内容宽 (~64+22+48+22+48 + 32 padding = 236pt 上下).
        // 大圆视觉占主位, 三个 tab 居中簇在一起.
        .fixedSize(horizontal: true, vertical: false)
        .background(
            Capsule()
                .fill(Color.black)
                .overlay(
                    Capsule().stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
                .shadow(color: .black.opacity(0.55), radius: 22, x: 0, y: 10)
        )
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)  // 让胶囊在屏幕水平居中
    }
}

private struct SideTab<Icon: View>: View {
    let label: String
    let active: Bool
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            // Icon 单独居中 — 指示器走 overlay, 不影响 icon 视觉中心.
            icon()
                .frame(width: 28, height: 28)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) {
                    // 指示器圆点 — 从 0 弹簧到 6×6, 跟"被点亮"小灯一样
                    Circle()
                        .fill(active ? MasoColor.accent : Color.clear)
                        .frame(width: active ? 6 : 0, height: active ? 6 : 0)
                        .padding(.bottom, 8)
                        .animation(.spring(response: 0.32, dampingFraction: 0.72), value: active)
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // VoiceOver 用户听到 tab 名 (UI 视觉上没显示文字, label 只用作 a11y)
        .accessibilityLabel(Text(LocalizedStringKey(label)))
    }
}

// MARK: - Icons (两侧 tab 视觉重量保持一致)

/// 训练计划 tab — 两根小横杠. 视觉同源于 Plans 列表行 (一行 = 一根杠).
/// 选中 = text 白, 未选中 = textDim 灰.
private struct IconPlans: View {
    let active: Bool
    var body: some View {
        VStack(spacing: 3) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(active ? MasoColor.text : MasoColor.textDim)
                .frame(width: 16, height: 5)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(active ? MasoColor.text : MasoColor.textDim)
                .frame(width: 16, height: 5)
        }
    }
}

/// 肌肉状态 tab — 横向时钟 (尺寸 / 视觉重量跟 IconPlans 对齐, 永远 filled).
/// 名字虽然路由叫 history, 但展示的是"7 天肌群活跃度 + 训练记录", 时钟符号能表达"时间维度".
/// 选中 = text 白, 未选中 = textDim 灰.
private struct IconHistory: View {
    let active: Bool
    var body: some View {
        Image(systemName: "clock.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? MasoColor.text : MasoColor.textDim)
    }
}
