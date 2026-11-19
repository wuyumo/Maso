import XCTest
import SwiftUI
import UIKit
import AVFoundation
import CryptoKit
@testable import Maso

@MainActor final class ExercisePrefetchPriorityTests: XCTestCase {
    func testLatestRoutineIsFirstAndSharedExercisesAreNotDuplicated() {
        XCTAssertEqual(ExerciseDemoService.mergedPrefetchIDs(
            ["squat", "row", "squat"], ["row", "press", "curl"]
        ), ["squat", "row", "press", "curl"])
    }

    func testConfirmedChestPressStillDoesNotPlayAnyMotion() {
        let id = "chest_press_machine_iso_lateral"
        let still = "1aa57235a0e8946f7cf5952004605919fcf1a33b9fb45abef5c3b571ec57dffd"
        let motion = "7118307bd064dc744bedf8dd7a108189aacca2d13e46f8534a8fca853bc33e9d"
        let record = CoreExerciseDemos.DemoReview(exerciseId: id, kind: "user-approved-static", assetSHA256: still, approvedAt: "2026-11-19T18:13:00+08:00", scope: "static-demo-visual")
        XCTAssertEqual(CoreExerciseDemos.presentation(id: id, motionSHA: motion, cachedSHA: motion, reviews: [record]), .approvedStill)
        XCTAssertEqual(CoreExerciseDemos.presentation(id: id, motionSHA: String(repeating: "ab", count: 32), cachedSHA: String(repeating: "cd", count: 32), reviews: [record]), .approvedStill)
        XCTAssertEqual(CoreExerciseDemos.assets[id]?.verification, "unverified")
        XCTAssertEqual(CoreExerciseDemos.presentation(id: "unknown-demo", motionSHA: motion, reviews: []), .placeholder)
        let approved = CoreExerciseDemos.DemoReview(exerciseId: "bench_press_barbell", kind: "approved-animation", assetSHA256: motion, approvedAt: nil, scope: nil)
        XCTAssertEqual(CoreExerciseDemos.presentation(id: "bench_press_barbell", motionSHA: motion, cachedSHA: "other", reviews: [approved]), .approvedMotion)
        XCTAssertEqual(CoreExerciseDemos.presentation(id: "bench_press_barbell", motionSHA: String(repeating: "ef", count: 32), reviews: [approved]), .placeholder)
    }

    func testMainActorPresentationMatchesPureOverload() {
        let service = ExerciseDemoService.shared
        let id = "bench_press_barbell"
        let remote = service.hasRemoteCatalog ? service.remoteAssets[id]?.sha256 : nil
        let cached = service.files[id]?.deletingPathExtension().lastPathComponent
        XCTAssertNil(CoreExerciseDemos.reviewOverrideForTests)
        let pure = CoreExerciseDemos.presentation(
            id: id,
            motionSHA: remote ?? CoreExerciseDemos.assets[id]?.sha256,
            cachedSHA: cached,
            reviews: CoreExerciseDemos.decisionReviews)
        XCTAssertEqual(service.presentation(for: id), pure)
        XCTAssertEqual(demoPresentation(id), pure)
    }
}

@MainActor final class ExerciseTutorialTests: XCTestCase {
    private func service() -> ExerciseTutorialService {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        return ExerciseTutorialService(session: URLSession(configuration: config), monitorNetwork: false)
    }
    override func tearDown() { DemoURLProtocol.handler = nil; super.tearDown() }

    func testUnreachableYouTubeUsesExactReviewedBilibiliLink() async throws {
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        DemoURLProtocol.handler = { _ in throw URLError(.timedOut) }
        let result = await service().resolve(exercise)
        XCTAssertEqual(result, .bilibili("BV1GJmpYLE8A"))
        XCTAssertEqual(result.url.host, "www.bilibili.com")
    }
    func testAccessibleYouTubeIsKeptEvenForChineseExerciseName() async throws {
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        var requests = 0
        DemoURLProtocol.handler = { request in
            requests += 1
            XCTAssertEqual(request.url?.host, "www.youtube.com")
            return (200, Data("var YT = {}; // www-widgetapi".utf8))
        }
        let router = service()
        let expected = ExerciseTutorialDestination.youtube(try XCTUnwrap(ExerciseMediaPolicy.youtubeID(exercise.videoURL)))
        let first = await router.resolve(exercise)
        let cached = await router.resolve(exercise)
        XCTAssertEqual(first, expected); XCTAssertEqual(cached, expected)
        XCTAssertEqual(requests, 1)
    }
    func testCaptivePortalAndForcedRetryDoNotPretendYouTubeIsReachable() async throws {
        let router = service()
        DemoURLProtocol.handler = { _ in (200, Data("<html>Please sign in to this Wi-Fi. YT</html>".utf8)) }
        let blocked = await router.youtubeAvailable()
        XCTAssertFalse(blocked)
        DemoURLProtocol.handler = { _ in (200, Data("var YT = {};".utf8)) }
        let cached = await router.youtubeAvailable()
        let retried = await router.youtubeAvailable(force: true)
        XCTAssertFalse(cached); XCTAssertTrue(retried)
    }
    func testLiveSearchSkipsWrongVariantAndUsesAnExactPlayableID() async throws {
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["bicep_curl_dumbbell"])
        let payload: [String: Any] = ["code": 0, "data": ["result": [
            ["bvid": "BV1aa4y1o7XA", "title": "上斜哑铃二头弯举教学"],
            ["bvid": "malicious/id", "title": "哑铃二头弯举教学"],
            ["bvid": "BV1nb4y1M7By", "title": "哑铃<em>二头弯举</em>教学"]
        ]]]
        let body = try JSONSerialization.data(withJSONObject: payload)
        DemoURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.host, "api.bilibili.com")
            XCTAssertTrue(request.url?.query?.contains("search_type=video") == true)
            return (200, body)
        }
        let result = await service().bilibili(for: exercise)
        XCTAssertEqual(result, .bilibili("BV1nb4y1M7By"))
    }
    func testBlockedSearchOrAmbiguousEquipmentOnlyOffersAnHonestSearch() async throws {
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["bicep_curl_dumbbell"])
        XCTAssertFalse(ExerciseTutorialService.matches(title: "杠铃二头弯举教学", exercise: exercise))
        XCTAssertFalse(ExerciseTutorialService.matches(title: "哑铃二头弯举全套跟练", exercise: exercise))
        DemoURLProtocol.handler = { _ in (412, Data()) }
        let result = await service().bilibili(for: exercise)
        guard case .search(let url) = result else { return XCTFail("Unverified first result must never auto-play") }
        XCTAssertEqual(url.host, "search.bilibili.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.name, "keyword")
    }
    func testReviewedIDsExistAndOfficialEmbedRejectsInjectedIdentifiers() {
        for (id, bvid) in ExerciseTutorialService.reviewed {
            XCTAssertNotNil(ExerciseLibrary.byId[id]); XCTAssertTrue(ExerciseTutorialService.validBVID(bvid))
        }
        let html = InlineYouTubeWebView.html(videoID: "bili:BV1GJmpYLE8A")
        XCTAssertTrue(html.contains("https://player.bilibili.com/player.html?bvid=BV1GJmpYLE8A"))
        XCTAssertTrue(html.contains("danmaku=0"))
        XCTAssertEqual(InlineYouTubeWebView.html(videoID: "bili:<script>alert(1)</script>"), "")
    }
}

private final class DemoURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, Data))?
    nonisolated(unsafe) static var rangedHandler: ((URLRequest) throws -> (Int, Data, [String: String]))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let status: Int
            let data: Data
            var headers = ["Content-Type": "application/json"]
            if request.url?.path.contains("/video/") == true, let ranged = Self.rangedHandler {
                let result = try ranged(request)
                status = result.0
                data = result.1
                for (key, value) in result.2 { headers[key] = value }
            } else {
                let result = try Self.handler!(request)
                status = result.0
                data = result.1
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
@MainActor final class ExerciseDemoTests: XCTestCase {
    override func tearDown() async throws {
        CoreExerciseDemos.reviewOverrideForTests = nil
        ExerciseDemoService.shared.clearTestMotionFixtures()
        DemoURLProtocol.handler = nil
        DemoURLProtocol.rangedHandler = nil
        try await super.tearDown()
    }

    private struct TestClip { var url: URL; var data: Data; var sha: String }

    private static func testMotionReview(_ id: String, sha: String) -> CoreExerciseDemos.DemoReview {
        CoreExerciseDemos.DemoReview(exerciseId: id, kind: "approved-animation", assetSHA256: sha,
                                     approvedAt: "2026-11-19T00:00:00Z", scope: "test-only")
    }

    /// Two or more solid frames. One frame per second stays on the two-frame renderer; faster clips use the player.
    private static func testVideo(colors: [UIColor], framesPerSecond: Int) async throws -> TestClip {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("maso-demo-test-\(UUID().uuidString).mp4")
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let side = 160
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: side,
            AVVideoHeightKey: side,
            AVVideoCompressionPropertiesKey: [AVVideoExpectedSourceFrameRateKey: framesPerSecond]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String: side,
            kCVPixelBufferHeightKey as String: side
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? URLError(.cannotCreateFile) }
        writer.startSession(atSourceTime: .zero)
        let scale = CMTimeScale(framesPerSecond)
        for (index, color) in colors.enumerated() {
            var spins = 0
            while !input.isReadyForMoreMediaData, spins < 200 {
                try await Task.sleep(for: .milliseconds(5))
                spins += 1
            }
            let time = CMTime(value: CMTimeValue(index), timescale: scale)
            guard let pool = adaptor.pixelBufferPool else { throw URLError(.cannotCreateFile) }
            var pooled: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pooled) == kCVReturnSuccess, let buffer = pooled else {
                throw URLError(.cannotCreateFile)
            }
            try fill(buffer, color: color, mark: index)
            guard adaptor.append(buffer, withPresentationTime: time) else {
                throw writer.error ?? URLError(.cannotWriteToFile)
            }
        }
        input.markAsFinished()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            writer.finishWriting { continuation.resume() }
        }
        guard writer.status == .completed else { throw writer.error ?? URLError(.cannotWriteToFile) }
        let data = try Data(contentsOf: url)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return TestClip(url: url, data: data, sha: sha)
    }

    private static func fill(_ buffer: CVPixelBuffer, color: UIColor, mark: Int) throws {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { throw URLError(.cannotCreateFile) }
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        let b = UInt8(blue * 255), g = UInt8(green * 255), r = UInt8(red * 255)
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        for y in 0..<height {
            let row = base.advanced(by: y * rowBytes).assumingMemoryBound(to: UInt8.self)
            for x in 0..<width {
                let offset = x * 4
                let marked = mark % 2 == 1 && x < width / 2
                row[offset] = marked ? 255 : b
                row[offset + 1] = marked ? 255 : g
                row[offset + 2] = marked ? 255 : r
                row[offset + 3] = 255
            }
        }
    }

    func testTwoFrameDemosChangeOnScreen() async throws {
        let clips = [
            try await Self.testVideo(colors: [.red, .blue], framesPerSecond: 1),
            try await Self.testVideo(colors: [.green, .yellow], framesPerSecond: 1)
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for clip in clips {
            XCTAssertGreaterThan(clip.data.count, 1024)
            let rate = try await AVURLAsset(url: clip.url).loadTracks(withMediaType: .video).first?.load(.nominalFrameRate) ?? 99
            XCTAssertLessThanOrEqual(rate, Float(2))
            window.rootViewController = UIHostingController(rootView: GeneratedExerciseVideo(url: clip.url).frame(width: 240, height: 240))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(1.5))
            func capture() -> Data? {
                window.layoutIfNeeded()
                return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }.pngData()
            }
            let first = try XCTUnwrap(capture())
            XCTAssertGreaterThan(first.count, 1000)
            try await Task.sleep(for: .seconds(1.3))
            let second = try XCTUnwrap(capture())
            XCTAssertNotEqual(first, second, "Two-frame demo must visibly advance")
        }
    }

    func testTwoFrameDemoInRealDetailSheet() async throws {
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById["clamshell_banded"])
        let clip = try await Self.testVideo(colors: [.red, .blue], framesPerSecond: 1)
        defer { CoreExerciseDemos.reviewOverrideForTests = nil; ExerciseDemoService.shared.clearTestMotionFixtures() }
        XCTAssertNil(ExerciseDemoService.shared.files[exercise.id])
        XCTAssertNotEqual(ExerciseDemoService.shared.presentation(for: exercise.id), .approvedMotion)
        CoreExerciseDemos.reviewOverrideForTests = [Self.testMotionReview(exercise.id, sha: clip.sha)]
        ExerciseDemoService.shared.stageTestMotion(exerciseID: exercise.id, file: clip.url, sha: clip.sha)
        await ExerciseDemoService.shared.loadMedia(exercise.id, force: true)
        XCTAssertEqual(ExerciseDemoService.shared.files[exercise.id], clip.url)
        XCTAssertEqual(ExerciseDemoService.shared.presentation(for: exercise.id), .approvedMotion)
        XCTAssertFalse(CoreExerciseDemos.reviews.contains { $0.kind == "approved-animation" })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        window.rootViewController = UIHostingController(rootView: Color.clear.sheet(isPresented: .constant(true)) {
            ExerciseDetailSheet(exercise: exercise).environment(data).presentationDetents([.large])
        })
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(2))
        func mediaCrop() throws -> Data {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let cg = try XCTUnwrap(image.cgImage)
            let rect = CGRect(x: CGFloat(cg.width) * 0.15, y: CGFloat(cg.height) * 0.14,
                              width: CGFloat(cg.width) * 0.7, height: CGFloat(cg.width) * 0.55).integral
            return try XCTUnwrap(UIImage(cgImage: try XCTUnwrap(cg.cropping(to: rect))).pngData())
        }
        let first = try mediaCrop()
        XCTAssertGreaterThan(first.count, 1000)
        try await Task.sleep(for: .seconds(1.3))
        XCTAssertNotEqual(first, try mediaCrop(), "The exercise detail hero should change frames")
    }
    func testCurrentAndUpcomingExercisesUseTheSameFilledVideoInPlayer() async throws {
        let data = DataStore.makeMock()
        let first = try XCTUnwrap(data.exById["bicep_curl_dumbbell"])
        let next = try XCTUnwrap(data.exById["squat_bodyweight"])
        defer { CoreExerciseDemos.reviewOverrideForTests = nil; ExerciseDemoService.shared.clearTestMotionFixtures() }
        for exercise in [first, next] {
            await ExerciseDemoService.shared.loadMedia(exercise.id, force: true)
            XCTAssertNil(ExerciseDemoService.shared.files[exercise.id])
            XCTAssertNotEqual(ExerciseDemoService.shared.presentation(for: exercise.id), .approvedMotion)
        }
        let firstClip = try await Self.testVideo(colors: [.red, .red, .orange, .orange], framesPerSecond: 10)
        let nextClip = try await Self.testVideo(colors: [.blue, .blue, .purple, .purple], framesPerSecond: 10)
        let firstStill = try await AVAssetImageGenerator(asset: AVURLAsset(url: firstClip.url)).image(at: .zero).image
        let nextStill = try await AVAssetImageGenerator(asset: AVURLAsset(url: nextClip.url)).image(at: .zero).image
        XCTAssertNotEqual(UIImage(cgImage: firstStill).pngData(), UIImage(cgImage: nextStill).pngData())
        CoreExerciseDemos.reviewOverrideForTests = [
            Self.testMotionReview(first.id, sha: firstClip.sha),
            Self.testMotionReview(next.id, sha: nextClip.sha)
        ]
        ExerciseDemoService.shared.stageTestMotion(exerciseID: first.id, file: firstClip.url, sha: firstClip.sha)
        ExerciseDemoService.shared.stageTestMotion(exerciseID: next.id, file: nextClip.url, sha: nextClip.sha)
        await ExerciseDemoService.shared.loadMedia(first.id, force: true)
        await ExerciseDemoService.shared.loadMedia(next.id, force: true)
        XCTAssertEqual(ExerciseDemoService.shared.files[first.id], firstClip.url)
        XCTAssertEqual(ExerciseDemoService.shared.files[next.id], nextClip.url)
        XCTAssertFalse(CoreExerciseDemos.reviews.contains { $0.kind == "approved-animation" })
        let plan = Plan(id: "media-regression", name: "Media regression", steps: [
            PlanStep(id: "first", exerciseId: first.id, sets: 1, reps: 8),
            PlanStep(id: "next", exerciseId: next.id, sets: 1, reps: 8)
        ], createdAt: Date(), updatedAt: Date())
        let training = TrainingSessionStore(completionSound: {})
        training.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById,
            defaultRest: 90, defaultBetweenExerciseRest: 120))
        training.togglePlay()
        XCTAssertEqual(training.segments.count, 3)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: Color.clear.fullScreenCover(isPresented: .constant(true)) {
            PlanPlayerScreen().environment(data).environment(training).preferredColorScheme(.dark)
        })
        window.makeKeyAndVisible()
        defer { training.end(); window.isHidden = true; previous?.makeKeyAndVisible() }
        func players(in layer: CALayer) -> [AVPlayerLayer] {
            (layer as? AVPlayerLayer).map { [$0] } ?? (layer.sublayers ?? []).flatMap { players(in: $0) }
        }
        var mediaFrames: [CGRect] = []
        for (index, exercise) in [(0, first), (1, next), (2, next)] {
            training.setIndex(index)
            let expected = try XCTUnwrap(ExerciseDemoService.shared.files[exercise.id])
            var layer: AVPlayerLayer?
            for _ in 0..<80 {
                layer = players(in: window.layer).first {
                    ($0.player?.currentItem?.asset as? AVURLAsset)?.url == expected
                }
                if layer?.player?.currentItem?.status == .readyToPlay { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let video = try XCTUnwrap(layer, "No video in training stage \(index)")
            XCTAssertEqual(video.videoGravity, .resizeAspect, "Training media must show the complete movement without cropping")
            XCTAssertEqual(video.player?.isMuted, true)
            XCTAssertEqual(video.player?.currentItem?.status, .readyToPlay)
            window.layoutIfNeeded()
            mediaFrames.append(video.convert(video.bounds, to: window.layer))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "training-media-stage-\(index)"; attachment.lifetime = .keepAlways; add(attachment)
            let png = try XCTUnwrap(image.pngData())
            XCTAssertGreaterThan(png.count, 8000, "Training stage \(index) did not render")
            try png.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("training-media-stage-\(index).png"))
        }
        XCTAssertEqual(mediaFrames[0], mediaFrames[1])
        XCTAssertEqual(mediaFrames[1], mediaFrames[2])
    }

    func testRemoteApprovedCatalogAddsRareExerciseAndPersistsOffline() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "masso-test-remote-catalog"))
        defaults.removePersistentDomain(forName: "masso-test-remote-catalog")
        defer { defaults.removePersistentDomain(forName: "masso-test-remote-catalog"); DemoURLProtocol.handler = nil }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        let session = URLSession(configuration: config)
        let bases = [URL(string: "https://demo.test")!]
        let service = ExerciseDemoService(session: session, baseURLs: bases, catalogDefaults: defaults)
        let rare = try XCTUnwrap(ExerciseLibrary.byId["pull_up_one_arm"])
        let policy = ExerciseSelectionPolicy.shared
        let initial = try JSONSerialization.data(withJSONObject: ["version": 1, "assets": []])
        let sha = String(repeating: "a", count: 64)
        let added = try JSONSerialization.data(withJSONObject: ["version": 1, "assets": [[
            "exerciseId": rare.id, "status": "ready", "sha256": sha, "bytes": 2048,
            "videoPath": "/v1/exercise-demos/video/" + sha, "mediaType": "gif"
        ]]])
        DemoURLProtocol.handler = { _ in (200, initial) }
        await service.refreshAvailableCatalog(force: true)
        XCTAssertFalse(policy.visibleExercises(from: [rare], settings: UserSettings(), availableMediaIDs: service.availableMediaIDs).contains { $0.id == rare.id })
        DemoURLProtocol.handler = { _ in (200, added) }
        await service.refreshAvailableCatalog(force: true)
        XCTAssertTrue(policy.visibleExercises(from: [rare], settings: UserSettings(), availableMediaIDs: service.availableMediaIDs).contains { $0.id == rare.id })
        DemoURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        let reopened = ExerciseDemoService(session: session, baseURLs: bases, catalogDefaults: defaults)
        await reopened.refreshAvailableCatalog(force: true)
        XCTAssertTrue(reopened.availableMediaIDs.contains(rare.id))
    }

    private func service() -> ExerciseDemoService {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [DemoURLProtocol.self]
        let defaults = UserDefaults(suiteName: "ExerciseDemoTests." + UUID().uuidString)!
        return ExerciseDemoService(session: URLSession(configuration: config), baseURLs: [URL(string:"https://demo.test")!], catalogDefaults: defaults)
    }
    func testCoreDeliveryCatalogAndRealDownloadSurvivesOfflineReopen() async throws {
        XCTAssertEqual(CoreExerciseDemos.assets.count, 696, "Reviewed adopted media catalog; ID/cover/hash invariants below must also hold")
        XCTAssertNotNil(CoreExerciseDemos.assets["inverted_row"], "Later reviewed exact-ID adoption replaces the earlier absence")
        XCTAssertNotNil(CoreExerciseDemos.assets["arnold_press"])
        XCTAssertNotNil(CoreExerciseDemos.assets["arnold_press_seated"])
        XCTAssertTrue(CoreExerciseDemos.revokedHashes.contains("3057a31465c0198465f8a5f8cd43569ada9580bb6da018d6c244ea277cd065af"))
        XCTAssertNotNil(CoreExerciseDemos.assets["hamstring_stretch_supine"])
        XCTAssertNotNil(CoreExerciseDemos.assets["hamstring_stretch_supine_strap"])
        let posterURL = try XCTUnwrap(Bundle.main.url(forResource: "poster-catalog", withExtension: "json", subdirectory: "CoreExerciseDemos"))
        let posters = try JSONDecoder().decode([String: String].self, from: Data(contentsOf: posterURL))
        for (id, row) in CoreExerciseDemos.assets {
            XCTAssertEqual(row.exerciseId, id)
            if posters[id] == row.sha256 {
                XCTAssertNotNil(CoreExerciseDemos.thumbnail(id), id)
            } else {
                // A replaced demo must never reuse a cover from a different SHA.
                XCTAssertNil(CoreExerciseDemos.thumbnail(id), id)
            }
            XCTAssertEqual(row.sha256?.count, 64)
            XCTAssertFalse(CoreExerciseDemos.revokedHashes.contains(row.sha256 ?? ""), id)
        }
        XCTAssertFalse(CoreExerciseDemos.reviews.contains { $0.kind == "approved-animation" })
        let blocked = ExerciseDemoService()
        await blocked.loadMedia("overhead_press_barbell", force: true)
        XCTAssertNil(blocked.files["overhead_press_barbell"])
        XCTAssertNotEqual(blocked.presentation(for: "overhead_press_barbell"), .approvedMotion)

        let clip = try await Self.testVideo(colors: [.red, .blue, .red, .blue], framesPerSecond: 8)
        XCTAssertGreaterThan(clip.data.count, 1024)
        XCTAssertFalse(CoreExerciseDemos.revokedHashes.contains(clip.sha))
        let exerciseID = "overhead_press_barbell"
        let suite = "ExerciseDemoTests.approved-motion." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer {
            defaults.removePersistentDomain(forName: suite)
            CoreExerciseDemos.reviewOverrideForTests = nil
            DemoURLProtocol.handler = nil
            DemoURLProtocol.rangedHandler = nil
        }
        let catalog = try JSONSerialization.data(withJSONObject: ["version": 1, "assets": [[
            "exerciseId": exerciseID, "status": "ready", "sha256": clip.sha, "bytes": clip.data.count,
            "videoPath": "/v1/exercise-demos/video/" + clip.sha, "mediaType": "video"
        ]]])
        CoreExerciseDemos.reviewOverrideForTests = [Self.testMotionReview(exerciseID, sha: clip.sha)]
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DemoURLProtocol.self]
        let session = URLSession(configuration: config)
        let bases = [URL(string: "https://demo.test")!]
        DemoURLProtocol.handler = { _ in (200, catalog) }
        DemoURLProtocol.rangedHandler = { request in
            let header = request.value(forHTTPHeaderField: "Range") ?? "bytes=0-\(clip.data.count - 1)"
            let span = header.replacingOccurrences(of: "bytes=", with: "")
            let parts = span.split(separator: "-")
            let start = Int(parts.first ?? "0") ?? 0
            let end = Int(parts.dropFirst().first ?? "") ?? (clip.data.count - 1)
            let slice = clip.data.subdata(in: start..<(end + 1))
            return (206, slice, ["Content-Range": "bytes \(start)-\(end)/\(clip.data.count)", "Content-Type": "video/mp4"])
        }
        let live = ExerciseDemoService(session: session, baseURLs: bases, catalogDefaults: defaults)
        await live.refreshAvailableCatalog(force: true)
        XCTAssertEqual(live.remoteAssets[exerciseID]?.sha256, clip.sha)
        await live.loadMedia(exerciseID, force: true)
        let url = try XCTUnwrap(live.files[exerciseID])
        let saved = try Data(contentsOf: url)
        XCTAssertEqual(saved, clip.data)
        XCTAssertGreaterThan(saved.count, 1024)
        XCTAssertEqual(try await AVURLAsset(url: url).load(.isPlayable), true)
        var networkRequests = 0
        DemoURLProtocol.handler = { _ in networkRequests += 1; throw URLError(.notConnectedToInternet) }
        DemoURLProtocol.rangedHandler = { _ in networkRequests += 1; throw URLError(.notConnectedToInternet) }
        let offline = ExerciseDemoService(session: session, baseURLs: bases, catalogDefaults: defaults)
        await offline.loadMedia(exerciseID, force: true)
        XCTAssertEqual(offline.files[exerciseID], url)
        XCTAssertEqual(networkRequests, 0)
        XCTAssertFalse(CoreExerciseDemos.reviews.contains { $0.assetSHA256 == clip.sha })
    }
    func testDeliveredVideoInRealExerciseDetailSheet() async throws {
        let priorLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        defer { LanguageManager.shared.selectedLanguage = priorLanguage }
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById["incline_curl"])
        defer { CoreExerciseDemos.reviewOverrideForTests = nil; ExerciseDemoService.shared.clearTestMotionFixtures() }
        await ExerciseDemoService.shared.loadMedia(exercise.id, force: true)
        XCTAssertNil(ExerciseDemoService.shared.files[exercise.id])
        let clip = try await Self.testVideo(colors: [.red, .blue], framesPerSecond: 1)
        CoreExerciseDemos.reviewOverrideForTests = [Self.testMotionReview(exercise.id, sha: clip.sha)]
        ExerciseDemoService.shared.stageTestMotion(exerciseID: exercise.id, file: clip.url, sha: clip.sha)
        await ExerciseDemoService.shared.loadMedia(exercise.id, force: true)
        XCTAssertEqual(ExerciseDemoService.shared.files[exercise.id], clip.url)
        XCTAssertEqual(ExerciseDemoService.shared.presentation(for: exercise.id), .approvedMotion)
        XCTAssertFalse(CoreExerciseDemos.reviews.contains { $0.kind == "approved-animation" })
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let view = Color.clear.sheet(isPresented: .constant(true)) {
            ExerciseDetailSheet(exercise: exercise).environment(data).preferredColorScheme(.dark)
        }
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .seconds(1.5))
        func capture() -> Data? {
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            return image.pngData()
        }
        let first = try XCTUnwrap(capture())
        XCTAssertGreaterThan(first.count, 8000)
        let attachment = XCTAttachment(image: try XCTUnwrap(UIImage(data: first)))
        attachment.name = "priority66-exercise-detail"
        attachment.lifetime = .keepAlways
        add(attachment)
        try first.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("priority66-exercise-detail.png"))
        try await Task.sleep(for: .seconds(1.3))
        XCTAssertNotEqual(first, try XCTUnwrap(capture()), "Approved test motion should change the detail hero")
    }
    func testRevokedDemoPurgesCachedFileAndRejectsStaleServerMetadata() async throws {
        let sha = try XCTUnwrap(CoreExerciseDemos.revokedHashes.first)
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ExerciseDemos")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent(sha + ".mp4")
        try Data(repeating: 1, count: 2048).write(to: file)
        let offline = service()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        var videoRequests = 0
        DemoURLProtocol.handler = { request in
            if request.url!.path.contains("/video/") { videoRequests += 1; return (500, Data()) }
            let payload: [String: Any] = ["status": "ready", "sha256": sha, "bytes": 2048, "videoPath": "/v1/exercise-demos/video/" + sha]
            return (200, try JSONSerialization.data(withJSONObject: payload))
        }
        await offline.loadMedia("revoked-server-metadata-fixture", force: true)
        XCTAssertNil(offline.files["revoked-server-metadata-fixture"])
        XCTAssertEqual(videoRequests, 0)
        XCTAssertTrue(CoreExerciseDemos.assets.values.allSatisfy { !CoreExerciseDemos.revokedHashes.contains($0.sha256 ?? "") })
    }
    func testQuoteUsesServerBalanceAndSubmitPreservesExactCostAndConsent() async throws {
        let s = service()
        var posts = 0
        DemoURLProtocol.handler = { request in
            XCTAssertNotNil(request.value(forHTTPHeaderField: "Authorization"))
            if request.url!.path.hasSuffix("wallet") { return (200, Data(#"{"walletId":"test","balance":9,"held":2,"available":7}"#.utf8)) }
            if request.url!.path.hasSuffix("quote") { return (200, Data(#"{"status":"missing","enabled":true,"cost":5,"version":"v1","wallet":{"walletId":"test","balance":9,"held":2,"available":7}}"#.utf8)) }
            posts += 1
            // URLProtocol may expose upload bodies as streams. Verify outgoing stream too.
            let bytes: Data
            if let data = request.httpBody { bytes = data }
            else if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }; var data = Data(); var buffer = [UInt8](repeating:0,count:1024)
                while stream.hasBytesAvailable { let n = stream.read(&buffer,maxLength:buffer.count); if n <= 0 { break }; data.append(buffer,count:n) }; bytes = data
            } else { bytes = Data() }
            let payload = try JSONSerialization.jsonObject(with:bytes) as! [String:Any]
            XCTAssertEqual(payload["acceptedCost"] as? Int,5); XCTAssertEqual(payload["shareConsent"] as? Bool,true)
            XCTAssertEqual(payload["exerciseId"] as? String,"bench_press_wide_grip")
            XCTAssertNil(payload["balance"]); XCTAssertNil(payload["prompt"])
            return (202, Data(#"{"jobId":"job","exerciseId":"bench_press_wide_grip","status":"queued"}"#.utf8))
        }
        let quote = try await s.quote("bench_press_wide_grip")
        XCTAssertEqual(quote.wallet?.available,7)
        let submitted = try await s.generate("bench_press_wide_grip",quote:quote)
        XCTAssertEqual(submitted.status,"queued")
        XCTAssertEqual(posts,1)
    }
    func testDisabledQuoteNeverSubmitsAndAllLanguagesHaveCopy() async throws {
        let s=service(); var submits=0
        DemoURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("wallet") { return (200,Data(#"{"walletId":"test","balance":0,"held":0,"available":0}"#.utf8)) }
            if request.url!.path.hasSuffix("quote") { return (200,Data(#"{"status":"missing","enabled":false,"cost":null,"version":"v1"}"#.utf8)) }
            submits += 1; return (500,Data())
        }
        let q=try await s.quote("bench_press_wide_grip")
        do { _ = try await s.generate("bench_press_wide_grip",quote:q); XCTFail("Disabled quote submitted") } catch { }
        XCTAssertEqual(submits,0)
        for lang in SupportedLanguage.allCases {
            let path = try XCTUnwrap(Bundle.main.path(forResource:lang.rawValue,ofType:"lproj")); let b=try XCTUnwrap(Bundle(path:path))
            for key in ["title","credits","available","reserved","cost","generate","insufficient","unavailable","sharing","confirm","confirmBody","ready","queued","running","review","failed","corePending","missing","refresh","check","quoteChanged","unknown","plan","planHint"] {
                XCTAssertNotEqual(b.localizedString(forKey:"demo."+key,value:"MISSING",table:nil),"MISSING",lang.rawValue+key)
            }
        }
    }
    func testGenerationSheetInNativeNavigationAndLargeText() async throws {
        let s=service()
        DemoURLProtocol.handler = { request in
            if request.url!.path.hasSuffix("wallet") { return (200,Data(#"{"walletId":"test","balance":0,"held":0,"available":0}"#.utf8)) }
            return (200,Data(#"{"status":"missing","enabled":false,"cost":null,"version":"v1","wallet":{"walletId":"test","balance":0,"held":0,"available":0}}"#.utf8))
        }
        let scene=try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first)
        let previous=scene.windows.first(where: \.isKeyWindow);let window=UIWindow(windowScene:scene)
        defer { window.isHidden=true;previous?.makeKeyAndVisible() }
        let exercise=try XCTUnwrap(DataStore.makeMock().exById["bench_press_wide_grip"])
        for lang in [SupportedLanguage.en,.zhHans,.de,.ar] {
            let old=LanguageManager.shared.selectedLanguage;LanguageManager.shared.selectedLanguage=lang
            let view=ExerciseDemoGenerationSheet(exercise:exercise,service:s).environment(\.scenePhase,.active)
                .environment(\.locale,Locale(identifier:lang.rawValue)).environment(\.layoutDirection,lang == .ar ? .rightToLeft:.leftToRight)
                .environment(\.dynamicTypeSize,lang == .de ? .accessibility1:.large)
            window.rootViewController=UIHostingController(rootView: Color.clear.sheet(isPresented: .constant(true)) { view });window.makeKeyAndVisible()
            try await Task.sleep(for:.milliseconds(350));window.layoutIfNeeded()
            let image=UIGraphicsImageRenderer(bounds:window.bounds).image{_ in window.drawHierarchy(in:window.bounds,afterScreenUpdates:true)}
            let attachment=XCTAttachment(image:image);attachment.name="demo-sheet-"+lang.rawValue;attachment.lifetime = .keepAlways;add(attachment)
            try image.pngData()?.write(to:FileManager.default.temporaryDirectory.appendingPathComponent("demo-sheet-"+lang.rawValue+".png"))
            LanguageManager.shared.selectedLanguage=old
        }
    }
}

final class ExerciseMediaOwnershipTests: XCTestCase {
    func testSharedFramesHaveAtMostOneExactOwnerAndNoEquipmentBorrowing() {
        let groups = Dictionary(grouping: ExerciseLibrary.all.filter { $0.imageFolder != nil }, by: { $0.imageFolder! })
        for (folder, exercises) in groups {
            XCTAssertLessThanOrEqual(exercises.filter { ExerciseMediaPolicy.ownsLegacy($0.id, folder: folder) }.count, 1, folder)
        }
        XCTAssertEqual(ExerciseMediaPolicy.legacyOwners["Arnold_Dumbbell_Press"], "arnold_press_seated")
        XCTAssertEqual(ExerciseMediaPolicy.legacyOwners["Air_Bike"], "crunch_bicycle")
        XCTAssertFalse(ExerciseMediaPolicy.ownsLegacy("bench_press_dumbbell", folder: "Barbell_Bench_Press_-_Medium_Grip"))
        XCTAssertNil(ExerciseMediaPolicy.legacyOwners["Neck_Press"])
    }

    func testEachDirectVideoBelongsToOneExerciseAndKnownWrongLinksAreReplaced() throws {
        let urls = ExerciseLibrary.all.compactMap { $0.videoURL?.absoluteString }
        XCTAssertEqual(Set(urls).count, urls.count)
        let press = try XCTUnwrap(ExerciseLibrary.byId["push_press_dumbbell"])
        let lunge = try XCTUnwrap(ExerciseLibrary.byId["lunge_walking_bodyweight"])
        XCTAssertNotEqual(press.videoURL, lunge.videoURL)
        let curl = try XCTUnwrap(ExerciseLibrary.byId["leg_curl_seated"])
        let extensionExercise = try XCTUnwrap(ExerciseLibrary.byId["leg_extension_single_leg"])
        XCTAssertNotEqual(curl.videoURL, extensionExercise.videoURL)
        XCTAssertNotNil(ExerciseMediaPolicy.youtubeThumbnail(for: extensionExercise))
    }

    func testYouTubeThumbnailParsingRejectsUntrustedHostsAndMalformedIDs() {
        for url in ["https://youtu.be/abcdefghijk", "https://www.youtube.com/watch?v=abcdefghijk", "https://youtube.com/shorts/abcdefghijk"] {
            XCTAssertEqual(ExerciseMediaPolicy.youtubeID(URL(string: url)), "abcdefghijk")
        }
        for url in ["https://youtube.com.evil.test/watch?v=abcdefghijk", "https://evil.test/abcdefghijk", "https://youtube.com/watch?v=short", "file:///abcdefghijk"] {
            XCTAssertNil(ExerciseMediaPolicy.youtubeID(URL(string: url)))
        }
    }
}

@MainActor
final class ExerciseMediaLayoutTests: XCTestCase {
    func testHeroUsesDisplayedSourceInsteadOfMerelyHavingAYouTubeLink() throws {
        let youtube = Exercise(id: "youtube-fallback-fixture", name: "Unadopted video", category: .strength,
                               tags: [], primaryMuscles: [.legs], muscleGroups: [.legs], imageFolder: nil,
                               instructions: [], videoURL: URL(string: "https://youtu.be/abcdefghijk"))
        let core = try XCTUnwrap(ExerciseLibrary.byId["bicep_curl_dumbbell"])
        XCTAssertTrue(ExerciseMediaPolicy.usesYouTubeThumbnail(for: youtube))
        XCTAssertEqual(ExerciseMediaHero.height(for: youtube, width: 400), 240)
        XCTAssertNotNil(core.videoURL)
        XCTAssertFalse(ExerciseMediaPolicy.usesYouTubeThumbnail(for: core))
        XCTAssertEqual(ExerciseMediaHero.height(for: core, width: 400), 400)
        var custom = youtube
        custom.customImageData = coloredCover().pngData()
        XCTAssertFalse(ExerciseMediaPolicy.usesYouTubeThumbnail(for: custom))
        XCTAssertEqual(ExerciseMediaHero.height(for: custom, width: 400), 400)
    }

    private func coloredCover() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
            UIColor.red.setFill(); context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
            UIColor.blue.setFill(); context.fill(CGRect(x: 70, y: 0, width: 180, height: 180))
        }
    }
    func testLandscapeCoverFillsSquareTileAndTallPlayerWithoutBands() throws {
        var exercise = try XCTUnwrap(ExerciseLibrary.byId["leg_extension_single_leg"])
        exercise.customImageData = coloredCover().pngData()
        let scenes: [(String, AnyView, CGSize)] = [
            ("square-fill", AnyView(ExerciseImage(category: exercise.category, customImageData: exercise.customImageData, cornerRadius: 0, size: 56)), CGSize(width: 56, height: 56)),
            ("portrait-fill", AnyView(FullBleedExerciseImage(exercise: exercise).frame(width: 100, height: 300)), CGSize(width: 100, height: 300))
        ]
        for (name, view, size) in scenes {
            let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            let cg = try XCTUnwrap(image.cgImage)
            var pixels = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
            let context = try XCTUnwrap(CGContext(data: &pixels, width: cg.width, height: cg.height, bitsPerComponent: 8,
                bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
            for point in [(2, 2), (cg.width / 2, 2), (cg.width - 3, cg.height - 3)] {
                let offset = (point.1 * cg.width + point.0) * 4
                XCTAssertGreaterThan(pixels[offset + 2], 220, "\(name) must contain blue photo content at its edges")
                XCTAssertLessThan(pixels[offset], 20)
            }
        }
    }

    func testRealDetailSetupAndPlayerUseTheNewMediaFrames() async throws {
        let previousLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        defer { LanguageManager.shared.selectedLanguage = previousLanguage }
        let data = DataStore.makeMock()
        let youtube = try XCTUnwrap(data.exById["leg_extension_single_leg"])
        let core = try XCTUnwrap(data.exById["bicep_curl_dumbbell"])
        let url = try XCTUnwrap(ExerciseMediaPolicy.youtubeThumbnail(for: youtube))
        let cover = await ExerciseImageCache.shared.loadURL(url.absoluteString)
        XCTAssertNotNil(cover, "The real YouTube cover must be loaded for visual verification")
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let training = TrainingSessionStore(completionSound: {})
        let now = Date()
        let plan = Plan(id: "media-layout-preview", name: "Media preview", steps: [PlanStep(id: "youtube-step", exerciseId: youtube.id, sets: 2, reps: 8, weight: 20, duration: nil)], createdAt: now, updatedAt: now)
        training.start(planId: plan.id, plan: plan, segments: expandPlan(plan, exById: data.exById, defaultRest: 90, defaultBetweenExerciseRest: 120))
        let scenes: [(String, AnyView)] = [
            ("youtube-detail", AnyView(Color.clear.sheet(isPresented: .constant(true)) { ExerciseDetailSheet(exercise: youtube).environment(data).presentationDetents([.large]) })),
            ("core-detail", AnyView(Color.clear.sheet(isPresented: .constant(true)) { ExerciseDetailSheet(exercise: core).environment(data).presentationDetents([.large]) })),
            ("youtube-setup", AnyView(Color.clear.sheet(isPresented: .constant(true)) { OpenWorkoutExerciseSetup(exercise: youtube, onStart: { _ in }).environment(data).presentationDetents([.large]) })),
            ("youtube-player", AnyView(PlanPlayerScreen().environment(data).environment(training))),
            ("youtube-row-and-grid", AnyView(AppNavigationStack { ScrollView { VStack { ExerciseRowContent(exercise: youtube); ExerciseGridContent(exercise: youtube).frame(width: 180) }.padding() } }.environment(data)))
        ]
        for (name, view) in scenes {
            window.rootViewController = UIHostingController(rootView: view.preferredColorScheme(.dark))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(900))
            window.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
        }
    }
}
