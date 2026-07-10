import Foundation
import Observation

// Coach tab (对话式生成) 的会话状态容器 — 批次 1 数据/AI 地基, 见 docs/coach-tab-design.md §1/§3.
//
// 为什么收归 DataStore 层而不是 view @State (工程评审钦点):
//   - 生成 45-60s 且无流式, 用户会切 tab / 锁屏; view 销毁 = @State 即丢, 回来一片空白.
//   - DataStore 持有 CoachSession + 生成 Task, 视图只渲染; 切走再回来, 等待清单/结果都还在.
// V1 刻意 in-memory (不落盘): 对话流是"工作台"不是"档案", 重启清空可接受;
// 真正的产物 (用户保存的 routine) 走 data.plans 持久化, 不受影响.

/// 对话流里的一条消息. assistant 消息可携带一轮生成的 [Plan] —
/// UI 渲染成 DAY 1..N 卡组 (DAY 序号 = plans 数组下标 + 1, 不写进 plan.name).
struct CoachMessage: Identifiable, Hashable {
    enum Role: Hashable {
        case user
        case assistant
    }

    let id: String
    let role: Role
    var text: String
    /// assistant 专用 — 本轮生成的 routine 卡组 (nil = 纯文本消息).
    var plans: [Plan]? = nil
    /// 深链来源标签 (e.g. "FROM WEEKLY SUMMARY") — 用户气泡顶部的 kicker; nil = 普通消息.
    var sourceKicker: String? = nil
    let createdAt: Date

    init(role: Role, text: String, plans: [Plan]? = nil, sourceKicker: String? = nil) {
        self.id = UUID().uuidString
        self.role = role
        self.text = text
        self.plans = plans
        self.sourceKicker = sourceKicker
        self.createdAt = Date()
    }
}

/// Coach 对话状态 — DataStore 持有单例实例 (data.coachSession), 视图只读渲染 + 通过
/// DataStore 的 coach* 方法改写. ⚠️ 聊天文本属 PII: 任何字段都不许进 analytics (只报长度/次数/surface).
@MainActor
@Observable
final class CoachSession {
    /// 对话流 (user / assistant 交替). "新对话" 清空.
    var messages: [CoachMessage] = []
    /// 生成中 — Composer 禁发 + 对话流尾部渲染诚实等待清单 (绝不做假打字机/假流式).
    var isGenerating = false
    /// 等待清单的渐进步骤 (0 上传 → 1 分析 → 2 生成; 最后一步等真实完成才落定).
    /// 文案键复用 AIGeneratingView 那套 ("Uploading your data" / "Analyzing your stats" / "Building your plan").
    var generationStep = 0
    /// 步骤总数 — UI 画清单用.
    static let generationStepCount = 3
    /// 离线/失败回落提示 (本地模板顶包 / 修订失败保留旧版时非 nil), 渲染在结果上方. 每轮开始时清空.
    var fallbackNote: String? = nil
    /// 每轮生成的 [Plan] 快照栈 — 本地版本历史, "捞回旧版"零 LLM 成本. 末尾 == currentRoutines.
    var versionStack: [[Plan]] = []
    /// 最新一轮的结果 — 修订轮以它为基 (CURRENT ROUTINES 块 + reconciliation 回填源). 空 = 还没生成过 (下一轮是首轮).
    var currentRoutines: [Plan] = []
    /// 生成卡 plan.id → 已存副本 planId. 保存时记录; bookmark 态用它反查 —
    /// savePlan 存的是重 id 副本, 纯签名匹配在副本改名后会失灵 (工程评审要求 id 映射优先, 签名只作兜底).
    var savedIdMap: [String: String] = [:]
    /// QA修复①: 上一轮结果是否来自本地模板回落. 回落轮的 currentRoutines 不是 AI 认可的基线 —
    /// 下一轮 (含 Retry) 若按修订轮走, LLM 会被锚死在模板上原样复读却报"已更新".
    /// 约束: 回落轮置 true, 真 AI 成功轮置 false; 修订轮判定必须同时看它 (见 coachGenerate).
    var lastRoundUsedFallback = false
    /// QA修复③: 在途生成轮的身份 token — startCoachGenerate 每轮发新值, 任务收尾用它比对,
    /// 被取消的旧任务不许清掉新任务的句柄. 约束: 只在 startCoachGenerate / reset 里写.
    var generationToken: UUID? = nil

    /// "新对话" — 清对话流/版本栈/回落提示, 不动 data.plans (已保存的 routine 是持久产物).
    /// savedIdMap 一并清: key 是旧对话里的生成卡 id, 新对话不会再引用.
    /// ⚠️ 调用方走 DataStore.resetCoachConversation() — 它负责先取消在途生成任务.
    func reset() {
        messages.removeAll()
        versionStack.removeAll()
        currentRoutines.removeAll()
        savedIdMap.removeAll()
        fallbackNote = nil
        generationStep = 0
        isGenerating = false
        lastRoundUsedFallback = false
        generationToken = nil
    }
}

// MARK: - DataStore + Coach 修订环 (one-shot, 不做真多轮 — 设计文档 §3)

extension DataStore {
    /// Coach 对话一轮生成的非 async 入口 — 任务由 DataStore 持有: 切 tab / 视图销毁不取消,
    /// 结果落回 coachSession (工程评审钦点). UI 一律调这个, 不要自己包 Task {}.
    /// - parameter feedback: 用户这轮说的话 (首轮 = 初始诉求, 修订轮 = 修改意见). nil/空 = 无言生成 (如深链自动触发).
    /// - parameter displayText: QA修复⑧ — 用户气泡显示的本地化短语; nil = 直接显示 feedback.
    ///   深链/建议 Apply 的 feedback 是英文 prompt 工程指令, 只进 prompt 不上屏.
    /// - parameter onlyModify: 定向修订目标 ("Day 2" / 动作名) — 长按动作行的引用式反馈传入.
    /// - parameter sourceKicker: 深链来源标签 (e.g. "FROM WEEKLY SUMMARY"), 渲染在用户气泡顶部.
    func startCoachGenerate(feedback: String? = nil,
                            displayText: String? = nil,
                            onlyModify: String? = nil,
                            sourceKicker: String? = nil,
                            surface: String = "coach_chat") {
        guard !coachSession.isGenerating else { return }
        // QA修复③: isGenerating 必须在进 Task 前同步置位 — 之前在 Task 体内才置 true,
        // 同一 runloop 双调用都能过上面的 guard, 两个生成任务并发互踩.
        coachSession.isGenerating = true
        let token = UUID()
        coachSession.generationToken = token
        coachGenerateTask = Task { [weak self] in
            await self?.coachGenerate(feedback: feedback, displayText: displayText,
                                      onlyModify: onlyModify,
                                      sourceKicker: sourceKicker, surface: surface,
                                      preflighted: true)
            await MainActor.run { [weak self] in
                // QA修复③: 身份比对 — 只有 token 仍是本轮的才清句柄;
                // 被取消的旧任务跑完 completion 时不许清掉新任务的句柄.
                guard let self, self.coachSession.generationToken == token else { return }
                self.coachGenerateTask = nil
            }
        }
    }

    /// "新对话" — 取消在途生成 + 清会话状态. 不动 data.plans.
    func resetCoachConversation() {
        coachGenerateTask?.cancel()
        coachGenerateTask = nil
        coachSession.reset()
    }

    /// 修订环核心 (async 本体):
    ///   - 首轮 (currentRoutines 空): 走既有 generateAIRoutines 管线 (count = weeklyTrainingDays 夹 2...4,
    ///     在它内部), feedback 作 focusNote 注入 PRIORITY 行; 失败回落本地模板 (usedFallback 语义沿用).
    ///   - 修订轮: AIWorkoutService.reviseRoutines (CURRENT ROUTINES + USER FEEDBACK [+ ONLY MODIFY]),
    ///     响应过 reconcileRevisedRoutines (缺天/多天对齐, 未提及的天用上一版回填) + applyScience 兜底;
    ///     失败 → 保留上一版原样 + fallbackNote (比换一批本地模板更不吓人).
    /// 每轮结束: push versionStack + append assistant 消息 (text = LLM rationale 或一句本地小结) + 清生成态.
    func coachGenerate(feedback: String?,
                       displayText: String? = nil,
                       onlyModify: String? = nil,
                       sourceKicker: String? = nil,
                       surface: String = "coach_chat",
                       preflighted: Bool = false) async {
        let session = coachSession
        // QA修复③: startCoachGenerate 已同步置 isGenerating 再进 Task (preflighted=true),
        // 此时守卫要放行自己; 罕见的直调路径 (preflighted=false) 保持原守卫语义.
        guard preflighted || !session.isGenerating else { return }
        let trimmed = feedback?.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = (trimmed?.isEmpty == false) ? trimmed : nil
        // QA修复⑧: 气泡显示 displayText (本地化短语) 而不是英文 prompt 指令;
        // note (focusNote) 只进下面的生成管线. displayText 为空时退回显示 note 原文 (普通聊天).
        let shownTrimmed = displayText?.trimmingCharacters(in: .whitespacesAndNewlines)
        let shown = (shownTrimmed?.isEmpty == false) ? shownTrimmed : note
        if let shown {
            session.messages.append(CoachMessage(role: .user, text: shown, sourceKicker: sourceKicker))
        }
        session.isGenerating = true
        session.fallbackNote = nil
        session.generationStep = 0
        // 渐进步骤: 前两步定时推进 (给"AI 在干活"的诚实感知), 最后一步停在"生成中"直到真实完成 —
        // 跟 AIGeneratingView 同模式 (真实延迟落定, 无假流式).
        let progress = Task { @MainActor [weak session] in
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            session?.generationStep = 1
            try? await Task.sleep(for: .seconds(2.0))
            guard !Task.isCancelled else { return }
            session?.generationStep = 2
        }
        defer { progress.cancel() }

        // QA修复①: 回落轮的结果只是本地模板顶包, 不是 AI 认可的基线 — 上一轮回落时下一轮
        // (含 Retry 原参重发) 必须重走首轮生成管线, 否则修订轮会把 LLM 锚死在模板上原样复读.
        let isRevision = !session.currentRoutines.isEmpty && !session.lastRoundUsedFallback
        if !isRevision {
            let (plans, usedFallback) = await generateAIRoutines(focusNote: note, surface: surface)
            guard !Task.isCancelled else { return }   // "新对话"取消后不要往清空的流里落旧结果
            finishCoachRound(plans: plans, usedFallback: usedFallback, isRevision: false)
        } else {
            let previous = session.currentRoutines
            let revised = await AIWorkoutService.shared.reviseRoutines(
                payload: buildAIPayload(), library: exercises,
                current: previous, feedback: note ?? "", onlyModify: onlyModify,
                maxExercises: settings.exercisesPerSession, surface: surface)
            guard !Task.isCancelled else { return }
            if let revised, !revised.isEmpty {
                // 客户端 reconciliation (设计文档 风险②): LLM 可能重写/漏掉未被要求改的天 —
                // 按 名称 → 序号 对齐, 对不上的天用上一版原数据回填; 修订结果同样过 applyScience 兜底.
                let reconciled = DataStore.reconcileRevisedRoutines(revised, previous: previous)
                    .map { applyScienceToCoachPlan($0) }
                if reconciled == previous {
                    // QA修复⑦: LLM 违规返回 (全对不上号) 被 reconcile 全量回填 → 结果与上一版全等,
                    // 计划一字未动 — 不许报 "Updated your plan." 假成功, 走诚实的"计划未变动"收尾.
                    finishUnchangedRevision()
                } else {
                    finishCoachRound(plans: reconciled, usedFallback: false, isRevision: true)
                }
            } else {
                // 修订失败 → 不回落本地模板 (会冲掉用户已改好的版本, 比失败更吓人), 保留上一版原样.
                finishUnchangedRevision()
            }
        }
    }

    /// 修订轮"没有实际变化"的收尾 (QA修复⑦) — 修订失败 与 reconcile 后跟上一版全等 共用:
    /// 保留上一版原样, 不 push versionStack (没有新版本), assistant 消息诚实说明"没改动".
    /// 约束: 不新增 Localizable key — 复用既有 fallbackNote 文案 (语义 = 计划保持原样).
    private func finishUnchangedRevision() {
        let session = coachSession
        let unchanged = NSLocalizedString("Couldn't reach the AI coach — your plan is unchanged.",
                                          comment: "coach chat — revision round failed, previous plan kept")
        session.messages.append(CoachMessage(role: .assistant, text: unchanged))
        session.fallbackNote = unchanged
        session.generationStep = 0
        session.isGenerating = false
    }

    /// 一轮收尾 (成功 / 首轮模板回落) — push 版本栈 / 写 currentRoutines / 追加 assistant 消息 / 清生成态.
    /// text: 首轮优先 LLM 给的 rationale (让用户看出"真 AI"); 修订轮固定用本地小结 —
    /// 修订后 Day 1 可能是回填的旧天, 它的 rationale 描述的不是这次修改, 用了反而误导.
    private func finishCoachRound(plans: [Plan], usedFallback: Bool, isRevision: Bool) {
        let session = coachSession
        session.versionStack.append(plans)
        session.currentRoutines = plans
        let rationale = plans.first?.rationale?.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if isRevision {
            text = NSLocalizedString("Updated your plan.", comment: "coach chat — assistant summary after a revision round")
        } else if let rationale, !rationale.isEmpty {
            text = rationale
        } else {
            text = NSLocalizedString("Your plan is ready", comment: "coach chat — assistant fallback summary")
        }
        session.messages.append(CoachMessage(role: .assistant, text: text, plans: plans))
        // QA修复①: 记录本轮是否回落 — 回落轮之后的下一轮重走首轮生成管线 (见 coachGenerate 的 isRevision).
        session.lastRoundUsedFallback = usedFallback
        session.fallbackNote = usedFallback
            ? NSLocalizedString("Couldn't reach the AI coach — showing templates instead.",
                                comment: "coach chat fallback when LLM unreachable")
            : nil
        session.generationStep = 0
        session.isGenerating = false
    }

    /// 修订响应 ↔ 上一版的对齐 (风险② reconciliation). 目标天数恒 = 上一版天数 (修订不改周分化结构):
    ///   ① 名称相同 (不区分大小写) 优先 — LLM 通常保留没被要求改的天名;
    ///   ② 否则取同序号的响应天;
    ///   ③ 都对不上 (LLM 漏了这天) → 用上一版原数据回填.
    /// 响应里多出来的天 (LLM 幻觉) 直接丢弃, 不进结果.
    static func reconcileRevisedRoutines(_ revised: [Plan], previous: [Plan]) -> [Plan] {
        guard !previous.isEmpty else { return revised }
        var remaining = Array(revised.enumerated())   // (原响应序号, plan)
        var out: [Plan] = []
        for (i, prev) in previous.enumerated() {
            if let byName = remaining.firstIndex(where: {
                $0.element.name.caseInsensitiveCompare(prev.name) == .orderedSame
            }) {
                out.append(remaining.remove(at: byName).element)
            } else if revised.count == previous.count,
                      let byOrder = remaining.firstIndex(where: { $0.offset == i }) {
                // 序号对齐只在"响应天数 = 上一版天数"时可信 — 定向修订现在只返回改动的天
                // (部分响应), 此时按序号硬套会把改名后的 Day2 错塞进 Day1 槽位.
                out.append(remaining.remove(at: byOrder).element)
            } else {
                out.append(prev)
            }
        }
        return out
    }

    // MARK: - 书签态 (savedIdMap 优先, 签名兜底 — 设计文档 §2)

    /// Coach 结果卡的保存 — savePlan + 记录 生成卡 id → 已存副本 id 映射 (bookmark 态反查).
    /// 幂等: 已存 → 直接成功. 返回 false = 撞免费上限 (调用方弹 paywall).
    @discardableResult
    func saveCoachPlan(_ plan: Plan) -> Bool {
        if isCoachPlanSaved(plan) { return true }
        guard let copy = savePlanReturningCopy(plan) else { return false }
        coachSession.savedIdMap[plan.id] = copy.id
        return true
    }

    /// 生成卡是否已存 — savedIdMap 反查优先 (副本改名后签名会漂移, id 不会), 签名匹配兜底
    /// (老对话恢复 / map 里没记录过的卡). 映射指向的副本已被删 → 视为未存 (陈旧映射无害, 不在读路径清理).
    func isCoachPlanSaved(_ plan: Plan) -> Bool {
        if let savedId = coachSession.savedIdMap[plan.id],
           plans.contains(where: { $0.id == savedId }) {
            return true
        }
        return isPlanSaved(plan)
    }

    /// applyScience 的 coach 修订轮出口 — 私有 applyScience 在 DataStore.swift 里, 这里包一层
    /// (extension 跨文件访问不到 private). 语义完全一致: enforceScience + lastSet 负重兜底.
    private func applyScienceToCoachPlan(_ plan: Plan) -> Plan {
        var p = plan
        p.steps = DataStore.enforceScience(p.steps, exById: exById)
        p.steps = p.steps.map { step in
            var s = step
            if s.reps != nil, let w = lastSet(forExerciseId: s.exerciseId)?.weight, w > 0 {
                s.weight = w
            }
            return s
        }
        return p
    }
}
