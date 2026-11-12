import SwiftUI
import UIKit
import CoreImage.CIFilterBuiltins

/// Shared share-page spacing; dense routine QR codes retain their larger scan size.
enum ShareLayout {
    static let contentInset: CGFloat = 24
    static let topInset: CGFloat = 16
    static let footerQRSize: CGFloat = 64
}

// App 全局链接常量.
enum MasoLinks {
    /// App Store 产品页 — routine 分享卡的 QR (引导没装 app 的人扫码下载).
    /// app id 来自 App Store Connect (6776689750). ⚠️ 上线前扫会 404, App 审核通过上线后即生效.
    static let appStore = "https://apps.apple.com/app/id6776689750"
}

/// Photo editing affordance only; the actual share photo is rendered once in the footer.
struct SharePhotoBanner: View {
    let photo: UIImage?
    var onTapToAdd: (() -> Void)? = nil
    var body: some View {
        if let onTapToAdd {
            Button(action: onTapToAdd) {
                if let photo {
                    HStack(spacing: 12) {
                        Color.clear.frame(width: 48, height: 48)
                            .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                            .clipped().clipShape(RoundedRectangle(cornerRadius: 8))
                            .accessibilityHidden(true)
                        Text("Replace photo").font(.body).foregroundStyle(MasoColor.text)
                        Spacer(minLength: 0)
                    }
                    .padding(MasoMetrics.cardPadding)
                    .contentCardChrome(padding: 0)
                } else {
                    AddPhotoPlaceholder().frame(height: 160)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .accessibilityLabel(photo == nil ? Text("Add photo") : Text("Replace photo"))
            .accessibilityIdentifier("share.photo.upload")
        }
    }
}

/// Kept as a shared workout scene adapter, without adding a second inset.
struct WorkoutSharePhotoBanner: View {
    let photo: UIImage?
    let muscles: [MuscleGroup]
    var onTapToAdd: (() -> Void)? = nil
    var body: some View { SharePhotoBanner(photo: photo, onTapToAdd: onTapToAdd) }
}

/// Shared export footer: physical left QR above brand, physical right square photo.
struct ShareCardFooter: View {
    @Environment(\.shareCardSelection) private var selection
    @Environment(\.layoutDirection) private var contentDirection
    private var visibleQRPayload: String? {
        selection?.excluded.isEmpty == false ? MasoLinks.appStore : qrPayload
    }
    var qrPayload: String? = nil
    /// Inner QR edge; the existing 3pt quiet-zone padding remains part of its visible size.
    var qrSize: CGFloat = ShareLayout.footerQRSize
    var photo: UIImage? = nil
    var photoSelectionID: String? = nil
    private var visiblePhoto: UIImage? {
        if let photoSelectionID, selection?.includes(photoSelectionID) == false { return nil }
        return photo
    }
    private var mediaSide: CGFloat { qrSize + 6 }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)
            HStack(alignment: .top, spacing: 16) {
                if visiblePhoto == nil { Spacer(minLength: 0) }
                VStack(alignment: visiblePhoto == nil ? .center : .leading, spacing: 12) {
                    if let payload = visibleQRPayload, let qr = ShareQR.image(for: payload) {
                        Image(uiImage: qr).interpolation(.none).resizable()
                            .frame(width: qrSize, height: qrSize)
                            .padding(3).background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("QR code")
                            .accessibilityIdentifier("share.footer.qr")
                    }
                    if let payload = visibleQRPayload, payload.contains("#ps=") {
                        Text("Scan to get this routine")
                            .font(.system(size: 11)).foregroundStyle(MasoColor.textDim)
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                            .environment(\.layoutDirection, contentDirection)
                    }
                    brandBlock
                        .environment(\.layoutDirection, contentDirection)
                        .accessibilityElement(children: .combine)
                        .accessibilityIdentifier("share.footer.brand")
                }
                Spacer(minLength: 0)
                if let photo = visiblePhoto {
                    Color.clear.frame(width: mediaSide, height: mediaSide)
                        .overlay { Image(uiImage: photo).resizable().scaledToFill() }
                        .clipped().clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Photo")
                        .accessibilityIdentifier("share.footer.photo")
                }
            }
            // Owner-defined physical left/right positions stay the same in RTL exports.
            .environment(\.layoutDirection, .leftToRight)
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 14)
        }
    }

    @ViewBuilder private var brandBlock: some View {
        if visiblePhoto == nil {
            VStack(spacing: 4) {
                MasoMarkIcon(color: MasoColor.accent).frame(width: 32, height: 32)
                Text(verbatim: "MASSO").font(.system(size: 13, weight: .heavy))
                    .tracking(2).foregroundStyle(MasoColor.text)
                Text(MasoBrand.slogan).font(.system(size: 10)).foregroundStyle(MasoColor.textDim)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
        } else {
        HStack(spacing: 10) {
            MasoMarkIcon(color: MasoColor.accent).frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: "MASSO").font(.system(size: 13, weight: .heavy))
                    .tracking(2).foregroundStyle(MasoColor.text)
                Text(MasoBrand.slogan).fixedSize(horizontal: false, vertical: true)
                    .font(.system(size: 10)).foregroundStyle(MasoColor.textDim)
            }
        }
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
                        Text("Training plan").textCase(.uppercase)
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

                ShareSelectableCard(id: "routine-muscles", title: NSLocalizedString("Muscles trained", comment: "")) {
                // 肌肉图居中
                if !muscles.isEmpty {
                    HStack {
                        Spacer(minLength: 0)
                        ShareMuscleMap2D(muscles: muscles)
                        Spacer(minLength: 0)
                    }
                }

                }

                ShareSelectableCard(id: "routine-summary", title: NSLocalizedString("Workout", comment: "")) {
                // 汇总数据 — Exercises / Sets (/ Volume 只在有配重时显示)
                HStack(spacing: 24) {
                    ShareStat(value: "\(plan.steps.count)", label: NSLocalizedString("Exercises count", comment: "exercise count stat label"))
                    ShareStat(value: "\(totalSets)", label: NSLocalizedString("Sets", comment: ""))
                    if totalVolumeKg > 0 {
                        ShareStat(value: volumeLabel, label: String(format: NSLocalizedString("Volume %@", comment: "total target volume — %@ = kg/lb"), WeightUnitProvider.current.label))
                    }
                    Spacer(minLength: 0)
                }

                }

                Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)

                ShareSelectableCard(id: "routine-exercises", title: NSLocalizedString("Exercises", comment: "")) {
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
            }
            .padding(.horizontal, ShareLayout.contentInset)
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

/// 共用的 stat 单元 — 大数字 + 下方小 label
/// (原定义在 WorkoutCompleteShareCard.swift; 该卡退役删除时挪来这里 — 5 张活卡都在用.)
struct ShareStat: View {
    let value: String
    let label: String
    var body: some View {
        VStack(spacing: 2) {
            MetricValueText(value: value, numeratorColor: MasoColor.text, denominatorColor: MasoColor.textDim, numeratorWeight: .heavy)
                .font(.system(size: 18, weight: .heavy).monospacedDigit())
                .foregroundStyle(MasoColor.text)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(1.2)
                .foregroundStyle(MasoColor.textDim)
        }
    }
}

/// Shared photo placeholder for share previews and meal entry. Caller controls size.
struct AddPhotoPlaceholder: View {
    var compact = false
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(MasoColor.borderSoft,
                              style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
            Group {
                if compact {
                    HStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus").font(.body.weight(.light))
                        Text("Add a photo").font(.subheadline.weight(.semibold))
                        Spacer()
                    }.padding(.horizontal, 14)
                } else {
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus").font(.system(size: 38, weight: .light))
                        Text("Add a photo").font(.subheadline.weight(.semibold))
                    }
                }
            }.foregroundStyle(MasoColor.textDim)
        }
        .background(MasoColor.surface.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        .contentShape(RoundedRectangle(cornerRadius: 14))
    }
}
