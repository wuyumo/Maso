import SwiftUI

// SwipeableRow — 自定义左滑 actions wrapper.
//
// 为什么不用 iOS 原生 .swipeActions:
//   - 原生把 button 高度对齐 cell bounds (含 listRowInsets 的 bottom spacing),
//     button 比可视卡片高出 12pt; 没法两全 (要么没间距, 要么 button 超出).
//   - 自定义实现: button 用 ZStack + .frame(maxHeight: .infinity) 跟 content 严格同高,
//     listRowInsets 的 bottom 12pt 仍是 List 行间距, button 不会被拉高.
//
// 行为:
//   - 左滑 → spring snap 到打开 (露出 right actions); 右滑或 tap → 关闭
//   - 不支持 full-swipe (swipe 一半 → 弹回打开; 必须 tap action 按钮)
//   - 同时多 row 可打开 (跟 iOS 原生一致, 不做 single-open 互斥)
//   - 关闭状态 tap → onContentTap (content 自己的 .onTapGesture 也会响应);
//     打开状态 tap content → 关闭 (overlay 拦截, 不触发 onContentTap)
//
// 跟 List 滚动冲突: DragGesture(minimumDistance: 8) + |dx| > |dy| * 1.5 gate,
// 水平拖才生效; 竖直拖让给 List.
struct SwipeableRow<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var actions: [SwipeAction]
    var onContentTap: (() -> Void)? = nil
    var cornerRadius: CGFloat = MasoMetrics.cornerRadiusMedium

    @State private var dragOffset: CGFloat = 0
    @State private var isOpen: Bool = false

    /// 每个 action button 宽 — 跟 iOS 原生 trailing swipe action 一致 (~76pt).
    private let actionWidth: CGFloat = 76

    private var totalActionsWidth: CGFloat {
        CGFloat(actions.count) * actionWidth
    }

    /// 当前 content 的 x offset — 打开 = -totalActionsWidth + dragOffset (右拖减小绝对值);
    /// 关闭 = dragOffset (本身就是负数).
    private var currentOffset: CGFloat {
        isOpen ? -totalActionsWidth + dragOffset : dragOffset
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            // 1) 底层 — actions row 钉在右侧, 高度跟 ZStack (= content) 一致
            HStack(spacing: 0) {
                ForEach(Array(actions.enumerated()), id: \.offset) { _, action in
                    actionButton(action)
                }
            }
            .frame(width: totalActionsWidth)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            // 仅在 row 开始打开 (offset != 0) 时显示 actions; 完全关闭时隐藏避免
            // VoiceOver / accessibility 把它当 reachable.
            .opacity(currentOffset < 0 ? 1 : 0)

            // 2) 上层 — content. offset 跟 drag 同步; spring snap 跟 isOpen / dragOffset reset.
            content()
                .contentShape(Rectangle())
                .offset(x: currentOffset)
                // 打开状态用 overlay 拦截 content 内部 .onTapGesture, 让 tap → 关闭
                // (而不是触发 content 的 onTap 进 detail).
                .overlay(alignment: .center) {
                    if isOpen {
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { snapClosed() }
                            .offset(x: currentOffset)
                    }
                }
                // simultaneousGesture — 不抢父 ScrollView 的竖直滚动手势.
                // dragGesture 内部用 |dx| > |dy| * 1.5 gate 只响应水平拖, 不会跟 vertical scroll 冲突.
                .simultaneousGesture(dragGesture)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    // MARK: - Action button

    private func actionButton(_ action: SwipeAction) -> some View {
        Button {
            // 先收回再 fire — 收回动画跟 action 执行同步, 避免 button 还停在屏上.
            snapClosed()
            action.action()
        } label: {
            // iOS 原生 swipe action 风格 — 只文字, 无 icon. 居中.
            Text(NSLocalizedString(action.label, comment: ""))
                .font(.system(size: 15))
                .foregroundStyle(action.foreground)
                .lineLimit(1)
                .frame(width: actionWidth)
                .frame(maxHeight: .infinity) // ← 严格跟 content 同高
                .background(action.color)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Drag gesture

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                // 水平 gate — 避免跟 List 竖直滚动抢手势.
                // 用 1.5x 比例 (而非 abs(dx) > abs(dy)) 防止斜向拖时误判.
                guard abs(dx) > abs(dy) * 1.5 else { return }

                if isOpen {
                    // 打开状态: 允许向右拖关闭, 不允许继续左拖超过 actions 宽度.
                    dragOffset = max(0, min(dx, totalActionsWidth))
                } else {
                    // 关闭状态: 只允许向左拖, 允许 30% 超拉 (橡皮筋感).
                    dragOffset = min(0, max(dx, -totalActionsWidth * 1.3))
                }
            }
            .onEnded { value in
                let dx = value.translation.width
                let predict = value.predictedEndTranslation.width

                if isOpen {
                    // 已打开: 右拖 > 一半宽度 或速度足够 → 关闭; 否则弹回打开.
                    if dx > totalActionsWidth / 2 || predict > totalActionsWidth {
                        snapClosed()
                    } else {
                        snapOpen()
                    }
                } else {
                    // 关闭中: 左拖 < -一半 或速度足够 → 打开; 否则弹回关闭.
                    if dx < -totalActionsWidth / 2 || predict < -totalActionsWidth {
                        snapOpen()
                    } else {
                        snapClosed()
                    }
                }
            }
    }

    private func snapOpen() {
        if !isOpen { Haptics.tap() }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            isOpen = true
            dragOffset = 0
        }
    }

    private func snapClosed() {
        if isOpen { Haptics.tap() }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
            isOpen = false
            dragOffset = 0
        }
    }
}

/// 单个左滑 action 描述 — Edit / Delete 等.
///
/// 不做 .destructive special handling (iOS 原生 full-swipe 才需要),
/// 红色仅靠 `color` 视觉传达; `isDestructive` 保留给未来 accessibility / analytics
/// 标识用.
struct SwipeAction: Identifiable {
    let id = UUID()
    /// i18n key — 通过 NSLocalizedString 解析.
    let label: String
    /// SF symbol name.
    let systemImage: String
    /// 背景色 (accent / red 等).
    let color: Color
    /// 文字 icon 色 (.white / .black).
    let foreground: Color
    let action: () -> Void
    var isDestructive: Bool = false
}
