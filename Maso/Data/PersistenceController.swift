import Foundation

/// 数据持久化层 — file-based JSON, 不引入 SwiftData refactor 风险.
///
/// ## 为什么用 file-based 而不是 SwiftData
/// 现有 Plan / PlanStep / SetRecord / UserSettings 都是 `Codable struct Sendable`.
/// 改成 `@Model class` 涉及 59+ 处调用点的"值类型 → 引用类型"语义变更, 风险高.
/// JSON 文件方案: 一行 encode/decode, 跟现有结构零冲突.
///
/// ## 设备迁移怎么走
/// 1. 文件存在 `Documents/maso-data.json`
/// 2. iOS 自动把 `Documents/` 纳入 **iCloud Backup**
/// 3. 用户买新手机 → "从 iCloud Backup 恢复" → 文件回来 → Maso 加载, 数据完整
/// 4. **不需要 Maso 内做任何特殊操作** — iOS 标准流程
///
/// ## 多设备实时同步 (P1)
/// 后续做 CloudKit / iCloud Drive ubiquity 时, 把 `path` 切到 ubiquity container 路径即可.
/// 这层逻辑封装在 `currentURL`, swap 一行就完事.
///
/// ## 文件格式
/// 单个 JSON 文件, schema:
/// ```json
/// {
///   "version": 1,
///   "plans": [...],
///   "sets": [...],
///   "settings": {...},
///   "aiTodayPlan": {...} | null,
///   "lastAIRefreshAt": "2026-05-16T..." | null,
///   "updatedAt": "..."
/// }
/// ```
/// version 字段给未来 schema migration 用.
struct PersistenceController {
    static let shared = PersistenceController()

    /// 当前 schema 版本. 改 model 时一起 bump, decode 失败兜底走 mock.
    static let schemaVersion = 1

    /// 数据文件路径 — Documents 目录, 被 iCloud Backup 默认覆盖
    ///
    /// **TODO[deploy-cloudkit-sync]**: 升级到 iCloud Drive ubiquity container (多设备实时同步).
    /// 具体步骤见 `docs/cloudkit-todo.md`. 改动点就在这一个 computed property:
    /// ```swift
    /// var currentURL: URL? {
    ///     if shouldUseICloud, let ubiquityURL = FileManager.default.url(
    ///         forUbiquityContainerIdentifier: "iCloud.com.maso.app"
    ///     ) { return ubiquityURL.appendingPathComponent("Documents/maso-data.json") }
    ///     return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    ///         .first?.appendingPathComponent("maso-data.json")
    /// }
    /// ```
    /// 依赖: 付费 Apple Developer Program + Apple Dev Console 建好 iCloud.com.maso.app container.
    var currentURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("maso-data.json")
    }

    /// 完整持久化 payload — 解码失败的话, 单字段缺失也允许 (向后兼容)
    struct Snapshot: Codable {
        let version: Int
        var plans: [Plan]
        var sets: [SetRecord]
        var settings: UserSettings
        var aiTodayPlan: Plan?
        var lastAIRefreshAt: Date?
        var updatedAt: Date
    }

    // MARK: - Load

    /// 从磁盘读 snapshot. 文件不存在 / 解析失败都返回 nil — caller 走 mock 兜底.
    func load() -> Snapshot? {
        guard let url = currentURL,
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let snapshot = try dec.decode(Snapshot.self, from: data)
            // schema 版本兼容性检查 — 文件版本 ≤ 当前版本时 OK (向前兼容由 JSON 字段缺失容忍处理).
            // 文件版本 > 当前版本 (用户从更新版本降级回来) → 不读, 用 mock, 避免破坏新版数据.
            guard snapshot.version <= Self.schemaVersion else { return nil }
            return snapshot
        } catch {
            // 解析失败 — 大多是 schema 变了或文件损坏. 回退到 mock, 老文件保留磁盘上 (没删).
            return nil
        }
    }

    // MARK: - Save

    /// 持久化 snapshot. 写文件用 atomic 选项防止中途崩溃产生 corrupt JSON.
    /// 失败静默 (没法做太多 — 磁盘满 / 权限问题等都是 user-out-of-control).
    func save(_ snapshot: Snapshot) {
        guard let url = currentURL else { return }
        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(snapshot)
            try data.write(to: url, options: [.atomic])
        } catch {
            // swallow — DataStore 下次 launch 会再试
        }
    }

    // MARK: - Export (for user-driven backup)

    /// 把当前 snapshot 写到临时文件, 返回 URL — caller 用 `.fileExporter` 把这个 URL 抛给 Files / AirDrop.
    /// 文件名带日期, 让用户在 Files app 里能区分多次备份.
    func exportToTempFile(_ snapshot: Snapshot) -> URL? {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd-HHmm"
        let filename = "maso-backup-\(df.string(from: Date())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        do {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try enc.encode(snapshot)
            try data.write(to: tempURL, options: [.atomic])
            return tempURL
        } catch {
            return nil
        }
    }

    // MARK: - Import (from user-provided file)

    /// 从用户挑的文件 (Files app / AirDrop / 邮件附件) 解析 snapshot.
    /// 解析失败返回 nil — caller 弹错误提示, 不动现有数据.
    func importFromFile(_ url: URL) -> Snapshot? {
        // Document picker 给的 URL 可能是 security-scoped, 需要 startAccessing
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let dec = JSONDecoder()
            dec.dateDecodingStrategy = .iso8601
            let snapshot = try dec.decode(Snapshot.self, from: data)
            return snapshot
        } catch {
            return nil
        }
    }

    // MARK: - Debug helpers

    /// 删除本地数据文件 — Settings 里"重置 app"或测试时用
    func reset() {
        guard let url = currentURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// 文件存在 + size + 修改时间 — Settings UI 显示"上次保存于..."
    func fileInfo() -> (exists: Bool, sizeBytes: Int?, modifiedAt: Date?) {
        guard let url = currentURL,
              FileManager.default.fileExists(atPath: url.path) else {
            return (false, nil, nil)
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = attrs?[.size] as? Int
        let date = attrs?[.modificationDate] as? Date
        return (true, size, date)
    }
}
