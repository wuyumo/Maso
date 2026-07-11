import SwiftUI
import UIKit

// 批量分享训练计划 (owner 指定, #routines-batch-share):
// 「全部训练计划」sheet 顶栏 share 入口 → 本 sheet 勾选若干计划 → 渲染合集分享图 → 系统分享.
// 分享图 = 逐计划区块 (名称 + 动作清单) + ShareCardFooter (宣传 logo + MASSO 名称 + slogan + App Store 二维码).

struct RoutinesShareSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 勾选的 plan.id 集合 — 默认全选 (onAppear 填充).
    @State private var selected: Set<String> = []
    @State private var seeded = false
    /// 渲染完成的分享图 → 弹系统 share sheet.
    @State private var renderedImage: UIImage? = nil

    /// 可分享清单 = 今日 AI 计划 (若不在已存里) + 已存 plans — 跟「全部」列表同一份口径.
    private var sharablePlans: [Plan] {
        var out: [Plan] = []
        if let today = data.suggestedTodayPlan,
           !data.plans.contains(where: { $0.id == today.id }) {
            out.append(today)
        }
        out.append(contentsOf: data.plans)
        return out
    }

    private var selectedPlans: [Plan] { sharablePlans.filter { selected.contains($0.id) } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(sharablePlans) { plan in
                        row(plan)
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle(NSLocalizedString("Share routines", comment: "batch share sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "")) { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button(action: renderAndShare) {
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up").font(.system(size: 14, weight: .heavy))
                        Text(String(format: NSLocalizedString("Share (%lld)", comment: "batch share CTA with count"),
                                    selectedPlans.count))
                            .font(.system(size: 15, weight: .heavy))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .foregroundStyle(selectedPlans.isEmpty ? MasoColor.textDim : .black)
                    // 主 CTA 玻璃 (映射表①); 没选任何计划 → 素玻璃禁用态.
                    .glassCapsuleButtonBackground(
                        tint: selectedPlans.isEmpty ? nil : MasoColor.accent.opacity(0.85),
                        fallback: selectedPlans.isEmpty ? MasoColor.surfaceHi : MasoColor.accent)
                }
                .buttonStyle(.plain)
                .disabled(selectedPlans.isEmpty)
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 8)
                .padding(.bottom, 8)
                .background(MasoColor.background)
            }
            .tint(MasoColor.text)
        }
        .presentationDragIndicator(.visible)
        .onAppear {
            if !seeded { seeded = true; selected = Set(sharablePlans.map(\.id)) }   // 默认全选
        }
        // 渲染完成 → 系统分享面板 (跟 ShareImageButton 同一套 ActivityViewController).
        .sheet(isPresented: Binding(
            get: { renderedImage != nil },
            set: { if !$0 { renderedImage = nil } }
        )) {
            if let img = renderedImage {
                ActivityViewController(activityItems: [img]) { completed in
                    renderedImage = nil
                    if completed {
                        Analytics.shared.track("workout_share", ["surface": .string("routines_batch")])
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { dismiss() }
                    }
                }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
            }
        }
    }

    /// 勾选行 — 左圆形勾选 + 计划名/badge + 动作·组数 meta. 整行可点切换.
    private func row(_ plan: Plan) -> some View {
        let on = selected.contains(plan.id)
        return Button {
            Haptics.tap()
            if on { selected.remove(plan.id) } else { selected.insert(plan.id) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? MasoColor.accent : MasoColor.textFaint)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        PlanSourceBadge(source: plan.resolvedSource)
                        Text(plan.name)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(1)
                    }
                    Text("\(String(format: NSLocalizedString("%d exercises", comment: ""), plan.steps.count)) · \(String(format: NSLocalizedString("%d sets", comment: ""), plan.steps.reduce(0) { $0 + $1.sets }))")
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textDim)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(MasoColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func renderAndShare() {
        let plans = selectedPlans
        guard !plans.isEmpty else { return }
        Haptics.tap()
        // 二合一 QR: App Store 链接 + 数据锚点 — 相机扫进商店 (宣传), Masso 照片导入无损还原 1:1.
        // 数据过大 (QR 印卡上扫不出) → 回落纯 App Store 链, 导入走 OCR 尽力解析.
        let qr = PlanShareCodec.appStoreDataLink(for: plans) ?? MasoLinks.appStore
        let img = ShareImageRenderer.render {
            MultiRoutinesShareCard(plans: plans, exById: data.exById, qrPayload: qr)
        }
        guard let img else { return }
        // PNG 往返规整化 — 跟 ShareImageButton 同因 (ImageRenderer 偶发奇异元数据).
        if let d = img.pngData(), let normalized = UIImage(data: d) {
            renderedImage = normalized
        } else {
            renderedImage = img
        }
    }
}

// MARK: - 合集分享卡 — 多个 routine 的紧凑清单 + 品牌 footer

struct MultiRoutinesShareCard: View {
    let plans: [Plan]
    let exById: [String: Exercise]
    /// footer QR 载荷 — 二合一链接 (App Store + 数据锚点), 回落纯 App Store 链.
    var qrPayload: String = MasoLinks.appStore

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                // 头部 — ROUTINES kicker + "My Routines" 标题 (跟 RoutineShareCard 同视觉骨架).
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 11, weight: .heavy))
                            .foregroundStyle(MasoColor.accent)
                        Text(verbatim: "ROUTINES")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(1.5)
                            .foregroundStyle(MasoColor.accent)
                    }
                    Text("My Routines")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(MasoColor.text)
                }
                .padding(.top, 6)

                ForEach(Array(plans.enumerated()), id: \.element.id) { index, plan in
                    if index > 0 {
                        Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)
                    }
                    planBlock(plan)
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 20)
            .frame(maxWidth: .infinity, alignment: .leading)

            // 宣传 footer — logo + MASSO 名称 + slogan + 二维码 (owner 指定四件套).
            // QR 是二合一链接, 带数据锚点时更密 → 用 104pt (跟 RoutineShareCard 数据 QR 同档) 保证可扫.
            ShareCardFooter(qrPayload: qrPayload, qrSize: 104)
        }
        .background(MasoColor.background)
    }

    /// 单个计划区块 — 计划名 + 逐动作行 (全名 + "组 × 次 (· 配重)", OCR 友好, 跟 RoutineShareCard 同格式).
    private func planBlock(_ plan: Plan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(plan.name.isEmpty ? NSLocalizedString("Shared workout", comment: "") : plan.name)
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.steps) { step in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(exById[step.exerciseId]?.displayName ?? step.exerciseId)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(MasoColor.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 12)
                        Text(stepSummary(step))
                            .font(.system(size: 12).monospacedDigit())
                            .foregroundStyle(MasoColor.textDim)
                            .layoutPriority(1)
                    }
                }
            }
        }
    }

    /// 同 RoutineShareCard.stepSummary — "N × M (· W kg/lb)" / 计时 "N × 30s".
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
