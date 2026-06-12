import Foundation

// iPhone ⇄ Watch 训练状态镜像协议 — 两个 target 共同编译这份文件
// (project.yml: Maso sources 包含 MasoWatch/Shared).
//
// 设计: 手机 (TrainingSessionStore) 是唯一 source of truth, 每次 mutation 把完整状态
// 推过来 (last-write-wins); 手表只渲染 + 回传动作指令. 没有双向状态合并, 不会脑裂.

/// 一帧完整的训练镜像状态. JSON 编码后塞在 WCSession 消息的 "s" key 里.
struct WatchSyncState: Codable, Equatable {
    enum Mode: String, Codable {
        case idle       // 没有进行中的训练
        case exercise   // 正在做某一组
        case rest       // 组间休息
        case done       // 训练完成 (等用户在手机上收尾)
    }

    var mode: Mode = .idle
    var planName: String = ""

    // exercise 态
    var exerciseName: String = ""
    var setN: Int = 0
    var setTotal: Int = 0
    /// 预格式化的目标行 ("8 reps · 60 kg" / "30s") — 手机端做本地化, 手表直接显示
    var detail: String = ""
    /// true = 力量组, 等用户打勾; false = 计时段 (倒计时自动走)
    var manualConfirm: Bool = false

    // rest 态
    var nextExercise: String? = nil

    // 倒计时: playing 时给 endsAt (手表本地 1Hz 算剩余); 暂停时给 pausedRemaining 静态显示
    var endsAt: Date? = nil
    var paused: Bool = false
    var pausedRemaining: Int? = nil

    // 总进度 (完成组数 / 总组数)
    var doneSets: Int = 0
    var totalSets: Int = 0

    /// 手机发出这帧的时刻 — 手表端陈旧判定用 (配对手机关机/失联后, applicationContext
    /// 会永远停留在最后一帧训练; 手表见到 6h+ 的旧帧自动回落 idle, 跟手机端
    /// autoCompleteAfter 的 6h 语义对齐). optional: 旧版本帧没有这个字段 → 视为陈旧.
    /// 注意: 去重比较 (WatchSyncManager.sync) 刻意忽略它, 时间戳不算"状态变化".
    var sentAt: Date? = nil

    static let idle = WatchSyncState()

    func encoded() -> Data? { try? JSONEncoder().encode(self) }
    static func decode(_ data: Data) -> WatchSyncState? {
        try? JSONDecoder().decode(WatchSyncState.self, from: data)
    }
}

/// watch → phone 的动作指令 (sendMessage ["a": rawValue]).
enum WatchAction: String {
    case advance      // 完成当前组 / 跳过休息 — 同手机上的主按钮
    case togglePlay   // 暂停 / 继续
    /// 手表已开 HKWorkoutSession — 手机端这次训练跳过自己的 HealthKit 写入,
    /// 由手表保存 (带实时心率 + 实测卡路里, 数据更全), 防止 Health 里双计.
    case hkActive
}
