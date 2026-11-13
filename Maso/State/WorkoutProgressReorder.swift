import CoreGraphics
import Foundation
import SwiftUI
import UIKit

/// Maps a long-press drag on the workout progress bar onto the same
/// `Array.move(fromOffsets:toOffset:)` values the playlist `List.onMove` uses.
/// The bar does not keep its own order. A wide Duo window can show the queue
/// and the bar together; both submit this move to `TrainingSessionStore.reorderSteps`.
enum WorkoutProgressReorder {
    static let spacing: CGFloat = 4
    static let armDuration: TimeInterval = 0.45
    static let armSlop: CGFloat = 16
    /// A finger that stays near the bar can still drop on the first or last segment.
    static let horizontalEdgeSlack: CGFloat = 32
    /// Past this vertical slack the drop is a cancel and the plan is left untouched.
    static let verticalCancelSlack: CGFloat = 36

    struct Move: Equatable {
        var source: IndexSet
        var destination: Int
    }

    /// Where playback is, independent of segment indexes.
    enum Anchor: Equatable {
        case exercise(stepId: String, setN: Int)
        case restAfterSet(stepId: String, setN: Int)
        /// `upcoming` is only the fallback when this gap disappears. It is not
        /// part of identity: a neighbor can move while this rest stays put.
        case restAfterStep(stepId: String, upcomingStepId: String?, upcomingSetN: Int?)

        enum Place: Equatable {
            case exercise(stepId: String, setN: Int)
            case restAfterSet(stepId: String, setN: Int)
            case restAfterStep(stepId: String)
        }

        var place: Place {
            switch self {
            case .exercise(let stepId, let setN): return .exercise(stepId: stepId, setN: setN)
            case .restAfterSet(let stepId, let setN): return .restAfterSet(stepId: stepId, setN: setN)
            case .restAfterStep(let stepId, _, _): return .restAfterStep(stepId: stepId)
            }
        }
    }

    /// Contiguous `0..<count` shortcut. `nil` when the item would not change slots.
    static func move(count: Int, from source: Int, toFinalIndex final: Int) -> Move? {
        guard count > 1, (0..<count).contains(source), (0..<count).contains(final) else { return nil }
        return planMove(visiblePlanIndices: Array(0..<count), from: source, toFinalIndex: final)
    }

    /// `visiblePlanIndices` are indexes into `plan.steps` for the segments on screen,
    /// in visual order. A later drop lands after that visible step. An earlier drop
    /// lands on that visible step, except the first bar slot, which is the start of
    /// the plan so the drag crosses a hidden step sitting in front of the bar.
    static func planMove(visiblePlanIndices: [Int], from source: Int, toFinalIndex final: Int) -> Move? {
        guard visiblePlanIndices.indices.contains(source), visiblePlanIndices.indices.contains(final), source != final else { return nil }
        let origin = visiblePlanIndices[source]
        let destination = final > source
            ? visiblePlanIndices[final] + 1
            : (final == 0 ? 0 : visiblePlanIndices[final])
        guard destination != origin, destination != origin + 1 else { return nil }
        return Move(source: IndexSet(integer: origin), destination: destination)
    }

    static func slotIndex(x: CGFloat, count: Int, width: CGFloat, spacing: CGFloat = spacing, rightToLeft: Bool) -> Int {
        guard count > 0, width > 0 else { return 0 }
        let logicalX = rightToLeft ? width - x : x
        let clamped = min(max(0, logicalX), max(width - 0.001, 0))
        let slot = max(0, (width - spacing * CGFloat(max(0, count - 1))) / CGFloat(count))
        let pitch = slot + spacing
        guard pitch > 0 else { return 0 }
        return min(max(0, Int(floor(clamped / pitch))), count - 1)
    }

    /// `nil` when the finger has left the bar. Edges inside the slack clamp to the end slots.
    static func landingIndex(count: Int, location: CGPoint, size: CGSize, rightToLeft: Bool) -> Int? {
        guard count > 0, size.width > 1, size.height > 1 else { return nil }
        guard location.x >= -horizontalEdgeSlack, location.x <= size.width + horizontalEdgeSlack,
              location.y >= -verticalCancelSlack, location.y <= size.height + verticalCancelSlack else { return nil }
        let x = min(max(location.x, 0), max(size.width - 0.001, 0))
        return slotIndex(x: x, count: count, width: size.width, spacing: spacing, rightToLeft: rightToLeft)
    }

    static func neighborOffset(index: Int, source: Int, finalIndex: Int, pitch: CGFloat, rightToLeft: Bool) -> CGFloat {
        guard index != source, source != finalIndex else { return 0 }
        let sign: CGFloat = rightToLeft ? -1 : 1
        if finalIndex > source, index > source, index <= finalIndex { return -pitch * sign }
        if finalIndex < source, index >= finalIndex, index < source { return pitch * sign }
        return 0
    }

    static func anchor(in segments: [Segment], index: Int) -> Anchor? {
        guard segments.indices.contains(index) else { return nil }
        let segment = segments[index]
        if case .exercise(_, let setN, _, _, _, _, _) = segment.kind {
            return .exercise(stepId: segment.stepId, setN: setN)
        }
        guard segment.isRest else { return nil }
        let previous = previousExercise(in: segments, before: index)
        let upcoming = nextExercise(in: segments, after: index)
        if let previous, let upcoming, upcoming.stepId == previous.stepId {
            return .restAfterSet(stepId: previous.stepId, setN: previous.setN)
        }
        let stepId = previous?.stepId ?? segment.stepId
        return .restAfterStep(stepId: stepId, upcomingStepId: upcoming?.stepId, upcomingSetN: upcoming?.setN)
    }

    /// Resolves `anchor` after `plan.steps` has been permuted and segments rebuilt.
    /// A rest gap that no longer exists lands on the exercise that rest was leading to.
    static func index(of anchor: Anchor, in segments: [Segment]) -> Int? {
        switch anchor {
        case .exercise(let stepId, let setN):
            return exerciseIndex(stepId: stepId, setN: setN, in: segments)
                ?? segments.firstIndex { $0.stepId == stepId && $0.isExercise }
        case .restAfterSet(let stepId, let setN):
            if let exercise = exerciseIndex(stepId: stepId, setN: setN, in: segments) {
                let rest = exercise + 1
                if segments.indices.contains(rest), segments[rest].isRest, segments[rest].stepId == stepId {
                    return rest
                }
                return exercise
            }
            return segments.firstIndex { $0.stepId == stepId && $0.isExercise }
        case .restAfterStep(let stepId, let upcomingStepId, let upcomingSetN):
            if let last = segments.indices.last(where: { segments[$0].stepId == stepId && segments[$0].isExercise }) {
                let rest = last + 1
                if segments.indices.contains(rest), segments[rest].isRest {
                    let followedByOtherExercise = !segments.indices.contains(rest + 1)
                        || segments[rest + 1].stepId != stepId
                        || !segments[rest + 1].isExercise
                    if followedByOtherExercise { return rest }
                }
            }
            if let upcomingStepId {
                if let upcomingSetN, let exact = exerciseIndex(stepId: upcomingStepId, setN: upcomingSetN, in: segments) {
                    return exact
                }
                if let upcoming = segments.firstIndex(where: { $0.stepId == upcomingStepId && $0.isExercise }) {
                    return upcoming
                }
            }
            return segments.firstIndex { $0.stepId == stepId && $0.isExercise }
        }
    }

    private static func exerciseIndex(stepId: String, setN: Int, in segments: [Segment]) -> Int? {
        segments.firstIndex { segment in
            guard segment.stepId == stepId, case .exercise(_, let number, _, _, _, _, _) = segment.kind else { return false }
            return number == setN
        }
    }

    private static func previousExercise(in segments: [Segment], before index: Int) -> (stepId: String, setN: Int)? {
        var cursor = index - 1
        while cursor >= 0 {
            if case .exercise(_, let setN, _, _, _, _, _) = segments[cursor].kind {
                return (segments[cursor].stepId, setN)
            }
            cursor -= 1
        }
        return nil
    }

    private static func nextExercise(in segments: [Segment], after index: Int) -> (stepId: String, setN: Int)? {
        var cursor = index + 1
        while cursor < segments.count {
            if case .exercise(_, let setN, _, _, _, _, _) = segments[cursor].kind {
                return (segments[cursor].stepId, setN)
            }
            cursor += 1
        }
        return nil
    }
}

/// Long press, then drag. A quick tap is left to the segment button, and a swipe
/// that moves before the hold fails the recognizer so it does not reorder.
struct WorkoutProgressReorderGesture: UIGestureRecognizerRepresentable {
    var enabled: Bool
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: (_ location: CGPoint, _ cancelled: Bool) -> Void

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var onBegan: (CGPoint) -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: (CGPoint, Bool) -> Void
        var armed = false
        init(onBegan: @escaping (CGPoint) -> Void, onChanged: @escaping (CGPoint) -> Void, onEnded: @escaping (CGPoint, Bool) -> Void) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }
    }

    /// Xcode 27's representable requires this converter argument. The recognizer
    /// still reports points in its own view, which is the progress bar.
    func makeCoordinator(converter _: UIGestureRecognizerRepresentableCoordinateSpaceConverter) -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    func makeUIGestureRecognizer(context: Context) -> OriginLongPressRecognizer {
        let recognizer = OriginLongPressRecognizer()
        recognizer.minimumPressDuration = WorkoutProgressReorder.armDuration
        recognizer.allowableMovement = WorkoutProgressReorder.armSlop
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: OriginLongPressRecognizer, context: Context) {
        recognizer.isEnabled = enabled
        recognizer.minimumPressDuration = WorkoutProgressReorder.armDuration
        recognizer.allowableMovement = WorkoutProgressReorder.armSlop
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
    }

    func handleUIGestureRecognizerAction(_ recognizer: OriginLongPressRecognizer, context: Context) {
        let current = recognizer.location(in: recognizer.view?.window)
        switch recognizer.state {
        case .began:
            context.coordinator.armed = true
            context.coordinator.onBegan(recognizer.origin ?? current)
        case .changed:
            guard context.coordinator.armed else { return }
            context.coordinator.onChanged(current)
        case .ended:
            guard context.coordinator.armed else { return }
            context.coordinator.armed = false
            context.coordinator.onEnded(current, false)
        case .cancelled, .failed:
            guard context.coordinator.armed else { return }
            context.coordinator.armed = false
            context.coordinator.onEnded(current, true)
        default:
            break
        }
    }
}

/// Remembers the first touch so a narrow segment is chosen from the press, not from later drift.
/// The segment button would otherwise force this recognizer to fail, so a long press that
/// starts on a segment never arms. It does not cancel that button: a short tap still jumps,
/// and the bar ignores the tap only after this hold has begun.
final class OriginLongPressRecognizer: UILongPressGestureRecognizer {
    private(set) var origin: CGPoint?
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        origin = touches.first?.location(in: view?.window)
    }
    override func reset() {
        super.reset()
        origin = nil
    }
    override func canPrevent(_ preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
    override func canBePrevented(by preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        false
    }
}
