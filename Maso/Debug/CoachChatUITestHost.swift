import SwiftUI
import UIKit

#if DEBUG
/// Shown only for MASO_COACH_CHAT_UI_TEST. Synthetic catalog plans.
/// Pro for UpgradePrompt is not stored here; CoachScreen.send passes it only in this process.
struct CoachChatUITestHost: View {
    @State private var data = CoachChatUITestHost.makeStore()
    @State private var training = TrainingSessionStore()
    @State private var libraryRequested = false
    @State private var routinePromptRequested = false
    @State private var quickWorkoutRequested = false
    @State private var bodyPhotoRequested = false

    var body: some View {
        NavigationStack {
            CoachScreen(
                onStart: { _ in },
                onNewPlan: {},
                libraryRequested: $libraryRequested,
                routinePromptRequested: $routinePromptRequested,
                quickWorkoutRequested: $quickWorkoutRequested,
                bodyPhotoRequested: $bodyPhotoRequested)
        }
        .environment(data).environment(training)
        .environment(\.locale, LanguageManager.currentLocale)
        .environment(\.layoutDirection, LanguageManager.currentLanguageCode == "ar" ? .rightToLeft : .leftToRight)
        .environment(\.dynamicTypeSize, ProcessInfo.processInfo.environment["MASO_COACH_LARGE_TYPE"] == "1" ? .accessibility3 : .large)
        .preferredColorScheme(ProcessInfo.processInfo.environment["MASO_UI_LIGHT"] == "1" ? .light : .dark)
        .task {
            if let mode = ProcessInfo.processInfo.environment["MASO_SOURCE_EXTRACT_UI_TEST"] {
                let rows = Self.fixtureRows()
                let request = "Extract these exercises into " + (mode == "two" ? "2 cards" : "one card") + "\n" + rows.map(\.sourceQuote).joined(separator:"\n")
                let image:Data? = mode == "image" ? Self.fixtureImage(rows) : nil
                await data.coachGenerate(feedback:request, photoData:image)
            }
        }
    }

    private static func makeStore() -> DataStore {
        let library = ExerciseLibrary.all
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let plan = Plan(
            id: "plan-catalog", name: "Catalog",
            steps: [
                PlanStep(id: "bench", exerciseId: "bench_press_barbell", sets: 4, reps: 8, weight: 60, restBetweenSets: 90),
                PlanStep(id: "pullover", exerciseId: "barbell_pullover", sets: 3, reps: 10, weight: 40, restBetweenSets: 90),
                PlanStep(id: "static", exerciseId: "static_hold_bench_press", sets: 1, reps: 1, weight: 60, restBetweenSets: 90),
                PlanStep(id: "dumbbell", exerciseId: "bench_press_dumbbell", sets: 3, reps: 12, weight: 20, restBetweenSets: 60),
                PlanStep(id: "row", exerciseId: "barbell_row", sets: 4, reps: 8, weight: 50, restBetweenSets: 90),
            ],
            createdAt: now, updatedAt: now, preservesExerciseVariants: true)
        var settings = UserSettings()
        settings.debugProUnlock = ProcessInfo.processInfo.environment["MASO_COACH_PRO_TEST"] == "1"
        let store = DataStore(exercises: library, plans: [plan], sets: [], settings: settings)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("maso-coach-chat-ui.json")
        store.equipmentSwapSaveOverride = { [weak store] in
            guard let store else { return false }
            return PersistenceController(storageURL: url).save(store.currentSnapshot())
        }
        if ProcessInfo.processInfo.environment["MASO_COACH_MESSAGE_MENU_TEST"] == "1" {
            store.coachSession.messages = [
                CoachMessage(role: .user, text: "Fixture original message — 原文 3 × 10"),
                CoachMessage(role: .assistant, text: "Fixture original reply — no live AI request")
            ]
        }
        if let mode = ProcessInfo.processInfo.environment["MASO_SOURCE_EXTRACT_UI_TEST"] {
            let rows = fixtureRows()
            let title = NSLocalizedString("Imported plan",comment:"")
            let groups = mode == "two" ? [WorkoutSourceGroup(title:title + " A",rows:Array(rows.prefix(3))),.init(title:title + " B",rows:Array(rows.suffix(3)))] : [.init(title:title,rows:rows)]
            let document = WorkoutSourceDocument(groups:groups,unreadable:false)
            AIWorkoutService.requestFixture = { _ in
                let text = String(decoding:try JSONEncoder().encode(document),as:UTF8.self)
                let bytes = try JSONSerialization.data(withJSONObject:["choices":[["message":["content":text]]]])
                return (bytes,HTTPURLResponse(url:URL(string:"https://fixture.invalid")!,statusCode:200,httpVersion:nil,headerFields:nil)!)
            }
        }
        return store
    }
    // Synthetic catalog data, never asserted to be the unknown six movements in the user's image.
    private static func fixtureRows() -> [WorkoutSourceRow] {
        Array(ExerciseLibrary.all.filter { $0.category.normalized == .strength && $0.tempo != .isometric }.prefix(6)).map {
            .init(sourceName:$0.name,sourceQuote:$0.name + " 3x8 rest 90",exerciseID:$0.id,sets:3,reps:8,weight:nil,restSeconds:90,durationSeconds:nil)
        }
    }
    private static func fixtureImage(_ rows:[WorkoutSourceRow]) -> Data? {
        UIGraphicsImageRenderer(size:CGSize(width:1200,height:720)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x:0,y:0,width:1200,height:720))
            let text = "SYNTHETIC SIX-EXERCISE FIXTURE\n" + rows.map(\.sourceQuote).joined(separator:"\n")
            (text as NSString).draw(in:CGRect(x:40,y:40,width:1120,height:640),withAttributes:[.font:UIFont.systemFont(ofSize:30),.foregroundColor:UIColor.black])
        }.jpegData(compressionQuality:0.9)
    }
}
#endif
