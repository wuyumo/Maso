import Foundation

// AI 训练计划生成 — 调 Anthropic Claude API.
//
// 流程:
//   1. App 启动 / 回前台 → DataStore.refreshAIWorkoutIfNeeded()
//   2. 该 method 检查"今天是否已经 refresh 过" — 是 → skip; 否 → 走 service
//   3. Service 把 user profile + 训练频率 + 最近 14 天历史 打包成 prompt
//   4. POST 到 Anthropic Messages API
//   5. 解析返回的 JSON, fuzzy match 动作名 → 内部 exerciseId
//   6. 生成 Plan 对象 → DataStore.aiTodayPlan
//   7. TodayScreen 优先用 aiTodayPlan, fallback 系统推荐
//
// 用户需要做的:
//   1. 后端实际走 Cloudflare Worker 代理 → api.deepseek.com (deepseek-chat); 见下 request 构造
//   2. Settings → AI Workout → 粘贴 key + 启用 toggle
//
// 安全说明:
//   - API key 走 @AppStorage (UserDefaults) — prototype 阶段可用,
//     production 应升级到 Keychain Services. 移动端直接调 LLM API 都有 key 暴露
//     的天然风险 (反编译 / 流量抓包), 业内推荐做法是过 server proxy.
//   - 网络请求强制 HTTPS.

@MainActor
@Observable
final class AIWorkoutService {
    static let shared = AIWorkoutService()

    enum State {
        case idle
        case generating
        case success(Date)
        case failure(String)
    }
    private(set) var state: State = .idle

    private init() {}

    /// AI 后端代理 URL — Cloudflare Worker. 从 Info.plist 读 (xcconfig 注入).
    /// 例如 "https://maso-ai.your-user.workers.dev" — endpoint path /v1/chat/completions 自动加.
    /// 空 → AI 功能不可用. App Store 提交前一定要配置.
    private static var proxyURL: String {
        Bundle.main.object(forInfoDictionaryKey: "MasoAIProxyURL") as? String ?? ""
    }

    /// 客户端 token — 跟 Cloudflare Worker secret MASO_CLIENT_TOKEN 同值.
    /// 不是真 auth (反编译可拿), 只是轻量挡 abuse + 让 worker 知道是 Maso app 在调.
    /// 真严格区分 Pro / Free 需要 StoreKit receipt 验证 — 1.1 再做.
    private static var clientToken: String {
        Bundle.main.object(forInfoDictionaryKey: "MasoClientToken") as? String ?? ""
    }

    /// 当前 AI 是否可用 — UI 用来 disable/enable Pro AI toggle.
    static var isConfigured: Bool { !proxyURL.isEmpty && !clientToken.isEmpty }

    // MARK: - Public

    /// 生成今日 AI 训练计划.
    /// 通过 Cloudflare Worker 后端代理调 DeepSeek — API key 在 server 端, client binary 无 key.
    func generateToday(
        payload: AIPayload,
        library: [Exercise],
        maxExercises: Int = 4,
        surface: String = "today_refresh"
    ) async -> Plan? {
        guard Self.isConfigured else {
            state = .failure("AI proxy not configured (set MasoAIProxyURL + MasoClientToken in Secrets.xcconfig)")
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("not_configured")])
            return nil
        }
        state = .generating
        Analytics.shared.track("ai_routine_generate_start", ["surface": .string(surface), "mode": .string("today")])

        do {
            let raw = try await callDeepSeek(payload: payload, library: library, maxExercises: maxExercises)
            let parsed = try parseResponse(raw)
            let plan = buildPlan(from: parsed, library: library, maxExercises: maxExercises)
            guard !plan.steps.isEmpty else {
                state = .failure("AI returned no matching exercises")
                Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("empty_match")])
                return nil
            }
            state = .success(Date())
            Analytics.shared.track("ai_routine_generate_success", [
                "surface": .string(surface), "step_count": .int(plan.steps.count), "source": .string("ai"),
            ])
            return plan
        } catch let error as AIError {
            state = .failure(error.userMessage)
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string(error.analyticsReason)])
            return nil
        } catch {
            state = .failure(error.localizedDescription)
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("network")])
            return nil
        }
    }

    /// 生成一组 (count 套) AI routine — "AI Routines" 标签用. 一次 LLM 调用返回多套,
    /// 各带自己的 rationale, 组成均衡周分化 (A/B/C). 全部 source:.ai —— 让标签页每张都是真 AI,
    /// 不再混"本地凑数"计划 (修掉"只有第一张有理由、后面是已存的本地计划"的困惑).
    func generateRoutines(
        payload: AIPayload,
        library: [Exercise],
        count: Int,
        maxExercises: Int = 4,
        surface: String = "ai_segment"
    ) async -> [Plan]? {
        guard Self.isConfigured else {
            state = .failure("AI proxy not configured")
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("not_configured")])
            return nil
        }
        state = .generating
        Analytics.shared.track("ai_routine_generate_start", ["surface": .string(surface), "mode": .string("routines")])
        do {
            let raw = try await callDeepSeekRoutines(payload: payload, library: library, count: count, perRoutine: maxExercises)
            let routines = try parseRoutinesResponse(raw)
            let plans = routines.enumerated().compactMap { (i, r) -> Plan? in
                let plan = buildPlan(from: r, library: library, maxExercises: maxExercises, index: i)
                return plan.steps.isEmpty ? nil : plan
            }
            guard !plans.isEmpty else {
                state = .failure("AI returned no matching exercises")
                Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("empty_match")])
                return nil
            }
            state = .success(Date())
            let totalSteps = plans.reduce(0) { $0 + $1.steps.count }
            Analytics.shared.track("ai_routine_generate_success", [
                "surface": .string(surface), "step_count": .int(totalSteps), "source": .string("ai"),
            ])
            return plans
        } catch let error as AIError {
            state = .failure(error.userMessage)
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string(error.analyticsReason)])
            return nil
        } catch {
            state = .failure(error.localizedDescription)
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("network")])
            return nil
        }
    }

    // MARK: - Coach 修订轮 (one-shot revision — coach-tab-design.md §3)

    /// 修订轮注入 buildRoutinesPrompt 骨架的三块上下文. ⚠️ USER PROFILE / RECENT BEST SETS /
    /// 负重进阶硬约束随骨架**原样保留** (评审红线: 不许拿它们腾 token) — 复用同一个 prompt builder
    /// 而不是另写一份, 就是为了让这些块结构上不可能被落下.
    private struct RevisionSpec {
        /// CURRENT ROUTINES 紧凑结构块 (每天: 名称 + 动作/组次/重量).
        let currentBlock: String
        /// 用户这轮的修改意见 (原话).
        let feedback: String
        /// 定向修订目标 ("Day 2" / 动作名) — 非空时追加 ONLY MODIFY 指令.
        let onlyModify: String?
        /// current routines 里出现的全部动作名 — 目录 mustInclude, 保证"不变的天"能逐字复述
        /// (否则 LLM 被"逐字从目录选"逼着给未改动的天换名, ONLY MODIFY 语义崩坏).
        let currentNames: [String]
    }

    /// Coach 对话的修订轮 — 在现有 buildRoutinesPrompt 骨架上追加 CURRENT ROUTINES + USER FEEDBACK
    /// (+ ONLY MODIFY). 响应 schema 跟 generateRoutines 完全一致 (routines 数组).
    /// ⚠️ 返回的天数/顺序**不保证** == current (LLM 会漂) — caller (DataStore.coachGenerate)
    /// 必须过 reconcileRevisedRoutines 对齐回填, 这里不兜.
    func reviseRoutines(
        payload: AIPayload,
        library: [Exercise],
        current: [Plan],
        feedback: String,
        onlyModify: String? = nil,
        maxExercises: Int = 4,
        surface: String = "coach_chat"
    ) async -> [Plan]? {
        guard Self.isConfigured else {
            state = .failure("AI proxy not configured")
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("not_configured")])
            return nil
        }
        guard !current.isEmpty else { return nil }   // 无基线不叫修订 — caller 走首轮管线
        state = .generating
        // 沿用 ai_routine_generate_* 事件族, mode 区分修订轮. 无 PII: feedback 原文不进 analytics.
        Analytics.shared.track("ai_routine_generate_start", ["surface": .string(surface), "mode": .string("revision")])
        do {
            let spec = RevisionSpec(
                currentBlock: currentRoutinesBlock(current, library: library),
                feedback: feedback,
                onlyModify: onlyModify,
                currentNames: currentExerciseNames(current, library: library)
            )
            let raw = try await callDeepSeekRoutines(
                payload: payload, library: library,
                count: current.count, perRoutine: maxExercises, revision: spec)
            let routines = try parseRoutinesResponse(raw)
            let plans = routines.enumerated().compactMap { (i, r) -> Plan? in
                let plan = buildPlan(from: r, library: library, maxExercises: maxExercises, index: i)
                return plan.steps.isEmpty ? nil : plan
            }
            guard !plans.isEmpty else {
                state = .failure("AI returned no matching exercises")
                Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("empty_match")])
                return nil
            }
            state = .success(Date())
            let totalSteps = plans.reduce(0) { $0 + $1.steps.count }
            Analytics.shared.track("ai_routine_generate_success", [
                "surface": .string(surface), "step_count": .int(totalSteps), "source": .string("ai"),
            ])
            return plans
        } catch let error as AIError {
            state = .failure(error.userMessage)
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string(error.analyticsReason)])
            return nil
        } catch {
            state = .failure(error.localizedDescription)
            Analytics.shared.track("ai_routine_generate_fail", ["surface": .string(surface), "reason": .string("network")])
            return nil
        }
    }

    /// CURRENT ROUTINES 紧凑结构块 — 每天一行: "DAY n — 名称: 动作 sets×reps @kg; …".
    /// 只放结构必需字段 (token 预算); 动作用库内 canonical 英文名 (跟 AVAILABLE EXERCISES 同一
    /// 词汇表, LLM 保留未改动作时能被 buildPlan 精确匹配回来); id 不进 prompt.
    private func currentRoutinesBlock(_ current: [Plan], library: [Exercise]) -> String {
        // 双 key lookup (id + 旧 imageFolder alias) — 跟 DataStore.exById 同思路, 老 plan 步骤也能解析.
        var byId: [String: Exercise] = [:]
        for ex in library {
            byId[ex.id] = ex
            if let folder = ex.imageFolder, byId[folder] == nil { byId[folder] = ex }
        }
        return current.enumerated().map { (i, plan) in
            let steps = plan.steps.map { s -> String in
                let name = byId[s.exerciseId]?.name ?? s.exerciseId
                var line = "\(name) \(s.sets)x\(s.reps.map(String.init) ?? "-")"
                if let w = s.weight, w > 0 { line += " @\(String(format: "%g", w))kg" }
                if let d = s.duration { line += " \(d)s" }
                return line
            }.joined(separator: "; ")
            return "DAY \(i + 1) — \(plan.name): \(steps)"
        }.joined(separator: "\n")
    }

    // MARK: - Free Workout exercise picker (AI-driven)

    /// 给 "自由训练" 自动挑动作 + 排序. 上下文比 generateToday 多一项 `targetMuscles`,
    /// 候选集合也由 caller 预过滤过, 只让 AI 在用户选的肌群范围内挑.
    ///
    /// - parameter payload: 跟 generateToday 一样的 user / history 上下文
    /// - parameter targetMuscles: 用户在 Step 1 选的 major chip (chest / back / ...)
    /// - parameter candidates: 已经按肌群预筛过的动作列表 (~30 项); AI 只能在这堆里选
    /// - returns: 动作 ID 数组, **按 AI 推荐顺序**. 失败 nil.
    func pickFreeWorkoutExercises(
        payload: AIPayload,
        targetMuscles: [String],
        candidates: [Exercise]
    ) async -> [String]? {
        guard Self.isConfigured else {
            state = .failure("AI proxy not configured")
            return nil
        }
        guard !candidates.isEmpty else { return nil }
        state = .generating

        do {
            let raw = try await callDeepSeekForPicker(
                payload: payload,
                targetMuscles: targetMuscles,
                candidates: candidates
            )
            let response = try parsePickerResponse(raw)
            // 用 candidates 的 id set 做校验 — AI 偶尔会返回不在列表里的 ID, 过滤掉
            let validIds = Set(candidates.map(\.id))
            let ordered = response.exerciseIds.filter { validIds.contains($0) }
            guard !ordered.isEmpty else {
                state = .failure("AI returned no valid exercises")
                return nil
            }
            state = .success(Date())
            return ordered
        } catch let error as AIError {
            state = .failure(error.userMessage)
            return nil
        } catch {
            state = .failure(error.localizedDescription)
            return nil
        }
    }

    private func callDeepSeekForPicker(
        payload: AIPayload,
        targetMuscles: [String],
        candidates: [Exercise]
    ) async throws -> String {
        // 走 Cloudflare Worker 代理 — worker 加 DeepSeek API key 转发给 api.deepseek.com.
        // Body / response format 跟 DeepSeek 原生 API 完全一样 (worker 透传).
        let url = URL(string: "\(Self.proxyURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientToken, forHTTPHeaderField: "X-Maso-Client-Token")

        let prompt = buildPickerPrompt(
            payload: payload,
            targetMuscles: targetMuscles,
            candidates: candidates
        )
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "max_tokens": 1024,
            "temperature": 0.6,  // 比 generateToday 稍低 — 选择题, 不需要太多创造性
            "messages": [
                ["role": "system", "content": "You are a fitness coach AI. Output strict JSON only, no prose, no markdown fences."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AIError.network("Bad response type")
        }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIError.api("DeepSeek \(http.statusCode): \(msg.prefix(200))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.api("Could not extract content from DeepSeek response")
        }
        return content
    }

    private func buildPickerPrompt(
        payload: AIPayload,
        targetMuscles: [String],
        candidates: [Exercise]
    ) -> String {
        let p = payload
        let recent = p.recentHistory.isEmpty
            ? "(none yet — this is the user's first week)"
            : p.recentHistory.map { "  • \($0.dateLabel): \($0.planName) (\($0.muscleSummary)) — \($0.setCount) sets" }
                .joined(separator: "\n")
        let strengthen = p.wantStrengthen.isEmpty
            ? "(no specific focus)"
            : p.wantStrengthen.joined(separator: ", ")
        let muscles = targetMuscles.isEmpty ? "(none)" : targetMuscles.joined(separator: ", ")

        // 候选 JSON: 只保留 id / name / category / muscle_groups — 够 AI 判断, prompt 不会爆
        let candidateJSON = candidates.prefix(40).map { ex in
            let mg = ex.muscleGroups.prefix(3).map { $0.rawValue }.joined(separator: ",")
            return """
              {"id": "\(ex.id)", "name": "\(ex.name.replacingOccurrences(of: "\"", with: "'"))", "category": "\(ex.category.rawValue)", "muscles": "\(mg)"}
            """
        }.joined(separator: ",\n")

        return """
        The user is building a "Free Workout" — they picked some muscles to train, you pick the exercises and order.

        USER PROFILE
        - Gender: \(p.gender ?? "unspecified")
        - Age: \(p.age.map(String.init) ?? "unknown")
        - Body weight: \(p.weightKg.map { "\(Int($0)) kg" } ?? "unknown")
        - Training days per week: \(p.daysPerWeek)
        - Wants to strengthen: \(strengthen)

        RECENT WORKOUTS (last 14 days)
        \(recent)

        TARGET MUSCLES (user's selection for this session)
        \(muscles)

        CANDIDATE EXERCISES (pick ONLY from this list, by id)
        [
        \(candidateJSON)
        ]

        TASK
        Pick 5-8 exercises that train the target muscles efficiently. Order them logically:
        - Compound movements before isolation
        - Heavier / more demanding moves first (when energy is high)
        - Vary equipment — avoid 3 back-to-back bench-based moves
        - If recent workouts already hit a muscle hard, skew toward complementary / under-trained ones
        - Respect the "wants to strengthen" focus if there's overlap with target muscles

        OUTPUT
        Strict JSON only, no prose, no markdown. Schema:
        {
          "rationale": "<one-sentence why this order>",
          "exercise_ids": ["<id from candidates>", "<id>", ...]
        }
        Order matters — the array order is the workout order.
        """
    }

    private func parsePickerResponse(_ raw: String) throws -> PickerResponse {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = s.data(using: .utf8) else {
            throw AIError.parse("Could not encode response")
        }
        do {
            return try JSONDecoder().decode(PickerResponse.self, from: data)
        } catch {
            throw AIError.parse("Bad JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - AI Insight Summary (§3)

    /// 生成 Progress→Insights 顶部的"AI 教练小结". 复用跟 generateToday/generateRoutines
    /// 完全相同的 Worker 管道 (proxyURL + X-Maso-Client-Token + deepseek-chat + json_object + isConfigured 门).
    /// 低温 (0.3 — 这是解读不是创作), max_tokens 1024. 所有数字都来自 payload, prompt 严令不许编数字.
    /// - throws: AISummaryError.notConfigured / .network / .api / .parse — caller (DataStore) 捕获后回落本地小结.
    func summarizeTraining(payload: AISummaryPayload) async throws -> AISummary {
        guard Self.isConfigured else {
            state = .failure("AI proxy not configured")
            Analytics.shared.track("ai_summary_generate_fail", ["reason": .string("not_configured")])
            throw AISummaryError.notConfigured
        }
        state = .generating
        Analytics.shared.track("ai_summary_generate_start", [:])
        do {
            let raw = try await callDeepSeekSummary(payload: payload)
            let summary = try parseSummaryResponse(raw)
            state = .success(Date())
            Analytics.shared.track("ai_summary_generate_success", ["rec_count": .int(summary.recommendations.count)])
            return summary
        } catch let error as AISummaryError {
            state = .failure(error.userMessage)
            Analytics.shared.track("ai_summary_generate_fail", ["reason": .string(error.analyticsReason)])
            throw error
        } catch {
            state = .failure(error.localizedDescription)
            Analytics.shared.track("ai_summary_generate_fail", ["reason": .string("network")])
            throw AISummaryError.network(error.localizedDescription)
        }
    }

    private func callDeepSeekSummary(payload: AISummaryPayload) async throws -> String {
        let url = URL(string: "\(Self.proxyURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientToken, forHTTPHeaderField: "X-Maso-Client-Token")

        let (system, user) = buildSummaryPrompt(payload: payload)
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "max_tokens": 1024,
            "temperature": 0.3,   // 解读任务 — 低温, 忠于数据不发散
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "response_format": ["type": "json_object"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw AISummaryError.network("Bad response type") }
            guard (200...299).contains(http.statusCode) else {
                let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
                throw AISummaryError.api("DeepSeek \(http.statusCode): \(msg.prefix(200))")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                throw AISummaryError.api("Could not extract content from DeepSeek response")
            }
            return content
        } catch let e as AISummaryError {
            throw e
        } catch {
            throw AISummaryError.network(error.localizedDescription)
        }
    }

    /// 构造 summary 的 (system, user) prompt. GROUNDING 是全部游戏 (§3):
    /// 严令不许 state 输入里没有的数字、不许命名 topLift/recentPRs 之外的动作、信号薄时明确 hedge.
    private func buildSummaryPrompt(payload: AISummaryPayload) -> (system: String, user: String) {
        let system = """
        You are a strength-training coach. You will be given a JSON summary of ONE athlete's recent training, with all numbers pre-computed.
        RULES — follow every one:
        (1) NEVER state a number that is not present in the input JSON. Do not invent, estimate, or round numbers the input doesn't contain.
        (2) NEVER name an exercise that is not in `topLift.name` or `recentPRs[].exercise`.
        (3) Interpret ONLY what the data shows. If `signal.thin` is true, explicitly hedge (e.g. "only a few sessions logged — treat this as a rough read"). Do not manufacture confidence.
        (4) Do NOT give medical advice or diagnose injuries.
        (5) Output 2–4 recommendations, most important first — prefer the one implied by `diagnosis`.
        (6) Each recommendation MUST pick an `action` from the allowed enum below. Use "regenerate_routines" (with a short focusNote) for anything that means changing the training split/volume; "add_coach_note" (with a note) to persist a standing preference; "none" for pure observations.
        (7) Keep `tldr` to at most 2 sentences, second-person, and tie every claim to a real number from the input. Each recommendation `detail` is one short line.
        Respond ONLY as JSON, no prose, no markdown fences.
        """

        let payloadJSON: String = {
            let enc = JSONEncoder()
            enc.outputFormatting = [.sortedKeys]
            if let d = try? enc.encode(payload), let s = String(data: d, encoding: .utf8) { return s }
            return "{}"
        }()

        let priority = payload.diagnosis.map {
            "The single most important fix is likely: \($0.title) — \($0.detail)."
        } ?? "No single dominant problem was diagnosed; give a balanced read."

        let user = """
        ATHLETE TRAINING SUMMARY (JSON — every number is authoritative, do not recompute):
        \(payloadJSON)

        \(priority)

        ALLOWED action.type values: "regenerate_routines" | "add_coach_note" | "none".
        For "regenerate_routines" include a short English "focusNote" the coach can act on (e.g. "bias the split toward legs").
        For "add_coach_note" include a short "note" (a standing preference to remember).

        OUTPUT — strict JSON only, this exact schema:
        {
          "tldr": "<= 2 sentences, second-person, only cite numbers from the input",
          "recommendations": [
            {
              "id": "<short slug>",
              "title": "<imperative, short>",
              "detail": "<one line — the grounded why>",
              "action": {
                "type": "regenerate_routines | add_coach_note | none",
                "focusNote": "<string or null>",
                "note": "<string or null>"
              }
            }
          ]
        }
        Return 2–4 recommendations, most important first.
        """
        return (system, user)
    }

    /// 解析 summary 响应 — 镜像 parseResponse: 剥 ```json fence → JSONDecoder.
    private func parseSummaryResponse(_ raw: String) throws -> AISummary {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = s.data(using: .utf8) else { throw AISummaryError.parse("Could not encode response") }
        do {
            let resp = try JSONDecoder().decode(AISummaryResponse.self, from: data)
            let recs: [AIRecommendation] = resp.recommendations.enumerated().map { (i, r) in
                AIRecommendation(
                    id: r.id?.isEmpty == false ? r.id! : "rec-\(i)",
                    title: r.title.trimmingCharacters(in: .whitespacesAndNewlines),
                    detail: r.detail.trimmingCharacters(in: .whitespacesAndNewlines),
                    action: r.action ?? .none
                )
            }
            .filter { !$0.title.isEmpty }
            guard !recs.isEmpty else { throw AISummaryError.parse("No recommendations") }
            return AISummary(tldr: resp.tldr.trimmingCharacters(in: .whitespacesAndNewlines), recommendations: recs)
        } catch let e as AISummaryError {
            throw e
        } catch {
            throw AISummaryError.parse("Bad JSON: \(error.localizedDescription)")
        }
    }

    // MARK: - DeepSeek API call (OpenAI-compatible)
    //
    // 切换原因: Anthropic 国内访问不稳定 + 付款不便. DeepSeek 性价比最高的国内 LLM:
    //   - V3.2 价格 ¥0.27/M input (cache hit) / ¥3/M output
    //   - API 完全兼容 OpenAI chat/completions 格式
    //   - 国内访问稳定, 支付宝 / 微信充值
    //   - 支持 response_format=json_object 强制 JSON 输出
    //
    // 想换其它 OpenAI-compatible (Moonshot / 通义 / 智谱) → 只改 endpoint + model.
    private func callDeepSeek(payload: AIPayload, library: [Exercise], maxExercises: Int = 4) async throws -> String {
        // 走 Cloudflare Worker 代理 — 跟 callDeepSeekForPicker 同模式.
        let url = URL(string: "\(Self.proxyURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientToken, forHTTPHeaderField: "X-Maso-Client-Token")

        let prompt = buildPrompt(payload: payload, library: library, maxExercises: maxExercises)
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "max_tokens": 2048,
            "temperature": 0.7,
            "messages": [
                ["role": "system", "content": "You are a fitness coach AI. Output strict JSON only, no prose, no markdown fences."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else {
            throw AIError.network("Bad response type")
        }
        guard (200...299).contains(http.statusCode) else {
            // DeepSeek 错误 body: {"error":{"message":"...","type":"..."}}
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIError.api("DeepSeek \(http.statusCode): \(msg.prefix(200))")
        }
        // OpenAI 标准结构: {"choices":[{"message":{"role":"assistant","content":"..."}}]}
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.api("Could not extract content from DeepSeek response")
        }
        return content
    }

    /// 多套 routine 调用 — 跟 callDeepSeek 同代理/格式, 只是换 multi-routine prompt + 更大 token 预算.
    /// revision 非 nil = Coach 修订轮 (同一 prompt 骨架追加修订块, 见 buildRoutinesPrompt).
    private func callDeepSeekRoutines(payload: AIPayload, library: [Exercise], count: Int, perRoutine: Int, revision: RevisionSpec? = nil) async throws -> String {
        let url = URL(string: "\(Self.proxyURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        // 120s — 全周 routine 的 JSON 输出 (max_tokens 4096) 生成常到 40-60s, 旧值 60 贴线,
        // 网络稍抖 (尤其大陆直连 Cloudflare) 就超时 → "Couldn't reach the AI coach" (owner 实机撞到).
        req.timeoutInterval = 120
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientToken, forHTTPHeaderField: "X-Maso-Client-Token")

        let prompt = buildRoutinesPrompt(payload: payload, library: library, count: count, perRoutine: perRoutine, revision: revision)
        let body: [String: Any] = [
            "model": "deepseek-chat",
            "max_tokens": 4096,                 // N 套 routine 需要更多 token
            "temperature": 0.8,                 // 略高 → 几套之间更有差异
            "messages": [
                ["role": "system", "content": "You are a fitness coach AI. Output strict JSON only, no prose, no markdown fences."],
                ["role": "user", "content": prompt]
            ],
            "response_format": ["type": "json_object"],
        ]
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw AIError.network("Bad response type") }
        guard (200...299).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw AIError.api("DeepSeek \(http.statusCode): \(msg.prefix(200))")
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw AIError.api("Could not extract content from DeepSeek response")
        }
        return content
    }

    // MARK: - Prompt: 动作目录 (基础扩容 + 定向检索)
    //
    // 老问题: 目录 = 每大区 8 个"最短名" canonical (≤48 行, 无肌肉标注) → ① Incline/细分变体
    // 全不在目录, "练上胸"这类细粒度要求 LLM 想服从也无从下手; ② 修订轮 CURRENT ROUTINES 里的
    // 动作不在目录, "其它天保持不变"被迫改名, ONLY MODIFY 语义崩坏. 修法 (三层):
    //   1. 基础目录扩容到每大区 ~15 (仍按 base 名去变体重复), 每行带主练肌英文标注;
    //   2. feedback/onlyModify/focusNote 关键词定向检索 — 命中肌群/器械 → 该目标的全部非 niche
    //      动作并入 (追加上限 ~40, 宁多勿缺; 不命中 = 目录退回基础版, 行为不劣化);
    //   3. 修订轮 mustInclude = current routines 全部动作名 — 保证"不变的天"能逐字复述.

    /// 基础候选池 — 非 niche, 每大区 15 个 canonical (短名优先, 去重 base 名).
    private func baseCandidates(from library: [Exercise]) -> [Exercise] {
        let sections: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]
        var out: [Exercise] = []
        for sec in sections {
            let inSec = library
                .filter { !$0.isNiche && $0.primaryMuscles.contains { ($0.section ?? $0) == sec } }
                .sorted { $0.name.count < $1.name.count }   // 短名 = 更 canonical/常见
            var seenBase = Set<String>()
            var picked = 0
            for ex in inSec {
                let base = baseName(ex.name)
                if seenBase.insert(base).inserted {
                    out.append(ex)
                    picked += 1
                    if picked >= 15 { break }
                }
            }
        }
        return out
    }

    /// 一行目录: "- Bench Press (Incline) — Upper Chest, Triceps". 标注 = 主练肌英文名
    /// (englishName 非本地化 — prompt 是英文语境, zh 设备也不能混中文标注).
    private func catalogLine(_ ex: Exercise) -> String {
        let muscles = ex.primaryMuscles.prefix(3).map(\.englishName).filter { !$0.isEmpty }
        return muscles.isEmpty ? "- \(ex.name)" : "- \(ex.name) — \(muscles.joined(separator: ", "))"
    }

    /// 中英关键词 → 目标肌群 (定向检索). 顺序 = 特异性优先 ("上胸"排"胸"前面 — 两者都会命中,
    /// 但更细的目标先入目录). 泛词 (back/腿) 命中大区全量也可接受 — 宁多勿缺, cap 兜底.
    private static let muscleKeywords: [(keys: [String], targets: [MuscleGroup])] = [
        // 胸
        (["上胸", "incline", "upper chest"], [.upperChest]),
        (["下胸", "decline", "lower chest"], [.lowerChest]),
        (["中胸", "mid chest", "middle chest"], [.midChest]),
        (["胸", "chest", "pec", "卧推", "bench press", "飞鸟"], [.chest]),
        // 肩 (细分在先)
        (["后束", "rear delt", "reverse fly", "face pull", "反向飞鸟"], [.rearDelts]),
        (["前束", "front delt", "front raise", "前平举"], [.frontDelts]),
        (["中束", "侧束", "side delt", "lateral raise", "侧平举"], [.sideDelts]),
        (["肩袖", "rotator cuff"], [.rotatorCuff]),
        (["肩", "shoulder", "delt", "推举", "overhead press"], [.shoulders]),
        // 背
        (["上背", "背阔", "lats", "pulldown", "引体", "pull-up", "pullup", "高位下拉"],
         [.lats, .upperLats, .lowerLats, .rhomboids]),
        (["斜方", "trap", "耸肩", "shrug"], [.upperTraps, .midTraps, .lowerTraps]),
        (["下背", "lower back", "竖脊", "腰部"], [.lowerBack]),
        (["背", "back", "row", "划船"], [.back]),
        // 臂
        (["二头", "bicep", "curl", "弯举"], [.biceps, .brachialis, .brachioradialis]),
        (["三头", "tricep", "臂屈伸", "pushdown", "skullcrusher"], [.triceps]),
        (["小臂", "前臂", "forearm", "握力", "grip", "腕弯举"], [.forearms, .forearmFlexors, .forearmExtensors]),
        (["手臂", "arms"], [.arms]),
        // 核心
        (["腹斜", "oblique", "侧腹"], [.obliques]),
        (["腹", "abs", "卷腹", "crunch", "核心", "core"], [.abs, .upperAbs, .lowerAbs, .obliques]),
        // 腿 (细分在先)
        (["腘绳", "腿后", "hamstring", "leg curl"], [.hamstrings]),
        (["股四", "腿前", "quad", "深蹲", "squat"], [.quads]),
        (["臀", "glute", "hip thrust"], [.glutes, .gluteusMaximus, .gluteusMedius]),
        (["小腿", "calf", "calves", "提踵"], [.calves]),
        (["内收", "adductor", "大腿内侧"], [.adductors]),
        (["腿", "leg"], [.legs]),
    ]

    /// 中英关键词 → 器械 raw token (Exercise.equipment/equipmentAll 的词汇表).
    /// "machine" 放最后 — smith_machine 等含它, 子串匹配语义上也算命中 ("器械"泛指).
    private static let equipmentKeywords: [(keys: [String], targets: [String])] = [
        (["哑铃", "dumbbell"], ["dumbbell"]),
        (["杠铃", "barbell"], ["barbell", "ez_bar"]),
        (["绳索", "龙门", "拉索", "cable"], ["cable"]),
        (["史密斯", "smith"], ["smith_machine"]),
        (["壶铃", "kettlebell"], ["kettlebell"]),
        (["弹力带", "resistance band", "band"], ["band", "resistance_band"]),
        (["自重", "徒手", "bodyweight", "body weight", "no equipment"], ["body_only"]),
        (["器械", "machine"], ["machine"]),
    ]

    /// ex 的主练肌是否命中 target — target 是大区 (chest/legs/...) 时按 section 归并;
    /// 细分 (upperChest/rearDelts/...) 时精确匹配 (数据源 exercises.json 带细分 sub, 能配上).
    private func matches(_ ex: Exercise, muscle target: MuscleGroup) -> Bool {
        ex.primaryMuscles.contains { $0 == target || $0.section == target }
    }

    /// ex 的器械是否命中 target (子串匹配 — "machine" 命中 leg_press_machine 等).
    private func matches(_ ex: Exercise, equipment target: String) -> Bool {
        let eqs = (ex.equipmentAll?.isEmpty == false) ? ex.equipmentAll! : [ex.equipment].compactMap { $0 }
        return eqs.contains { $0 == target || $0.contains(target) }
    }

    /// feedback / onlyModify / focusNote 的定向检索 — 关键词命中肌群/器械 → 该目标的全部
    /// 非 niche 动作 (追加上限 cap). 不命中 → 空数组 (目录退回基础版, 行为不劣化).
    private func targetedCandidates(query: String, library: [Exercise], cap: Int = 40) -> [Exercise] {
        let q = query.lowercased()
        guard !q.isEmpty else { return [] }
        var muscleTargets: [MuscleGroup] = []
        for entry in Self.muscleKeywords where entry.keys.contains(where: { q.contains($0) }) {
            for m in entry.targets where !muscleTargets.contains(m) { muscleTargets.append(m) }
        }
        var equipTargets: [String] = []
        for entry in Self.equipmentKeywords where entry.keys.contains(where: { q.contains($0) }) {
            for e in entry.targets where !equipTargets.contains(e) { equipTargets.append(e) }
        }
        guard !muscleTargets.isEmpty || !equipTargets.isEmpty else { return [] }

        let pool = library.filter { !$0.isNiche }
        var out: [Exercise] = []
        var seen = Set<String>()
        func add(_ ex: Exercise) {
            guard out.count < cap, seen.insert(ex.name).inserted else { return }
            out.append(ex)
        }
        // ① 肌群 × 器械 同时命中最相关 ("哑铃练上胸" → 哑铃上胸动作最先入).
        if !muscleTargets.isEmpty && !equipTargets.isEmpty {
            for m in muscleTargets {
                for ex in pool where matches(ex, muscle: m)
                    && equipTargets.contains(where: { matches(ex, equipment: $0) }) {
                    add(ex)
                }
            }
        }
        // ② 肌群命中 (按特异性顺序 — 细分目标的动作先占 cap).
        for m in muscleTargets {
            for ex in pool where matches(ex, muscle: m) { add(ex) }
        }
        // ③ 只命中器械 (无肌群词, e.g. "只用哑铃") — 该器械动作全量入 (cap 内).
        if muscleTargets.isEmpty {
            for t in equipTargets {
                for ex in pool where matches(ex, equipment: t) { add(ex) }
            }
        }
        return out
    }

    /// 组装 AVAILABLE EXERCISES 目录 (带肌肉标注) = 基础目录 ∪ 定向检索 ∪ mustInclude.
    /// mustInclude = 修订轮 current routines 的动作名 — 必须逐字在目录里, "保持不变的天"才能复述.
    private func catalogBlock(library: [Exercise], query: String?, mustInclude: [String] = []) -> String {
        var seen = Set<String>()
        var lines: [String] = []
        func add(_ ex: Exercise) {
            guard seen.insert(ex.name).inserted else { return }
            lines.append(catalogLine(ex))
        }
        baseCandidates(from: library).forEach(add)
        if let query, !query.isEmpty {
            targetedCandidates(query: query, library: library).forEach(add)
        }
        for name in mustInclude where !seen.contains(name) {
            if let ex = library.first(where: { $0.name == name }) {
                add(ex)
            } else {
                // 库里找不到 (自创已删/旧 id 兜底名) → 裸名入目录, 至少能被逐字复述回来.
                seen.insert(name)
                lines.append("- \(name)")
            }
        }
        return lines.joined(separator: "\n")
    }

    /// current routines 里出现的全部动作名 (canonical, 去重保序) — 修订轮目录 mustInclude 用.
    /// 双 key lookup 跟 currentRoutinesBlock 一致, 保证两块 prompt 用同一词汇表.
    private func currentExerciseNames(_ current: [Plan], library: [Exercise]) -> [String] {
        var byId: [String: Exercise] = [:]
        for ex in library {
            byId[ex.id] = ex
            if let folder = ex.imageFolder, byId[folder] == nil { byId[folder] = ex }
        }
        var seen = Set<String>()
        var out: [String] = []
        for plan in current {
            for s in plan.steps {
                let name = byId[s.exerciseId]?.name ?? s.exerciseId
                if seen.insert(name).inserted { out.append(name) }
            }
        }
        return out
    }

    private func buildPrompt(payload: AIPayload, library: [Exercise], maxExercises: Int = 4) -> String {
        let p = payload
        let recent = p.recentHistory.isEmpty
            ? "(none yet — this is the user's first week)"
            : p.recentHistory.map { "  • \($0.dateLabel): \($0.planName) (\($0.muscleSummary)) — \($0.setCount) sets" }
                .joined(separator: "\n")
        let strengthen = p.wantStrengthen.isEmpty
            ? "(no specific focus)"
            : p.wantStrengthen.joined(separator: ", ")
        // focusNote 走定向检索 — "focus upper chest" 这类侧重能把 Incline 系动作带进目录.
        let catalog = catalogBlock(library: library, query: p.focusNote)

        // ⚠️ GUIDELINES 跟 buildRoutinesPrompt (多 routine) 的科学规则刻意成对镜像 (改一处记得改另一处).
        return """
        You are a fitness coach AI. Generate exactly ONE workout plan for the user to do today.

        USER PROFILE
        - Gender: \(p.gender ?? "unspecified")
        - Age: \(p.age.map(String.init) ?? "unknown")
        - Body weight: \(p.weightKg.map { "\(Int($0)) kg" } ?? "unknown")
        - Training days per week: \(p.daysPerWeek)
        - Wants to strengthen: \(strengthen)
        - Primary goal: \(p.goalLabel)
        - Available equipment: \(p.equipmentLine)\(p.coachMemoryBlock)

        RECENT WORKOUTS (last 14 days)
        \(recent)\(p.bestSetsBlock)

        TODAY IS: \(p.todayDateLabel)

        GUIDELINES
        - Balance muscle groups across the week with >=48h recovery — avoid hitting the same primary muscle as yesterday. At 1-3 days/wk make this a full-body session; at 4-5 days/wk an upper/lower or push/pull split; at 6+ days/wk a Push/Pull/Legs rotation.
        - The session MUST start with a COMPOUND (multi-joint) movement for its primary muscle. NEVER put an isolation exercise in slot 1. Order compound-first, then isolation; within compounds put the heaviest/most technical lift first (squat/deadlift/bench/row/press before machines or single-joint work).
        - Do NOT place an isolation exercise for a small muscle before a compound that uses it as a helper (no curls before rows/pulldowns; no triceps extensions before presses; no lateral raises before overhead press).
        - MUSCLE BALANCE: no more than 2 exercises whose PRIMARY muscle is the same in this session (never 3 chest moves in one day). If two exercises share a primary muscle, they must differ in angle, equipment, or movement plane. Isolation exercises must be at most 40% of the session. Prefer including a pull for every push.
        - This user's goal is \(p.goalLabel). Write COMPOUND lifts at \(p.goalRepCompound)-\(p.goalRepCompoundHi) reps and ISOLATION lifts at \(p.goalRepIso)-\(p.goalRepIsoHi) reps. Use \(p.goalSetsLo)-\(p.goalSetsHi) sets per exercise. Stop ~1-3 reps short of failure (do not write 'to failure').
        - Set "duration_seconds" only for timed holds/cardio; otherwise null. Rest between sets is \(p.goalRest)s (handled by the app).
        - Pick ONLY exercises the user can perform with: \(p.equipmentLine). Pick weights conservatively if no history; scale to recent volume if any.\(p.bestSetsGuideline)\(p.focusNote.map { "\n        - PRIORITY TODAY: \($0). Bias this session to address it directly without breaking the rules above." } ?? "")
        - EXACTLY \(maxExercises) exercises in this session — no more, no fewer.

        AVAILABLE EXERCISES — each line is "- <exercise name> — <its target muscles>". Every "exercise_name" MUST be copied EXACTLY (verbatim, character-for-character) from this list — copy ONLY the name part, NEVER include the "—" or the muscle annotation. Do NOT invent names or use synonyms. When the user asks for a specific muscle (e.g. upper chest, rear delts), you MUST pick exercises whose listed target muscles match it:
        \(catalog)

        OUTPUT
        Strict JSON only, no prose, no markdown. Schema:
        {
          "name": "<session name, ≤ 40 chars>",
          "rationale": "<one-sentence why this plan today>",
          "steps": [
            {
              "exercise_name": "<common gym name>",
              "sets": <int 1-5>,
              "reps": <int 1-20 or null>,
              "weight_kg": <number or null>,
              "duration_seconds": <int or null>
            }
          ]
        }
        """
    }

    /// 多套 routine 的 prompt — 让 LLM 一次产出 count 套组成均衡周分化的 routine, 每套各带 rationale.
    /// revision 非 nil = Coach 修订轮: 同一骨架上插 CURRENT ROUTINES + USER FEEDBACK 块与修订规则
    /// (⚠️ 修订轮不另写 prompt — USER PROFILE / RECENT BEST SETS / 负重进阶硬约束必须原样保留,
    ///  评审红线; 共用 builder 让这些块结构上不可能被落下).
    private func buildRoutinesPrompt(payload: AIPayload, library: [Exercise], count: Int, perRoutine: Int, revision: RevisionSpec? = nil) -> String {
        let p = payload
        let recent = p.recentHistory.isEmpty
            ? "(none yet — this is the user's first week)"
            : p.recentHistory.map { "  • \($0.dateLabel): \($0.planName) (\($0.muscleSummary)) — \($0.setCount) sets" }
                .joined(separator: "\n")
        let strengthen = p.wantStrengthen.isEmpty
            ? "(no specific focus)"
            : p.wantStrengthen.joined(separator: ", ")
        // 定向检索 query = focusNote (首轮侧重) + 修订轮 feedback/onlyModify — 命中"上胸/后束/哑铃"
        // 这类细粒度词时把对应动作全量带进目录; 修订轮再并入 current 动作名 (mustInclude).
        let retrievalQuery = [p.focusNote, revision?.feedback, revision?.onlyModify]
            .compactMap { $0 }
            .joined(separator: " ")
        let catalog = catalogBlock(library: library, query: retrievalQuery,
                                   mustInclude: revision?.currentNames ?? [])

        // 修订块 — 插在 RECENT WORKOUTS 之后 (上下文区), 规则行追加在 GUIDELINES 开头 (优先级最高).
        let revisionContext: String = revision.map { r in
            """
            \n
            CURRENT ROUTINES (the user's existing weekly plan — you are REVISING these, NOT starting over)
            \(r.currentBlock)

            USER FEEDBACK (the revision request)
            "\(r.feedback)"
            """
        } ?? ""
        let revisionRules: String = revision.map { r in
            var rules = "\n        - REVISION MODE: apply USER FEEDBACK to CURRENT ROUTINES. Return ALL \(count) days. Any day or exercise the feedback does not mention must stay IDENTICAL to CURRENT ROUTINES (same exercises, sets, reps, weights). Keep each day's \"name\" unchanged unless the feedback asks to rename it."
            if let only = r.onlyModify, !only.isEmpty {
                // 只返回改动的天 (不再复述全周) — 修订输出砍 3-4 倍 = 延迟砍 3-4 倍
                // (owner 实机撞 60s 超时的主因是全周 JSON 输出太长); 未返回的天由
                // reconcileRevisedRoutines 用上一版回填. name 必须原样保留 — 对齐靠名称匹配.
                rules += "\n        - ONLY MODIFY \(only). Return ONLY the routine(s) you actually changed — do NOT repeat unchanged days (the app keeps them as-is). Keep each returned routine's \"name\" EXACTLY as it appears in CURRENT ROUTINES."
            }
            return rules
        } ?? ""

        // ⚠️ GUIDELINES 跟 buildPrompt (单 Today plan) 的科学规则刻意成对镜像 (改一处记得改另一处)
        //    — 编译期无法强约束两者一致, 故并排放, 靠 enforceScience() 在代码侧兜底真正落实硬规则.
        return """
        You are a fitness coach AI. Generate exactly \(count) DISTINCT workout routines that together form one balanced weekly training split for this user.

        USER PROFILE
        - Gender: \(p.gender ?? "unspecified")
        - Age: \(p.age.map(String.init) ?? "unknown")
        - Body weight: \(p.weightKg.map { "\(Int($0)) kg" } ?? "unknown")
        - Training days per week: \(p.daysPerWeek)
        - Wants to strengthen: \(strengthen)
        - Primary goal: \(p.goalLabel)
        - Available equipment: \(p.equipmentLine)\(p.coachMemoryBlock)

        RECENT WORKOUTS (last 14 days)
        \(recent)\(p.bestSetsBlock)\(revisionContext)

        GUIDELINES\(revisionRules)
        - The \(count) routines MUST together form a balanced weekly split with >=48h before the same muscle is trained hard again. Use Push/Pull/Legs only at 5-6 days, Upper/Lower at 4 days, and full-body A/B/C at <=3 days. Never output \(count) near-copies.
        - Every routine MUST start with a COMPOUND (multi-joint) movement for its primary muscle. NEVER put an isolation exercise in slot 1. Order each routine compound-first, then isolation; within compounds put the heaviest/most technical lift first (squat/deadlift/bench/row/press before machines or single-joint work).
        - Do NOT place an isolation exercise for a small muscle before a compound that uses it as a helper (no curls before rows/pulldowns; no triceps extensions before presses; no lateral raises before overhead press).
        - MUSCLE BALANCE: no more than 2 exercises whose PRIMARY muscle is the same in one routine (never 3 chest moves in one day). If two exercises share a primary muscle, they must differ in angle, equipment, or movement plane — no two near-identical presses. Isolation exercises must be at most 40% of each routine.
        - PUSH/PULL BALANCE across the week: total pulling exercises MUST be >= pushing exercises (never let pushes exceed pulls by more than ~20%). Each week must include both a knee-dominant (squat/leg press) and a hip-dominant (hinge/RDL/deadlift) movement.
        - This user's goal is \(p.goalLabel). Write COMPOUND lifts at \(p.goalRepCompound)-\(p.goalRepCompoundHi) reps and ISOLATION lifts at \(p.goalRepIso)-\(p.goalRepIsoHi) reps. Use \(p.goalSetsLo)-\(p.goalSetsHi) sets per exercise. Stop ~1-3 reps short of failure (do not write 'to failure').
        - Set "duration_seconds" only for timed holds/cardio; otherwise null. Rest between sets is \(p.goalRest)s (handled by the app).
        - Pick ONLY exercises the user can perform with: \(p.equipmentLine). Pick weights conservatively if no history; scale to recent volume if any.\(p.bestSetsGuideline)
        - Respect the "wants to strengthen" focus by giving those muscles an extra exercise / earlier slot where it fits, without breaking the rules above.\(p.focusNote.map { "\n        - PRIORITY THIS TIME (OVERRIDES the profile): \($0). This is what the user just asked for in their own words — when it conflicts with the profile's equipment / focus-muscle defaults above, THIS wins (e.g. 'dumbbells only' beats the profile equipment list; 'upper body' beats a profile legs focus). Skew the split, equipment picks and volume to address it directly. Only the safety/balance rules and the exercise catalog stay non-negotiable." } ?? "")
        - EXACTLY \(perRoutine) exercises in EVERY routine — no more, no fewer.

        AVAILABLE EXERCISES — each line is "- <exercise name> — <its target muscles>". Every "exercise_name" MUST be copied EXACTLY (verbatim, character-for-character) from this list — copy ONLY the name part, NEVER include the "—" or the muscle annotation. Do NOT invent names or use synonyms. When the user asks for a specific muscle (e.g. upper chest, rear delts), you MUST pick exercises whose listed target muscles match it:
        \(catalog)

        OUTPUT
        Strict JSON only, no prose, no markdown. Schema:
        {
          "routines": [
            {
              "name": "<routine name, ≤ 40 chars>",
              "rationale": "<one sentence: what this routine targets / why>",
              "steps": [
                { "exercise_name": "<from list>", "sets": <int 1-5>, "reps": <int 1-20 or null>, "weight_kg": <number or null>, "duration_seconds": <int or null> }
              ]
            }
          ]
        }
        Return exactly \(count) routines in the "routines" array, and each routine's "steps" array MUST contain exactly \(perRoutine) items.
        """
    }

    // MARK: - Response parsing

    private func parseResponse(_ raw: String) throws -> AIResponse {
        // LLM 有时会 wrap 在 ```json ... ``` 里, 先剥壳
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = s.data(using: .utf8) else {
            throw AIError.parse("Could not encode response")
        }
        do {
            return try JSONDecoder().decode(AIResponse.self, from: data)
        } catch {
            throw AIError.parse("Bad JSON: \(error.localizedDescription)")
        }
    }

    /// 解析多套 routine 响应 — 先试 {"routines":[...]}, 再退一步试裸数组 [...] (LLM 偶尔不裹外层).
    private func parseRoutinesResponse(_ raw: String) throws -> [AIResponse] {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.replacingOccurrences(of: "```json", with: "")
                 .replacingOccurrences(of: "```", with: "")
                 .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard let data = s.data(using: .utf8) else { throw AIError.parse("Could not encode response") }
        if let wrapped = try? JSONDecoder().decode(AIRoutinesResponse.self, from: data) {
            return wrapped.routines
        }
        if let bare = try? JSONDecoder().decode([AIResponse].self, from: data) {
            return bare
        }
        throw AIError.parse("Bad JSON: expected {\"routines\":[...]}")
    }

    // MARK: - Build Plan

    private func buildPlan(from r: AIResponse, library: [Exercise], maxExercises: Int = 4, index: Int = 0) -> Plan {
        let now = Date()
        var steps: [PlanStep] = []
        for (i, s) in r.steps.enumerated() {
            guard let ex = matchExercise(s.exerciseName, library: library) else { continue }
            steps.append(PlanStep(
                id: "ai-step-\(i)-\(ex.id)",
                exerciseId: ex.id,
                sets: max(1, min(5, s.sets)),
                reps: s.reps.map { max(1, min(50, $0)) },
                weight: s.weightKg.map { max(0, min(500, $0)) },
                duration: s.durationSeconds.map { max(5, min(600, $0)) },
                restBetweenSets: 90,
                rest: 0
            ))
        }
        // 保底: 即使 prompt 失效, 客户端也强制截到 4. 跟 RecommendedPrograms 的
        // kMaxStepsPerRecommendedPlan 同一节奏 — "今日训练" 不应该是 marathon.
        // P3: 尊重用户的 exercisesPerSession (1-6), 不再硬截 4.
        let capped = Array(steps.prefix(max(1, min(8, maxExercises))))   // 8 = exercisesPerSession 上限, 别把 7/8 砍到 6
        return Plan(
            id: "plan-ai-\(Int(now.timeIntervalSince1970))-\(index)",   // index → 同秒生成的多套 routine id 不撞
            name: r.name.isEmpty ? "AI Workout" : r.name,
            steps: capped,
            createdAt: now,
            updatedAt: now,
            // P1-2: 标 autoGenerated → 训练中编辑后, 完成屏的 canSaveCurrentPlan 命中,
            // 给出 "Save as plan" 按钮. 否则 AI plan 既不在 data.plans 又非 autoGenerated,
            // 编辑全丢且无任何保存入口.
            autoGenerated: true,
            lastUsedAt: nil,
            source: .ai,           // → routine 列表挂 AI 标签 (savePlan 保存时沿用)
            rationale: r.rationale?.trimmingCharacters(in: .whitespacesAndNewlines)  // LLM 给的"为什么这么排" — 露在卡上
        )
    }

    /// 几个 AI 常用但新库没有的叫法 → 映射到新库的等价名 (word-level, 安全).
    private static let nameSynonyms: [String: String] = [
        "bent over row": "barbell row",       // 新库无 "Bent-Over Row"
        "shoulder press": "overhead press",   // 新库用 "Overhead Press"
        "pec deck": "chest fly machine",
    ]

    /// Fuzzy match 一个 "common name" 到 library 里的 Exercise.
    /// 三段: 完全相等 → token 集合包含 → Jaccard.
    ///
    /// ⚠️ 新库动作名是 "Bicep Curl (Dumbbell)" / "Leg Press (45°)" 这种带括号变体, 旧的"子串包含"
    /// 策略会乱配 (e.g. "Leg Press" → "Calf Raise (Leg Press)"). 改成 token 集合包含, 并优先
    /// base 名 (括号前) 跟 query 相等的, 这样 "Leg Press" → "Leg Press (45°)".
    private func matchExercise(_ name: String, library: [Exercise]) -> Exercise? {
        var norm = normalize(name)
        for (k, v) in Self.nameSynonyms where norm.contains(k) {
            norm = norm.replacingOccurrences(of: k, with: v)
        }
        let q = tokenSet(norm)
        // 1. 完全相等 (多个时取名字最短的 = 最 canonical)
        let exacts = library.filter { normalize($0.name) == norm }
        if !exacts.isEmpty { return exacts.min { $0.name.count < $1.name.count } }
        // 2. token 集合包含 (q ⊆ et 或 et ⊆ q). 排序键: base==query 优先 → token 数差小 →
        //    不带括号优先 → 名字短.
        var best: Exercise? = nil
        var bestKey = (2, Int.max, 9, Int.max)
        for ex in library {
            let et = tokenSet(normalize(ex.name))
            guard q.isSubset(of: et) || et.isSubset(of: q) else { continue }
            let key = (baseName(ex.name) == norm ? 0 : 1,
                       abs(et.count - q.count),
                       ex.name.contains("(") ? 1 : 0,
                       ex.name.count)
            if key < bestKey { bestKey = key; best = ex }
        }
        if let best { return best }
        // 3. Jaccard ≥ 0.5 (比旧的 0.35 严, 减少乱配)
        var jBest: Exercise? = nil
        var jScore = 0.0
        for ex in library {
            let et = tokenSet(normalize(ex.name))
            let inter = q.intersection(et).count
            let uni = q.union(et).count
            let score = uni == 0 ? 0 : Double(inter) / Double(uni)
            if score > jScore { jScore = score; jBest = ex }
        }
        return jScore >= 0.5 ? jBest : nil
    }

    /// 名字里第一个 "(" 之前的部分, normalize 后 — 给"base 名相等"判断用.
    private func baseName(_ s: String) -> String {
        normalize(String(s.prefix { $0 != "(" }))
    }
    /// normalize → 切 token → 去尾 s (单复数归一: triceps/tricep, rows/row).
    private func tokenSet(_ norm: String) -> Set<String> {
        Set(norm.split(separator: " ").map { stem(String($0)) })
    }
    private func stem(_ t: String) -> String {
        (t.count > 3 && t.hasSuffix("s")) ? String(t.dropLast()) : t
    }

    private func normalize(_ s: String) -> String {
        var r = s.lowercased()
        for (a, b) in [("_", " "), ("-", " "), (".", ""), (",", ""), ("(", " "), (")", " "), ("/", " ")] {
            r = r.replacingOccurrences(of: a, with: b)
        }
        r = r.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return r.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Payload

/// 发给 AI 的用户数据快照
struct AIPayload {
    let gender: String?
    let age: Int?
    let weightKg: Double?
    let daysPerWeek: Int
    let wantStrengthen: [String]  // muscle display names
    let recentHistory: [HistoryEntry]
    /// 近 14 天每个练过动作的最佳组 ("Bench Press: 80kg×8", canonical 英文名) — DataStore.buildAIPayload
    /// 按 e1RM 挑选注入, 上限 ~20 条. 非空时 prompt 注 RECENT BEST SETS 块 + 负重进阶硬约束
    /// (P0#1-②: 否则 LLM 对 weight_kg 只能盲猜, 练 5 年的人看到卧推 55kg 一眼判死).
    let recentBestSets: [String]
    let todayDateLabel: String

    // --- 目标驱动的科学化字段 (DataStore.buildAIPayload 从 settings.trainingGoalKind 派生) ---
    /// 用户面目标显示名, e.g. "Build muscle" — 注进 prompt 的 GOAL 行 + rep 指引.
    let goalLabel: String
    /// 复合动作 rep band 下/上限 (从 loading 档 rep 表 ± 小区间).
    let goalRepCompound: Int
    let goalRepCompoundHi: Int
    /// 孤立动作 rep band 下/上限.
    let goalRepIso: Int
    let goalRepIsoHi: Int
    /// 每动作组数 band (defaultSetsPerExercise 上下浮动).
    let goalSetsLo: Int
    let goalSetsHi: Int
    /// 该目标推荐组间歇 (秒).
    let goalRest: Int
    /// 可用器械 (EquipmentCategory display names). 空 = 不限制.
    let equipment: [String]

    /// 本次生成的优先侧重 (optimize 建议卡注入) — e.g. "bias the split toward legs".
    /// 非空时往 GUIDELINES 末尾追加一条强优先级行, 让这次 routine 偏向修复诊断出的问题. 默认 nil = 不加.
    var focusNote: String? = nil

    /// 教练记忆 (Coaching Memory) — 用户长期沉淀的自然语言偏好 / 限制 (DataStore 从 settings.coachMemory 注入).
    /// 非空时往 USER PROFILE / GUIDELINES 区注一块, 让 AI 每次生成都遵守. 默认 nil = 不加.
    var coachMemory: String? = nil

    /// prompt 里"可用器械"那行的成文 — 空时给"no restriction — assume a full gym".
    var equipmentLine: String {
        equipment.isEmpty
            ? "no restriction — assume a full gym"
            : equipment.joined(separator: ", ")
    }

    /// 注进 prompt 的"最佳组"块 — 非空时跟在 RECENT WORKOUTS 后面 (含换行前缀), 空时 "".
    var bestSetsBlock: String {
        guard !recentBestSets.isEmpty else { return "" }
        return "\n\nRECENT BEST SETS (the user's actual best working set per exercise, last 14 days)\n"
            + recentBestSets.map { "  • \($0)" }.joined(separator: "\n")
    }

    /// 负重进阶硬约束 — 只在有历史最佳组时注入 GUIDELINES (跟 bestSetsBlock 成对出现).
    /// 0~+2.5kg 微进阶 + 偏差 ≤10%: 让 weight_kg 从盲猜变成基于真实负重的 progression.
    var bestSetsGuideline: String {
        guard !recentBestSets.isEmpty else { return "" }
        return "\n        - WEIGHT PROGRESSION: for every exercise listed in RECENT BEST SETS, \"weight_kg\" MUST be based on that recorded set — keep the same weight or add a small progression of 0 to +2.5 kg, and NEVER deviate more than 10% from the recorded weight. Guess weights ONLY for exercises with no recorded set."
    }

    /// 注进 prompt 的教练记忆块 — 非空时返回完整段落 (含换行前缀), 空时返回 "".
    /// 截到最后 ~1200 字符 (留近期最新的偏好), 避免长记忆把 prompt 撑爆.
    var coachMemoryBlock: String {
        guard let raw = coachMemory?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return "" }
        let capped = raw.count > 1200 ? String(raw.suffix(1200)) : raw
        return "\n\nCOACH NOTES — the user's standing preferences/constraints, ALWAYS respect these unless they conflict with safety:\n\(capped)"
    }

    struct HistoryEntry {
        let dateLabel: String
        let planName: String
        let muscleSummary: String
        let setCount: Int
    }
}

// MARK: - Response types

private struct AIResponse: Codable {
    let name: String
    let rationale: String?
    let steps: [AIStep]
}

/// 多套 routine 响应外层 — {"routines": [AIResponse, ...]}.
private struct AIRoutinesResponse: Codable {
    let routines: [AIResponse]
}

private struct AIStep: Codable {
    let exerciseName: String
    let sets: Int
    let reps: Int?
    let weightKg: Double?
    let durationSeconds: Int?

    enum CodingKeys: String, CodingKey {
        case exerciseName = "exercise_name"
        case sets
        case reps
        case weightKg = "weight_kg"
        case durationSeconds = "duration_seconds"
    }
}

/// AI 教练小结的解析壳 — 对应 §3 output schema. action 复用 AISummaryAction 的
/// 自定义 Decodable (未知 type 降级 .none / add_sets 折叠成 regenerate_routines).
private struct AISummaryResponse: Codable {
    let tldr: String
    let recommendations: [Rec]
    struct Rec: Codable {
        let id: String?
        let title: String
        let detail: String
        let action: AISummaryAction?
    }
}

/// Free-workout picker 的 AI 响应 — 只要 ordered ID 列表 (动作信息已在客户端 library 里).
private struct PickerResponse: Codable {
    let rationale: String?
    let exerciseIds: [String]

    enum CodingKeys: String, CodingKey {
        case rationale
        case exerciseIds = "exercise_ids"
    }
}

// MARK: - Errors

private enum AIError: Error {
    case network(String)
    case api(String)
    case parse(String)

    var userMessage: String {
        switch self {
        case .network(let m), .api(let m), .parse(let m): return m
        }
    }

    /// 分析事件 reason (无 PII 枚举) — 映射到 ai_routine_generate_fail 的 reason 字段.
    var analyticsReason: String {
        switch self {
        case .network: return "network"
        case .api: return "api"
        case .parse: return "parse"
        }
    }
}

/// summarizeTraining 的错误 — 非 private, 让 DataStore.generateSummary() 能捕获后回落本地小结.
/// (AIError 是 private 只服务 routine 生成; summary 单独一套, 语义一致.)
enum AISummaryError: Error {
    case notConfigured
    case network(String)
    case api(String)
    case parse(String)

    var userMessage: String {
        switch self {
        case .notConfigured: return "AI proxy not configured"
        case .network(let m), .api(let m), .parse(let m): return m
        }
    }

    var analyticsReason: String {
        switch self {
        case .notConfigured: return "not_configured"
        case .network: return "network"
        case .api: return "api"
        case .parse: return "parse"
        }
    }
}
