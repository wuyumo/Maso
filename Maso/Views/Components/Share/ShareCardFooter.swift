import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

// App 全局链接常量.
enum MasoLinks {
    /// App Store 产品页 — routine 分享卡的 QR (引导没装 app 的人扫码下载).
    /// app id 来自 App Store Connect (6776689750). ⚠️ 上线前扫会 404, App 审核通过上线后即生效.
    static let appStore = "https://apps.apple.com/app/id6776689750"
}

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
//   - 左 App icon 32×32 accent + "MASSO" wordmark + tagline
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
                // 只在有真实 payload 时画二维码 (RoutineShareCard 传 maso:// 深链).
                // 其余卡片没 payload → 不画 — 假占位二维码"扫了能下载"是误导, 扫出来是空的.
                // App Store 链接出来后给这些卡传固定 https://apps.apple.com/app/id... 即可恢复.
                if let payload = qrPayload, let qr = ShareQR.image(for: payload) {
                    Image(uiImage: qr)
                        .interpolation(.none)
                        .resizable()
                        .frame(width: qrSize, height: qrSize)
                        .padding(3)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
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

// MARK: - RoutineShareCard — Routine 分享图 (仿训练完成卡的逐组完整版 + 品牌 footer + 真 QR)
//
// 对照 WorkoutDetailShareCard (完成分享卡): 同一视觉骨架 —— ROUTINE kicker + 计划名 +
// 肌肉图 + 三项汇总 + 逐组实测网格 + ShareCardFooter(带 maso:// 深链 QR). 区别只在数据源:
// 完成卡读"本次实际练的 SetRecord", routine 卡读"计划的逐组目标" (step.repsForSet/weightForSet/durationForSet).
//
// 关键: 卡上所见 == 导入所得. QR 里编的是整张 Plan (PlanShareCodec, 含逐组 setReps/setWeights/setDurations),
// 收图的人"从照片导入"扫 QR → 无损还原同一份 routine.
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

    private var totalSets: Int { plan.steps.reduce(0) { $0 + $1.sets } }

    /// 计划目标总容量 (kg) = Σ 逐组 (weight × reps). 自重/计时类不计入 → 0 时不显示这项.
    private var totalVolumeKg: Double {
        var v = 0.0
        for s in plan.steps {
            for n in 1...max(s.sets, 1) {
                if let w = s.weightForSet(n), w > 0, let r = s.repsForSet(n), r > 0 {
                    v += w * Double(r)
                }
            }
        }
        return v
    }

    private var volumeLabel: String {
        // 跟随全局单位换算 (P1#21) — lb 用户分享出去的 Volume 数值/标签跟 app 内一致, 不再恒 kg.
        let v = WeightUnitProvider.current.fromKg(totalVolumeKg)
        return v.truncatingRemainder(dividingBy: 1) == 0 ? String(format: "%.0f", v) : String(format: "%.1f", v)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                // 头部 — ROUTINE kicker + 计划名
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.accent)
                        Text(verbatim: "ROUTINE")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                    }
                    Text(plan.name.isEmpty ? NSLocalizedString("Shared workout", comment: "") : plan.name)
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(MasoColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)

                // 肌肉图居中
                if !muscles.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        MuscleVisualBlock(muscles: muscles, sideLength: 150)
                            .frame(width: 150, height: 150)
                        Spacer(minLength: 0)
                    }
                }

                // 汇总数据 — Exercises / Sets (/ Volume 只在有配重时显示)
                HStack(spacing: 24) {
                    ShareStat(value: "\(plan.steps.count)", label: NSLocalizedString("Exercises count", comment: "exercise count stat label"))
                    ShareStat(value: "\(totalSets)", label: NSLocalizedString("Sets", comment: ""))
                    if totalVolumeKg > 0 {
                        ShareStat(value: volumeLabel, label: String(format: NSLocalizedString("Volume %@", comment: "total target volume — %@ = kg/lb"), WeightUnitProvider.current.label))
                    }
                    Spacer(minLength: 0)
                }

                Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)

                // 动作清单 — 每个动作一行: 全名 (不截断) + "组数 × 次数 (· 配重)".
                // 故意用 "N × M" 这种 OCR 友好格式且把所有动作完整列出: 收图的人 "从照片导入" 时,
                // OCR 能逐行读出动作名 + 组数/次数, 把这份 routine 识别还原 (QR 现在是 App Store 下载链,
                // 不再承担导入). 名字不设 lineLimit — 长名 ("Row (Cable · Seated)") 也完整显示.
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(plan.steps) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(exById[step.exerciseId]?.displayName ?? step.exerciseId)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(MasoColor.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 12)
                            Text(stepSummary(step))
                                .font(.system(size: 14).monospacedDigit())
                                .foregroundStyle(MasoColor.textDim)
                                .layoutPriority(1)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            ShareCardFooter(qrPayload: qrPayload, qrSize: 104)
        }
        .background(MasoColor.background)
    }

    /// 动作的组数概要 — OCR 友好: "N × M" (组 × 次), 配重加 "· W kg/lb", 计时类 "N × 30s".
    /// 用 base sets/reps/weight (逐组覆盖在分享/OCR 场景读不出, base 最具代表性).
    /// 配重走 weightLabel (kg → 用户单位) — 跟上方 Volume 同一单位, 不再同卡双单位;
    /// OCR 导入侧 (PlanShareCodec) 认得 kg/lb 且会把 lb 换算回 kg, 单位互通.
    private func stepSummary(_ s: PlanStep) -> String {
        if s.reps == nil, let d = s.duration, d > 0 {
            let dur = d >= 60 ? "\(d / 60)m\(d % 60 == 0 ? "" : " \(d % 60)s")" : "\(d)s"
            return "\(s.sets) × \(dur)"
        }
        var out = "\(s.sets) × \(s.reps ?? 0)"
        if let w = s.weight, w > 0 {
            out += " · \(weightLabel(w))"
        }
        return out
    }
}
