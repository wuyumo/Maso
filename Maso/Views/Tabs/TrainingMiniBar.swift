import SwiftUI

// "训练中" 横向迷你播放条 — iOS 默认 Now-Playing 风格 (Apple Music mini player).
//
// 位置: 通过 RootView 的 `.safeAreaInset(edge: .bottom)` 浮在系统 TabBar 之上
//   - bar 跟 TabBar 同时可见, 不互相遮挡
//   - 整 bar 用 .ultraThinMaterial 半透明背景, 跟 TabBar 视觉风格一致
//   - 顶部一条 hairline 分隔; 底部 0 边距, 紧贴 TabBar
//
// 内容布局 (Apple Music mini player 1:1):
//   [缩略图 44pt] [动作名 (粗) / 1/3 × 8 reps (淡)] ─────── [主控按钮 ✓ / 跳过 / 暂停 32pt]
//
// 交互:
//   - 点 bar 主体 → 拉起 PlanPlayer
//   - 点主控按钮 → advance / togglePlay (Button 自己 hitTest, 不被外层 onTapGesture 吃)
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
        HStack(spacing: 10) {
            // 缩略图 — 小一点, 跟 Apple Music 的 album art 同款 36pt
            ExerciseImage(
                category: thumbCategory,
                imageFolder: thumbFolder,
                cornerRadius: 6,
                size: 36,
                animated: false
            )

            // 信息块 — title (粗) / subtitle (淡)
            VStack(alignment: .leading, spacing: 1) {
                switch segment.kind {
                case .rest:
                    Text(isCrossExercise ? NSLocalizedString("Switching", comment: "") : NSLocalizedString("Rest", comment: ""))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                        .lineLimit(1)
                    HStack(spacing: 4) {
                        if let remaining {
                            Text(formatRemaining(remaining))
                                .font(.system(size: 11, weight: .medium).monospacedDigit())
                                .foregroundStyle(MasoColor.accent)
                        }
                        if let next = nextExercise {
                            Text("· \(next.displayName)")
                                .font(.system(size: 11))
                                .foregroundStyle(MasoColor.textDim)
                                .lineLimit(1)
                        }
                    }
                case .exercise(let ex, let setN, let total, let reps, _, _, let countdown):
                    Text(ex.displayName)
                        .font(.system(size: 13, weight: .semibold))
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
            .contentShape(Rectangle())
            .onTapGesture { onTap() }

            // 主控按钮 — Button 自己 hitTest, 不被外层 onTapGesture 抢走.
            // 尺寸跟 Apple Music mini player 一致 (32pt), 比之前的 40pt 紧凑.
            Button(action: handlePrimary) {
                ZStack {
                    Circle().fill(actionBg).frame(width: 32, height: 32)
                    actionIcon
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(actionFg)
                }
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        // 整 bar onTapGesture — 缩略图 / spacing 区域也能拉起 player
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        // iOS 默认 Now-Playing 样式 — 半透明 material 背景 + 顶边 hairline.
        // 跟系统 TabBar (也用 material) 视觉对齐, 两者并排时层次清晰.
        .background(
            ZStack(alignment: .top) {
                Rectangle().fill(.ultraThinMaterial)
                // 顶部 hairline — 跟 TabBar 顶边 separator 一致, 标识 bar 的上边界
                Rectangle()
                    .fill(Color.white.opacity(0.08))
                    .frame(height: 0.33)
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
