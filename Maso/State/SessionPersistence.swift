import Foundation

// 进行中训练的磁盘镜像 — iOS 杀后台后冷启动把训练接回来.
//
// 跟 maso-data.json (DataStore) 分开存:
//   - 这是"易失型"小文件: session 每次 mutation 整体重写 (~KB), 结束即删;
//   - 主数据走 debounced save, 两者节奏不同, 不该纠缠.
//
// 写入点: TrainingSessionStore.session 的 didSet (用户操作级频率).
// 读取点: 冷启动 MasoApp .task → restorePersistedSession (已 completed / 闲置 6h+ 不复活).
enum SessionPersistence {
    /// 当前播放位置的语义锚 — segmentIndex 是对"当时展开的 segments"的裸下标,
    /// 恢复时 rest 默认值可能已被用户改过 (mid-workout 进 Settings), 重新展开后段数不同,
    /// 裸下标会落错位置. 锚定 (stepId, setN) 跟 store 内 mutator 的映射逻辑一致.
    struct Anchor: Codable {
        var stepId: String
        var setN: Int
        /// 保存时停在该组前面的 rest 段上 (恢复时若 rest 还在, 落回 rest)
        var onRestBefore: Bool
    }

    struct Payload: Codable {
        var session: TrainingSessionStore.Session
        /// session-local plan 副本 (训练中可被编辑, 跟 data.plans 里的不一定一致)
        var plan: Plan?
        var planParamsDirty: Bool
        var anchor: Anchor? = nil
    }

    private static var fileURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("active-session.json")
    }

    static func save(_ payload: Payload) {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601   // 跟 maso-data.json (PersistenceController) 一致
        guard let data = try? enc.encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return try? dec.decode(Payload.self, from: data)
    }

    static func clear() {
        try? FileManager.default.removeItem(at: fileURL)
    }
}
