import SwiftUI

// List ↔ Grid 视图模式切换器 — Plans tab (PlanDetailSheet) 和 History tab (SessionDetailSheet)
// 共用同一个组件, 视觉 + 行为统一. 持久化 @AppStorage key 由 caller 决定 (两个 sheet 可以
// 独立保存偏好或共享同一 key).
//
// 用 spring 0.35/0.85 切换 — 跟 Plans 之前的同款节奏.
struct LayoutToggle: View {
    /// true = grid card layout; false = list row layout
    @Binding var useCardLayout: Bool

    var body: some View {
        HStack(spacing: 2) {
            button(isGrid: false, icon: "list.bullet")
            button(isGrid: true, icon: "square.grid.2x2.fill")
        }
        .padding(2)
        .background(
            Capsule()
                .fill(MasoColor.surface.opacity(0.5))
        )
    }

    @ViewBuilder
    private func button(isGrid: Bool, icon: String) -> some View {
        let active = useCardLayout == isGrid
        Button(action: {
            guard !active else { return }
            Haptics.tap()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                useCardLayout = isGrid
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(active ? MasoColor.text : MasoColor.textFaint)
                .frame(width: 26, height: 22)
                .background(
                    Capsule()
                        .fill(active ? MasoColor.accent.opacity(0.85) : Color.clear)
                )
        }
        .buttonStyle(.plain)
    }
}
