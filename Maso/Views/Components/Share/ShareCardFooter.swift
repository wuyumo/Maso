import SwiftUI
import UIKit

/// Share card 顶部可选 photo banner — 用户在 customize sheet 加了自己照片就显示.
/// 4 个 share card 都用这个 (放在内容区最顶, footer 不动).
///
/// 三种状态:
///   1. 有 photo → 显示正方形照片 (中心裁切)
///   2. 没 photo + onTapToAdd 非 nil (preview 模式) → 显示"Add photo" 虚线占位, tap 触发 add
///   3. 没 photo + onTapToAdd nil (渲染最终图模式) → 不渲染 (EmptyView)
///
/// 视觉: 正方形 1:1, 用 .fill + .clipped() 中心裁切 — 不管用户照片是横/竖, 都裁成正方形.
struct SharePhotoBanner: View {
    let photo: UIImage?
    /// preview 模式: 传 callback → 没 photo 时显示"添加照片"占位, tap 触发 caller 弹选择器.
    /// 渲染模式: 传 nil → 没 photo 时不渲染, 让最终输出图干净不带 UI.
    var onTapToAdd: (() -> Void)? = nil

    var body: some View {
        if let img = photo {
            // 有照片 — 显示, tap 仍可触发 onTapToAdd (用户改照片). 渲染模式 (onTapToAdd nil)
            // tap gesture 不挂, 渲染图无副作用.
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay(
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                )
                .clipped()
                .contentShape(Rectangle())
                .onTapGesture { onTapToAdd?() }
        } else if let onTap = onTapToAdd {
            // 没照片 + preview 模式 — 显示"添加照片" 占位 (1:1 dashed border)
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .overlay {
                    ZStack {
                        // 虚线 border 提示"可点击区域"
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(
                                MasoColor.borderSoft,
                                style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                            )
                            .padding(12)
                        VStack(spacing: 10) {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 38, weight: .light))
                                .foregroundStyle(MasoColor.textDim)
                            Text("Add a photo")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(MasoColor.textDim)
                        }
                    }
                    .background(MasoColor.surface.opacity(0.4))
                }
                .clipShape(RoundedRectangle(cornerRadius: 0))
                .contentShape(Rectangle())
                .onTapGesture { onTap() }
        }
        // 渲染模式: photo nil + onTapToAdd nil → EmptyView
    }
}

// 分享图底部 footer — 所有 4 个 share card 共用.
// 内容: 左侧 App icon + 名称, 右侧 QR placeholder (后期换真 App Store 二维码).
//
// 视觉规则:
//   - 左 App icon 32×32 accent + "MASO" wordmark + tagline
//   - 右 QR placeholder (36×36 灰底 + qrcode SF symbol)
//   - 整条 footer 上方有 0.5pt 细分割线, 跟主内容区视觉分割
struct ShareCardFooter: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(MasoColor.borderSoft)
                .frame(height: 0.5)
            HStack(spacing: 12) {
                HStack(spacing: 10) {
                    MasoMarkIcon(color: MasoColor.accent)
                        .frame(width: 32, height: 32)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "MASO")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(MasoColor.text)
                        Text("My Personal AI Trainer")
                            .font(.system(size: 10))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                Spacer()
                // QR placeholder — 后期接真 App Store 二维码.
                // 视觉给用户"扫了能下载"的暗示, 即使现在 placeholder 也保留位置稳定.
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(MasoColor.surfaceHi)
                        .frame(width: 38, height: 38)
                    Image(systemName: "qrcode")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(MasoColor.textDim.opacity(0.55))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}
