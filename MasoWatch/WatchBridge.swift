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

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func send(_ action: WatchAction) {
        let s = WCSession.default
        guard s.activationState == .activated, s.isReachable else { return }
        s.sendMessage(["a": action.rawValue], replyHandler: nil, errorHandler: nil)
    }

    private func apply(_ dict: [String: Any]) {
        guard let data = dict["s"] as? Data,
              let st = WatchSyncState.decode(data) else { return }
        Task { @MainActor in
            self.state = st
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
