import SwiftUI
#if DEBUG
import Foundation
import HealthKit

/// Synthetic, local-only records used exclusively by the screenshot launch mode.
/// No purchase, HealthKit write, remote AI request or user-data import is made.
@MainActor enum MarketingCaptureSeed {
    static func apply(to data: DataStore) {
        guard ProcessInfo.processInfo.environment["MASO_SHOWCASE_SEED"] == "1" else { return }
        data.settings.coachIntroTipPending = false
        data.settings.coachBodyPhotoTipSeen = true
        data.settings.firstHomeMuscleIntroPending = false
        data.settings.debugProUnlock = true
        if ProcessInfo.processInfo.environment["MASO_MARKETING_MUSCLE"] == "1" {
            let isMorning = ProcessInfo.processInfo.environment["MASO_MARKETING_MORNING"] == "1"
            let workoutDate = Date().addingTimeInterval(ProcessInfo.processInfo.environment["MASO_MARKETING_GYM"] == "1" ? -72 * 3600 : (isMorning ? -26 * 3600 : -3600))
            data.sets = (0..<3).map { index in
                SetRecord(id: "marketing-recovery-\(index)", exerciseId: "bench_press_barbell", exerciseName: "Bench Press (Barbell)", category: .strength, weight: 50, reps: 8, performedAt: workoutDate, planId: nil)
            }
        }
        if ProcessInfo.processInfo.environment["MASO_MARKETING_PROGRESS"] == "1" {
            // Progress screen only: four synthetic weeks so the muscle bars are full and
            // bench press shows a real climb. Day offsets are anchored to today (never to
            // the calendar week, which can start today and collapse every record onto one
            // date). Never mixed into the recovery, plan or player captures.
            let calendar = data.settings.calendar
            let now = Date()
            let today = calendar.startOfDay(for: now)
            var cursor = 0
            func add(_ daysAgo: Int, _ id: String, _ name: String, weight: Double?, reps: Int?, duration: Int? = nil, sets: Int) {
                guard let day = calendar.date(byAdding: .day, value: -daysAgo, to: today) else { return }
                let base = min(day.addingTimeInterval(18 * 3600), now.addingTimeInterval(-180))
                for index in 0..<sets {
                    cursor += 1
                    let performedAt = min(base.addingTimeInterval(Double(index) * 180), now.addingTimeInterval(-120))
                    data.sets.append(SetRecord(id: "marketing-progress-\(cursor)", exerciseId: id, exerciseName: name,
                                               category: duration == nil ? .strength : .calisthenics,
                                               weight: weight, reps: reps, duration: duration,
                                               performedAt: performedAt, planId: "marketing-progress",
                                               planName: nil, workoutSessionID: "marketing-progress-day-\(daysAgo)",
                                               stepID: "marketing-progress-step-\(cursor)", setNumber: index + 1))
                }
            }
            add(21, "bench_press_barbell", "Bench Press (Barbell)", weight: 45, reps: 8, sets: 3)
            add(21, "incline_bench_press_barbell", "Incline Press (Barbell)", weight: 35, reps: 10, sets: 2)
            add(17, "lat_pulldown", "Lat Pulldown (Cable)", weight: 40, reps: 10, sets: 3)
            add(17, "barbell_row", "Row (Barbell)", weight: 40, reps: 8, sets: 2)
            add(14, "squat_barbell", "Squat (Barbell)", weight: 55, reps: 8, sets: 3)
            add(14, "leg_curl_lying", "Leg Curl (Machine)", weight: 25, reps: 12, sets: 2)
            add(12, "bench_press_barbell", "Bench Press (Barbell)", weight: 47.5, reps: 8, sets: 3)
            add(12, "incline_bench_press_barbell", "Incline Press (Barbell)", weight: 37.5, reps: 10, sets: 2)
            add(10, "overhead_press_barbell", "Overhead Press (Barbell)", weight: 27.5, reps: 8, sets: 2)
            add(10, "lateral_raise_dumbbell", "Lateral Raise (Dumbbell)", weight: 7, reps: 12, sets: 2)
            add(7, "bench_press_barbell", "Bench Press (Barbell)", weight: 50, reps: 8, sets: 3)
            add(7, "bicep_curl_dumbbell", "Bicep Curl (Dumbbell)", weight: 12, reps: 12, sets: 2)
            add(7, "triceps_pushdown_rope", "Triceps Pushdown (Cable)", weight: 25, reps: 12, sets: 2)
            add(5, "lat_pulldown", "Lat Pulldown (Cable)", weight: 45, reps: 10, sets: 3)
            add(5, "barbell_row", "Row (Barbell)", weight: 45, reps: 8, sets: 2)
            add(4, "squat_barbell", "Squat (Barbell)", weight: 60, reps: 8, sets: 3)
            add(4, "leg_curl_lying", "Leg Curl (Machine)", weight: 30, reps: 12, sets: 2)
            add(3, "overhead_press_barbell", "Overhead Press (Barbell)", weight: 30, reps: 8, sets: 2)
            add(3, "lateral_raise_dumbbell", "Lateral Raise (Dumbbell)", weight: 8, reps: 12, sets: 2)
            add(2, "bench_press_barbell", "Bench Press (Barbell)", weight: 52.5, reps: 8, sets: 3)
            add(2, "cable_crossover_mid", "Cable Crossover (Cable)", weight: 15, reps: 12, sets: 2)
            add(1, "plank", "Plank", weight: nil, reps: nil, duration: 60, sets: 3)
            add(1, "barbell_row", "Row (Barbell)", weight: 47.5, reps: 8, sets: 2)
            add(0, "bench_press_barbell", "Bench Press (Barbell)", weight: 55, reps: 8, sets: 3)
        }
        data.settings.dietEnabled = true
        data.settings.sleepEnabled = true
        var sleep = SleepPreferences()
        sleep.durationTargetMinutes = 480
        data.settings.sleepPreferences = sleep
        let calendar = data.settings.calendar
        let today = calendar.startOfDay(for: Date())
        let marketingLanguage = LanguageManager.shared.effectiveLanguage.rawValue
        let chinese = marketingLanguage.hasPrefix("zh")
        // Demo copy only. zh-Hant must not reuse the Simplified strings: they would render
        // 简体 characters on a Traditional screenshot. Wording follows the same Taiwan
        // choices as scripts/zh_hant_tw_terms.tsv (計畫/優格/青花菜/儲存/週).
        let hant = marketingLanguage.hasPrefix("zh-Hant") || marketingLanguage.hasPrefix("zh-TW")
            || marketingLanguage.hasPrefix("zh-HK")
        data.settings.mealCheckIns = [
            MealCheckIn(day: today, mealID: "preview-breakfast", title: "Breakfast", photoFilename: "",
                        foods: chinese ? (hant ? "雞蛋、優格和燕麥" : "鸡蛋、酸奶和燕麦") : "Eggs, yogurt and oats",
                        nutrition: .init(protein: 36, carbs: 54, fat: 18),
                        confirmedAt: calendar.date(byAdding: .hour, value: 8, to: today)!),
            MealCheckIn(day: today, mealID: "preview-lunch", title: "Lunch", photoFilename: "",
                        foods: chinese ? (hant ? "雞肉、米飯和青花菜" : "鸡肉、米饭和西兰花") : "Chicken, rice and broccoli",
                        nutrition: .init(protein: 48, carbs: 82, fat: 20),
                        confirmedAt: calendar.date(byAdding: .hour, value: 13, to: today)!)
        ]
        if ProcessInfo.processInfo.environment["MASO_MARKETING_REAL_SCREENS"] == "1" {
            let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
            let earlier = calendar.date(byAdding: .day, value: -2, to: today)!
            // The food line is user-entered text, but a Chinese deck must not show an English
            // entry, so it follows the same zh / zh-Hant split as the meals above. Other
            // languages keep the English names the 2026-11-06 batch already shipped.
            let chickenMeal = chinese ? (hant ? "雞肉、米飯和青花菜" : "鸡肉、米饭和西兰花") : "Chicken, rice and broccoli"
            let salmonMeal = chinese ? (hant ? "鮭魚、地瓜和沙拉" : "三文鱼、红薯和沙拉") : "Salmon, sweet potato and greens"
            data.settings.mealCheckIns = [
                MealCheckIn(day: today, mealID: "preview-lunch", title: "Lunch", photoFilename: "marketing-chicken.png",
                            foods: chickenMeal, nutrition: .init(protein: 48, carbs: 82, fat: 20),
                            confirmedAt: calendar.date(byAdding: .hour, value: 12, to: today)!),
                MealCheckIn(day: yesterday, mealID: "preview-salmon", title: "Dinner", photoFilename: "marketing-salmon.png",
                            foods: salmonMeal, nutrition: .init(protein: 42, carbs: 63, fat: 24),
                            confirmedAt: calendar.date(byAdding: .hour, value: 18, to: yesterday)!),
                MealCheckIn(day: earlier, mealID: "preview-chicken", title: "Lunch", photoFilename: "marketing-chicken.png",
                            foods: chickenMeal, nutrition: .init(protein: 48, carbs: 82, fat: 20),
                            confirmedAt: calendar.date(byAdding: .hour, value: 12, to: earlier)!)
            ]
            if let target = data.wellnessGoal(on: today) {
                data.settings.wellnessGoals = [SleepPreferences.dayKey(yesterday, calendar: calendar): target,
                                               SleepPreferences.dayKey(earlier, calendar: calendar): target]
            }
            for (offset, weight) in [(2, 50.0), (1, 55.0)] {
                let day = calendar.date(byAdding: .day, value: -offset, to: today)!
                data.sets.append(SetRecord(id: "marketing-lift-\(offset)", exerciseId: "bench_press_barbell", exerciseName: "Bench Press (Barbell)", category: .strength, weight: weight, reps: 8, performedAt: day.addingTimeInterval(12 * 3600), planId: nil))
            }
        }
        // Marketing captures must use RootView's real pushed Coach destination.
        // Only conversation data is synthetic; navigation and components are production UI.
        if let capture = ProcessInfo.processInfo.environment["MASO_MARKETING_COACH_NAVIGATION"] {
            let language = LanguageManager.shared.effectiveLanguage.rawValue
            let zh = language.hasPrefix("zh")
            let hant = language.hasPrefix("zh-Hant") || language.hasPrefix("zh-TW")
                || language.hasPrefix("zh-HK")
            let ar = language.hasPrefix("ar")
            if capture == "report",
               let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
               let photo = try? Data(contentsOf: directory.appendingPathComponent("marketing-body-photo.jpg")) {
                var report = CoachMessage(role: .assistant, text: zh ? (hant ? "從這個角度來看，你的上半身較均衡。背部和腿部照片能幫助完善分析。" : "从这个角度看，你的上半身较均衡。背部和腿部照片能帮助完善分析。") : ar ? "يبدو الجزء العلوي متوازنًا من هذه الزاوية. تساعد صور الظهر والساقين على إكمال التقييم." : "Your upper body appears balanced from this angle. A clear view of your back and legs would help complete the picture.")
                if let text = ProcessInfo.processInfo.environment["MASO_MARKETING_REPORT_TEXT"], !text.isEmpty { report.text = text }
                report.bodyPhotoPlanFocus = zh ? (hant ? "結合你的訓練偏好，均衡安排胸部和背部訓練。" : "结合你的训练偏好，均衡安排胸部和背部训练。") : ar ? "وازن تمارين الصدر والظهر بما يناسب تفضيلاتك." : "Balanced chest and back work, within your training preferences."
            report.bodyPhotoFocusMuscles = [.chest, .back]
                data.coachSession.messages = [CoachMessage(role: .user, text: zh ? (hant ? "幫我分析身材，制定均衡的週計畫。" : "帮我分析身材，制定均衡的周计划。") : ar ? "حلّل بنية جسمي وساعدني في إعداد خطة أسبوعية متوازنة." : "Review my physique and help me build a balanced week.", photoData: photo), report]
            } else if capture == "plans" {
                let plans = RecommendedPrograms.plans(forDays: 3, now: Date(), byId: data.exById).map { original in
                    var plan = original
                    plan.source = .ai
                    return plan
                }
                data.coachSession.messages = [
                    CoachMessage(role: .user, text: zh ? (hant ? "好的，按我的偏好制定週計畫，多練胸部和背部。" : "好的，按我的偏好制定周计划，多练胸部和背部。") : ar ? "نعم، أنشئ خطة تناسب تفضيلاتي مع التركيز على الصدر والظهر." : "Yes — build my week around my preferences, with extra chest and back work."),
                    CoachMessage(role: .assistant, text: zh ? (hant ? "你的週計畫已準備好，可以直接開始訓練或儲存。" : "你的周计划已准备好，可以直接开始训练或保存。") : ar ? "خطتك الأسبوعية جاهزة. ابدأ التمرين أو احفظ البطاقات." : "Your weekly plan is ready. You can start a workout or save the cards to your routines.", plans: plans)
                ]
                data.coachSession.currentRoutines = plans
                data.coachSession.versionStack = [plans]
            }
        }
        data.settings.sleepRecords = [:]
        data.settings.sleepStageRecords = [:]
        for offset in 0..<14 {
            let day = calendar.date(byAdding: .day, value: -offset, to: today)!
            let key = SleepPreferences.dayKey(day, calendar: calendar)
            data.settings.sleepRecords?[key] = Double(454 + (offset % 4) * 7)
            data.settings.sleepStageRecords?[key] = .init(deep: 74, rem: 102, core: 278, awake: 16)
        }
        HealthKitService.shared.installMarketingSleepPreview(day: today)
    }
}

#endif

/// Capture-only readiness comes from the destination actually mounting, never a timer after launch.
/// The Release build returns the original view without any capture task.
extension View {
    func marketingCaptureReady(_ scene: String) -> some View {
        #if DEBUG
        return self.task {
            let env = ProcessInfo.processInfo.environment
            guard env["MASO_SCREENSHOT_CAPTURE"] == "1", let nonce = env["MASO_CAPTURE_NONCE"],
                  nonce.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" }) else { return }
            let raw = env["MASO_SHOWCASE"] ?? ""
            let requested = raw.isEmpty ? "today" : raw == "library" ? "exercises" : raw
            guard requested == scene else { return }
            do {
                try await Task.sleep(for: .seconds(1))
                try Task.checkCancellation()
                guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
                let payload = ["scene": scene, "nonce": nonce, "language": LanguageManager.shared.effectiveLanguage.rawValue]
                let bytes = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
                try bytes.write(to: directory.appendingPathComponent("capture-ready-" + nonce + ".json"), options: .atomic)
            } catch { }
        }
        #else
        return self
        #endif
    }
}
