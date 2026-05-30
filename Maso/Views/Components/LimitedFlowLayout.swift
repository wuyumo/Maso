import SwiftUI

// MARK: - LimitedFlowLayout — wrap 子视图, 最多 N 行 + 自动 overflow indicator
//
// 用法:
//   LimitedFlowLayout(spacing: 6, maxRows: 3, onTruncate: { count in ... }) {
//       ForEach(items) { ItemView() }
//       // 最后一个 subview 必须是 overflow indicator (e.g. ExercisePill("+N more")).
//       OverflowIndicator()
//   }
//
// 行为:
//   - 把"主 subviews" (除最后一个外) 按 flow 排, 自动换行.
//   - 总行数 > maxRows → 多余的主 subviews 不画 (place 到屏外), 把 overflow indicator 放在
//     最后一行末尾. 当前行末尾装不下 overflow → 回吐已放主 pill, 给 overflow 让位.
//   - 没截断 → overflow indicator 也不画.
//   - 截断个数通过 onTruncate(Int) 异步回调写回 caller (用 DispatchQueue.main.async 避开
//     "modifying state during view update" 警告). Caller 拿到 count 可以更新 overflow 文案
//     ("+N more"), 下一帧 Layout 重排 — 一般 1-2 帧内收敛.
struct LimitedFlowLayout: Layout {
    var spacing: CGFloat = 6
    var maxRows: Int = 3
    /// Callback — Layout 算完后告诉 caller "几个主 subviews 被截掉了" (0 = 没截).
    /// 用 async 写回 state 避免 SwiftUI re-render 循环警告.
    var onTruncate: ((Int) -> Void)? = nil

    private struct Plan {
        /// [(subview index, place position)] — 这些是要画的 subviews
        var placements: [(Int, CGPoint)] = []
        var totalSize: CGSize = .zero
        var truncatedCount: Int = 0
    }

    private func makePlan(subviews: Subviews, maxWidth: CGFloat) -> Plan {
        guard subviews.count >= 1 else { return Plan() }

        // 最后一个 subview = overflow indicator. 至少 1 个主 subview 才意义.
        let overflowIdx = subviews.count - 1
        let mainCount = subviews.count - 1
        guard mainCount > 0 else {
            return Plan(placements: [], totalSize: .zero, truncatedCount: 0)
        }

        // 预先量 overflow 的尺寸 — 决定是否要给它在当前行/上一行回吐空间.
        let overflowSize = subviews[overflowIdx].sizeThatFits(.unspecified)

        // 主 pill 的尺寸列表
        let sizes = (0..<mainCount).map { subviews[$0].sizeThatFits(.unspecified) }

        // 第一遍 — 把主 pill 按 flow 排到 maxRows 行内
        var placements: [(Int, CGPoint)] = []
        var rowHeights: [CGFloat] = []  // 每行的最大高
        var curX: CGFloat = 0
        var curY: CGFloat = 0
        var curRowH: CGFloat = 0
        var rowIdx = 0  // 0-based
        var truncatedCount = 0

        for i in 0..<mainCount {
            let size = sizes[i]
            let candidateX = (curX == 0) ? size.width : curX + spacing + size.width

            if candidateX <= maxWidth {
                let placeX = (curX == 0) ? 0 : curX + spacing
                placements.append((i, CGPoint(x: placeX, y: curY)))
                curX = placeX + size.width
                curRowH = max(curRowH, size.height)
            } else {
                // 换行
                rowHeights.append(curRowH)
                if rowIdx + 1 >= maxRows {
                    // 用尽 row budget — 后面所有主 pill 算被截
                    truncatedCount = mainCount - i
                    break
                }
                rowIdx += 1
                curY += curRowH + spacing
                curRowH = size.height
                curX = size.width
                placements.append((i, CGPoint(x: 0, y: curY)))
            }
        }

        // 如果有截断, 把 overflow 塞到最后一行末尾.
        // 当前行装不下 overflow → 砍最后几个主 pill 让位.
        if truncatedCount > 0 {
            // 重新计算 curX (current 行的占用宽)
            var lastRowMaxY = curY
            // 找当前 lastRowMaxY 行上所有 pill, 算它们的右端
            var lastRowEnd: CGFloat = 0
            for (idx, pos) in placements where abs(pos.y - lastRowMaxY) < 0.5 {
                let w = sizes[idx].width
                lastRowEnd = max(lastRowEnd, pos.x + w)
            }
            curX = lastRowEnd

            // 尝试把 overflow 加到当前行末尾
            var overflowCandidate = curX + spacing + overflowSize.width
            // 如果 curX == 0 (空行), 不加 spacing
            if curX == 0 { overflowCandidate = overflowSize.width }

            while overflowCandidate > maxWidth && !placements.isEmpty {
                // 砍最后一个 placement (它应该跟 curY 同行)
                let last = placements.removeLast()
                if abs(last.1.y - lastRowMaxY) > 0.5 {
                    // 跨行了 — 直接放弃 truncation, 不画 overflow (异常路径)
                    placements.append(last)
                    break
                }
                truncatedCount += 1
                // 重算 lastRowEnd
                lastRowEnd = 0
                for (idx, pos) in placements where abs(pos.y - lastRowMaxY) < 0.5 {
                    let w = sizes[idx].width
                    lastRowEnd = max(lastRowEnd, pos.x + w)
                }
                curX = lastRowEnd
                overflowCandidate = (curX == 0) ? overflowSize.width : curX + spacing + overflowSize.width
            }

            // 放 overflow
            let placeX = (curX == 0) ? 0 : curX + spacing
            placements.append((overflowIdx, CGPoint(x: placeX, y: lastRowMaxY)))
            curRowH = max(curRowH, overflowSize.height)
        }

        rowHeights.append(curRowH)
        let totalH = curY + curRowH
        return Plan(
            placements: placements,
            totalSize: CGSize(width: maxWidth, height: totalH),
            truncatedCount: truncatedCount
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // 宽度有值且有限 → 正常按可用宽度排 (撑满).
        if let w = proposal.width, w.isFinite {
            return makePlan(subviews: subviews, maxWidth: w).totalSize
        }
        // 宽度未指定 (nil) 或无限 —— List 的 sizing pass 会给 nil. 绝不能回报 .infinity 宽度,
        // 否则整个 list row 连同它后面的所有 row 都不渲染. 回报"自然单行宽度" (所有 subview 宽度之和).
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let natural = sizes.reduce(0) { $0 + $1.width } + spacing * CGFloat(max(0, sizes.count - 1))
        let h = sizes.map(\.height).max() ?? 0
        return CGSize(width: natural, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let plan = makePlan(subviews: subviews, maxWidth: bounds.width)
        let placedIndices = Set(plan.placements.map { $0.0 })

        // 把要画的 subviews 放到位
        for (i, pos) in plan.placements {
            subviews[i].place(
                at: CGPoint(x: bounds.minX + pos.x, y: bounds.minY + pos.y),
                proposal: .unspecified
            )
        }

        // 不画的 subviews → place 到屏外 (避免占空间)
        for idx in 0..<subviews.count where !placedIndices.contains(idx) {
            subviews[idx].place(
                at: CGPoint(x: -10_000, y: -10_000),
                proposal: ProposedViewSize(width: 0, height: 0)
            )
        }

        // 把截断 count 异步告诉 caller (避免 "modifying state during view update")
        if let cb = onTruncate {
            let count = plan.truncatedCount
            DispatchQueue.main.async { cb(count) }
        }
    }
}
