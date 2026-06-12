import Foundation
import WatchConnectivity

// iPhone 端 WatchConnectivity 桥 — 模式抄 LiveActivityManager:
// 单例, TrainingSessionStore 每次 mutation 末尾推一帧 WatchSyncState 过去;
// 手表的动作指令 (完成组 / 暂停) 回调到 RootView 接线的闭包.
final class WatchSyncManager: NSObject, @unchecked Sendable {
    static let shared = WatchSyncManager()

    /// 手表点 ✓ / Skip → store.advance (RootView 接线, 带 recordSet 落库)
    @MainActor var onAdvance: (() -> Void)?
    /// 手表点 暂停/继续 → store.togglePlay
    @MainActor var onTogglePlay: (() -> Void)?
    /// 手表本次训练开了 HKWorkoutSession → 手机端不再写自己的 HKWorkout
    /// (手表那份带实时心率 + 实测卡路里, 数据更全; 双写会让 Health 双计).
    @MainActor private(set) var watchHealthSessionActive = false

    /// 去重 — tick 引发的同值 sync 不重发 (省电 + 避免 applicationContext 节流).
    /// 比较的是"去掉 sentAt 的语义 payload" — 时间戳每帧都变, 不能参与去重.
    private var lastSemanticPayload: Data?
    /// 最后一帧状态 — 手表晚连上 (装 app / 变 reachable) 时重推, 不然开局帧会被守卫吞掉.
    private var lastState: WatchSyncState?

    func activate() {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        s.delegate = self
        s.activate()
    }

    /// 新一次训练开始 — 重置手表 HK 标记 (上次训练的标记不能带过来).
    @MainActor func resetForNewWorkout() { watchHealthSessionActive = false }

    func sync(_ state: WatchSyncState) {
        lastState = state
        // 语义去重: 比较不带 sentAt 的 payload — 同语义帧不重发 (省电 + 防节流).
        var semantic = state
        semantic.sentAt = nil
        guard let semanticData = semantic.encoded(), semanticData != lastSemanticPayload else { return }
        lastSemanticPayload = semanticData
        // 真正发出的帧盖当前时间戳 — 手表端据此做 6h 陈旧判定.
        var stamped = state
        stamped.sentAt = Date()
        push(stamped)
    }

    /// 推状态: reachable 时 sendMessage (低延迟) + 永远 updateApplicationContext
    /// (last-write-wins, 手表 app 后开也能拿到).
    private func push(_ state: WatchSyncState) {
        guard WCSession.isSupported() else { return }
        let s = WCSession.default
        guard s.activationState == .activated, s.isPaired, s.isWatchAppInstalled else { return }
        guard let data = state.encoded() else { return }
        if s.isReachable {
            s.sendMessage(["s": data], replyHandler: nil, errorHandler: nil)
        }
        try? s.updateApplicationContext(["s": data])
    }

    /// 手表连接状态变化 (装了 app / app 进前台 reachable) → 把最后一帧补推过去.
    private func repushOnMain() {
        DispatchQueue.main.async {
            self.lastSemanticPayload = nil   // 强制重发 (绕过去重)
            if let st = self.lastState { self.sync(st) }
        }
    }
}

extension WatchSyncManager: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        repushOnMain()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        // 用户换表 — 重新激活到新表
        session.activate()
    }

    func sessionWatchStateDidChange(_ session: WCSession) {
        repushOnMain()   // 手表刚装上 app / 卸载重装
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        repushOnMain()   // 手表 app 进前台 — 补一帧最新状态
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let raw = message["a"] as? String,
              let action = WatchAction(rawValue: raw) else { return }
        Task { @MainActor in
            switch action {
            case .advance: self.onAdvance?()
            case .togglePlay: self.onTogglePlay?()
            case .hkActive: self.watchHealthSessionActive = true
            }
        }
    }
}
