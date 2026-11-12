import XCTest
import UIKit
import WebKit
@testable import Maso

@MainActor
final class ExerciseLibraryBrowserTests: XCTestCase {
    func testConcreteIdentityAndExactSearchSurviveLocalizedNameCollisions() throws {
        let data = DataStore.makeMock()
        let original = try XCTUnwrap(data.exById["bench_press_barbell"])
        var second = try XCTUnwrap(data.exById["incline_bench_press_barbell"])
        second.localizedName = original.localizedName
        let groups = ExerciseGrouping.group([original, second])
        XCTAssertEqual(groups.count, 2, "Flat and incline remain separate training-intent groups")
        XCTAssertEqual(Set(groups.flatMap { $0.all.map(\.id) }), Set([original.id, second.id]))
        let exact = ExerciseGrouping.exactSearchIDs(in: data.userLibrary, query: "Incline Dumbbell Bench Press")
        XCTAssertTrue(exact.contains("incline_bench_press_dumbbell"))
        let matched = data.userLibrary.filter { $0.matchesSearch(exerciseSearchWords("Incline Dumbbell Bench Press")) }
        let searched = ExerciseGrouping.group(matched, preferredExerciseIDs: exact)
        XCTAssertEqual(searched.first?.canonical.id, "incline_bench_press_dumbbell")
    }

    func testFamilyEntryUsesFamiliarityAndExpansionKeepsEveryCommonVersion() throws {
        let policy = ExerciseSelectionPolicy.shared
        let all = ExerciseLibrary.all
        let flat = all.filter { policy.programmingGroupID(for: $0) == "bench_press.flat" }
        let rare = try XCTUnwrap(flat.first { policy.tier(for: $0) == .specialist })
        // A retained/pinned specialist may seed the group, but not take its entry.
        let group = try XCTUnwrap(ExerciseGrouping.group([rare], fullLibrary: all, previewLibrary: flat).first)
        XCTAssertEqual(group.canonical.id, "bench_press_barbell")
        XCTAssertEqual(group.commonVariants.count, flat.filter { $0.id != group.canonical.id && policy.tier(for: $0) != .specialist }.count)
        XCTAssertEqual(group.lessCommonVariants.count, flat.filter { policy.tier(for: $0) == .specialist }.count)
        XCTAssertEqual(group.count, flat.count)
        XCTAssertEqual(Set(group.all.map(\.id)), Set(flat.map(\.id)))
        XCTAssertTrue(Set(group.commonVariants.map(\.id)).isDisjoint(with: group.lessCommonVariants.map(\.id)))
        XCTAssertEqual(group.all.count, Set(group.all.map(\.id)).count)
    }

    func testPullUpAndPushUpBrowseAsFamiliesWithoutChangingProgrammingGroups() throws {
        let ids = ["pull_up", "scapular_pull_up", "push_up", "push_up_knee", "push_up_incline", "scapular_push_up", "handstand_push_up"]
        let exercises = ids.compactMap { id in ExerciseLibrary.all.first { $0.id == id } }
        XCTAssertEqual(exercises.count, ids.count)
        let groups = ExerciseGrouping.group(exercises, previewLibrary: exercises)
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(Set(groups.flatMap { $0.all.map(\.id) }), Set(ids))
        let policy = ExerciseSelectionPolicy.shared
        XCTAssertNotEqual(policy.programmingGroupID(for: exercises[2]), policy.programmingGroupID(for: exercises[3]))
    }

    func testBrowseGroupingCoversCatalogByNameAndKeepsConcreteIDs() throws {
        let all = ExerciseLibrary.all
        let groups = ExerciseGrouping.group(all, groupByName: true)
        XCTAssertEqual(Set(groups.flatMap { $0.all.map(\.id) }), Set(all.map(\.id)))
        XCTAssertEqual(groups.flatMap { $0.all.map(\.id) }.count, all.count)
        for group in groups {
            let names = Set(group.all.map { $0.name.split(separator: "(", maxSplits: 1).first.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? "" })
            XCTAssertEqual(names.count, 1)
        }
        let bench = try XCTUnwrap(groups.first { $0.all.contains { $0.id == "bench_press_barbell" } })
        XCTAssertTrue(Set(bench.all.map(\.id)).isSuperset(of: ["incline_bench_press_barbell", "floor_press_dumbbell"]))
        XCTAssertFalse(bench.all.contains { $0.id == "bench_press_machine" })
    }

    func testChestPressAndBenchPressHaveDistinctFamilies() throws {
        let policy = ExerciseSelectionPolicy.shared
        let bench = try XCTUnwrap(ExerciseLibrary.all.first { $0.id == "bench_press_barbell" })
        let chest = try XCTUnwrap(ExerciseLibrary.all.first { $0.id == "cable_chest_press_standing" })
        XCTAssertNotEqual(policy.displayFamilyID(for: bench), policy.displayFamilyID(for: chest))
        XCTAssertNotEqual(policy.programmingGroupID(for: bench), policy.programmingGroupID(for: chest))
        XCTAssertEqual(ExerciseGrouping.group([bench, chest]).count, 2)
    }

    func testInlineVersionsRespectFiltersAndExactSearchWithoutCatalogRefill() throws {
        let policy = ExerciseSelectionPolicy.shared
        let scoped = ExerciseLibrary.all.filter {
            policy.programmingGroupID(for: $0) == "bench_press.flat" && $0.equipment == "dumbbell"
        }
        let group = try XCTUnwrap(ExerciseGrouping.group(scoped, fullLibrary: ExerciseLibrary.all, previewLibrary: scoped).first)
        XCTAssertTrue(group.all.allSatisfy { $0.equipment == "dumbbell" })
        XCTAssertEqual(group.count, scoped.count)
        XCTAssertEqual(group.canonical.id, "bench_press_dumbbell")
        let rare = try XCTUnwrap(group.lessCommonVariants.first)
        let exact = try XCTUnwrap(ExerciseGrouping.group(scoped, preferredExerciseIDs: [rare.id], previewLibrary: scoped).first)
        XCTAssertEqual(exact.canonical.id, rare.id)
        XCTAssertFalse(exact.lessCommonVariants.contains { $0.id == rare.id })
    }

    func testManualPictureInPictureRetainsTheSamePlayerUntilInlineReturn() throws {
        let playback = WorkoutYouTubePlayback()
        playback.select(exerciseID: "bench_press_barbell", videoID: "M7lc1UVf-VE")
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        playback.attachInline(to: container, videoID: "M7lc1UVf-VE")
        let web = try XCTUnwrap(playback.webView)
        web.stopLoading()
        let host = UIView(frame: .zero)
        playback.registerRetentionHost(host)
        // Native presentation callback contract; not a claim of real system PiP.
        playback.presentationChanged(isPictureInPicture: true)
        playback.detachInline(from: container)
        XCTAssertTrue(playback.webView === web)
        XCTAssertTrue(web.superview === host)
        playback.enteredBackground()
        XCTAssertEqual(playback.exerciseID, "bench_press_barbell")
        let reopened = UIView(frame: container.frame)
        playback.attachInline(to: reopened, videoID: "M7lc1UVf-VE")
        XCTAssertTrue(playback.webView === web)
        XCTAssertTrue(web.superview === reopened)
        playback.presentationChanged(isPictureInPicture: false)
        XCTAssertEqual(playback.exerciseID, "bench_press_barbell")
        playback.stop()
        XCTAssertNil(playback.webView)
        XCTAssertNil(playback.exerciseID)
    }

    func testOrdinaryMinimizationAndClosingFloatingPlaybackStopThePlayer() {
        let playback = WorkoutYouTubePlayback()
        playback.select(exerciseID: "bench_press_barbell", videoID: "M7lc1UVf-VE")
        playback.minimize()
        XCTAssertNil(playback.exerciseID)
        playback.select(exerciseID: "bench_press_barbell", videoID: "M7lc1UVf-VE")
        playback.presentationChanged(isPictureInPicture: true)
        playback.minimize()
        playback.presentationChanged(isPictureInPicture: false)
        XCTAssertNil(playback.exerciseID)
        XCTAssertNil(playback.webView)
    }

    func testUnavailableTutorialKeepsItsRetryAndExternalFallback() {
        let playback = WorkoutYouTubePlayback()
        playback.select(exerciseID: "bench_press_barbell", videoID: "M7lc1UVf-VE")
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 220))
        playback.attachInline(to: container, videoID: "M7lc1UVf-VE")
        playback.status = .failed
        playback.detachInline(from: container)
        XCTAssertNil(playback.webView)
        XCTAssertEqual(playback.exerciseID, "bench_press_barbell")
        XCTAssertEqual(playback.status, .failed)
        let previousAttempt = playback.loadID
        playback.retry()
        XCTAssertNotEqual(playback.loadID, previousAttempt)
        XCTAssertEqual(playback.status, .loading)
        playback.stop()
    }

    func testRoutineSaveDefaultSignatureAndExplicitEquipmentSurviveRoundTrip() throws {
        var settings = UserSettings()
        settings.availableEquipment = ["barbell"]
        let data = DataStore(exercises: ExerciseLibrary.all, plans: [], sets: [], settings: settings)
        let step = PlanStep(id: "step", exerciseId: "bench_press_dumbbell", sets: 3, reps: 10, weight: 20)
        var plan = Plan(id: "source", name: "Intent round trip", steps: [step], createdAt: Date(), updatedAt: Date())
        let copied = try XCTUnwrap(data.savePlanReturningCopy(plan))
        XCTAssertEqual(copied.steps.first?.exerciseId, "bench_press_barbell")
        XCTAssertTrue(data.isPlanSaved(plan))
        XCTAssertEqual(data.savePlanReturningCopy(plan)?.id, copied.id)
        data.unsavePlan(matching: plan)
        XCTAssertTrue(data.plans.isEmpty)
        plan.constraints = [.init(kind: .equipment, value: "dumbbell", label: "Dumbbells only")]
        let constrained = try XCTUnwrap(data.savePlanReturningCopy(plan))
        XCTAssertEqual(constrained.steps.first?.exerciseId, "bench_press_dumbbell")
        XCTAssertEqual(constrained.constraints, plan.constraints)
        XCTAssertEqual(data.routinePlanDefaults(constrained).steps.first?.exerciseId, "bench_press_dumbbell")
        XCTAssertTrue(data.isPlanSaved(plan))
        data.unsavePlan(matching: plan)
        XCTAssertTrue(data.plans.isEmpty)
    }

    func testEnglishNameCollisionRetainsDistinctMovementCues() throws {
        let previousLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        defer { LanguageManager.shared.selectedLanguage = previousLanguage }
        let strict = try XCTUnwrap(ExerciseLibrary.byId["military_press"])
        let ordinary = try XCTUnwrap(ExerciseLibrary.byId["overhead_press_barbell"])
        XCTAssertEqual(strict.displayName, ordinary.displayName)
        let strictCue = try XCTUnwrap(ExerciseGrouping.disambiguationText(for: strict, among: ExerciseLibrary.all))
        let ordinaryCue = try XCTUnwrap(ExerciseGrouping.disambiguationText(for: ordinary, among: ExerciseLibrary.all))
        XCTAssertFalse(strictCue.isEmpty)
        XCTAssertFalse(ordinaryCue.isEmpty)
        XCTAssertNotEqual(strictCue, ordinaryCue)
        XCTAssertNotEqual(strict.id, ordinary.id)
    }
}
