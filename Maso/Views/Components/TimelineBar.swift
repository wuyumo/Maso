import SwiftUI

// 训练播放器顶部进度条 — DESIGN §3.2 (修订 v3)
//
// 设计:
//   - 只显示 exercise 段, rest 段从视觉上隐藏
//   - **同一动作的多个组之间** 连成一根连续 bar (无 gap)
//   - **不同动作之间** 留 gap (视觉上明显的分隔)
//   - 同组内每个 set 单独着色 (过去=绿 / 当前=白 / 未来=灰)
//   - 用户在 rest 时, 白色 "当前指针" 跳到下一个 exercise
struct TimelineBar: View {
    let segments: [Segment]
    let currentIndex: Int
    /// 用户点了"打勾"真正做完的 (stepId, setN) 集合 — 跳过 setIndex 的不算.
    /// 只有这个集合里的 exercise segment 才标绿. 跳过的段保持灰.
    let completedSets: Set<TrainingSessionStore.CompletedSet>
    let onJump: (Int) -> Void

    private static let setGap: CGFloat = 0          // 同动作组内 0 gap (连体)
    private static let exerciseGap: CGFloat = 8     // 不同动作之间 8pt gap
    private static let hPad: CGFloat = 16
    private static let vPad: CGFloat = 8
    private static let barHeight: CGFloat = 5

    /// 只 keep exercise 段, 并按 stepId 分组 (相同 stepId = 同一动作的多个组)
    /// 返回: [[(originalIdx, segment)]] — 外层是动作组列表, 内层是该动作的所有 set
    private var exerciseGroups: [[(idx: Int, seg: Segment)]] {
        let exercises: [(idx: Int, seg: Segment)] = segments.enumerated().compactMap { (i, s) in
            s.isExercise ? (i, s) : nil
        }
        var groups: [[(idx: Int, seg: Segment)]] = []
        var currentGroup: [(idx: Int, seg: Segment)] = []
        var currentStepId: String? = nil
        for item in exercises {
            if item.seg.stepId == currentStepId {
                currentGroup.append(item)
            } else {
                if !currentGroup.isEmpty { groups.append(currentGroup) }
                currentGroup = [item]
                currentStepId = item.seg.stepId
            }
        }
        if !currentGroup.isEmpty { groups.append(currentGroup) }
        return groups
    }

    var body: some View {
        GeometryReader { geo in
            let groups = exerciseGroups
            let totalSets = groups.reduce(0) { $0 + $1.count }
            let availableWidth = geo.size.width - Self.hPad * 2
            // 总 gap = 不同动作之间 (groups.count - 1) 个 exerciseGap
            let totalGap = Self.exerciseGap * CGFloat(max(0, groups.count - 1))
            let unitWidth: CGFloat = totalSets > 0
                ? max(2, (availableWidth - totalGap) / CGFloat(totalSets))
                : 0

            HStack(spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { (groupIdx, group) in
                    // 一个动作组: N 个 Rectangle 连体, 外层 clipShape Capsule 只圆外两端
                    HStack(spacing: 0) {
                        ForEach(Array(group.enumerated()), id: \.element.idx) { (_, item) in
                            Button(action: { onJump(item.idx) }) {
                                Rectangle()
                                    .fill(color(forExerciseSeg: item.seg, originalIdx: item.idx))
                                    .frame(width: unitWidth, height: Self.barHeight)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("exercise-set")
                        }
                    }
                    .clipShape(Capsule())  // 只让组的"外两端"变圆, 中间 set 与 set 直接拼接

                    if groupIdx < groups.count - 1 {
                        Spacer().frame(width: Self.exerciseGap)
                    }
                }
            }
            .padding(.horizontal, Self.hPad)
            .padding(.vertical, Self.vPad)
        }
        .frame(height: Self.barHeight + Self.vPad * 2)
    }

    /// 配色规则:
    ///   - 当前 segment = 白 (正在做)
    ///   - 在 completedSets 里 (用户点过打勾) = 绿
    ///   - 其它 = 灰 (包括"位置上在 current 之前但用户跳过没做"的)
    /// 跟"位置式着色"的区别: 用户用 playlist 跳到后面再跳回来, 中间没打勾的段不会假装"已完成".
    private func color(forExerciseSeg seg: Segment, originalIdx: Int) -> Color {
        let cur = min(max(0, currentIndex), segments.count - 1)
        if originalIdx == cur { return MasoColor.text }      // 当前 = 白 (优先级最高)
        if case .exercise(_, let setN, _, _, _, _, _) = seg.kind {
            let key = TrainingSessionStore.CompletedSet(stepId: seg.stepId, setN: setN)
            if completedSets.contains(key) { return MasoColor.accent }  // 真做完了 = 绿
        }
        return MasoColor.textFaint.opacity(0.4)              // 未做 / 跳过 = 灰
    }
}
