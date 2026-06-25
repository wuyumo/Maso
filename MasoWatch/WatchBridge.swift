import Foundation
import WatchConnectivity
import Observation

/// 手表端 WCSession 桥 — 收手机推来的 WatchSyncState, 发动作指令回去.
/// 三个接收口都喂 apply():
///   - applicationContext: last-write-wins, 手表 app 后开也能拿到最近状态
///   - didReceiveMessage:  手机 reachable 时的低延迟通道
///   - activation 完成时读 receivedApplicationContext 兜底
@Observable
final class WatchBridge: NSObject, @unchecked Sendable {
    static let shared = WatchBridge()

    var state: WatchSyncState = .idle

    /// 陈旧阈值 — 跟手机端 TrainingSessionStore.autoCompleteAfter (6h) 对齐:
    /// 手机 6h 不活动会把训练自动结束, 所以 6h+ 的训练帧不可能还有效.
    /// 场景: 配对手机关机/失联后, applicationContext 永远停在最后一帧训练,
    /// 手表会无限显示"练到一半" — 这里见到旧帧 (或无 sentAt 的老版本帧) 回落 idle.
    private static let staleAfter: TimeInterval = 6 * 60 * 60
    private var staleTimer: Timer?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
        // 帧不更新时间也在走 — 周期检查让"手机失联后挂着的旧训练"最终自己消失.
        staleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.expireIfStale() }
        }
    }

    /// 返回是否真发出去了 — iPhone 未激活/不可达时返回 false, 调用方据此给"失败"触觉而非假"成功".
    @discardableResult
    func send(_ action: WatchAction) -> Bool {
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { return false }
        s.sendMessage(["a": action.rawValue], replyHandler: nil, errorHandler: nil)
        return true
    }

    @MainActor private func expireIfStale() {
        guard state.mode != .idle else { return }
        let born = state.sentAt ?? .distantPast
        if Date().timeIntervalSince(born) > Self.staleAfter {
            state = .idle
        }
    }

    private func apply(_ dict: [String: Any]) {
        guard let data = dict["s"] as? Data,
              let st = WatchSyncState.decode(data) else { return }
        Task { @MainActor in
            self.state = st
            self.expireIfStale()   // 收到的就是旧帧 (重启后读到的陈旧 context) → 立刻判
        }
    }
}

extension WatchBridge: WCSessionDelegate {
    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: Error?) {
        apply(session.receivedApplicationContext)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        apply(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        apply(message)
    }
}
