import SwiftUI

// AI Insight Summary 卡 — 钉在 Progress→Insights 列表最顶 (InsightsChartsView body 的第一个子, 固定不可重排).
// 教练的一句话判读 + 2-4 条可一键 apply 的建议. 见 docs/ai-insight-summary-design.md §1 / §6.
//
// 状态 (§1):
//   · insufficient-data  — 未达 min-data 阈值 (routineSuggestion() == nil): 灰底文案, 不调 LLM.
//   · locked (非 Pro)     — TL;DR 用本地 routineSuggestion() 免费露出; AI 建议行 blur + 中央解锁按钮 → onUnlock.
//   · idle/cached         — 渲缓存 + "as of <date>" + Refresh.
//   · loading             — 缓存内容变暗 + spinner (never 空卡).
//   · generated           — TL;DR + 建议行 + Apply; 一次 session 显 "Updated" 标.
//   · error               — inline chip "AI summary unavailable — Retry" (有缓存则叠在缓存上).
//
// LLM 调用只在 Pro (§6 — 非 Pro 免费 teaser 100% 本地, 绝不花 token).
struct AISummaryCard: View {
    let data: DataStore
    /// 非 Pro 点锁 → 拉付费墙.
    var onUnlock: () -> Void = {}
    /// Apply 一条建议 — parent (HistoryScreen) 接管 Pro gate + 路由到 AI Routines / 写 coach note + toast.
    var onApply: (AISummaryAction) -> Void = { _ in }

    /// 当前渲染的 summary (缓存优先; 生成成功后更新). nil 且 Pro → 触发首次生成.
    @State private var summary: AISummary? = nil
    @State private var isGenerating = false
    @State private var errorNote: String? = nil
    /// 本 session 刚生成过 → 显 "Updated" 标一次.
    @State private var justUpdated = false
    @State private var didAppear = false

    private var isPro: Bool { data.settings.isPro }

    var body: some View {
        Group {
            if !data.summaryMinDataMet {
                insufficientCard
            } else if !isPro {
                lockedCard
            } else {
                proCard
            }
        }
        .onAppear(perform: handleAppear)
    }

    // MARK: - 生命周期

    private func handleAppear() {
        guard !didAppear else { return }
        didAppear = true
        guard data.summaryMinDataMet else { return }
        // 先渲缓存 (立即).
        summary = data.cachedSummary ?? (isPro ? nil : data.localSummaryFallback())
        // 非 Pro 不花 token — teaser 走本地.
        guard isPro else { return }
        // 冷启动 (没缓存) 或满足 cadence → 一次后台生成 (dimmed spinner 叠缓存).
        if summary == nil || data.shouldRegenerateSummary() {
            regenerate()
        }
    }

    private func regenerate() {
        guard isPro, !isGenerating else { return }
        Haptics.tap()
        errorNote = nil
        withAnimation(.easeOut(duration: 0.2)) { isGenerating = true }
        Task { @MainActor in
            let result = await data.generateSummary()
            withAnimation(.easeOut(duration: 0.25)) {
                isGenerating = false
                if let result {
                    let changed = result.tldr != summary?.tldr
                    summary = result
                    justUpdated = changed
                    // AISummaryService 成功与否都写了缓存; 若返回的是本地回落, 给个温和 error chip.
                    errorNote = nil
                } else {
                    errorNote = NSLocalizedString("AI summary unavailable — Retry", comment: "AI summary error chip")
                }
            }
        }
    }

    // MARK: - 状态: insufficient data

    private var insufficientCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            header(showRefresh: false)
            Text(NSLocalizedString("Keep logging — your AI summary unlocks after about 2 weeks of training.", comment: "AI summary insufficient data"))
                .font(.system(size: 13))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .cardChrome()
    }

    // MARK: - 状态: locked (非 Pro) — 本地 TL;DR teaser + blurred 建议行 + 解锁按钮

    private var lockedCard: some View {
        let teaser = summary ?? data.localSummaryFallback()
        return VStack(alignment: .leading, spacing: 10) {
            header(showRefresh: false)
            // TL;DR 免费露出 (本地 routineSuggestion(), 无 LLM).
            Text(teaser.tldr)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)

            ZStack {
                VStack(alignment: .leading, spacing: 10) {
                    // blur 的假建议行 — 用本地回落 (或占位) 撑起高度, 视觉暗示"这里有内容".
                    ForEach(placeholderRecs(from: teaser)) { rec in
                        recommendationRow(rec, applyEnabled: false)
                    }
                }
                .blur(radius: isPro ? 0 : 7)
                .allowsHitTesting(isPro)

                Button(action: onUnlock) {
                    VStack(spacing: 6) {
                        Image(systemName: "lock.fill").font(.system(size: 15, weight: .bold))
                        Text(NSLocalizedString("Unlock your AI coach summary with Pro", comment: "AI summary paywall"))
                            .font(.system(size: 12, weight: .semibold))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(MasoColor.text)
                    .padding(.horizontal, 16).padding(.vertical, 12)
                }
                .buttonStyle(.plain)
            }
        }
        .cardChrome()
    }

    /// 非 Pro 时给 blur 层用的占位建议行 — 有本地建议就用它 (+1 条通用占位), 否则两条通用占位.
    private func placeholderRecs(from s: AISummary) -> [AIRecommendation] {
        if !s.recommendations.isEmpty {
            var out = s.recommendations
            out.append(AIRecommendation(
                id: "ph-more",
                title: NSLocalizedString("Rebalance your weekly volume", comment: "AI summary locked placeholder title"),
                detail: NSLocalizedString("Personalized set-by-set guidance from your data.", comment: "AI summary locked placeholder detail"),
                action: .none))
            return out
        }
        return [
            AIRecommendation(id: "ph1",
                             title: NSLocalizedString("Rebalance your weekly volume", comment: "AI summary locked placeholder title"),
                             detail: NSLocalizedString("Personalized set-by-set guidance from your data.", comment: "AI summary locked placeholder detail"),
                             action: .none),
            AIRecommendation(id: "ph2",
                             title: NSLocalizedString("Break your main-lift plateau", comment: "AI summary locked placeholder title 2"),
                             detail: NSLocalizedString("Concrete progression tailored to your recent sessions.", comment: "AI summary locked placeholder detail 2"),
                             action: .none),
        ]
    }

    // MARK: - 状态: Pro — cached / loading / generated / error

    private var proCard: some View {
        let shown = summary ?? data.localSummaryFallback()
        return VStack(alignment: .leading, spacing: 10) {
            header(showRefresh: true)

            ZStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(shown.tldr)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(MasoColor.text)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(shown.recommendations) { rec in
                        recommendationRow(rec, applyEnabled: true)
                    }
                }
                .opacity(isGenerating ? 0.4 : 1)      // loading = 缓存变暗, never 空卡
                .allowsHitTesting(!isGenerating)

                if isGenerating {
                    ProgressView().tint(MasoColor.accent)
                }
            }

            if let errorNote {
                Button(action: regenerate) {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .bold))
                        Text(errorNote).font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(MasoColor.negative)
                    .padding(.top, 2)
                }
                .buttonStyle(.plain)
            }

            footer(generatedAt: data.settings.aiSummaryGeneratedAt)
        }
        .cardChrome()
    }

    // MARK: - 子组件

    private func header(showRefresh: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(MasoColor.accent)
            Text(NSLocalizedString("AI Coach Summary", comment: "AI summary card title"))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(MasoColor.text)
            if justUpdated {
                Text(NSLocalizedString("Updated", comment: "AI summary just-updated tag"))
                    .font(.system(size: 9, weight: .heavy)).tracking(0.5)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(MasoColor.accent))
            }
            Spacer()
            if showRefresh {
                // 分享小结 — 只在 cached/generated 态出现 (summary 非 nil):
                // insufficient / locked teaser / 无缓存的 loading/error 都拿不到 showRefresh
                // 或 summary, 不给用户广播占位内容的机会.
                if summary != nil {
                    shareButton
                }
                Button(action: regenerate) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MasoColor.textDim)
                }
                .buttonStyle(.plain)
                .disabled(isGenerating)
                .accessibilityLabel(Text(NSLocalizedString("Refresh", comment: "AI summary refresh")))
            }
        }
    }

    /// 分享入口 — InsightShareCard (TL;DR hero + 4 个头条数字). 只读缓存/已生成结果,
    /// 绝不为分享触发 LLM. 分享本身免费 (有机增长), 数字由 DataStore.summaryKeyStats() 统一供给.
    private var shareButton: some View {
        ShareImageButton(
            previewTitle: NSLocalizedString("My AI Summary", comment: ""),
            defaultSections: ShareSections(),
            shareContent: { photo, onTapAdd, _ in
                InsightShareCard(
                    tldr: summary?.tldr ?? data.cachedSummary?.tldr,
                    generatedAt: data.settings.aiSummaryGeneratedAt,
                    stats: data.summaryKeyStats(),
                    // 这个入口只在有已生成小结时出现 (= Pro), 但仍显式传 isPro —
                    // 渲染层兜底: 非 Pro 永远分享不出 quote/e1RM/坚持度 (#insights-share-pro).
                    isPro: data.settings.isPro,
                    userPhoto: photo,
                    onTapAddPhoto: onTapAdd
                )
            },
            shareSurface: "ai_summary",
            label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
            }
        )
        .accessibilityLabel(Text(NSLocalizedString("Share", comment: "")))
    }

    private func footer(generatedAt: Date?) -> some View {
        Group {
            if let generatedAt {
                let df: DateFormatter = {
                    let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .none; return f
                }()
                Text(String(format: NSLocalizedString("As of %@ · based on the last 14 days", comment: "AI summary footer"), df.string(from: generatedAt)))
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textFaint)
            } else {
                EmptyView()
            }
        }
    }

    @ViewBuilder
    private func recommendationRow(_ rec: AIRecommendation, applyEnabled: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "chevron.forward.circle.fill")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MasoColor.accent)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(rec.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)
                Text(rec.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            applyControl(for: rec, enabled: applyEnabled)
        }
        .padding(.vertical, 6)
        .overlay(alignment: .top) { Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5) }
    }

    /// Apply 控件 — action 决定文案/是否有按钮. .none = 纯观察, 无按钮.
    @ViewBuilder
    private func applyControl(for rec: AIRecommendation, enabled: Bool) -> some View {
        switch rec.action {
        case .none:
            EmptyView()
        case .regenerateRoutines:
            applyButton(NSLocalizedString("Apply to routine", comment: "AI summary apply — regenerate"), rec.action, enabled: enabled)
        case .addCoachNote:
            applyButton(NSLocalizedString("Add to notes", comment: "AI summary apply — coach note"), rec.action, enabled: enabled)
        }
    }

    private func applyButton(_ label: String, _ action: AISummaryAction, enabled: Bool) -> some View {
        Button {
            Haptics.tap()
            onApply(action)
        } label: {
            Text(label)
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.black)
                .padding(.vertical, 6).padding(.horizontal, 10)
                .background(Capsule().fill(MasoColor.accent))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .allowsHitTesting(enabled)
    }
}

// 卡片外壳 cardChrome() 已抽到 Maso/Theme/CardChrome.swift (internal),
// 跟 Training Preferences 卡共用同一片壳.
