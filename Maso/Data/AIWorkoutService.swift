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
//   1. 去 https://console.anthropic.com 拿 API key
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
        library: [Exercise]
    ) async -> Plan? {
        guard Self.isConfigured else {
            state = .failure("AI proxy not configured (set MasoAIProxyURL + MasoClientToken in Secrets.xcconfig)")
            return nil
        }
        state = .generating

        do {
            let raw = try await callDeepSeek(payload: payload)
            let parsed = try parseResponse(raw)
            let plan = buildPlan(from: parsed, library: library)
            guard !plan.steps.isEmpty else {
                state = .failure("AI returned no matching exercises")
                return nil
            }
            state = .success(Date())
            return plan
        } catch let error as AIError {
            state = .failure(error.userMessage)
            return nil
        } catch {
            state = .failure(error.localizedDescription)
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

    // MARK: - DeepSeek API call (OpenAI-compatible)
    //
    // 切换原因: Anthropic 国内访问不稳定 + 付款不便. DeepSeek 性价比最高的国内 LLM:
    //   - V3.2 价格 ¥0.27/M input (cache hit) / ¥3/M output
    //   - API 完全兼容 OpenAI chat/completions 格式
    //   - 国内访问稳定, 支付宝 / 微信充值
    //   - 支持 response_format=json_object 强制 JSON 输出
    //
    // 想换其它 OpenAI-compatible (Moonshot / 通义 / 智谱) → 只改 endpoint + model.
    private func callDeepSeek(payload: AIPayload) async throws -> String {
        // 走 Cloudflare Worker 代理 — 跟 callDeepSeekForPicker 同模式.
        let url = URL(string: "\(Self.proxyURL)/v1/chat/completions")!
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.timeoutInterval = 45
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(Self.clientToken, forHTTPHeaderField: "X-Maso-Client-Token")

        let prompt = buildPrompt(payload: payload)
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

    // MARK: - Prompt

    private func buildPrompt(payload: AIPayload) -> String {
        let p = payload
        let recent = p.recentHistory.isEmpty
            ? "(none yet — this is the user's first week)"
            : p.recentHistory.map { "  • \($0.dateLabel): \($0.planName) (\($0.muscleSummary)) — \($0.setCount) sets" }
                .joined(separator: "\n")
        let strengthen = p.wantStrengthen.isEmpty
            ? "(no specific focus)"
            : p.wantStrengthen.joined(separator: ", ")

        return """
        You are a fitness coach AI. Generate exactly ONE workout plan for the user to do today.

        USER PROFILE
        - Gender: \(p.gender ?? "unspecified")
        - Age: \(p.age.map(String.init) ?? "unknown")
        - Body weight: \(p.weightKg.map { "\(Int($0)) kg" } ?? "unknown")
        - Training days per week: \(p.daysPerWeek)
        - Wants to strengthen: \(strengthen)

        RECENT WORKOUTS (last 14 days)
        \(recent)

        TODAY IS: \(p.todayDateLabel)

        GUIDELINES
        - Balance muscle groups across the week — avoid hitting the same primary muscle as yesterday
        - 1–3 days/wk → full-body (chest + back + legs + small accessory)
        - 4–5 days/wk → 1–2 major muscle groups per session + accessory
        - 6+ days/wk → Push / Pull / Legs split rotation
        - 4–7 exercises per session
        - Sets 3–4, reps 6–12 for strength; reps 12–15 for accessory
        - Pick weights conservative if no history; scale to recent volume if any
        - Use real, common exercise names (e.g. "Barbell Squat", "Bench Press", "Pull-up", "Bent-Over Row", "Standing Overhead Press", "Dumbbell Bicep Curl", "Romanian Deadlift", "Lat Pulldown", "Plank")

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

    // MARK: - Build Plan

    private func buildPlan(from r: AIResponse, library: [Exercise]) -> Plan {
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
        return Plan(
            id: "plan-ai-\(Int(now.timeIntervalSince1970))",
            name: r.name.isEmpty ? "AI Workout" : r.name,
            steps: steps,
            createdAt: now,
            updatedAt: now
        )
    }

    /// Fuzzy match 一个 "common name" 到 library 里的 Exercise.
    /// 三段策略: 完全相等 → 子串包含 → token Jaccard.
    private func matchExercise(_ name: String, library: [Exercise]) -> Exercise? {
        let norm = normalize(name)
        // Exact
        if let exact = library.first(where: { normalize($0.name) == norm }) { return exact }
        // Contains (一方包另一方)
        if let sub = library.first(where: {
            let exN = normalize($0.name)
            return exN.contains(norm) || norm.contains(exN)
        }) { return sub }
        // Jaccard
        let qTok = Set(norm.split(separator: " ").map(String.init))
        var best: Exercise? = nil
        var bestScore = 0.0
        for ex in library {
            let exTok = Set(normalize(ex.name).split(separator: " ").map(String.init))
            let inter = qTok.intersection(exTok).count
            let uni = qTok.union(exTok).count
            let score = uni == 0 ? 0 : Double(inter) / Double(uni)
            if score > bestScore { bestScore = score; best = ex }
        }
        return bestScore > 0.35 ? best : nil
    }

    private func normalize(_ s: String) -> String {
        s.lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
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
}
