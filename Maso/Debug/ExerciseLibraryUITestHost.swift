#if DEBUG
import SwiftUI

/// Explicitly launched by MasoUITests, never part of a Release build. The test
/// process drives the production sheets through XCTest's public AX interface.
/// SwiftUI re-executes this view's initializer on every parent update. The session
/// report seed publishes `session`, and that publication was re-entering layout.
/// Build the fixture once; later initializers only read it.
@MainActor
private final class SessionReportUIFixture {
    let data: DataStore
    let session: TrainingSessionStore

    init(data: DataStore, session: TrainingSessionStore) {
        self.data = data
        self.session = session
    }

    private static var ready: [String: SessionReportUIFixture] = [:]
    private static var partial: [String: SessionReportUIFixture] = [:]
    private static let scenes: Set<String> = ["session-report-history", "session-report-clean-player", "session-report-changed-player"]

    static func prepare(_ scene: String) -> SessionReportUIFixture? {
        guard scenes.contains(scene) else { return nil }
        if let existing = ready[scene] { return existing }
        if let existing = partial[scene] { return existing }
        let data = DataStore.makeMock()
        let player = TrainingSessionStore(completionSound: {})
        let fixture = SessionReportUIFixture(data: data, session: player)
        partial[scene] = fixture
        if ExerciseLibraryUITestHost.sessionReportPlayer(scene: scene, data: data, player: player) == nil,
           scene != "session-report-history" {
            partial[scene] = nil
            return nil
        }
        ready[scene] = fixture
        partial[scene] = nil
        return fixture
    }
}

struct ExerciseLibraryUITestHost: View {
    let scene: String
    @State private var data: DataStore
    @State private var session = TrainingSessionStore()
    @State private var subscriptions = SubscriptionManager()
    @State private var presented = false
    @State private var pickedIDs: [String] = []
    @State private var dismissalCount = 0
    @State private var coachWorkoutPresented = false

    init(scene: String) {
        self.scene = scene
        if let fixture = SessionReportUIFixture.prepare(scene) {
            _data = State(initialValue: fixture.data)
            _session = State(initialValue: fixture.session)
            return
        }
        let data = DataStore.makeMock()
        if ProcessInfo.processInfo.environment["MASO_TEST_OLD_AI_CONSENT"] == "1" {
            AIDataConsent.shared.revoke()
            UserDefaults.standard.set(true, forKey: "masso.aiDataSharingConsent.v1")
        }
        data.settings.favoriteExerciseIds = ["bench_press_barbell"]
        if ProcessInfo.processInfo.environment["MASO_IDENTITY_AUDIT"] == "1" {
            data.settings.hideRareVariants = false
        }
        if scene == "diet-health" {
            data.settings.debugProUnlock = true
            data.settings.weight = 80
            let now = Date(), calendar = data.settings.calendar
            let snapshot = BodyActivityHealthSnapshot(refreshedAt: now, timeZone: calendar.timeZone.identifier,
                weights: [.init(id: "old", date: now.addingTimeInterval(-500 * 86400), value: 76, source: "Scale"),
                          .init(id: "new", date: now.addingTimeInterval(-86400), value: 74, source: "Scale"),
                          .init(id: "latest", date: now.addingTimeInterval(-3600), value: 72.5, source: "Scale")],
                heights: [.init(id: "height", date: now.addingTimeInterval(-600 * 86400), value: 178, source: "Health")],
                activity: [.init(day: calendar.startOfDay(for: now), steps: 6000, activeEnergy: 420, restingEnergy: 1100)])
            data.settings.bodyActivityHealth = .init(enabled: true)
            data.settings.applyBodyActivityHealth(snapshot)
        }
        if scene == "body-profile-empty" {
            data.settings.weight = nil; data.settings.heightCentimeters = nil
            data.settings.bodyActivityHealth = nil
        }
        if scene == "meal-live" || scene == "diet-targets" {
            data.settings.debugProUnlock = true
            data.settings.mealCheckIns = []
        }
        if scene == "coach-live" || scene == "coach-frequency" || scene == "coach-photo-report" {
            data.settings.debugProUnlock = true
            data.settings.weeklyTrainingDays = Int(ProcessInfo.processInfo.environment["MASO_COACH_TEST_DAYS"] ?? "") ?? 3
            data.settings.exercisesPerSession = Int(ProcessInfo.processInfo.environment["MASO_COACH_TEST_EXERCISES"] ?? "") ?? 4
            data.settings.coachMemory = ""
        }
        if scene == "coach-frequency" {
            data.settings.weeklyTrainingDays = 2
            data.coachSession.currentRoutines = RecommendedPrograms.plans(forDays: 2, now: Date(), byId: data.exById)
        }
        if ["home-overview", "free-picker", "short-player", "stable-player", "preferences"].contains(scene) {
            data.settings.debugProUnlock = true
        }
        if scene == "coach-save" {
            data.settings.debugProUnlock = true
            var plans = RecommendedPrograms.plans(forDays: 3, now: Date(), byId: data.exById).map { original in
                var plan = original
                plan.name = "Preview " + plan.name
                plan.source = .ai
                return plan
            }
            if ProcessInfo.processInfo.environment["MASO_COACH_TALL_CARD"] == "1", plans.count > 1 {
                plans[0].steps = Array(plans[0].steps.prefix(1))
                plans[1].steps = Array(ExerciseLibrary.all.prefix(12)).enumerated().map { index, exercise in
                    PlanStep(id: "tall-card-\(index)", exerciseId: exercise.id, sets: 3, reps: 10)
                }
            }
            data.coachSession.currentRoutines = plans
            data.coachSession.messages = [CoachMessage(role: .assistant, text: "", plans: plans)]
        }
        if scene == "coach-session" {
            data.settings.debugProUnlock = true
            let request = CoachSessionRequest(sourceQuote: "30-minute abs workout", durationMinutes: 30, focusMuscles: [.core])
            let plan = Plan(id: "plan-ai-single-ui-test", name: "Core", steps: ["crunch", "plank", "dead_bug", "leg_raise_lying"].enumerated().map {
                PlanStep(id: "single-\($0.offset)", exerciseId: $0.element, sets: 3, reps: 12)
            }, createdAt: Date(), updatedAt: Date(), autoGenerated: true, source: .ai)
            data.coachSession.currentRoutines = data.plans
            data.finishCoachSession(plan: plan, request: request)
        }
        if scene == "coach-photo-report" {
            data.settings.debugProUnlock = true
            var report = CoachMessage(role: .assistant, text: "Synthetic report: visible upper-body development; photo angle limits assessment. Optional focus: balanced chest and back work.")
            report.bodyPhotoPlanFocus = "Optional balanced chest and back work, within existing training preferences."
            report.bodyPhotoFocusMuscles = [.chest, .back]
            if ProcessInfo.processInfo.environment["MASO_MARKETING_BODY_PHOTO"] == "1",
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let image = try? Data(contentsOf: directory.appendingPathComponent("marketing-body-photo.jpg")) {
                report.text = "Your upper body appears balanced from this angle. A clear view of your back and legs would help complete the picture."
                data.coachSession.messages = [CoachMessage(role: .user, text: "Can you review my physique?", photoData: image), report]
            } else {
                data.coachSession.messages = [report]
            }
        }
        if scene == "coach-image-local" || scene == "coach-image-live" || scene == "coach-image-choice" {
            data.settings.debugProUnlock = true
        }
        if scene == "coach-image-choice" {
            let jpeg = CoachImageTestFixture.image(kind: "unknown").jpegData(compressionQuality: 0.8)!
            var message = CoachMessage(role: .assistant, text: "Synthetic mixed image: choose its use.")
            var review = CoachPhotoReview(jpeg: jpeg, caption: nil, kind: .unknown)
            review.needsChoice = true
            review.possibleKinds = [.body, .photo]
            if ProcessInfo.processInfo.environment["MASO_IMAGE_FIXTURE"] == "error" { review.failed = true }
            message.photoReview = review
            data.coachSession.messages = [message]
        }
        if scene == "classics-save" { data.settings.debugProUnlock = true }
        if ProcessInfo.processInfo.environment["MASO_TEST_FREE_USER"] == "1" {
            data.settings.debugProUnlock = false
            data.settings.proSubscription = nil
            data.settings.polarProActive = false
        }
        if ProcessInfo.processInfo.environment["MASO_TEST_EMPTY_MEALS"] == "1" {
            data.settings.mealCheckIns = []
        }
        if scene == "workout-report" {
            if ProcessInfo.processInfo.environment["MASO_REPORT_HEART_ENABLED"] == "1" {
                data.settings.workoutHeartRateEnabled = true
            }
            if ProcessInfo.processInfo.environment["MASO_REPORT_UNIT_LB"] == "1" { data.settings.weightUnit = .lb }
            let start = Date().addingTimeInterval(-600)
            data.sets = (0..<3).map { index in
                var record = SetRecord(id: "report-\(index)", exerciseId: "bench_press_barbell", exerciseName: "Bench Press", category: .strength,
                    weight: 40, reps: 8, performedAt: start.addingTimeInterval(Double(index * 70 + 25)), planId: "report")
                record.planName = "Upper body & core"; record.workoutSessionID = "ui-report"; record.stepID = "step"; record.setNumber = index + 1
                record.activeIntervals = [.init(start: start.addingTimeInterval(Double(index * 70)), end: record.performedAt)]
                record.restBeforeSeconds = index == 0 ? nil : 45
                return record
            }
            var row = SetRecord(id: "report-row", exerciseId: "lat_pulldown", exerciseName: "Lat Pulldown", category: .strength, weight: 30, reps: 10, performedAt: start.addingTimeInterval(255), planId: "report")
            row.planName = "Upper body & core"; row.workoutSessionID = "ui-report"; row.stepID = "row"; row.setNumber = 1
            row.activeIntervals = [.init(start: start.addingTimeInterval(220), end: row.performedAt)]
            data.sets.append(row)
            for second in stride(from: 0, to: ProcessInfo.processInfo.environment["MASO_REPORT_NO_HEART"] == "1" ? 0 : 260, by: 5) {
                let rangeExample = [95.0, 105, 120, 132, 150]
                let bpm = (70..<95).contains(second) ? rangeExample[(second - 70) / 5] : Double(150 + second % 10)
                var sample = WorkoutHeartSample(id: "report-heart-\(second)", sessionID: "ui-report", date: start.addingTimeInterval(Double(second)), bpm: bpm, source: "Test fixture")
                sample.reminderLimit = 145
                WorkoutHeartLocalStore.shared.append(sample)
            }
            if ProcessInfo.processInfo.environment["MASO_REPORT_WIDE"] == "1" {
                for index in 0..<5 {
                    let intervalStart = start.addingTimeInterval(Double(300 + index * 50))
                    var record = SetRecord(id: "report-extra-\(index)", exerciseId: "lat_pulldown", exerciseName: "Lat Pulldown", category: .strength, weight: 30, reps: 10, performedAt: intervalStart.addingTimeInterval(40), planId: "report")
                    record.workoutSessionID = "ui-report"; record.stepID = "extra-\(index)"; record.setNumber = 1
                    record.activeIntervals = [.init(start: intervalStart, end: record.performedAt)]
                    data.sets.append(record)
                    for second in stride(from: 5, through: 35, by: 10) {
                        var sample = WorkoutHeartSample(id: "report-extra-\(index)-\(second)", sessionID: "ui-report", date: intervalStart.addingTimeInterval(Double(second)), bpm: 140, source: "Test fixture")
                        sample.reminderLimit = 145
                        WorkoutHeartLocalStore.shared.append(sample)
                    }
                }
            }
        }
        if scene == "workout-history-cards", ProcessInfo.processInfo.environment["MASO_HISTORY_PHOTO"] == "1",
           let session = data.recordedWorkoutSessions().first,
           let jpeg = Self.shareFixturePhoto().jpegData(compressionQuality: 0.8) {
            data.settings.sessionPhotos[session.id] = jpeg
        }
        if ProcessInfo.processInfo.environment["MASO_CROSS_REFERENCE_HISTORY"] == "1" {
            data.plans = []; data.settings.gender = .male; data.settings.age = 25
            data.sets = [SetRecord(id: "cross-reference-ui", exerciseId: "bench_press_barbell", exerciseName: "Bench Press",
                category: .strength, weight: 50, reps: 6, duration: nil,
                performedAt: Date().addingTimeInterval(-86400), planId: nil)]
        }
        _data = State(initialValue: data)
        if ["short-player", "long-player", "stable-player"].contains(scene), let exercise = data.exById[ProcessInfo.processInfo.environment["MASO_MARKETING_EXERCISE_ID"] ?? (ProcessInfo.processInfo.environment["MASO_MARKETING_PLAYER"] == "1" ? "barbell_row" : "bench_press_barbell")] {
            var firstClockRead = true
            let heartFixture = ProcessInfo.processInfo.environment["MASO_WORKOUT_HEART_FIXTURE"] == "1"
            let player = TrainingSessionStore(completionSound: {}, clock: {
                let date = Date()
                defer { firstClockRead = false }
                return heartFixture && firstClockRead ? date.addingTimeInterval(-60) : date
            })
            var exercises = scene == "stable-player" ? [exercise, data.exById["incline_bench_press_barbell"]!] :
                (scene == "long-player" ? Array(data.exercises.prefix(12)) : [exercise])
            if ProcessInfo.processInfo.environment["MASO_CROSS_EXERCISE_ESTIMATE"] == "1" {
                exercises = [data.exById["bicep_curl_barbell"]!, data.exById["overhead_extension_dumbbell_two_hand"]!]
            }
            var plan = Plan(id: "ui-short", name: "Playlist", steps: exercises.enumerated().map { index, ex in
                PlanStep(id: "queue-step-\(index)", exerciseId: ex.id, sets: scene == "stable-player" ? 3 : 2, reps: 8, weight: ProcessInfo.processInfo.environment["MASO_TEST_EMPTY_WEIGHT"] == "1" ? nil : (ProcessInfo.processInfo.environment["MASO_MARKETING_PLAYER"] == "1" ? 50 : 60), duration: nil)
            }, createdAt: Date(), updatedAt: Date())
            if ProcessInfo.processInfo.environment["MASO_ROUGH_LOAD_ESTIMATE"] == "1" {
                data.plans = []; data.sets = []; data.settings.exerciseWeightInputs = nil
                data.settings.confirmedExerciseWeightInputIDs = nil
                data.settings.hasSeenWeightEstimateExplanation = nil
                plan.steps[1].weight = nil
                plan.steps.append(.init(id: "queue-step-2", exerciseId: "triceps_pushdown_straight_bar",
                                        sets: 3, reps: 8, duration: nil))
            }
            if ProcessInfo.processInfo.environment["MASO_PARAMETER_SUGGESTIONS"] == "1" {
                data.plans = []; data.settings.exerciseWeightInputs = nil
                data.sets = [SetRecord(id: "suggestion-history", exerciseId: exercise.id, exerciseName: exercise.name,
                    category: .strength, weight: 42.5, reps: 9, duration: nil,
                    performedAt: Date().addingTimeInterval(-86400), planId: nil)]
                plan.steps = exercises.enumerated().map { index, ex in
                    data.makeSeededStep(for: ex, stepId: "queue-step-\(index)")
                }
            }
            if ProcessInfo.processInfo.environment["MASO_CROSS_EXERCISE_ESTIMATE"] == "1" {
                data.plans = []; data.settings.gender = .male; data.settings.age = 25
                data.settings.exerciseWeightInputs = nil
                var record = SetRecord(id: "cross-reference-ui", exerciseId: "bench_press_barbell", exerciseName: "Bench Press",
                    category: .strength, weight: 50, reps: 6, duration: nil,
                    performedAt: Date().addingTimeInterval(-86400), planId: nil)
                record.sixRMReference = SixRMReference(kilograms: 50)
                data.sets = [record]
                plan.steps = exercises.enumerated().map { index, ex in
                    data.makeSeededStep(for: ex, stepId: "queue-step-\(index)")
                }
            }
            if ProcessInfo.processInfo.environment["MASO_PERSONAL_EXERCISE_ESTIMATE"] == "1" {
                data.plans = []; data.sets = []; data.settings.exerciseWeightInputs = nil
                data.settings.confirmedExerciseWeightInputIDs = nil
                data.settings.gender = nil; data.settings.age = nil
                for index in 0..<6 {
                    let day = index == 5 ? -1 : -70 + index * 7
                    let sourceWeight = index == 5 ? 63.0 : 50 + Double(index) * 2.5
                    for id in index == 5 ? ["bench_press_barbell"] : ["bench_press_barbell", "bicep_curl_barbell"] {
                        for number in 1...2 {
                            data.sets.append(SetRecord(id: "personal-\(index)-\(id)-\(number)", exerciseId: id,
                                exerciseName: id, category: .strength, weight: id == "bench_press_barbell" ? sourceWeight : sourceWeight / 2,
                                reps: 8, duration: nil, performedAt: Date().addingTimeInterval(Double(day) * 86400 + Double(number)),
                                planId: nil, workoutSessionID: "personal-\(index)", setNumber: number))
                        }
                    }
                }
                plan.steps = [data.makeSeededStep(for: data.exById["bicep_curl_barbell"]!, stepId: "queue-step-0")]
            }
            if ProcessInfo.processInfo.environment["MASO_QUIET_PROGRESSION"] == "1" {
                data.plans = []; data.sets = []; data.settings.loadProgression = nil
                data.settings.trainingGoalKind = .buildMuscle
                for day in 0..<3 {
                    for n in 1...3 {
                        data.sets.append(SetRecord(id: "quiet-\(day)-\(n)", exerciseId: exercise.id, exerciseName: exercise.name,
                            category: .strength, weight: 50, reps: 12, duration: nil,
                            performedAt: Date().addingTimeInterval(-Double(2 + day * 2) * 86400 + Double(n)),
                            planId: nil, workoutSessionID: "quiet-\(day)", setNumber: n))
                    }
                }
                plan.steps = [.init(id: "queue-step-0", exerciseId: exercise.id, sets: 3, reps: 8, weight: 50, duration: nil)]
            }
            player.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120))
            _session = State(initialValue: player)
        }
    }

    /// Seeds the finished-session report. History stays a pushed screen; the player scenes
    /// are a completed workout, with or without a real routine diff.
    fileprivate static func sessionReportPlayer(scene: String, data: DataStore, player: TrainingSessionStore) -> TrainingSessionStore? {
        let history = scene == "session-report-history"
        let changed = scene == "session-report-changed-player"
        guard history || changed || scene == "session-report-clean-player",
              let exercise = data.exById["bench_press_barbell"] else { return nil }
        data.settings.hasOfferedReminderPrompt = true
        data.settings.hasRequestedReview = true
        let end = Date()
        let start = end.addingTimeInterval(-40)
        func record(sessionID: String) -> SetRecord {
            var value = SetRecord(id: "session-report-set", exerciseId: exercise.id, exerciseName: exercise.name,
                category: .strength, weight: 60, reps: 8, duration: nil, performedAt: end,
                planId: "ui-session-report")
            value.workoutSessionID = sessionID
            value.stepID = "step-bench"
            value.setNumber = 1
            value.activeIntervals = [.init(start: start, end: end)]
            return value
        }
        func heart(sessionID: String) {
            for offset in [5.0, 10, 15, 20] {
                WorkoutHeartLocalStore.shared.append(WorkoutHeartSample(
                    id: "session-report-heart-\(sessionID)-\(Int(offset))",
                    sessionID: sessionID,
                    date: start.addingTimeInterval(offset),
                    bpm: 110 + offset,
                    source: "Test fixture"))
            }
        }
        if history {
            data.sets = [record(sessionID: "ui-session-report")]
            heart(sessionID: "ui-session-report")
            return nil
        }
        let plan = Plan(id: "ui-session-report", name: "Push", steps: [
            PlanStep(id: "step-bench", exerciseId: exercise.id, sets: 2, reps: 8, weight: 60, duration: nil)
        ], createdAt: end, updatedAt: end)
        data.plans = [plan]
        player.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120))
        let sessionID = player.workoutSessionID ?? "ui-session-report"
        data.sets = [record(sessionID: sessionID)]
        heart(sessionID: sessionID)
        if changed { player.updateStepWeight(stepId: "step-bench", weightKg: 62.5) }
        player.finishEarly()
        return player
    }

    var body: some View {
        AppNavigationStack {
            VStack(spacing: 16) {
                Text("Exercise UI test")
                Text(String(pickedIDs.count)).accessibilityIdentifier("exercise.ui-test.selection-count")
                Text(pickedIDs.last ?? "none").accessibilityIdentifier("exercise.ui-test.selection-id")
                Text(String(dismissalCount)).accessibilityIdentifier("exercise.ui-test.dismissal-count")
                Button("Open exercise scene") { presented = true }
                    .accessibilityIdentifier("exercise.ui-test.open")
            }
        }
        .sheet(isPresented: Binding(get: { presented && !scene.hasSuffix("-player") }, set: { presented = $0 }), onDismiss: { dismissalCount += 1 }) {
            page.presentationDetents([.large]).presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: Binding(get: { presented && scene.hasSuffix("-player") }, set: { presented = $0 }), onDismiss: { session.youtubePlayback.minimize() }) {
            // The cover does not inherit Dynamic Type from modifiers outside this closure.
            Group {
                if ProcessInfo.processInfo.environment["MASO_TEST_NARROW"] == "1" {
                    page.frame(width: 320).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    page
                }
            }
            .modifier(SessionReportLargeType())
        }
        .background {
            WorkoutYouTubeRetentionHost(playback: session.youtubePlayback)
                .frame(width: 1, height: 1).allowsHitTesting(false).accessibilityHidden(true)
        }
        .environment(data)
        .environment(session)
        .environment(subscriptions)
        .environment(\.locale, LanguageManager.currentLocale)
        .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight)
        .preferredColorScheme(ProcessInfo.processInfo.environment["MASO_TEST_COLOR_SCHEME"] == "light" ? .light : .dark)
        .modifier(SessionReportLargeType())
        .tint(MasoColor.text)
        .task {
            presented = true
            if ProcessInfo.processInfo.environment["MASO_WORKOUT_HEART_FIXTURE"] == "1" {
                // Simulate live samples after the native full-screen player has appeared.
                // A warning pre-seeded before presentation is not the live sensor flow.
                try? await Task.sleep(for: .seconds(2))
                if let key = session.workoutSessionID, let start = session.session?.startedAt {
                    // Marketing capture: a lower personal limit lets a plausible reading sit
                    // above it, so the reminder state is real UI state instead of a staged tint.
                    let limit = Int(ProcessInfo.processInfo.environment["MASO_TEST_HEART_LIMIT"] ?? "") ?? 180
                    data.settings.workoutHeartRateEnabled = true; data.settings.workoutHeartRateLimit = limit
                    // Marketing capture: show the full heart-rate card instead of the
                    // compact capsule, so a mid-range reading reads as a card.
                    if ProcessInfo.processInfo.environment["MASO_WORKOUT_HEART_CARD"] == "1" {
                        data.settings.workoutHeartRateShowCard = true
                    }
                    session.heartRate.bind(sessionID: key, start: start, enabled: true, limit: limit)
                    if ProcessInfo.processInfo.environment["MASO_TEST_HEART_ASSIST"] == "1" {
                        data.settings.workoutHeartRateAutomaticEnabled = true
                        let rest = ProcessInfo.processInfo.environment["MASO_TEST_HEART_ASSIST_REST"] == "1"
                        if rest { try? await Task.sleep(for: .seconds(4)) }
                        let values = rest ? [116.0, 124.0, 130.0] : [116.0, 124.0, 130.0, 124.0, 116.0]
                        for (index, bpm) in values.enumerated() {
                            let sampleTime = Date()
                            session.heartRate.receive(.init(id: UUID().uuidString, sessionID: key, date: sampleTime, bpm: bpm, source: "Test fixture"), now: sampleTime)
                            if index < values.count - 1 { try? await Task.sleep(for: .seconds(8)) }
                        }
                        return
                    }
                    // Sensor-input fixture only: preserve a real compact-control phase before high readings.
                    if let delay = Double(ProcessInfo.processInfo.environment["MASO_TEST_HEART_SAMPLE_DELAY"] ?? ""), delay > 0 {
                        let initial = Date()
                        session.heartRate.receive(.init(id: UUID().uuidString, sessionID: key, date: initial, bpm: 128, source: "Test fixture"), now: initial)
                        try? await Task.sleep(for: .seconds(min(delay, 20)))
                    }
                    let now = Date()
                    for offset in [-16.0, -8, 0] {
                        let bpm: Double = Double(ProcessInfo.processInfo.environment["MASO_TEST_HEART_BPM"] ?? "") ??
                            (ProcessInfo.processInfo.environment["MASO_MARKETING_PLAYER"] == "1" ? 128 :
                            (ProcessInfo.processInfo.environment["MASO_TEST_ESCALATED_HEART"] == "1" ? 230 : 193))
                        session.heartRate.receive(.init(id: UUID().uuidString, sessionID: key, date: now.addingTimeInterval(offset), bpm: bpm, source: "Test fixture"), now: now)
                    }
                    if ProcessInfo.processInfo.environment["MASO_MARKETING_PLAYER"] == "1" {
                        var sentBriefDip = false
                        while !Task.isCancelled {
                            try? await Task.sleep(for: .seconds(5))
                            let sampleTime = Date()
                            let dip = ProcessInfo.processInfo.environment["MASO_TEST_HEART_BRIEF_DIP"] == "1" && session.heartRate.warningPending && !sentBriefDip
                            if dip { sentBriefDip = true }
                            let bpm = dip ? 160 : (Double(ProcessInfo.processInfo.environment["MASO_TEST_HEART_BPM"] ?? "") ?? 128)
                            session.heartRate.receive(.init(id: UUID().uuidString, sessionID: key, date: sampleTime, bpm: bpm, source: "Test fixture"), now: sampleTime)
                        }
                    }
                }
            }
        }
    }

    private static func shareFixturePhoto() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 300, height: 100)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.green.setFill(); context.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
            UIColor.blue.setFill(); context.fill(CGRect(x: 200, y: 0, width: 100, height: 100))
        }
    }

    @ViewBuilder private var page: some View {
        if scene == "coach-live" || scene == "coach-frequency" || scene == "coach-save" || scene == "coach-session" || scene == "coach-photo-report" || scene.hasPrefix("coach-image-") {
            CoachScreen(onStart: { plan in
                let plan = data.routinePlanDefaults(plan)
                session.start(planId: plan.id, plan: plan,
                    segments: expandPlan(plan, exById: data.exById, defaultRest: data.settings.defaultRestSeconds,
                        defaultBetweenExerciseRest: data.settings.defaultBetweenExerciseRestSeconds), source: "ai")
                coachWorkoutPresented = true
            }, onNewPlan: {}, libraryRequested: .constant(false), routinePromptRequested: .constant(false))
                .fullScreenCover(isPresented: $coachWorkoutPresented) {
                    PlanPlayerScreen().onChange(of: session.session?.planId) { _, id in
                        if id == nil { coachWorkoutPresented = false }
                    }
                }
                .onAppear {
                    if (scene == "coach-image-local" || scene == "coach-image-live"), data.coachSession.messages.isEmpty {
                        let kind = ProcessInfo.processInfo.environment["MASO_IMAGE_FIXTURE"] ?? "qr"
                        let plan = Plan(id: "qr-reference", name: "Shared exact routine", steps: [.init(id: "qr-step", exerciseId: "bench_press_barbell", sets: 3, reps: 8, weight: 60)], createdAt: Date(), updatedAt: Date())
                        let image = CoachImageTestFixture.image(kind: kind, plan: plan)
                        data.startCoachGenerate(feedback: ProcessInfo.processInfo.environment["MASO_IMAGE_CAPTION"],
                                                displayText: NSLocalizedString("Review this image", comment: ""),
                                                photoData: CoachScreen.prepareBodyPhoto(image))
                    }
                }
                .overlay(alignment: .top) {
                    if ProcessInfo.processInfo.environment["MASO_MARKETING_BODY_PHOTO"] != "1" {
                    VStack {
                        Text(coachDiagnostic).font(.caption2).accessibilityIdentifier("coach.test.status")
                        Text(String(data.plans.count)).font(.caption2).accessibilityIdentifier("routine.test.saved-count")
                        if scene.hasPrefix("coach-image-") {
                            Text(data.coachSession.messages.last(where: { $0.photoReview != nil })?.photoReview?.kind.rawValue ?? "pending")
                                .font(.caption2).accessibilityIdentifier("coach.image.test.kind")
                            Text(String(data.settings.mealCheckIns?.count ?? 0)).font(.caption2).accessibilityIdentifier("coach.image.test.meals")
                            Text(String(data.coachSession.currentSessionPlan?.steps.count ?? 0)).font(.caption2).accessibilityIdentifier("coach.image.test.steps").accessibilityValue(coachImageIDsDiagnostic)
                            if let meal = data.coachSession.messages.last(where: { $0.photoReview?.meal != nil })?.photoReview?.meal {
                                Text("\(meal.nutrition.protein),\(meal.nutrition.carbs),\(meal.nutrition.fat)")
                                    .font(.caption2).accessibilityIdentifier("coach.image.test.macros")
                            }
                        }
                    }
                    }
                }
        } else if scene == "classics-save" {
            AppNavigationStack { ClassicsScreen(onStart: { _ in }) }
        } else if scene == "home-overview" {
            AppNavigationStack { ScrollView { DailyOverviewCard(onReplay: { _ in }).padding(16) } }
        } else if ["short-player", "long-player", "stable-player", "session-report-clean-player", "session-report-changed-player"].contains(scene) {
            PlanPlayerScreen()
        } else if scene == "session-report-history" {
            SessionReportHistoryProbe(records: data.sets)
        } else if scene == "workout-report" {
            AppNavigationStack { WorkoutReportView(records: data.sets) }
        } else if scene == "sleep-chart" {
            let start = data.settings.calendar.startOfDay(for: Date()).addingTimeInterval(-2 * 3600 - 17 * 60)
            let intervals = [
                SleepStageInterval(value: 3, start: start, end: start.addingTimeInterval(3600)),
                SleepStageInterval(value: 4, start: start.addingTimeInterval(3600), end: start.addingTimeInterval(3 * 3600)),
                SleepStageInterval(value: 5, start: start.addingTimeInterval(3 * 3600), end: start.addingTimeInterval(7 * 3600 + 13 * 60))
            ]
            AppNavigationStack {
                ScrollView {
                    SleepNightChart(day: Date(), intervals: intervals, minutes: 433)
                        .padding(MasoMetrics.pagePaddingHorizontal)
                }.background(MasoColor.background).navigationTitle("Sleep")
            }
        } else if scene == "workout-history-detail", let session = data.recordedWorkoutSessions().first {
            SessionDetailSheet(session: session, exerciseStats: data.recordedExerciseStats(for: session),
                               replayPlan: data.recordedReplayPlan(for: session), onReplay: { _ in })
        } else if scene == "workout-history-cards" {
            AppNavigationStack { RecordHistoryArchiveScreen(kind: .workout) }
        } else if scene == "free-picker" {
            ExercisePickerSheet(onPick: { pickedIDs.append($0.id) }, directPick: true,
                pickerTitle: "What would you like to train next?", onFinishWorkout: { presented = false },
                onPickConfigured: { ex, _ in pickedIDs.append(ex.id) })
        } else if scene == "preferences" {
            TrainingPreferencesSheet(onConfirm: {})
        } else if scene == "settings-ai" {
            SettingsScreen(onStartWorkout: { _ in })
        } else if scene == "share-layout" || scene == "share-layout-photo" {
            ShareCustomizeSheet(previewTitle: "Workout", defaultSections: ShareSections(workout: true),
                                initialPhoto: scene == "share-layout-photo" ? Self.shareFixturePhoto() : nil,
                                shareSurface: "ui-test") { photo, onTap, _ in
                WorkoutDetailShareCard(planName: "Upper body", muscles: [.chest], detail: [],
                                       setCount: 4, totalVolumeKg: 120, durationLabel: "30 min",
                                       qrPayload: MasoLinks.appStore, userPhoto: photo, onTapAddPhoto: onTap,
                                       footerQRSize: 64)
            }
        } else if scene == "diet-health" {
            AppNavigationStack { SettingsScreen(onStartWorkout: { _ in }, isPushed: true) }
        } else if scene == "body-profile-empty" {
            AppNavigationStack { BodyProfileScreen() }
        } else if scene == "diet-targets" {
            AppNavigationStack { DietScreen() }
        } else if scene == "meal-live" {
            DietScreen()
                .overlay(alignment: .top) {
                    Text("saved: \(data.settings.mealCheckIns?.count ?? 0)")
                        .font(.caption2).accessibilityIdentifier("meal.test.status")
                }
        } else if scene == "library" {
            ExerciseLibraryBrowser()
        } else {
            ExercisePickerSheet(onPick: { pickedIDs.append($0.id) }, initialMuscle: scene == "replace" ? .chest : nil,
                replacingExerciseId: scene == "replace" ? "bench_press_barbell" : nil,
                pickerTitle: scene == "replace" ? "Replace exercise" : "Choose exercise")
        }
    }

    private var coachImageIDsDiagnostic: String {
        if let plan = data.coachSession.currentSessionPlan { return plan.steps.map(\.exerciseId).joined(separator: ",") }
        guard let review = data.coachSession.messages.last(where: { $0.photoReview != nil })?.photoReview else { return "" }
        return "IDs=" + review.exerciseIDs.joined(separator: ",") + "; Names=" + review.exerciseNames.joined(separator: " | ")
    }

    private var coachDiagnostic: String {
        if data.coachSession.isGenerating { return "generating" }
        if let failure = data.coachSession.fallbackNote { return "fallback: " + failure }
        if data.coachSession.latestIsSingleWorkout, data.coachSession.currentSessionPlan != nil { return "success: 1" }
        if data.coachSession.currentRoutines.isEmpty { return "idle" }
        if data.coachSession.lastRoundUsedFallback { return "fallback: " + (data.coachSession.fallbackNote ?? "") }
        return "success: \(data.coachSession.currentRoutines.count)"
    }
}
@MainActor
enum CoachImageTestFixture {
    static func image(kind: String, plan: Plan? = nil) -> UIImage {
        if kind == "routine-eight", let encoded = ProcessInfo.processInfo.environment["MASO_TEST_ROUTINE_IMAGE"],
           let bytes = Data(base64Encoded: encoded), let image = UIImage(data: bytes) { return image }
        return UIGraphicsImageRenderer(size: CGSize(width: 900, height: 900)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 900, height: 900))
            let text: String
            switch kind {
            case "qr": text = "Masso shared training plan"
            case "routine-eight": text = "视频里提到的 8 个动作如下：\n1. Pull-ups — 引体向上\n2. Dips — 双杠臂屈伸\n3. Push-ups — 俯卧撑\n4. Rows — 自重划船\n5. Pike push-ups — 折刀俯卧撑\n6. Squats — 深蹲\n7. Lunges — 箭步蹲\n8. RDLs — 罗马尼亚硬拉\n训练方式是每天只练其中一个动作，8 个动作轮着来，每个动作做 20 组，每分钟一组，每组 1～10 次。"
            case "routine": text = "Workout A\nBench Press (Barbell) 3 x 8 60 kg\nSquat (Barbell) 3 x 10 80 kg"
            case "label": text = "NUTRITION FACTS\nServing size 100 g\nCalories 290 kcal\nProtein 20 g\nTotal carbohydrate 30 g\nTotal fat 10 g"
            case "records": text = "Sleep\n21 October 2026\nTotal sleep 7 hr 30 min\nDeep 1 hr 20 min\nREM 1 hr 45 min"
            case "bug": text = "Masso AI Coach\nRequest failed\nHTTP 403\nPlease try again"
            default: text = "Synthetic image for interface routing tests"
            }
            (text as NSString).draw(in: CGRect(x: 50, y: 35, width: 800, height: 800),
                withAttributes: [.font: UIFont.systemFont(ofSize: 34), .foregroundColor: UIColor.black])
            if kind == "qr", let plan, let payload = PlanShareCodec.appStoreDataLink(for: [plan]),
               let filter = CIFilter(name: "CIQRCodeGenerator") {
                filter.setValue(Data(payload.utf8), forKey: "inputMessage")
                filter.setValue("M", forKey: "inputCorrectionLevel")
                if let output = filter.outputImage,
                   let cg = CIContext().createCGImage(output, from: output.extent) {
                    context.cgContext.interpolationQuality = .none
                    UIImage(cgImage: cg).draw(in: CGRect(x: 100, y: 140, width: 700, height: 700))
                }
            }
        }
    }
}

/// Only the large-type fixture overrides Dynamic Type. Other scenes keep the system size.
private struct SessionReportLargeType: ViewModifier {
    func body(content: Content) -> some View {
        if ProcessInfo.processInfo.environment["MASO_TEST_LARGE_TYPE"] == "1" {
            content.environment(\.dynamicTypeSize, .accessibility3)
        } else {
            content
        }
    }
}

/// Test-only stack around the history report. Production history keeps its own system Back.
private struct SessionReportHistoryProbe: View {
    let records: [SetRecord]
    @State private var path = NavigationPath()

    var body: some View {
        AppNavigationStack(path: $path) {
            Button("Open session report") { path.append("report") }
                .accessibilityIdentifier("workout.sessionReport.openHistory")
                .navigationTitle("History")
                .navigationDestination(for: String.self) { _ in
                    WorkoutSessionReportScreen(records: records, workoutName: "Push", presentation: .history)
                        .navigationBarBackButtonHidden(true)
                        .toolbar {
                            ToolbarItem(placement: .topBarLeading) {
                                Button("Back") { path.removeLast() }
                                    .accessibilityIdentifier("workout.sessionReport.historyBack")
                            }
                        }
                }
        }
    }
}

#endif
