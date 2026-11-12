import XCTest
import SwiftUI
import UIKit
import AVFoundation
@testable import Maso

@MainActor final class ExercisePrefetchPriorityTests: XCTestCase {
    func testLatestRoutineIsFirstAndSharedExercisesAreNotDuplicated() {
        XCTAssertEqual(ExerciseDemoService.mergedPrefetchIDs(
            ["squat", "row", "squat"], ["row", "press", "curl"]
        ), ["squat", "row", "press", "curl"])
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
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: ["Content-Type":"application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() { }
}
@MainActor final class ExerciseDemoTests: XCTestCase {
    func testTwoFrameDemosChangeOnScreen() async throws {
        let paths = [
            "docs/gif-import-2026-10-31/clamshell_banded.mp4",
            "docs/gif-review-decisions-2026-11-02/banded_lateral_walk.mp4"
        ]
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for path in paths {
            let url = URL(fileURLWithPath: "/Users/yumowu/Projects/Maso-iOS/" + path)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
            window.rootViewController = UIHostingController(rootView: GeneratedExerciseVideo(url: url).frame(width: 240, height: 240))
            window.makeKeyAndVisible()
            try await Task.sleep(for: .seconds(1.5))
            func capture() -> Data? {
                window.layoutIfNeeded()
                return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }.pngData()
            }
            let first = capture()
            try await Task.sleep(for: .seconds(0.95))
            XCTAssertNotEqual(first, capture(), "Two-frame demo must visibly advance: \(path)")
        }
    }

    func testTwoFrameDemoInRealDetailSheet() async throws {
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById["clamshell_banded"])
        let sha = try XCTUnwrap(CoreExerciseDemos.assets[exercise.id]?.sha256)
        let source = URL(fileURLWithPath: "/Users/yumowu/Projects/Maso-iOS/docs/gif-import-2026-10-31/clamshell_banded.mp4")
        let directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("ExerciseDemos")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let cached = directory.appendingPathComponent(sha + ".mp4")
        try Data(contentsOf: source).write(to: cached, options: .atomic)
        await ExerciseDemoService.shared.loadMedia(exercise.id, force: true)
        XCTAssertEqual(ExerciseDemoService.shared.files[exercise.id], cached)
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
        try await Task.sleep(for: .seconds(0.95))
        XCTAssertNotEqual(first, try mediaCrop(), "The exercise detail hero should change frames")
    }
    func testCurrentAndUpcomingExercisesUseTheSameFilledVideoInPlayer() async throws {
        let data = DataStore.makeMock()
        let first = try XCTUnwrap(data.exById["bicep_curl_dumbbell"])
        let next = try XCTUnwrap(data.exById["squat_bodyweight"])
        for exercise in [first, next] {
            await ExerciseDemoService.shared.loadMedia(exercise.id)
            XCTAssertNotNil(ExerciseDemoService.shared.files[exercise.id])
        }
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
            XCTAssertEqual(video.videoGravity, .resizeAspectFill)
            XCTAssertEqual(video.player?.isMuted, true)
            XCTAssertEqual(video.player?.currentItem?.status, .readyToPlay)
            window.layoutIfNeeded()
            mediaFrames.append(video.convert(video.bounds, to: window.layer))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "training-media-stage-\(index)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("training-media-stage-\(index).png"))
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
        return ExerciseDemoService(session: URLSession(configuration: config), baseURLs: [URL(string:"https://demo.test")!])
    }
    func testCoreDeliveryCatalogAndRealDownloadSurvivesOfflineReopen() async throws {
        XCTAssertEqual(CoreExerciseDemos.assets.count, 91)
        XCTAssertNil(CoreExerciseDemos.assets["inverted_row"])
        XCTAssertNil(CoreExerciseDemos.assets["arnold_press"])
        XCTAssertNotNil(CoreExerciseDemos.assets["arnold_press_seated"])
        XCTAssertTrue(CoreExerciseDemos.revokedHashes.contains("3057a31465c0198465f8a5f8cd43569ada9580bb6da018d6c244ea277cd065af"))
        XCTAssertNil(CoreExerciseDemos.assets["hamstring_stretch_supine"])
        XCTAssertNotNil(CoreExerciseDemos.assets["hamstring_stretch_supine_strap"])
        for (id, row) in CoreExerciseDemos.assets {
            XCTAssertEqual(row.exerciseId, id)
            XCTAssertNotNil(CoreExerciseDemos.thumbnail(id), id)
            XCTAssertEqual(row.sha256?.count, 64)
        }
        let live = ExerciseDemoService()
        await live.loadMedia("overhead_press_barbell")
        let url = try XCTUnwrap(live.files["overhead_press_barbell"])
        XCTAssertGreaterThan(try Data(contentsOf: url).count, 1024)
        let offline = service()
        var networkRequests = 0
        DemoURLProtocol.handler = { _ in networkRequests += 1; throw URLError(.notConnectedToInternet) }
        await offline.loadMedia("overhead_press_barbell")
        XCTAssertEqual(offline.files["overhead_press_barbell"], url)
        XCTAssertEqual(networkRequests, 0)
    }
    func testDeliveredVideoInRealExerciseDetailSheet() async throws {
        let priorLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        defer { LanguageManager.shared.selectedLanguage = priorLanguage }
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById["incline_curl"])
        await ExerciseDemoService.shared.loadMedia(exercise.id)
        XCTAssertNotNil(ExerciseDemoService.shared.files[exercise.id])
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let view = Color.clear.sheet(isPresented: .constant(true)) {
            ExerciseDetailSheet(exercise: exercise).environment(data).preferredColorScheme(.dark)
        }
        window.rootViewController = UIHostingController(rootView: view)
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(1000))
        window.layoutIfNeeded()
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image); attachment.name = "priority66-exercise-detail"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("priority66-exercise-detail.png"))
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
        await offline.loadMedia("arnold_press", force: true)
        XCTAssertNil(offline.files["arnold_press"])
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
        let youtube = try XCTUnwrap(ExerciseLibrary.byId["leg_extension_single_leg"])
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
