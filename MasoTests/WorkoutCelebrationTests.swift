import XCTest
import AVFoundation
import CryptoKit
import SwiftUI
@testable import Maso

@MainActor
final class WorkoutCelebrationTests: XCTestCase {
    private func assertNoninterruptingAudio(otherAudioWasPlaying: Bool, file: StaticString = #filePath, line: UInt = #line) {
        let session = AVAudioSession.sharedInstance()
        XCTAssertEqual(session.category, .ambient, file: file, line: line)
        XCTAssertEqual(session.mode, .default, file: file, line: line)
        // Ambient is implicitly mixable; iOS may return an empty options bitmask.
        // Real external playback, not that explicit playback-category flag, is
        // the regression signal below (and in the independent audio probe).
        XCTAssertFalse(session.categoryOptions.contains(.duckOthers), file: file, line: line)
        XCTAssertFalse(session.categoryOptions.contains(.interruptSpokenAudioAndMixWithOthers), file: file, line: line)
        if otherAudioWasPlaying {
            XCTAssertTrue(session.isOtherAudioPlaying, "External playback was interrupted", file: file, line: line)
        }
    }

    /// Real local silent video; does not rely on the network or approved media catalog.
    private func makeSilentDemo() async throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mov")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 32
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 32, kCVPixelBufferHeightKey as String: 32
        ])
        writer.add(input)
        XCTAssertTrue(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        var frame: CVPixelBuffer?
        XCTAssertEqual(CVPixelBufferCreate(nil, 32, 32, kCVPixelFormatType_32BGRA, nil, &frame), kCVReturnSuccess)
        let buffer = try XCTUnwrap(frame)
        CVPixelBufferLockBaseAddress(buffer, [])
        if let pixels = CVPixelBufferGetBaseAddress(buffer) {
            memset(pixels, 0, CVPixelBufferGetBytesPerRow(buffer) * 32)
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        for index in 0..<2 {
            for _ in 0..<200 {
                if input.isReadyForMoreMediaData { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(index), timescale: 2)))
        }
        writer.endSession(atSourceTime: CMTime(seconds: 1, preferredTimescale: 600))
        input.markAsFinished()
        await writer.finishWriting()
        XCTAssertEqual(writer.status, .completed)
        return url
    }

    func testSilentDemoStartAndExerciseReplacementKeepMixing() async throws {
        let externalAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying
        let first = try await makeSilentDemo(), second = try await makeSilentDemo()
        defer { try? FileManager.default.removeItem(at: first); try? FileManager.default.removeItem(at: second) }
        let view = GeneratedExerciseVideo.PlayerView(frame: .zero)
        defer { view.player?.pause(); view.looper = nil }
        for url in [first, second] {
            view.play(url)
            for _ in 0..<200 {
                if view.player?.currentItem?.status == .readyToPlay { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertEqual(view.player?.currentItem?.status, .readyToPlay)
            XCTAssertEqual(view.player?.isMuted, true)
            XCTAssertEqual(view.player?.volume, 0)
            XCTAssertEqual(view.player?.allowsExternalPlayback, false)
            assertNoninterruptingAudio(otherAudioWasPlaying: externalAudio)
        }
    }

    func testCompletionRestCelebrationAndHapticsKeepMixing() async throws {
        let externalAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying
        let cues: [() -> Void] = [
            { SoundPlayer.shared.playTick() }, { SoundPlayer.shared.playSetComplete() },
            { SoundPlayer.shared.playRestEnded() }, { Haptics.setComplete() },
            { Haptics.restEnded() }, { Haptics.tap() }
        ]
        for cue in cues {
            cue()
            try await Task.sleep(for: .milliseconds(100))
            assertNoninterruptingAudio(otherAudioWasPlaying: externalAudio)
        }
        let feedback = WorkoutCelebrationFeedback()
        feedback.prepare(.approved); feedback.play()
        try await Task.sleep(for: .milliseconds(200))
        assertNoninterruptingAudio(otherAudioWasPlaying: externalAudio)
        feedback.cancel()
    }

    func testSpeechStartReplacementAndStopDoNotDuckOtherAudio() async throws {
        let externalAudio = AVAudioSession.sharedInstance().isOtherAudioPlaying
        let speech = SpeechManager()
        defer { speech.stop() }
        speech.speak(steps: ["Keep your movement controlled"], locale: "en-US", source: "audio-test-1")
        speech.speak(steps: ["Take a short rest"], locale: "en-US", source: "audio-test-2")
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertEqual(speech.currentSource, "audio-test-2", "Stale cancellation must not clear replacement speech")
        assertNoninterruptingAudio(otherAudioWasPlaying: externalAudio)
        speech.stop()
        SoundPlayer.shared.playSetComplete()
        assertNoninterruptingAudio(otherAudioWasPlaying: externalAudio)
    }

    func testApprovedExportAndOriginalAudioAreBundled() throws {
        let url = try XCTUnwrap(WorkoutCelebrationConfiguration.resource("WorkoutCelebration", extension: "json"))
        let config = try JSONDecoder().decode(WorkoutCelebrationConfiguration.self, from: Data(contentsOf: url))
        XCTAssertEqual(config.motion.peakScale, 1.55)
        XCTAssertEqual(config.motion.turns, 1.9)
        XCTAssertEqual(config.anchor, 0.36)
        XCTAssertEqual(config.confetti.count, 150)
        XCTAssertEqual(config.haptics.hapticCount, 2)
        XCTAssertEqual(config.haptics.hapticGap, 0.09)
        XCTAssertEqual(config.sound.sound, "levelup")
        for (name, checksum) in [
            ("masso-celebration-levelup", "3876c6e251aa81e5f50b3ef90a9b549a46ac26d05c1b726e4f49ab50e3a8ed66"),
            ("masso-celebration-glass", "370c04275a6e4f1aa745a373fe02540bf592d001f90920a0278551411add55c8")
        ] {
            let file = try XCTUnwrap(WorkoutCelebrationConfiguration.resource(name, extension: "wav"))
            let hash = SHA256.hash(data: try Data(contentsOf: file)).map { String(format: "%02x", $0) }.joined()
            XCTAssertEqual(hash, checksum)
            let audio = try AVAudioFile(forReading: file)
            XCTAssertEqual(audio.fileFormat.sampleRate, 44100)
            XCTAssertEqual(audio.fileFormat.channelCount, 1)
            XCTAssertGreaterThan(audio.length, 20000)
        }
    }

    func testNativeMotionMatchesApprovedWebSamples() {
        let config = WorkoutCelebrationConfiguration.approved
        // Captured independently from celebration-lab/engine.js with the user's export.
        let expected: [[Double]] = [
            [0,0.16,-684,0,0,0.55,0,0],
            [0.18,1.37625,-381.83783392931554,1,0,0.55,0,0],
            [0.36,1.55,-186.12360506937,1,0,0.55,0,0],
            [0.5,0.9342731593443199,-92.149633450058,1,1,0.9955874083909516,0.9016841147018663,0],
            [0.72,1.0389431738786272,-18.913089957515403,1,1,0.9986568781787211,1,0.7333333333333333],
            [1.05,0.9817020566983955,0,1,1,1.0000325562920223,1,1],
            [3.38,1.0000002162739383,0,1,1,1,1,1]
        ]
        for row in expected {
            let f = config.frame(at: row[0])
            let actual = [f.scale, f.angle, f.opacity, f.checkOpacity, f.checkScale, f.checkStroke, f.titleOpacity]
            for (a, b) in zip(actual, row.dropFirst()) { XCTAssertEqual(a, b, accuracy: 1e-8) }
        }
        let reduced = config.frame(at: 0.5, reducedMotion: true)
        XCTAssertEqual(reduced.scale, 1); XCTAssertEqual(reduced.angle, 0); XCTAssertEqual(reduced.checkOpacity, 1)
    }

    func testNativeParticlesMatchSeededWebPhysics() throws {
        let config = WorkoutCelebrationConfiguration.approved.confetti
        let particles = CelebrationParticle.make(config)
        XCTAssertEqual(particles.count, 150)
        let expected: [[Double]] = [
            [0,468.37807382007264,-576.80662535304,152.32511050699333,414.8483911366384,1.22529967829135,1],
            [1,-363.5570961943038,-845.4747302747735,255.18804069569245,309.1281573437918,6.849429390618548,1],
            [149,-345.5181447423779,-500.5990524021577,262.32497836635423,438.9893087830666,5.891917595050254,1]
        ]
        for row in expected {
            let p = particles[Int(row[0])]
            let value = try XCTUnwrap(p.position(at: 0.5, config: config, size: CGSize(width: 390, height: 844)))
            let actual = [p.vx,p.vy,Double(value.point.x),Double(value.point.y),value.angle,value.alpha]
            for (a,b) in zip(actual,row.dropFirst()) { XCTAssertEqual(a,b,accuracy:1e-8) }
            XCTAssertNil(p.position(at: -0.1, config: config, size: CGSize(width: 390, height: 844)))
            XCTAssertNil(p.position(at: config.life + config.emission + 1, config: config, size: CGSize(width: 390, height: 844)))
        }
    }

    func testRecordedSetRestDuplicateAndFinalSetSoundBoundaries() throws {
        let data = DataStore.makeMock(), now = Date()
        let exercise = try XCTUnwrap(data.exById.values.first { $0.category == .strength })
        let plan = Plan(id: "feedback-test", name: "Workout", steps: [
            .init(id: "a", exerciseId: exercise.id, sets: 2, reps: 8, weight: 20, duration: nil),
            .init(id: "b", exerciseId: exercise.id, sets: 1, reps: 8, weight: 20, duration: nil)
        ], createdAt: now, updatedAt: now)
        var sounds = 0
        let store = TrainingSessionStore(completionSound: { sounds += 1 })
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById))
        defer { store.end() }
        store.advance(); XCTAssertEqual(sounds, 1) // Real set, entering rest.
        store.advance(); XCTAssertEqual(sounds, 1) // Rest ending is not glass.
        store.advance(); XCTAssertEqual(sounds, 2)
        store.setIndex(0); store.advance(); XCTAssertEqual(sounds, 2) // Already logged; no repeat reward.
        if store.currentSegment?.isRest == true { store.advance() }
        store.advance()
        XCTAssertEqual(store.session?.completed, true)
        XCTAssertEqual(sounds, 2, "Final set defers to the celebration page; no overlapping glass cue")
        store.advance(); XCTAssertEqual(sounds, 2)
    }

    func testOpenWorkoutAndCountdownCompletionUseGlassWithoutEndingSession() throws {
        let data = DataStore.makeMock(), now = Date()
        let exercise = try XCTUnwrap(data.exById.values.first { $0.category == .cardio })
        let plan = Plan(id: "qw-open-feedback", name: "Workout", steps: [
            .init(id: "a", exerciseId: exercise.id, sets: 1, reps: nil, weight: nil, duration: 30)
        ], createdAt: now, updatedAt: now, autoGenerated: true)
        var sounds = 0
        let store = TrainingSessionStore(completionSound: { sounds += 1 })
        store.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById))
        defer { store.end() }
        store.advance()
        XCTAssertEqual(sounds, 1); XCTAssertTrue(store.awaitingExercise)
        store.advance(); XCTAssertEqual(sounds, 1)
        store.finishEarly(); XCTAssertEqual(sounds, 1) // Celebration is owned by its page.
    }
}
