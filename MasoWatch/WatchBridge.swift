import Foundation
import WatchConnectivity
import Observation
import WatchKit

/// 手表端 WCSession 桥 — 收手机推来的 WatchSyncState, 发动作指令回去.
/// 三个接收口都喂 apply():
///   - applicationContext: last-write-wins, 手表 app 后开也能拿到最近状态
///   - didReceiveMessage:  手机 reachable 时的低延迟通道
///   - activation 完成时读 receivedApplicationContext 兜底
@Observable
final class WatchBridge: NSObject, @unchecked Sendable {
    static let shared = WatchBridge()

    var state: WatchSyncState = .idle
    var sending = false
    var message: String?
    var showUndo = false
    var undoDeadline: Date?
    private var pendingID: String?
    private var undoToken = UUID()

    @MainActor
    func command(_ kind: WatchCommand.Kind, stepID: String? = nil, value: Double? = nil,
                 completion: @escaping (Bool) -> Void = { _ in }) {
        let session = WCSession.default
        guard !sending, let key = state.workoutSessionID, let context = state.context,
              session.activationState == .activated, session.isReachable else {
            message = NSLocalizedString("Open your iPhone to reconnect", comment: "")
            WKInterfaceDevice.current().play(.failure); completion(false); return
        }
        let completedSet = kind == .advance && state.mode == .exercise
        let command = WatchCommand(sessionID: key, context: context, kind: kind, stepID: stepID, value: value)
        guard let bytes = try? JSONEncoder().encode(command) else { completion(false); return }
        sending = true; pendingID = command.id; message = nil; showUndo = false; undoDeadline = nil; undoToken = UUID()
        session.sendMessage(["command": bytes], replyHandler: { reply in
            Task { @MainActor in
                guard self.pendingID == command.id else { return }
                self.pendingID = nil; self.sending = false
                let ok = reply["ok"] as? Bool == true
                if reply["discarded"] as? Bool == true { WatchWorkoutManager.shared.end(discard: true) }
                if let data = reply["s"] as? Data, let state = WatchSyncState.decode(data) {
                    self.state = state
                }
                if ok {
                    WKInterfaceDevice.current().play(.click)
                    if completedSet && self.state.canUndo == true {
                        let token = UUID()
                        self.undoToken = token
                        self.undoDeadline = Date().addingTimeInterval(3)
                        self.showUndo = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(3))
                            if self.undoToken == token { self.showUndo = false; self.undoDeadline = nil }
                        }
                    }
                } else { self.message = NSLocalizedString("Workout changed. Try again.", comment: "") }
                completion(ok)
            }
        }, errorHandler: { _ in
            Task { @MainActor in
                guard self.pendingID == command.id else { return }
                self.pendingID = nil; self.sending = false
                self.message = NSLocalizedString("Open your iPhone to reconnect", comment: "")
                completion(false)
            }
        })
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            if self.pendingID == command.id {
                self.pendingID = nil; self.sending = false
                self.message = NSLocalizedString("Open your iPhone to reconnect", comment: "")
                completion(false)
            }
        }
    }

    /// 陈旧阈值 — 跟手机端 TrainingSessionStore.autoCompleteAfter (6h) 对齐:
    /// 手机 6h 不活动会把训练自动结束, 所以 6h+ 的训练帧不可能还有效.
    /// 场景: 配对手机关机/失联后, applicationContext 永远停在最后一帧训练,
    /// 手表会无限显示"练到一半" — 这里见到旧帧 (或无 sentAt 的老版本帧) 回落 idle.
    private static let staleAfter: TimeInterval = 6 * 60 * 60
    private var staleTimer: Timer?

    override init() {
        super.init()
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASSO_WATCH_PREVIEW"] != nil {
            state = Self.previewState(); return
        }
        #endif
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

    @MainActor func sendHeartRate(_ bpm: Double, date: Date) {
        let session = WCSession.default
        guard state.heartRateSharingEnabled == true, let key = state.workoutSessionID,
              state.mode == .exercise || state.mode == .rest,
              session.activationState == .activated, session.isReachable else { return }
        session.sendMessage(["workoutSessionID": key, "heartRate": bpm, "sampleDate": date], replyHandler: nil, errorHandler: nil)
    }

    @MainActor private func resendCurrentVitals() {
        let workout = WatchWorkoutManager.shared
        guard workout.running else { return }
        send(.hkActive)
        // Preserve the measurement time; reconnecting must not freshen old data.
        if let date = workout.heartRateDate, Date().timeIntervalSince(date) <= 20 {
            sendHeartRate(Double(workout.heartRate), date: date)
        }
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
            let previous = self.state
            self.state = st
            self.expireIfStale()   // 收到的就是旧帧 (重启后读到的陈旧 context) → 立刻判
            if previous.workoutSessionID != self.state.workoutSessionID ||
                previous.heartRateSharingEnabled != self.state.heartRateSharingEnabled {
                self.resendCurrentVitals()
            }
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

    func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor in self.resendCurrentVitals() }
    }
}

#if DEBUG
extension WatchBridge {
    static func previewState() -> WatchSyncState {
        WatchPreviewFixture.snapshot(
            environment: ProcessInfo.processInfo.environment,
            language: Locale.preferredLanguages.first ?? "en",
            now: Date()
        )?.state ?? WatchSyncState()
    }
}
#endif
