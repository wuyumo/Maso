import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

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
    /// 真 QR 内容 (e.g. maso:// routine 深链). nil → 占位 qrcode 图标 (后期接 App Store 链接).
    var qrPayload: String? = nil
    /// 真 QR 边长 — routine 深链 payload 压缩后仍 ~300 字符 (QR v13), 38pt 太密难扫,
    /// routine 卡传 64. 占位图标始终 38.
    var qrSize: CGFloat = 38

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
                        Text(verbatim: "MASSO")
                            .font(.system(size: 13, weight: .heavy))
                            .tracking(2)
                            .foregroundStyle(MasoColor.text)
                        Text("My Personal AI Trainer")
                            .font(.system(size: 10))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                Spacer()
                if let payload = qrPayload, let qr = ShareQR.image(for: payload) {
                    // 真二维码 — 白底黑码 (扫描兼容性), 38pt 跟占位同尺寸.
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: qrSize, height: qrSize)
                        .padding(3)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                } else {
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
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }
}

// MARK: - ShareQR — 真二维码生成 (CoreImage)

enum ShareQR {
    /// payload → 黑白二维码 UIImage (最近邻放大, 不糊). 失败返回 nil (caller 回退占位).
    static func image(for payload: String, side: CGFloat = 200) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(payload.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        let scale = side / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - RoutineShareCard — My Routines 分享图 (计划内容 + 品牌 footer + 真 QR)

/// Routine 分享卡: kicker + 计划名 + 肌肉图 + 动作列表 (最多 8 行) + ShareCardFooter(带 maso:// 深链 QR).
/// 收到图的人扫 QR → 打开 app 直接导入这张计划 (PlanShareCodec 深链).
struct RoutineShareCard: View {
    let plan: Plan
    let exById: [String: Exercise]
    /// maso:// 深链 — 进 footer 的 QR.
    let qrPayload: String?

    private var muscles: [MuscleGroup] {
        var seen = Set<MuscleGroup>(); var out: [MuscleGroup] = []
        for s in plan.steps {
            for m in exById[s.exerciseId]?.muscleGroups ?? [] where seen.insert(m).inserted { out.append(m) }
        }
        return out
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                    Text(verbatim: "ROUTINE")
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .foregroundStyle(MasoColor.accent)
                }
                Text(plan.name)
                    .font(.system(size: 22, weight: .heavy))
                    .foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(pluralizedExercises(plan.steps.count)) · \(pluralizedSets(plan.steps.reduce(0) { $0 + $1.sets }))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(MasoColor.textDim)
                HStack {
                    Spacer(minLength: 0)
                    MuscleVisualBlock(muscles: muscles, sideLength: 120)
                        .frame(width: 120, height: 120)
                    Spacer(minLength: 0)
                }
                VStack(spacing: 8) {
                    ForEach(Array(plan.steps.prefix(8).enumerated()), id: \.offset) { _, step in
                        HStack {
                            Text(exById[step.exerciseId]?.displayName ?? step.exerciseId)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.text)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(stepSummary(step))
                                .font(.system(size: 12).monospacedDigit())
                                .foregroundStyle(MasoColor.textDim)
                        }
                    }
                    if plan.steps.count > 8 {
                        Text(String(format: NSLocalizedString("+%d more", comment: "truncated exercises"), plan.steps.count - 8))
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textFaint)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .padding(20)
            ShareCardFooter(qrPayload: qrPayload, qrSize: 64)
        }
        .background(MasoColor.background)
    }

    private func stepSummary(_ s: PlanStep) -> String {
        var parts = ["\(s.sets)×\(s.reps.map(String.init) ?? "–")"]
        if let w = s.weight, w > 0 {
            let num = w.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", w) : String(format: "%.1f", w)
            parts.append("\(num) kg")
        }
        return parts.joined(separator: " · ")
    }
}

// MARK: - PeriodSummaryShareCard — History 周/月训练汇总分享图

struct PeriodSummaryShareCard: View {
    let title: LocalizedStringKey      // "This Week" / "This Month"
    let rangeText: String              // "Jun 8 – Jun 14"
    let workouts: Int
    let totalSets: Int
    let volumeKg: Double
    let muscles: [MuscleGroup]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(MasoColor.accent)
                    Text(title)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.5)
                        .textCase(.uppercase)
                        .foregroundStyle(MasoColor.accent)
                    Spacer()
                    Text(rangeText)
                        .font(.system(size: 10))
                        .foregroundStyle(MasoColor.textFaint)
                }
                HStack(spacing: 0) {
                    stat(String(workouts), NSLocalizedString("Workouts", comment: ""))
                    stat(String(totalSets), NSLocalizedString("Sets", comment: ""))
                    stat(volumeText, NSLocalizedString("Volume", comment: ""))
                }
                HStack {
                    Spacer(minLength: 0)
                    MuscleVisualBlock(muscles: muscles, sideLength: 140)
                        .frame(width: 140, height: 140)
                    Spacer(minLength: 0)
                }
            }
            .padding(20)
            ShareCardFooter()
        }
        .background(MasoColor.background)
    }

    private var volumeText: String {
        volumeKg >= 1000 ? String(format: "%.1ft", volumeKg / 1000) : String(format: "%.0fkg", volumeKg)
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .font(.system(size: 26, weight: .heavy).monospacedDigit())
                .foregroundStyle(MasoColor.text)
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.8)
                .foregroundStyle(MasoColor.textDim)
        }
        .frame(maxWidth: .infinity)
    }
}
