import XCTest
@testable import Maso

/// Fixed ids from the bundled 917 catalog. Expectations are not chosen by
/// asking the matcher which row happens to produce a preview.
@MainActor
final class CoachEquipmentSwapCatalogTests: XCTestCase {
    private let request = "把所有练胸的杠铃器械都换成machine"

    func testBenchPressBecomesMachineAndControlsStay() throws {
        let library = ExerciseLibrary.all
        try require(library)
        let plan = plan(steps: [
            step("bench", "bench_press_barbell"),
            step("pullover", "barbell_pullover"),
            step("static", "static_hold_bench_press"),
            step("dumbbell", "bench_press_dumbbell"),
            step("row", "barbell_row"),
        ])
        let outcome = CoachEquipmentSwap.interpret(request, context: context([plan], library: library))
        guard case .preview(let proposal) = outcome else {
            return XCTFail("expected a preview, got \(outcome)")
        }
        XCTAssertEqual(proposal.lines.map(\.stepId), ["bench"])
        XCTAssertEqual(proposal.lines.map(\.fromExerciseId), ["bench_press_barbell"])
        XCTAssertEqual(proposal.lines.map(\.toExerciseId), ["bench_press_machine"])
        let unmatched = proposal.unreplaced.sorted { $0.stepId < $1.stepId }
        XCTAssertEqual(unmatched.map(\.stepId), ["pullover", "static"])
        XCTAssertEqual(unmatched.map(\.exerciseId), ["barbell_pullover", "static_hold_bench_press"])
        XCTAssertEqual(unmatched.map(\.reason), [.noCandidate, .noCandidate])
        let touched = Set(proposal.lines.map(\.stepId) + proposal.unreplaced.map(\.stepId))
        XCTAssertFalse(touched.contains("dumbbell"))
        XCTAssertFalse(touched.contains("row"))
        XCTAssertEqual(plan.steps.map(\.exerciseId), [
            "bench_press_barbell", "barbell_pullover", "static_hold_bench_press",
            "bench_press_dumbbell", "barbell_row",
        ])
    }

    func testPulloverAloneIsReportedAndNotSwapped() throws {
        try assertBlocked("barbell_pullover")
    }

    func testStaticHoldAloneIsReportedAndNotSwapped() throws {
        try assertBlocked("static_hold_bench_press")
    }

    private func assertBlocked(_ exerciseId: String) throws {
        let library = ExerciseLibrary.all
        try require(library)
        let plan = plan(steps: [step("only", exerciseId)])
        let outcome = CoachEquipmentSwap.interpret(request, context: context([plan], library: library))
        guard case .blocked(let unreplaced, _) = outcome else {
            return XCTFail("\(exerciseId) must be reported unmatched, got \(outcome)")
        }
        XCTAssertEqual(unreplaced.map(\.exerciseId), [exerciseId])
        XCTAssertEqual(unreplaced.map(\.reason), [.noCandidate])
        XCTAssertEqual(plan.steps.map(\.exerciseId), [exerciseId])
    }

    private func require(_ library: [Exercise]) throws {
        for id in [
            "bench_press_barbell", "bench_press_machine", "barbell_pullover",
            "static_hold_bench_press", "bench_press_dumbbell", "barbell_row",
        ] {
            XCTAssertNotNil(library.first { $0.id == id }, "missing bundled id \(id)")
        }
    }

    private func context(_ plans: [Plan], library: [Exercise]) -> CoachEquipmentSwap.Context {
        CoachEquipmentSwap.Context(
            plans: plans,
            library: library,
            candidates: library,
            availableEquipment: UserSettings().availableEquipment,
            focusedPlanId: plans.first?.id,
            conversationPlanIds: [],
            onlyModifyName: nil,
            languageCode: "zh-Hans")
    }

    private func plan(steps: [PlanStep]) -> Plan {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        return Plan(
            id: "plan-catalog", name: "Catalog", steps: steps,
            createdAt: now, updatedAt: now, preservesExerciseVariants: true)
    }

    private func step(_ id: String, _ exerciseId: String) -> PlanStep {
        PlanStep(id: id, exerciseId: exerciseId, sets: 4, reps: 8, weight: 60, restBetweenSets: 90)
    }
}
