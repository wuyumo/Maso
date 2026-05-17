import SwiftUI

// "训练中" 横向迷你播放条 — Apple Music Now-Playing 风格
// 位置: 浮在 TabBar 上方 (作为一个独立的 bar, 不再占据 TabBar 的中间 cell)
//
// 内容: 缩略图 · 动作名 / 1/3 × 8 (或 休息中 · 倒计时) · 主控按钮 (✓ / 跳过 / 暂停)
// 点 body → 打开 PlanPlayer; 点主控 → advance / togglePlay
struct TrainingMiniBar: View {
    let segment: Segment
    let playing: Bool
    let remaining: Int?
    let nextExercise: Exercise?
    /// true = 当前 rest 是 "切换到下一个动作" 的过渡 rest, MiniBar 上 kicker 用 "切换动作"
    let isCrossExercise: Bool
    let onTap: () -> Void
    let onAdvance: () -> Void
    let onTogglePlay: () -> Void

    var body: some View {
        // 改用 onTapGesture 而非外层 Button — 嵌套 Button (外层 + 内层主控) 在 SwiftUI 里
        // 整个 hit zone 会被 button-style sibling 吃掉, 外层 onTap 不触发. onTapGesture +
        // .contentShape(Rectangle()) 让 HStack 整个区域都可点 (除了内层 Button 优先 hitTest).
        HStack(spacing: 12) {
            // 缩略图
            ExerciseImage(
                category: thumbCategory,
                imageFolder: thumbFolder,
                cornerRadius: MasoMetrics.cornerRadiusSmall,
                size: 44,
                animated: false
            )

            // 信息块
            VStack(alignment: .leading, spacing: 2) {
                switch segment.kind {
                case .rest:
                    HStack(spacing: 5) {
                        Circle().fill(MasoColor.accent).frame(width: 5, height: 5)
                        Text(isCrossExercise ? "Switching" : "Rest")
                            .font(.system(size: 11, weight: .bold))
                            .tracking(1)
                            .textCase(.uppercase)
                            .foregroundStyle(MasoColor.accent)
                    }
                    HStack(spacing: 4) {
                        if let remaining {
                            Text(formatRemaining(remaining))
                                .font(.system(size: 13, weight: .bold).monospacedDigit())
                                .foregroundStyle(MasoColor.text)
                        }
                        if let next = nextExercise {
                            Text("→ \(next.displayName)")
                                .font(.system(size: 11))
                                .foregroundStyle(MasoColor.textDim)
                                .lineLimit(1)
                        }
                    }
                case .exercise(let ex, let setN, let total, let reps, _, _, let countdown):
                    Text(ex.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        Text("\(setN)/\(total)")
                            .font(.system(size: 11).monospacedDigit())
                        if let reps {
                            Text("× \(reps)").font(.system(size: 11).monospacedDigit())
                        }
                        if countdown, let remaining {
                            Text("· \(formatRemaining(remaining))").font(.system(size: 11).monospacedDigit())
                        }
                    }
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            // 缩略图 + 信息块都加 onTapGesture, 让"非按钮区域"明确接 onTap 不被外层吃
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            // 主控按钮 — Button 自己 hitTest, 不被外层 onTapGesture 抢走
            Button(action: handlePrimary) {
                ZStack {
                    Circle().fill(actionBg).frame(width: 40, height: 40)
                    actionIcon
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(actionFg)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // 整 bar 加 onTapGesture — 缩略图 / spacing 区域也能拉起 player
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .background(
            // 纯黑, 跟 TabBar 一致. 不再加 material 以免颜色稍浅.
            Rectangle()
                .fill(Color.black)
                .overlay(alignment: .top) {
                    Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)
                }
        )
    }

    private var thumbCategory: ExerciseCategory {
        switch segment.kind {
        case .exercise(let ex, _, _, _, _, _, _): return ex.category
        case .rest: return nextExercise?.category ?? .strength
        }
    }
    private var thumbFolder: String? {
        switch segment.kind {
        case .exercise(let ex, _, _, _, _, _, _): return ex.imageFolder
        case .rest: return nextExercise?.imageFolder
        }
    }

    private func handlePrimary() {
        if case .exercise(_, _, _, _, _, _, true) = segment.kind {
            onTogglePlay()
        } else {
            onAdvance()
        }
    }

    private var actionBg: Color {
        switch segment.kind {
        case .rest, .exercise(_, _, _, _, _, _, true):
            return MasoColor.text
        case .exercise:
            return MasoColor.accent
        }
    }
    private var actionFg: Color {
        actionBg == MasoColor.accent ? .black : MasoColor.background
    }
    @ViewBuilder private var actionIcon: some View {
        switch segment.kind {
        case .exercise(_, _, _, _, _, _, true):
            Image(systemName: playing ? "pause.fill" : "play.fill")
        case .rest:
            // "一个三角形加一个杠" — App 内统一的跳过图标
            Image(systemName: "forward.end.fill")
        case .exercise:
            Image(systemName: "checkmark")
        }
    }
}
