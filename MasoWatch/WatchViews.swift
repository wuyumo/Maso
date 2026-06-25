import SwiftUI
import WatchKit

// Masso Watch UI — 黑底 + 品牌绿, 跟 iPhone 端 DESIGN.md 同一气质.
// 只有 4 个状态页: idle / exercise / rest / done, 全部由 WatchBridge.state 驱动.

enum WatchTheme {
    static let accent = Color(red: 30 / 255, green: 215 / 255, blue: 96 / 255)   // #1ED760
    static let dim = Color.white.opacity(0.55)
    static let faint = Color.white.opacity(0.35)
}

struct WatchRootView: View {
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        Group {
            switch bridge.state.mode {
            case .idle: WatchIdleView()
            case .exercise: WatchExerciseView(state: bridge.state)
            case .rest: WatchRestView(state: bridge.state)
            case .done: WatchDoneView(state: bridge.state)
            }
        }
        .onChange(of: bridge.state.mode) { old, new in
            // HKWorkoutSession 跟随训练起止
            switch new {
            case .exercise, .rest:
                WatchWorkoutManager.shared.startIfNeeded()
            case .done, .idle:
                WatchWorkoutManager.shared.end()
            }
            // 关键节点触觉 — 跟 iPhone 端 Haptics 语义对齐
            if old == .rest && new == .exercise {
                WKInterfaceDevice.current().play(.start)      // 休息结束, 开干
            } else if new == .rest {
                WKInterfaceDevice.current().play(.stop)       // 进入休息
            } else if new == .done && old != .done {
                WKInterfaceDevice.current().play(.success)    // 训练完成
            }
        }
    }
}

// MARK: - Idle

struct WatchIdleView: View {
    var body: some View {
        VStack(spacing: 8) {
            WatchBrandMark(color: WatchTheme.accent)
                .frame(width: 34, height: 34)
            Text(verbatim: "MASSO")
                .font(.system(size: 14, weight: .heavy))
                .tracking(2)
            Text("Start a workout on your iPhone")
                .font(.system(size: 12))
                .foregroundStyle(WatchTheme.dim)
                .multilineTextAlignment(.center)
            Text("It will appear here automatically")
                .font(.system(size: 11))
                .foregroundStyle(WatchTheme.faint)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - Exercise

struct WatchExerciseView: View {
    let state: WatchSyncState
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        VStack(spacing: 6) {
            Text(String(format: NSLocalizedString("SET %d/%d", comment: ""), state.setN, state.setTotal))
                .font(.system(size: 11, weight: .heavy))
                .tracking(1)
                .foregroundStyle(WatchTheme.accent)
            Text(state.exerciseName)
                .font(.system(size: 17, weight: .bold))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.7)
            if !state.detail.isEmpty {
                Text(state.detail)
                    .font(.system(size: 13).monospacedDigit())
                    .foregroundStyle(WatchTheme.dim)
            }

            Spacer(minLength: 2)

            if state.manualConfirm {
                // 力量组 — 大打勾按钮 (同手机主按钮语义: 完成这组)
                Button {
                    // 发送成功才给"完成"触觉; iPhone 不可达 → 失败触觉, 不假装成功 (避免"按了没反应"的误判).
                    WKInterfaceDevice.current().play(bridge.send(.advance) ? .click : .failure)
                } label: {
                    Image(systemName: "checkmark")
                        .font(.system(size: 22, weight: .heavy))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .background(WatchTheme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            } else {
                // 计时段 — 倒计时 + 暂停/继续
                WatchCountdown(state: state)
                Button {
                    if !bridge.send(.togglePlay) { WKInterfaceDevice.current().play(.failure) }
                } label: {
                    Text(state.paused ? "Resume" : "Pause")
                        .font(.system(size: 13, weight: .semibold))
                }
                .tint(WatchTheme.accent.opacity(0.3))
            }

            WatchVitalsFooter(state: state)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Rest

struct WatchRestView: View {
    let state: WatchSyncState
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        VStack(spacing: 6) {
            Text("REST")
                .font(.system(size: 11, weight: .heavy))
                .tracking(1.5)
                .foregroundStyle(WatchTheme.accent)

            WatchCountdown(state: state, big: true)

            if let next = state.nextExercise {
                VStack(spacing: 1) {
                    Text("Next")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(WatchTheme.faint)
                    Text(next)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }

            Spacer(minLength: 2)

            Button {
                WKInterfaceDevice.current().play(bridge.send(.advance) ? .click : .failure)
            } label: {
                Text("Skip")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Color.white.opacity(0.12), in: Capsule())
            }
            .buttonStyle(.plain)

            WatchVitalsFooter(state: state)
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 2)
    }
}

// MARK: - Done

struct WatchDoneView: View {
    let state: WatchSyncState

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 34))
                .foregroundStyle(WatchTheme.accent)
            Text("Workout complete")
                .font(.system(size: 15, weight: .bold))
            Text(String(format: NSLocalizedString("%d sets", comment: ""), state.doneSets))
                .font(.system(size: 13).monospacedDigit())
                .foregroundStyle(WatchTheme.dim)
            if WatchWorkoutManager.shared.activeCalories > 0 {
                Text(verbatim: "\(WatchWorkoutManager.shared.activeCalories) kcal")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(WatchTheme.faint)
            }
        }
        .padding(.horizontal, 8)
    }
}

// MARK: - 倒计时 (本地 1Hz, 不依赖手机推帧)

struct WatchCountdown: View {
    let state: WatchSyncState
    var big: Bool = false

    var body: some View {
        Group {
            if state.paused, let rem = state.pausedRemaining {
                text(rem)
            } else if let endsAt = state.endsAt {
                TimelineView(.periodic(from: .now, by: 1)) { ctx in
                    text(max(0, Int(endsAt.timeIntervalSince(ctx.date).rounded(.up))))
                }
            } else {
                text(0).hidden()
            }
        }
    }

    private func text(_ seconds: Int) -> some View {
        Text(verbatim: String(format: "%d:%02d", seconds / 60, seconds % 60))
            .font(.system(size: big ? 40 : 24, weight: .heavy).monospacedDigit())
            .foregroundStyle(state.paused ? WatchTheme.dim : .white)
            .contentTransition(.numericText(countsDown: true))
    }
}

// MARK: - 底部心率 / 卡路里 / 进度

struct WatchVitalsFooter: View {
    let state: WatchSyncState
    private var workout: WatchWorkoutManager { WatchWorkoutManager.shared }

    var body: some View {
        HStack(spacing: 8) {
            if workout.running, workout.heartRate > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.red)
                    Text(verbatim: "\(workout.heartRate)")
                        .font(.system(size: 11, weight: .semibold).monospacedDigit())
                }
            }
            if workout.running, workout.activeCalories > 0 {
                Text(verbatim: "\(workout.activeCalories) kcal")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(WatchTheme.faint)
            }
            Spacer(minLength: 0)
            if state.totalSets > 0 {
                Text(verbatim: "\(state.doneSets)/\(state.totalSets)")
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WatchTheme.dim)
            }
        }
        .padding(.horizontal, 2)
    }
}
