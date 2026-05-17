import SwiftUI

// 3-tab 底部栏 — 跟 web 端 BottomNav.tsx 对齐 (但不再 morph)
//   - 左: 我的训练 (两横杠)
//   - 中: 今日 (大圆闪电按钮; Today 上长按 → 自由组菜单)
//   - 右: 历史 (横向时钟)
//
// 训练中状态不在 TabBar 内体现 — 由独立的 TrainingMiniBar (Apple Music 风) 浮在 TabBar 上方.
// TabBar 始终 3 列固定布局.
struct TabBarView: View {
    @Binding var selection: RootTab

    /// 点中间按钮 → 主流程
    let onCenterPrimary: () -> Void
    /// 长按中间按钮 菜单 "New workout" 选项 — 跟 Plans tab 标题行的 "+" 按钮同流程,
    /// 直接新建空白 plan → 打开编辑 sheet, 让用户加动作配 sets/reps.
    /// 之前这个按钮拉起 QuickWorkoutScreen (muscle picker → exercise picker), 现在两边统一.
    /// QuickWorkoutScreen 的入口保留在 Today 的 "Free workout" 按钮下方 (那条路径是 muscle 推荐, 不一样).
    let onNewWorkout: () -> Void

    var body: some View {
        let isTodayActive = (selection == .today)
        HStack(spacing: 0) {
            SideTab(
                label: "Plans",
                active: selection == .plans,
                icon: { IconPlans(active: selection == .plans) }
            ) { selection = .plans }

            // 中间按钮 — 始终是大圆 (没有 pill morph)
            Menu {
                Button {
                    onNewWorkout()
                } label: {
                    // icon 强制白色 — Menu 默认 systemImage 走 accent (绿色), 用户偏好 icon 统一白
                    Label {
                        Text("New workout")
                    } icon: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(.white)
                    }
                }
            } label: {
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
                    // Maso 标志 — active 用深色 (在绿底上对比), inactive 用浅色 (在黑底上对比)
                    // 新版 SVG 是 320×320 方形 viewBox, 内置 padding, 用 32×32 frame
                    // 可见 M 宽度 ≈ 19pt, 跟左右两侧 tab icon (~18pt) 接近, 略大一点
                    MasoMarkIcon(color: isTodayActive ? .black : Color(red: 0.945, green: 1.0, blue: 0.965))
                        .frame(width: 32, height: 32)
                }
                .frame(width: 64, height: 64)
                .offset(y: -14)
            } primaryAction: {
                onCenterPrimary()
            }
            .menuStyle(.button)
            .frame(maxWidth: .infinity)

            SideTab(
                label: "Muscle Status",
                active: selection == .history,
                icon: { IconHistory(active: selection == .history) }
            ) { selection = .history }
        }
        .frame(height: MasoMetrics.bottomNavHeight)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
        .background(
            // 用纯黑 — Home Indicator 区延续同色, 跟 PlanPlayer 底部黑铺到一起视觉一致.
            // 之前用 material + 接近黑 (#131313), 跟 PlanPlayer 的 #000 不一致, 缩 sheet 时有色差.
            Rectangle()
                .fill(Color.black)
                .overlay(alignment: .top) {
                    Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)
                }
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

private struct SideTab<Icon: View>: View {
    let label: String
    let active: Bool
    @ViewBuilder let icon: () -> Icon
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                icon()
                    .frame(width: 28, height: 28)
                Capsule()
                    .fill(active ? MasoColor.accent : Color.clear)
                    .frame(width: 20, height: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Icons (两侧 tab 视觉重量保持一致)

/// 第 1 tab — 两根小横杠
/// 选中 = text 白, 未选中 = textDim 灰 (跟 IconHistory 颜色逻辑保持一致)
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

/// 第 3 tab — 横向时钟 (尺寸 / 视觉重量跟 IconPlans 对齐, 永远 filled)
/// 选中 = text 白, 未选中 = textDim 灰
private struct IconHistory: View {
    let active: Bool
    var body: some View {
        Image(systemName: "clock.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(active ? MasoColor.text : MasoColor.textDim)
    }
}
