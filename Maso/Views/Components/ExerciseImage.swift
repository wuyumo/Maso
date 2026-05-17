import SwiftUI

// Spotify "album cover" 风格的动作缩略图 — DESIGN §3.3
//   - 两帧 cross-fade (yuhonas/free-exercise-db 的 0.jpg + 1.jpg)
//   - 加载中 / 失败时回退到 category 渐变
//   - 用 jsdelivr CDN URL (比 GitHub raw 稳)
//   - animated=true (默认): TimelineView 驱动 2s 周期切换两帧
//   - animated=false: 只显示 0.jpg (列表 / 缩略图用)
struct ExerciseImage: View {
    let category: ExerciseCategory
    /// 来自 Exercise.imageFolder; 为 nil 时直接用渐变占位
    var imageFolder: String? = nil
    var cornerRadius: CGFloat = 4
    var size: CGFloat = 48
    /// 是否做两帧 cross-fade 动画
    var animated: Bool = true

    var body: some View {
        ZStack {
            // 底层 — category 渐变 (作为加载中 / 失败的兜底)
            gradient
                .overlay(
                    Image(systemName: iconName)
                        .foregroundStyle(.white.opacity(0.35))
                        .font(.system(size: size * 0.4, weight: .semibold))
                )

            // 上层 — 实际图片 (有 imageFolder 时才尝试加载)
            // CrossFadeFrames: 共享 UIImage cache + 严格 frame 锚定, 解决两帧
            // intrinsic size 略不同时 scaledToFill 算出不同 scale → 像素抖动的问题.
            if let folder = imageFolder {
                CrossFadeFrames(folder: folder, animated: animated)
                    .overlay(
                        // 强调色调染 — 类似 Spotify album cover 的多色叠加
                        gradient.opacity(0.35).blendMode(.multiply)
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var gradient: LinearGradient {
        let colors: [Color] = {
            switch category {
            case .strength:    return [Color.green.opacity(0.6), Color.green.opacity(0.95)]
            case .cardio:      return [Color.pink.opacity(0.6), Color.pink.opacity(0.95)]
            case .flexibility: return [Color.orange.opacity(0.6), Color.orange.opacity(0.95)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var iconName: String {
        switch category {
        case .strength:    return "dumbbell.fill"
        case .cardio:      return "figure.run"
        case .flexibility: return "figure.flexibility"
        }
    }
}

// AnimatedFrameImage 已废弃 — 改用共享的 CrossFadeFrames (见 Views/Components/CrossFadeFrames.swift).
// 旧实现的问题: AsyncImage 两帧独立加载, 加载完成时机不同步, 切换那一刻闪烁;
//             scaledToFill 在两张 intrinsic size 不同时算出不同 scale, 像素位置抖动.
// 新实现: 共享 ExerciseImageCache 预加载 UIImage, 严格 GeometryReader + .frame 锚定 size.
