import SwiftUI

// MARK: - CoachingPreferencesSheet — "Coaching" 记忆管理 + Tune-with-AI 输入 (设计 §3)
//
// 从 Training Preferences 卡底部 "Tune with AI" pill 拉起 (.large detent, 拖动指示, nav "Coaching", Done).
// 三段自上而下:
//   (a) 表头: sparkles + "What your AI coach knows" + 诚实用途说明.
//   (b) 结构化偏好启动行: slider.horizontal.3 + "Training profile" + prefSummary + chevron
//       → 拉起既有结构化编辑层 (TrainingPreferencesSheet), 不重复 pickers.
//   (c) 教练记忆 = 可删 chip (ChatGPT-memory gold standard): 每条 coachNote 一个 chip, ✕ 删该条;
//       "Clear all" (仅非空, 带确认 alert); 空态一句 faint 引导. chip 用 FlowLayout (复用 OnboardingScreen 里那个).
//   (d) 钉底输入 (safeAreaInset .bottom): port 原 refineComposer (多行 TextField + 圆形 arrow.up 发送 +
//       URL 提示) + 上方一排 "Add:" suggestion chip (点 = 发送那句话).
//
// 交互 (设计 §4):
//   - 发送 tune (typed / suggestion): Pro gate (onSend 里做) → append note + 立即重生成.
//   - 删除 chip: onDelete (仅 save, 不自动重生成); 删过后底部露 "Notes changed — Regenerate" pill → onRegenerate.
//   - 删除对非 Pro 也免费; 发送/重生成 Pro-gated (由 parent 的闭包决定弹 paywall).
struct CoachingPreferencesSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    /// 是否 Pro — 控制本 sheet 内 send / 重生成的 paywall (删除不受影响).
    let isPro: Bool
    /// 发送一条 tune (typed 或 suggested chip) — Pro gate + append + 立即重生成都在 parent 做.
    var onSend: (String) -> Void
    /// 删除某条教练记忆 (按显示下标) — 仅 save, 不重生成.
    var onDelete: (Int) -> Void
    /// 清空全部教练记忆.
    var onClearAll: () -> Void
    /// "Notes changed — Regenerate" 触发的重生成 (focusNote nil, surface coaching_edit).
    var onRegenerate: () -> Void
    /// "Training profile" 行的结构化编辑层点 "Generate routines" 确认后 → parent 重生成.
    var onEditProfileConfirmed: () -> Void

    /// 输入框文本 (本 sheet 自持有, 不搬回 PlansScreen).
    @State private var refineInput: String = ""
    /// 打开 sheet 那一刻的记忆条数 — 删除后跟当前对不上 → 露出重生成 pill.
    @State private var notesCountOnOpen: Int = 0
    /// 结构化偏好编辑层 (嵌套 sheet).
    @State private var showEditor = false
    /// 清空确认 alert.
    @State private var confirmClear = false
    /// 非 Pro 点发送 → 本 sheet 内自弹 paywall (parent 的 sheet 已占用, 不能再从 parent 弹).
    @State private var paywallPresented = false

    private var notes: [String] { data.coachNotes }
    private var canSend: Bool { !refineInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// 记忆自打开后被删过 → 值得让用户一键把改动应用到 routine.
    private var notesChanged: Bool { notes.count != notesCountOnOpen }

    /// suggested-add chip 候选 — 结构化 pickers 里没有的长尾常见项. 点 = 发送那句话.
    private var suggestions: [String] {
        [
            NSLocalizedString("bad knee", comment: "coaching suggestion"),
            NSLocalizedString("hate burpees", comment: "coaching suggestion"),
            NSLocalizedString("home gym only", comment: "coaching suggestion"),
            NSLocalizedString("train mornings", comment: "coaching suggestion"),
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    headerSection
                    profileLauncherRow
                    Rectangle().fill(MasoColor.borderSoft).frame(height: 0.5)
                    notesSection
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .background(MasoColor.background)
            .navigationTitle(NSLocalizedString("Coaching", comment: "coaching sheet title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(NSLocalizedString("Done", comment: "")) { dismiss() }
                }
            }
            // 钉底输入 — suggestion chip 行 + tune 输入框. 记忆列表滚动时它保持钉在底部 (拇指可达).
            .safeAreaInset(edge: .bottom) { composer }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .onAppear { notesCountOnOpen = notes.count }
        .sheet(isPresented: $showEditor) {
            // 复用既有结构化编辑层 (pickers + "Generate routines" CTA), 不重复偏好 UI.
            TrainingPreferencesSheet(onConfirm: onEditProfileConfirmed)
        }
        .sheet(isPresented: $paywallPresented) {
            PaywallScreen().presentationDragIndicator(.visible)
        }
        .alert(NSLocalizedString("Clear all coaching notes?", comment: "coaching clear all confirm"),
               isPresented: $confirmClear) {
            Button(NSLocalizedString("Clear all", comment: "coaching clear all"), role: .destructive) {
                onClearAll()
                Haptics.tap()
            }
            Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) {}
        }
    }

    // MARK: - (a) 表头

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MasoColor.accent)
                Text(NSLocalizedString("What your AI coach knows", comment: "coaching header"))
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
            }
            Text(NSLocalizedString("Your plans are built from your training profile below, plus the notes you add here. Edit or remove anything anytime.", comment: "coaching header explainer"))
                .font(.system(size: 12))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - (b) 结构化偏好启动行

    private var profileLauncherRow: some View {
        Button {
            showEditor = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.accent)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(NSLocalizedString("Training profile", comment: "coaching profile row"))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                    Text(prefSummary)
                        .font(.system(size: 12))
                        .foregroundStyle(MasoColor.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - (c) 教练记忆 chip

    private var notesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            // kicker 行 — 复刻 coachMemorySection: brain.head.profile accent + "Coaching notes" + Clear all.
            HStack(spacing: 6) {
                Image(systemName: "brain.head.profile")
                    .font(.system(size: 11, weight: .heavy))
                Text(NSLocalizedString("Coaching notes", comment: "coaching notes kicker"))
                    .font(.system(size: 12, weight: .bold))
                    .tracking(0.5)
                Spacer()
                if !notes.isEmpty {
                    Button { confirmClear = true } label: {
                        Text(NSLocalizedString("Clear all", comment: "coaching clear all"))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .buttonStyle(.plain)
                }
            }
            .foregroundStyle(MasoColor.accent)

            if notes.isEmpty {
                Text(NSLocalizedString("No notes yet. Tell your coach a preference below — e.g. 'bad shoulder, no overhead'.", comment: "coaching notes empty"))
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textFaint)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                FlowLayout(spacing: 8) {
                    ForEach(Array(notes.enumerated()), id: \.offset) { index, note in
                        noteChip(note, index: index)
                    }
                }
            }

            // 记忆自打开后被删过 → 一键把改动应用到 routine (删除本身不自动重生成).
            if notesChanged {
                Button {
                    onRegenerate()
                    notesCountOnOpen = notes.count
                    Haptics.tap()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 12, weight: .bold))
                        Text(NSLocalizedString("Notes changed — Regenerate", comment: "coaching regenerate pill"))
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(MasoColor.accent.opacity(0.14)))
                    .overlay(Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
    }

    /// 单个可删 chip — 文字 + 尾部 ✕ (点 ✕ 删该条). surfaceHi 胶囊 + borderSoft 描边, 文字 lineLimit 2.
    private func noteChip(_ note: String, index: Int) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                onDelete(index)
            }
            Haptics.tap()
        } label: {
            HStack(spacing: 6) {
                Text(note)
                    .font(.system(size: 13))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(MasoColor.textDim)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(Capsule().fill(MasoColor.surfaceHi))
            .overlay(Capsule().stroke(MasoColor.borderSoft, lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(String(format: NSLocalizedString("Remove note: %@", comment: "coaching chip a11y"), note)))
    }

    // MARK: - (d) 钉底输入 (suggestion chip + tune 输入框)

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            // suggested-add chip — 点 = 发送那句话 (append + 重生成). accent entry-pill 样式.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(suggestions, id: \.self) { s in
                        Button { send(s) } label: {
                            Text(String(format: NSLocalizedString("Add: %@", comment: "coaching suggestion chip"), s))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(MasoColor.accent)
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(Capsule().fill(MasoColor.accent.opacity(0.14)))
                                .overlay(Capsule().stroke(MasoColor.accent.opacity(0.35), lineWidth: 0.5))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }

            // 视频链接温和提示 — 文本 LLM 看不了视频. (TODO(backend): fetch video transcript.)
            if refineInput.containsURL {
                Text(NSLocalizedString("I can't watch the video yet — paste the key moves or the plan from it and I'll work it in.", comment: "AI refine url hint"))
                    .font(.system(size: 11))
                    .foregroundStyle(MasoColor.textDim)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }

            // tune 输入框 — port 原 refineComposer: 多行 TextField + 圆形 arrow.up 发送.
            HStack(spacing: 10) {
                TextField(NSLocalizedString("Tell the AI a preference or change in plain words — e.g. 'bad shoulder, no overhead'. It remembers.", comment: "AI refine + coach memory input placeholder"),
                          text: $refineInput, axis: .vertical)
                    .font(.system(size: 14))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1...4)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(MasoColor.surface)
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(MasoColor.borderSoft, lineWidth: 0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .submitLabel(.send)
                    .onSubmit { send(refineInput) }

                Button { send(refineInput) } label: {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(canSend ? MasoColor.accent : MasoColor.surfaceHi))
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .accessibilityLabel(NSLocalizedString("Send", comment: "AI refine send"))
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(.bar)
    }

    /// 发送 — 非 Pro 先弹本 sheet 内的 paywall (什么都不写); Pro 走 parent 的 onSend (append + 重生成).
    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard isPro else { paywallPresented = true; return }
        refineInput = ""
        onSend(text)
        // 发送后本次生成已带上, 打开时的基线也随之更新, 避免误报 "Notes changed".
        notesCountOnOpen = notes.count + 1
    }

    // MARK: - 偏好摘要 (跟 PlanRationaleCard.prefSummary 同逻辑)

    /// 已选参数拼成一行小字 (天数 · 目标 · 动作数 · 组数 · 器械 · 重点肌群), 用 " · " 分隔.
    private var prefSummary: String {
        let s = data.settings
        var parts: [String] = []
        parts.append(String(format: NSLocalizedString("%lld days / week", comment: ""), s.weeklyTrainingDays))
        parts.append(s.trainingGoalKind.displayName)
        parts.append(String(format: NSLocalizedString("%d exercises", comment: ""), s.exercisesPerSession))
        parts.append(String(format: NSLocalizedString("%d sets", comment: ""), s.defaultSetsPerExercise))
        if s.availableEquipment.isEmpty {
            parts.append(NSLocalizedString("Any equipment", comment: ""))
        } else {
            let cats = s.availableEquipment.compactMap { EquipmentCategory(rawValue: $0)?.displayName }
            let shown = cats.prefix(2).joined(separator: ", ")
            parts.append(shown + (cats.count > 2 ? " +\(cats.count - 2)" : ""))
        }
        let majors = MuscleSelector.focusSummary(Set(s.wantStrengthen))
        if !majors.isEmpty {
            let names = majors.prefix(3).map(\.displayName).joined(separator: ", ")
            parts.append(String(format: NSLocalizedString("Focus: %@", comment: "training prefs focus muscles"),
                                names + (majors.count > 3 ? " +\(majors.count - 3)" : "")))
        }
        return parts.joined(separator: " · ")
    }
}

// URL 检测 — 原 PlansScreen.containsURL 抽成 String 扩展, tune 输入的 PlansScreen + Coaching sheet 共用.
extension String {
    var containsURL: Bool {
        guard !isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return false }
        let range = NSRange(startIndex..., in: self)
        return detector.firstMatch(in: self, options: [], range: range) != nil
    }
}
