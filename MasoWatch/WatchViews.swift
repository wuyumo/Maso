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
            if bridge.showUndo, bridge.state.canUndo == true, let deadline = bridge.undoDeadline {
                WatchUndoView(deadline: deadline)
            } else { switch bridge.state.mode {
            case .idle: WatchIdleView()
            case .exercise, .rest: WatchPlayerView()
            case .done: WatchDoneView(state: bridge.state)
            } }
        }
        .onChange(of: bridge.state.mode, initial: true) { old, new in
            #if DEBUG
            if ProcessInfo.processInfo.environment["MASSO_WATCH_PREVIEW"] != nil { return }
            #endif
            // HKWorkoutSession 跟随训练起止
            switch new {
            case .exercise, .rest:
                WatchWorkoutManager.shared.startIfNeeded()
            case .done, .idle:
                WatchWorkoutManager.shared.end(discard: bridge.state.discarded == true)
            }
            // 关键节点触觉 — 跟 iPhone 端 Haptics 语义对齐
            guard old != new else { return }
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


private struct WatchUndoView: View {
    @Environment(WatchBridge.self) private var bridge
    let deadline: Date
    var body: some View {
        VStack(spacing: 8) {
            TimelineView(.periodic(from: .now, by: 0.2)) { context in
                Text("\(max(0, Int(ceil(deadline.timeIntervalSince(context.date)))))")
                    .font(.title2.bold().monospacedDigit())
                    .accessibilityIdentifier("watch.undo.countdown")
            }
            Button { bridge.command(.undo) } label: {
                Text("Set logged · Undo").font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 52)
            }.buttonStyle(.borderedProminent).tint(WatchTheme.accent).foregroundStyle(.black)
                .disabled(bridge.sending)
        }.padding(.horizontal, 6)
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

// MARK: - Small-watch-first player

private enum WatchPage: String, Identifiable { case queue, more, reps, weight, rest
    var id: String { rawValue }
}

struct WatchPlayerView: View {
    @Environment(WatchBridge.self) private var bridge
    @State private var page: WatchPage?
    @State private var confirmEnd = false
    private var state: WatchSyncState { bridge.state }

    var body: some View {
        ScrollView {
            VStack(spacing: 7) {
                if state.mode == .rest {
                    Button { page = .rest } label: {
                        HStack(spacing: 3) { Text("Rest"); Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)) }
                            .font(.caption).foregroundStyle(WatchTheme.accent)
                    }.buttonStyle(.plain).frame(minHeight: 18)
                    WatchCountdown(state: state, big: true)
                    HStack(spacing: 3) { Text("Next"); prescription }
                        .font(.system(size: 10)).foregroundStyle(WatchTheme.dim).lineLimit(1)
                    primary("Skip rest", symbol: "forward.end.fill") { bridge.command(.advance) }
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(state.exerciseName).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text(String(format: NSLocalizedString("SET %d/%d", comment: ""), state.setN, state.setTotal))
                            .font(.system(size: 9)).foregroundStyle(WatchTheme.dim)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                    if state.manualConfirm {
                        HStack(spacing: 0) {
                            parameter("Reps", value: state.reps.map { String($0) } ?? "—", page: .reps)
                            if state.expectsWeight == true {
                                Divider().frame(height: 25)
                                parameter(state.weightUnit == "lb" ? "lb" : "kg", value: weightText, page: .weight)
                            }
                        }.padding(.vertical, 2).background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                        primary("Log set", symbol: "checkmark") { bridge.command(.advance) }
                            .padding(.top, 4)
                    } else {
                        WatchCountdown(state: state, big: true)
                        primary(state.paused ? "Resume" : "Pause", symbol: state.paused ? "play.fill" : "pause.fill") {
                            bridge.command(.togglePlay)
                        }
                    }
                }
                HStack(spacing: 0) {
                    Button { page = .queue } label: { Image(systemName: "list.bullet").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle()) }
                        .accessibilityLabel(Text("This Workout"))
                    heart.frame(minWidth: 28)
                    Button { page = .more } label: { Image(systemName: "ellipsis").font(.system(size: 15, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 52).contentShape(Rectangle()) }
                        .accessibilityLabel(Text("More"))
                }.font(.system(size: 12)).buttonStyle(.plain).foregroundStyle(WatchTheme.dim)
            }.padding(.horizontal, 4)
        }.scrollIndicators(.hidden)
        .onAppear {
            #if DEBUG
            switch ProcessInfo.processInfo.environment["MASSO_WATCH_PREVIEW"] {
            case "queue": page = .queue
            case "edit": page = .weight
            case "more": page = .more
            default: break
            }
            #endif
        }
        .sheet(item: $page) { selected in
            NavigationStack {
                switch selected {
                case .queue: queue
                case .more: more
                case .reps, .weight, .rest: WatchValueEditor(page: selected, snapshot: state)
                }
            }
        }
        .alert("Workout", isPresented: Binding(get: { bridge.message != nil }, set: { if !$0 { bridge.message = nil } })) {
            Button("Done") { bridge.message = nil }
        } message: { Text(bridge.message ?? "") }
    }

    private var weightText: String {
        guard let kg = state.weight else { return "—" }
        let value = state.weightUnit == "lb" ? kg * 2.2046226218 : kg
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
    private var prescription: some View {
        Text([state.reps.map { String(format: NSLocalizedString("%d reps", comment: ""), $0) },
              state.weight.map { _ in weightText + " " + (state.weightUnit ?? "kg") }].compactMap { $0 }.joined(separator: " · "))
    }
    private var heart: some View {
        TimelineView(.periodic(from: .now, by: 5)) { context in
            let workout = WatchWorkoutManager.shared
            let fresh = workout.heartRateDate.map { context.date.timeIntervalSince($0) <= 20 } ?? false
            HStack(spacing: 3) {
                Image(systemName: "heart.fill").foregroundStyle(.red).font(.system(size: 9))
                Text(fresh && workout.heartRate > 0 ? String(workout.heartRate) : "—").monospacedDigit()
            }.font(.system(size: 10))
        }
    }
    private func parameter(_ label: String, value: String, page: WatchPage) -> some View {
        Button { self.page = page } label: {
            VStack(spacing: 0) {
                Text(LocalizedStringKey(label)).font(.system(size: 10)).foregroundStyle(WatchTheme.dim)
                Text(value).font(.system(size: 22, weight: .semibold).monospacedDigit())
            }.frame(maxWidth: .infinity, minHeight: 38)
        }.buttonStyle(.plain)
    }
    private func primary(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Group {
            if #available(watchOS 26.0, *) {
                primaryButton(title, symbol: symbol, action: action).buttonStyle(.glassProminent)
            } else {
                primaryButton(title, symbol: symbol, action: action).buttonStyle(.borderedProminent)
            }
        }.tint(WatchTheme.accent).foregroundStyle(.black).disabled(bridge.sending)
    }
    private func primaryButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(LocalizedStringKey(title), systemImage: symbol).font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, minHeight: 34)
        }
    }
    private var queue: some View {
        List {
            ForEach(state.rows ?? []) { row in
                Button {
                    bridge.command(.jump, stepID: row.id) { ok in if ok { page = nil } }
                } label: {
                    HStack(spacing: 6) {
                        Text(row.name).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                        Text("\(row.completed)/\(row.total)").font(.caption2).monospacedDigit()
                            .foregroundStyle(row.id == state.stepID ? WatchTheme.accent : WatchTheme.dim)
                    }
                }.disabled(bridge.sending || row.completed >= row.total)
            }
        }.navigationTitle("This Workout")
    }
    private var more: some View {
        List {
            Button(LocalizedStringKey(state.paused ? "Resume" : "Pause")) { bridge.command(.togglePlay) { ok in if ok { page = nil } } }
            Button("Undo last action") { bridge.command(.undo) { ok in if ok { page = nil } } }.disabled(state.canUndo != true)
            if state.mode == .exercise && !state.manualConfirm {
                Button("Skip") { bridge.command(.advance) { ok in if ok { page = nil } } }
            }
            Button("End workout", role: .destructive) { confirmEnd = true }
        }.navigationTitle("More")
            .confirmationDialog("End workout?", isPresented: $confirmEnd, titleVisibility: .visible) {
                Button("End & save") { bridge.command(.finish) { ok in if ok { page = nil } } }
                Button("Discard workout", role: .destructive) { bridge.command(.discard) { ok in if ok { page = nil } } }
                Button("Cancel", role: .cancel) {}
            }.disabled(bridge.sending)
    }
}

private struct WatchValueEditor: View {
    let page: WatchPage
    let snapshot: WatchSyncState
    @Environment(WatchBridge.self) private var bridge
    @Environment(\.dismiss) private var dismiss
    @State private var value = 0.0
    private var pounds: Bool { snapshot.weightUnit == "lb" }
    private var title: String { page == .rest ? "Rest" : page == .reps ? "Reps" : "Weight" }
    var body: some View {
        Form {
            if page == .rest { Text("This rest only").font(.caption2).foregroundStyle(WatchTheme.dim) }
            Stepper(value: $value, in: 0...maximum, step: increment) {
                Text(value.formatted(.number.precision(.fractionLength(0...1))) + " " + unit)
                    .font(.title3).monospacedDigit()
            }
            .focusable()
            .digitalCrownRotation($value, from: page == .reps ? 1 : 0, through: maximum, by: increment,
                                  sensitivity: .low, isContinuous: false, isHapticFeedbackEnabled: true)
            Button("Done") {
                guard snapshot.context == bridge.state.context else {
                    bridge.message = NSLocalizedString("Workout changed. Try again.", comment: ""); dismiss(); return
                }
                bridge.command(page == .rest ? .rest : page == .reps ? .reps : .weight,
                               value: page == .weight && pounds ? value / 2.2046226218 : value) { ok in
                    if ok { dismiss() }
                }
            }.disabled(bridge.sending || (page == .reps && value < 1))
        }.navigationTitle(LocalizedStringKey(title))
            .onAppear {
                if page == .rest { value = Double(snapshot.restDuration ?? 90) }
                else if page == .reps { value = Double(snapshot.reps ?? 8) }
                else { value = (snapshot.weight ?? 0) * (pounds ? 2.2046226218 : 1) }
            }
    }
    private var unit: String { page == .rest ? NSLocalizedString("seconds", comment: "") : page == .reps ? "" : pounds ? "lb" : "kg" }
    private var increment: Double { page == .rest ? 15 : page == .reps ? 1 : pounds ? 5 : 2.5 }
    private var maximum: Double { page == .rest ? 3600 : page == .reps ? 999 : pounds ? 1100 : 500 }
}

// MARK: - Done

struct WatchDoneView: View {
    let state: WatchSyncState
    @Environment(WatchBridge.self) private var bridge

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
            .font(.system(size: big ? 32 : 24, weight: .heavy).monospacedDigit())
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
                ProgressFractionText(numerator: String(state.doneSets), denominator: String(state.totalSets), separator: "/",
                                     numeratorColor: .white, denominatorColor: WatchTheme.dim)
                    .font(.system(size: 10, weight: .semibold).monospacedDigit())
                    .foregroundStyle(WatchTheme.dim)
            }
        }
        .padding(.horizontal, 2)
    }
}
