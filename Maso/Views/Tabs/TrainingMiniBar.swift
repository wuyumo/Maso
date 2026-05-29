import SwiftUI

// "训练中" 横向迷你播放条 — Apple Music Now-Playing 风格的浮动胶囊.
//
// 视觉:
//   - 胶囊 (Capsule) 形, 不再是满宽矩形 — 跟系统 TabBar 胶囊视觉一致
//   - .ultraThinMaterial 半透明背景 (跟 TabBar 同材质)
//   - 水平两侧留 ~12pt 边距, 不顶到屏边
//   - 底部跟 TabBar 之间留 6pt gap, 两个胶囊明显分开
//   - 极淡描边 (white@10% × 0.5pt) — 暗色背景下勾出胶囊轮廓
//
// 交互 (跟 Apple Music mini player 对齐):
//   - 整 bar tap → 拉起 PlanPlayer (现有逻辑)
//   - 按下时 scale 0.97 + spring 反弹, 给"可点"的物理反馈
//   - 主控按钮 (✓ / pause / skip) 独立 Button — hitTest 优先于外层 tap, 不被吃
//
// 内容布局 (Apple Music mini player 1:1):
//   [缩略图 36pt] [动作名 (粗) / 1/3 × 8 reps (淡)] ─── [主控按钮 ✓ / 跳过 / 暂停 32pt]
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

    /// 按下态 — 整 bar scale 反馈, 跟 Apple Music mini player 的"按一下凹一下"一致
    @State private var pressed = false

    var body: some View {
        HStack(spacing: 10) {
            // 缩略图 36pt — Apple Music album art 同款大小
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
            // P3: 去掉这里的 onTapGesture — 外层胶囊整体已有 onTap, 信息区落在它范围内,
            // 双份 tap 手势冗余且偶尔在标题附近抢手势.

            // 主控按钮 — Button 自己 hitTest, 不被外层 onTapGesture 抢走.
            // 32pt 跟 Apple Music mini player 一致.
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
        // 跟系统 TabBar 同款液态玻璃材质 (`.bar` material): iOS 18+ 在 TabView 底栏自动用,
        // iOS 26+ 就是 Liquid Glass. 我们手动取这个 material, 让 MiniBar 和 TabBar 视觉融为一体.
        .background(.bar, in: Capsule(style: .continuous))
        // 极淡描边勾边界 — 跟 TabBar 同款 0.5pt × 8% 白
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 0.5)
        )
        // 按下态 scale + spring — Apple Music mini player 同款"按一下凹一下"
        .scaleEffect(pressed ? 0.97 : 1.0)
        .animation(.spring(response: 0.28, dampingFraction: 0.65), value: pressed)
        .contentShape(Capsule(style: .continuous))
        .onTapGesture { onTap() }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !pressed { pressed = true } }
                .onEnded { _ in pressed = false }
        )
        // 跟系统 home bar / TabBar 视觉宽度一致 — 不顶到屏边, 浮在中间. 跟 TabBar 是 centered
        // floating capsule 的感觉对齐. 40pt 让 iPhone 主流尺寸下 MiniBar 跟 TabBar 看上去同款宽.
        .padding(.horizontal, 40)
        // 跟下方 TabBar 留 6pt gap — 两个 bar 明显分开, 不糊成一团
        .padding(.bottom, 6)
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
