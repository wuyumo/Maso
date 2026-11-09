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
        // A navigation title the scene never sets still reserves a top band on
        // watchOS and pushes the training stack down. Hiding it does not draw
        // into the clock safe area.
        .toolbar(.hidden, for: .navigationBar)
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
        WatchFittedSession(
            page: state.manualConfirm ? .exerciseManual : .exerciseTimed,
            showsDetail: !state.detail.isEmpty
        ) { chrome in
            VStack(spacing: chrome.spacing) {
                Text(String(format: NSLocalizedString("SET %d/%d", comment: ""), state.setN, state.setTotal))
                    .font(.system(size: chrome.kicker * chrome.drawScale, weight: .heavy))
                    .tracking(1)
                    .foregroundStyle(WatchTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(state.exerciseName)
                    .font(.system(size: chrome.title * chrome.drawScale, weight: .bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
                if !state.detail.isEmpty {
                    Text(state.detail)
                        .font(.system(size: chrome.detail * chrome.drawScale).monospacedDigit())
                        .foregroundStyle(WatchTheme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer(minLength: 0)

                if state.manualConfirm {
                    // 力量组 — 大打勾按钮 (同手机主按钮语义: 完成这组)
                    Button {
                        // 发送成功才给"完成"触觉; iPhone 不可达 → 失败触觉, 不假装成功 (避免"按了没反应"的误判).
                        WKInterfaceDevice.current().play(bridge.send(.advance) ? .click : .failure)
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.system(size: 22 * min(chrome.drawScale, 1.4), weight: .heavy))
                            .foregroundStyle(.black)
                            .frame(maxWidth: .infinity)
                            .frame(height: chrome.buttonHeight * chrome.drawScale)
                            .background(WatchTheme.accent, in: Capsule())
                    }
                    .buttonStyle(.plain)
                } else {
                    // 计时段 — 倒计时 + 暂停/继续. plain + 固定高度, 系统按钮样式会再加一层
                    // 垂直 chrome, 在 40mm 上把心率行挤出安全区.
                    WatchCountdown(state: state, size: chrome.countdown * chrome.drawScale)
                    Button {
                        if !bridge.send(.togglePlay) { WKInterfaceDevice.current().play(.failure) }
                    } label: {
                        Text(state.paused ? "Resume" : "Pause")
                            .font(.system(size: 13 * chrome.drawScale, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: .infinity)
                            .frame(height: chrome.buttonHeight * chrome.drawScale)
                            .background(WatchTheme.accent.opacity(0.3), in: Capsule())
                    }
                    .buttonStyle(.plain)
                }

                WatchVitalsFooter(state: state, fontSize: chrome.footer * chrome.drawScale)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

// MARK: - Rest

struct WatchRestView: View {
    let state: WatchSyncState
    @Environment(WatchBridge.self) private var bridge

    var body: some View {
        WatchFittedSession(
            page: .rest,
            showsNext: state.nextExercise != nil
        ) { chrome in
            VStack(spacing: chrome.spacing) {
                Text("REST")
                    .font(.system(size: chrome.kicker * chrome.drawScale, weight: .heavy))
                    .tracking(1.5)
                    .foregroundStyle(WatchTheme.accent)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                WatchCountdown(state: state, size: chrome.countdown * chrome.drawScale)

                if let next = state.nextExercise {
                    VStack(spacing: 1) {
                        Text("Next")
                            .font(.system(size: 10 * chrome.drawScale, weight: .semibold))
                            .foregroundStyle(WatchTheme.faint)
                            .lineLimit(1)
                        Text(next)
                            .font(.system(size: 13 * chrome.drawScale, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    WKInterfaceDevice.current().play(bridge.send(.advance) ? .click : .failure)
                } label: {
                    Text("Skip")
                        .font(.system(size: 14 * chrome.drawScale, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity)
                        .frame(height: chrome.buttonHeight * chrome.drawScale)
                        .background(Color.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)

                WatchVitalsFooter(state: state, fontSize: chrome.footer * chrome.drawScale)
            }
            .frame(maxWidth: .infinity, alignment: .top)
        }
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
    var size: CGFloat = 24

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
            .font(.system(size: size, weight: .heavy).monospacedDigit())
            .foregroundStyle(state.paused ? WatchTheme.dim : .white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .contentTransition(.numericText(countsDown: true))
    }
}

// MARK: - 底部心率 / 卡路里 / 进度

struct WatchVitalsFooter: View {
    let state: WatchSyncState
    var fontSize: CGFloat = 11
    private var workout: WatchWorkoutManager { WatchWorkoutManager.shared }

    var body: some View {
        // 展示条件不变: 心率 / 卡路里仍只在 session 跑起来且读数 > 0 时出现.
        // 行高按「三者都在」预算过, 读数晚到不会把按钮顶出安全区.
        HStack(spacing: 8) {
            if workout.running, workout.heartRate > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "heart.fill")
                        .font(.system(size: fontSize * 0.82))
                        .foregroundStyle(.red)
                    Text(verbatim: "\(workout.heartRate)")
                        .font(.system(size: fontSize, weight: .semibold).monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            if workout.running, workout.activeCalories > 0 {
                Text(verbatim: "\(workout.activeCalories) kcal")
                    .font(.system(size: fontSize * 0.9).monospacedDigit())
                    .foregroundStyle(WatchTheme.faint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
            if state.totalSets > 0 {
                Text(verbatim: "\(state.doneSets)/\(state.totalSets)")
                    .font(.system(size: fontSize * 0.9, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WatchTheme.dim)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
        }
        .padding(.horizontal, 2)
    }
}

// MARK: - 安全区内自适应容器

private struct WatchFittedSession<Content: View>: View {
    let page: WatchTrainingPage
    var showsDetail: Bool = false
    var showsNext: Bool = false
    @ViewBuilder var content: (WatchTrainingChrome) -> Content
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        GeometryReader { geo in
            let insets = geo.safeAreaInsets
            let width = max(0, geo.size.width - insets.leading - insets.trailing)
            let height = max(0, geo.size.height - insets.top - insets.bottom)
            let chrome = WatchTrainingLayout.resolve(
                contentWidth: width,
                contentHeight: height,
                page: page,
                showsDetail: showsDetail,
                showsNext: showsNext,
                typeScale: WatchTrainingLayout.typeScale(dynamicTypeSize)
            )
            let stack = content(chrome)
                .padding(.horizontal, chrome.horizontalPadding)
            // 默认字号: 把栈定在安全区高度里, Spacer 只吃安全区里剩下的空隙,
            // 按钮和心率落在安全区底, 不再画到表冠外. 大于默认的 Dynamic Type
            // 改为滚动, 不把字缩回去硬塞一屏.
            Group {
                if chrome.scrollFallback {
                    ScrollView {
                        stack.frame(maxWidth: .infinity, alignment: .top)
                    }
                } else {
                    stack.frame(width: width, height: height, alignment: .top)
                }
            }
            .padding(.top, insets.top)
            .padding(.bottom, insets.bottom)
            .padding(.leading, insets.leading)
            .padding(.trailing, insets.trailing)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
        }
    }
}
