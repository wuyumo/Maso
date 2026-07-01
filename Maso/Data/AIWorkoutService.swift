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
    private func callDeepSeekRoutines(payload: AIPayload, library: [Exercise], count: Int, perRoutine: Int) async throws -> String {
        let url = URL(string: "\(Self.proxyURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 60
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientToken, forHTTPHeaderField: "X-Maso-Client-Token")

        let prompt = buildRoutinesPrompt(payload: payload, library: library, count: count, perRoutine: perRoutine)
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

    // MARK: - Prompt

    /// 给 generateToday 的候选动作池 — 非 niche, 每大区取若干 canonical (短名优先, 去重 base 名).
    /// LLM 只能从这堆真实库内动作名里选, 保证 buildPlan 能精确匹配 (修掉自由命名→匹配落空的老问题).
    private func candidateNames(from library: [Exercise]) -> [String] {
        let sections: [MuscleGroup] = [.chest, .back, .shoulders, .arms, .core, .legs]
        var out: [String] = []
        for sec in sections {
            let inSec = library
                .filter { !$0.isNiche && $0.primaryMuscles.contains { ($0.section ?? $0) == sec } }
                .sorted { $0.name.count < $1.name.count }   // 短名 = 更 canonical/常见
            var seenBase = Set<String>()
            var picked = 0
            for ex in inSec {
                let base = baseName(ex.name)
                if seenBase.insert(base).inserted {
                    out.append(ex.name)
                    picked += 1
                    if picked >= 8 { break }
                }
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
        let catalog = candidateNames(from: library).map { "- \($0)" }.joined(separator: "\n")

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
        \(recent)

        TODAY IS: \(p.todayDateLabel)

        GUIDELINES
        - Balance muscle groups across the week with >=48h recovery — avoid hitting the same primary muscle as yesterday. At 1-3 days/wk make this a full-body session; at 4-5 days/wk an upper/lower or push/pull split; at 6+ days/wk a Push/Pull/Legs rotation.
        - The session MUST start with a COMPOUND (multi-joint) movement for its primary muscle. NEVER put an isolation exercise in slot 1. Order compound-first, then isolation; within compounds put the heaviest/most technical lift first (squat/deadlift/bench/row/press before machines or single-joint work).
        - Do NOT place an isolation exercise for a small muscle before a compound that uses it as a helper (no curls before rows/pulldowns; no triceps extensions before presses; no lateral raises before overhead press).
        - MUSCLE BALANCE: no more than 2 exercises whose PRIMARY muscle is the same in this session (never 3 chest moves in one day). If two exercises share a primary muscle, they must differ in angle, equipment, or movement plane. Isolation exercises must be at most 40% of the session. Prefer including a pull for every push.
        - This user's goal is \(p.goalLabel). Write COMPOUND lifts at \(p.goalRepCompound)-\(p.goalRepCompoundHi) reps and ISOLATION lifts at \(p.goalRepIso)-\(p.goalRepIsoHi) reps. Use \(p.goalSetsLo)-\(p.goalSetsHi) sets per exercise. Stop ~1-3 reps short of failure (do not write 'to failure').
        - Set "duration_seconds" only for timed holds/cardio; otherwise null. Rest between sets is \(p.goalRest)s (handled by the app).
        - Pick ONLY exercises the user can perform with: \(p.equipmentLine). Pick weights conservatively if no history; scale to recent volume if any.\(p.focusNote.map { "\n        - PRIORITY TODAY: \($0). Bias this session to address it directly without breaking the rules above." } ?? "")
        - EXACTLY \(maxExercises) exercises in this session — no more, no fewer.

        AVAILABLE EXERCISES — every "exercise_name" MUST be copied EXACTLY (verbatim, character-for-character) from this list. Do NOT invent names or use synonyms:
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
    private func buildRoutinesPrompt(payload: AIPayload, library: [Exercise], count: Int, perRoutine: Int) -> String {
        let p = payload
        let recent = p.recentHistory.isEmpty
            ? "(none yet — this is the user's first week)"
            : p.recentHistory.map { "  • \($0.dateLabel): \($0.planName) (\($0.muscleSummary)) — \($0.setCount) sets" }
                .joined(separator: "\n")
        let strengthen = p.wantStrengthen.isEmpty
            ? "(no specific focus)"
            : p.wantStrengthen.joined(separator: ", ")
        let catalog = candidateNames(from: library).map { "- \($0)" }.joined(separator: "\n")

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
        \(recent)

        GUIDELINES
        - The \(count) routines MUST together form a balanced weekly split with >=48h before the same muscle is trained hard again. Use Push/Pull/Legs only at 5-6 days, Upper/Lower at 4 days, and full-body A/B/C at <=3 days. Never output \(count) near-copies.
        - Every routine MUST start with a COMPOUND (multi-joint) movement for its primary muscle. NEVER put an isolation exercise in slot 1. Order each routine compound-first, then isolation; within compounds put the heaviest/most technical lift first (squat/deadlift/bench/row/press before machines or single-joint work).
        - Do NOT place an isolation exercise for a small muscle before a compound that uses it as a helper (no curls before rows/pulldowns; no triceps extensions before presses; no lateral raises before overhead press).
        - MUSCLE BALANCE: no more than 2 exercises whose PRIMARY muscle is the same in one routine (never 3 chest moves in one day). If two exercises share a primary muscle, they must differ in angle, equipment, or movement plane — no two near-identical presses. Isolation exercises must be at most 40% of each routine.
        - PUSH/PULL BALANCE across the week: total pulling exercises MUST be >= pushing exercises (never let pushes exceed pulls by more than ~20%). Each week must include both a knee-dominant (squat/leg press) and a hip-dominant (hinge/RDL/deadlift) movement.
        - This user's goal is \(p.goalLabel). Write COMPOUND lifts at \(p.goalRepCompound)-\(p.goalRepCompoundHi) reps and ISOLATION lifts at \(p.goalRepIso)-\(p.goalRepIsoHi) reps. Use \(p.goalSetsLo)-\(p.goalSetsHi) sets per exercise. Stop ~1-3 reps short of failure (do not write 'to failure').
        - Set "duration_seconds" only for timed holds/cardio; otherwise null. Rest between sets is \(p.goalRest)s (handled by the app).
        - Pick ONLY exercises the user can perform with: \(p.equipmentLine). Pick weights conservatively if no history; scale to recent volume if any.
        - Respect the "wants to strengthen" focus by giving those muscles an extra exercise / earlier slot where it fits, without breaking the rules above.\(p.focusNote.map { "\n        - PRIORITY THIS TIME: \($0). Skew this week's split to address it directly (more volume / earlier slots / an extra movement) without breaking the rules above." } ?? "")
        - EXACTLY \(perRoutine) exercises in EVERY routine — no more, no fewer.

        AVAILABLE EXERCISES — every "exercise_name" MUST be copied EXACTLY (verbatim, character-for-character) from this list. Do NOT invent names or use synonyms:
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
