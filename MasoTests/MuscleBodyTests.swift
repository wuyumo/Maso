import XCTest
import SceneKit
import SwiftUI
import PDFKit
@testable import Maso

final class MuscleBodyTests: XCTestCase {
    func testRecoverySurfaceHasAUniqueColorForEachDisplayedPercent() {
        var colors = Set<[Double]>()
        var previousGreen = -Double.infinity
        for percent in 0...100 {
            let rgb = MasoColor.recoverySurfaceRGB(fatigue: Double(percent) / 100)
            colors.insert([rgb.red, rgb.green, rgb.blue])
            XCTAssertGreaterThan(rgb.green, previousGreen)
            if percent > 0 { XCTAssertLessThan(rgb.green - previousGreen, 0.01) }
            previousGreen = rgb.green
        }
        XCTAssertEqual(colors.count, 101, "One-percent intervals include both 0% and 100% endpoints")
        let idle = MasoColor.recoverySurfaceRGB(fatigue: 0)
        XCTAssertEqual(idle.red, idle.green)
        XCTAssertEqual(idle.green, idle.blue)
        let full = MasoColor.recoverySurfaceRGB(fatigue: 1)
        XCTAssertEqual(full.red, MasoColor.accentRGB.red, accuracy: 0.000001)
        XCTAssertEqual(full.green, MasoColor.accentRGB.green, accuracy: 0.000001)
        XCTAssertEqual(full.blue, MasoColor.accentRGB.blue, accuracy: 0.000001)
        XCTAssertEqual(MasoColor.recoveryBlendAmount(fatigue: 0.418), MasoColor.recoveryBlendAmount(fatigue: 0.422),
                       "Both recovery cards display 58%")
        for (before, after) in [(0.1199, 0.1201), (0.3499, 0.3501), (0.6499, 0.6501)] {
            XCTAssertEqual(MasoColor.recoveryBlendAmount(fatigue: before), MasoColor.recoveryBlendAmount(fatigue: after),
                           "Semantic tier boundaries must not introduce color jumps")
        }
        for invalid in [Double.nan, .infinity, -.infinity, -2] {
            XCTAssertEqual(MasoColor.recoveryBlendAmount(fatigue: invalid), 0)
        }
        XCTAssertEqual(MasoColor.recoveryBlendAmount(fatigue: 2), 1)
    }

    func testRecoveryMaterialMatchesThePercentPaletteAndKeepsNeutralModes() throws {
        func channels(_ property: SCNMaterialProperty) throws -> [CGFloat] {
            let color = try XCTUnwrap(property.contents as? UIColor)
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
            XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
            XCTAssertEqual(a, 1)
            return [r, g, b]
        }
        func base(_ material: SCNMaterial) throws -> [CGFloat] {
            zip(try channels(material.diffuse), try channels(material.emission)).map(+)
        }
        let mapping = try regions()
        let values: [MuscleGroup: Double] = [.upperAbs: 0.418, .lowerAbs: 0.418, .obliques: 0.422, .serratus: 0.422]
        var matched: [[CGFloat]] = []
        for name in ["abs_center", "obliques_left", "obliques_right"] {
            let region = try XCTUnwrap(mapping.first { $0.node == name })
            let material = SCNMaterial()
            region.applyRecoveryColor(to: material, fatigueMap: values)
            let actual = try base(material)
            let rgb = MasoColor.recoverySurfaceRGB(fatigue: region.fatigue(in: values))
            for (value, expected) in zip(actual, [rgb.red, rgb.green, rgb.blue]) {
                XCTAssertEqual(Double(value), expected, accuracy: 0.000001)
            }
            matched.append(actual)
            region.applyRecoveryColor(to: material, fatigueMap: values, showsFatigueColors: false)
            for component in try base(material) { XCTAssertEqual(Double(component), 0.24, accuracy: 0.000001) }
        }
        XCTAssertEqual(matched[0], matched[1])
        XCTAssertEqual(matched[1], matched[2])
        let fullyTrained = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0, 1.0) })
        for region in mapping where !region.fatigueEligible {
            let material = SCNMaterial()
            region.applyRecoveryColor(to: material, fatigueMap: fullyTrained)
            for component in try base(material) { XCTAssertEqual(Double(component), 0.32, accuracy: 0.000001) }
        }
    }

    func testRecoveryListMatchesModelGroupsAndCurveAndSortsKnownValues() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let regions = try MuscleBodyRegion.loadBundled()
        let bench = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        let squat = try XCTUnwrap(ExerciseLibrary.byId.values.first { $0.primaryMuscles.contains(.quads) })
        let records = [SetRecord(id: "recover-old", exerciseId: squat.id, exerciseName: squat.name,
                                category: .strength, reps: 8, performedAt: now.addingTimeInterval(-8 * 86400)),
                       SetRecord(id: "recover-new", exerciseId: bench.id, exerciseName: bench.name,
                                category: .strength, weight: 40, reps: 8, performedAt: now.addingTimeInterval(-3600))]
        let rows = MuscleStatusCompute.recoverySummaries(regions: regions, sets: records,
                                                        exById: ExerciseLibrary.byId, now: now)
        XCTAssertEqual(rows.count, 17)
        XCTAssertEqual(Set(rows.map(\.id)).count, rows.count)
        let values = rows.compactMap(\.recovered)
        XCTAssertEqual(values, values.sorted(by: >))
        XCTAssertTrue(rows.dropFirst(values.count).allSatisfy { $0.recovered == nil })
        XCTAssertEqual(try XCTUnwrap(rows.first { $0.muscle == .quads }?.recovered), 1, accuracy: 0.00001)
        let fatigue = MuscleStatusCompute.muscleFatigueMap(sets: records, exById: ExerciseLibrary.byId, now: now)
        for row in rows where row.recovered != nil {
            XCTAssertEqual(try XCTUnwrap(row.recovered), 1 - row.region.fatigue(in: fatigue), accuracy: 0.00001)
            let curve = MuscleStatusCompute.recoveryTimeline(muscles: row.region.muscles, sets: records,
                                                            exById: ExerciseLibrary.byId, now: now)
            XCTAssertEqual(try XCTUnwrap(row.recovered), try XCTUnwrap(curve.last?.recovered), accuracy: 0.00001)
        }
    }

    func testRecoveryListKeepsUnrecordedMusclesUnknownAndIgnoresFutureRecords() throws {
        let regions = try MuscleBodyRegion.loadBundled()
        let now = Date()
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["bench_press_barbell"])
        let future = SetRecord(id: "recover-future", exerciseId: exercise.id, exerciseName: exercise.name,
                               category: .strength, reps: 8, performedAt: now.addingTimeInterval(3600))
        for records in [[], [future]] {
            let rows = MuscleStatusCompute.recoverySummaries(regions: regions, sets: records,
                                                            exById: ExerciseLibrary.byId, now: now)
            XCTAssertEqual(rows.count, 17)
            XCTAssertTrue(rows.allSatisfy { $0.recovered == nil })
            XCTAssertFalse(rows.contains { !$0.region.fatigueEligible })
        }
    }

    @MainActor
    func testRecoveryListInNativeNavigationAndLanguages() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let oldLanguage = LanguageManager.shared.selectedLanguage
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible(); LanguageManager.shared.selectedLanguage = oldLanguage }
        for name in ["en", "zh-Hans", "de", "ar", "empty", "accessibility"] {
            let language = SupportedLanguage(rawValue: name) ?? .en
            LanguageManager.shared.selectedLanguage = language
            let data = DataStore.makeMock()
            if name == "empty" { data.sets = [] }
            let state = RecoveryListTestState()
            let host = UIHostingController(rootView: RecoveryListTestFixture(state: state)
                .environment(data)
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .environment(\.dynamicTypeSize, name == "accessibility" ? .accessibility3 : .large)
                .preferredColorScheme(.dark))
            window.rootViewController = host; window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(300))
            state.path = ["list"]
            try await Task.sleep(for: .milliseconds(550))
            func navigation(_ controller: UIViewController) -> UINavigationController? {
                if let result = controller as? UINavigationController { return result }
                return controller.children.lazy.compactMap { navigation($0) }.first
            }
            let nav = try XCTUnwrap(navigation(host))
            XCTAssertEqual(nav.viewControllers.count, 2)
            XCTAssertTrue(nav.interactivePopGestureRecognizer?.isEnabled == true)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = "Recovery list \(name)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recovery-list-\(name).png"))
            // Keep one fully settled frame available to the simulator compositor;
            // UIKit's hierarchy renderer can mirror an RTL-backed List snapshot.
            if name == "en" { try await Task.sleep(for: .seconds(2)) }
            state.path = []
            try await Task.sleep(for: .milliseconds(350))
            XCTAssertEqual(nav.viewControllers.count, 1)
            window.isHidden = true
        }
    }

    @MainActor
    func testBothMuscleNavigationHandoffsAndInterruptedBack() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        let state = MuscleHandoffTestState()
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: MuscleHandoffNavigationFixture(state: state).environment(data).preferredColorScheme(.dark))
        window.rootViewController = host; window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        func renderer(_ role: MuscleNavigationRole, in view: UIView) -> MuscleBody3DView.Coordinator? {
            if let model = view as? SCNView, model.scene != nil,
               let coordinator = model.gestureRecognizers?.compactMap({ $0.delegate as? MuscleBody3DView.Coordinator }).first,
               coordinator.navigationRole == role { return coordinator }
            return view.subviews.lazy.compactMap { renderer(role, in: $0) }.first
        }
        func awaitRenderer(_ role: MuscleNavigationRole, completed: Bool = false) async throws -> MuscleBody3DView.Coordinator {
            for _ in 0..<60 {
                if let result = renderer(role, in: window), !completed || result.completedNavigationHandoffs > 0 { return result }
                try await Task.sleep(for: .milliseconds(100))
            }
            return try XCTUnwrap(renderer(role, in: window), "Renderer must load for the destination")
        }
        func snapshot(_ name: String) throws {
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
            let attachment = XCTAttachment(image: image); attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
        }
        let home = try await awaitRenderer(.home)
        try await Task.sleep(for: .milliseconds(500))
        try snapshot("muscle-handoff-home-before")
        home.prepareNavigation(to: .status)
        state.path.append(1)
        try await Task.sleep(for: .milliseconds(220))
        try snapshot("muscle-handoff-home-status-mid")
        let status = try await awaitRenderer(.status, completed: true)
        XCTAssertEqual(status.completedNavigationHandoffs, 1)
        XCTAssertNil(status.navigationTransfer)
        XCTAssertEqual(status.view?.alpha, 1)
        try snapshot("muscle-handoff-status-after")
        let region = try XCTUnwrap(regions().first { $0.node == "obliques_left" })
        status.onMuscleTap?(region, false)
        try await Task.sleep(for: .milliseconds(750))
        try snapshot("muscle-handoff-selected-before")
        MuscleNavigationBridge.shared.prepare(from: .status, to: .exercises)
        state.path.append(2)
        try await Task.sleep(for: .milliseconds(260))
        try snapshot("muscle-handoff-status-exercises-mid")
        let detail = try await awaitRenderer(.exercises, completed: true)
        XCTAssertEqual(detail.completedNavigationHandoffs, 1)
        XCTAssertEqual(detail.view?.alpha, 1)
        XCTAssertNil(detail.navigationTransfer)
        try snapshot("muscle-handoff-exercises-after")
        state.path.removeLast()
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(status.view?.alpha, 1)
        // Reverse the next push while the screenshot/live handoff is still in progress.
        MuscleNavigationBridge.shared.prepare(from: .status, to: .exercises)
        state.path.append(2)
        try await Task.sleep(for: .milliseconds(180))
        state.path.removeLast()
        try await Task.sleep(for: .milliseconds(850))
        func overlays(in view: UIView) -> Int {
            (["muscle.navigation.snapshot", "muscle.navigation.live"].contains(view.accessibilityIdentifier ?? "") ? 1 : 0) + view.subviews.reduce(0) { $0 + overlays(in: $1) }
        }
        XCTAssertEqual(overlays(in: window), 0)
        XCTAssertEqual(status.view?.alpha, 1)
        func navigation(in controller: UIViewController) -> UINavigationController? {
            if let result = controller as? UINavigationController { return result }
            return controller.children.lazy.compactMap { navigation(in: $0) }.first
        }
        XCTAssertTrue(try XCTUnwrap(navigation(in: host)?.interactivePopGestureRecognizer).isEnabled)
    }

    @MainActor
    func testLocalizedBrandFooterFitsLongSloganAlongsideQR() throws {
        for language in ["en", "zh-Hans", "fr", "de", "ar"] {
            let image = try XCTUnwrap(ShareImageRenderer.render(width: 390) {
                ShareCardFooter(qrPayload: MasoLinks.appStore, qrSize: 64)
                    .environment(\.locale, Locale(identifier: language))
                    .environment(\.layoutDirection, language == "ar" ? .rightToLeft : .leftToRight)
                    .padding(20).background(MasoColor.background)
            })
            XCTAssertGreaterThan(image.size.height, 80)
            let attachment = XCTAttachment(image: image); attachment.name = "Brand footer \(language)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("brand-footer-\(language).png"))
        }
    }

    @MainActor
    func testMuscleDetailsRetainNativeInteractiveBackWhenPushed() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: MuscleBackNavigationFixture().environment(DataStore.makeMock()).preferredColorScheme(.dark))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(1200))
        func navigation(in controller: UIViewController) -> UINavigationController? {
            if let result = controller as? UINavigationController { return result }
            return controller.children.lazy.compactMap { navigation(in: $0) }.first
        }
        let stack = try XCTUnwrap(navigation(in: host))
        XCTAssertEqual(stack.viewControllers.count, 2)
        XCTAssertFalse(try XCTUnwrap(stack.topViewController).navigationItem.hidesBackButton)
        let gesture = try XCTUnwrap(stack.interactivePopGestureRecognizer)
        XCTAssertTrue(gesture.isEnabled)
        XCTAssertTrue(gesture.delegate?.gestureRecognizerShouldBegin?(gesture) ?? true)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Muscle details native back"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("muscle-details-native-back.png"))
    }

    @MainActor
    func testRecoveryCardInNativeFullPage() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(ExerciseLibrary.byId["russian_twist"])
        data.sets = [SetRecord(id: "recovery-layout", exerciseId: exercise.id, exerciseName: exercise.name,
                               category: .strength, reps: 10, performedAt: Date().addingTimeInterval(-3600))]
        var recoveryVisibility: [Bool] = []
        let view = MuscleMapDetailScreen(fatigueMap: MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById),
                                        gapMuscles: [], onStartGapWorkout: {}, onRecoveryCardVisibilityChange: { recoveryVisibility.append($0) })
            .navigationTitle("My Muscle Status").navigationBarTitleDisplayMode(.inline)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView: NavigationStack { view }.environment(data).preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        func model(in view: UIView) -> SCNView? {
            if let result = view as? SCNView { return result }
            return view.subviews.lazy.compactMap { model(in: $0) }.first
        }
        try await Task.sleep(for: .milliseconds(900))
        let modelView = try XCTUnwrap(model(in: window))
        let coordinator = try XCTUnwrap(modelView.gestureRecognizers?.compactMap { $0.delegate as? MuscleBody3DView.Coordinator }.first)
        let defaultPage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let defaultAttachment = XCTAttachment(image: defaultPage); defaultAttachment.name = "Recovery gradient on native muscle status"; defaultAttachment.lifetime = .keepAlways; add(defaultAttachment)
        try defaultPage.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recovery-gradient-status.png"))
        try modelView.snapshot().pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recovery-gradient-model.png"))
        let region = try XCTUnwrap(regions().first { $0.node == "obliques_left" })
        coordinator.onMuscleTap?(region, false)
        try await Task.sleep(for: .milliseconds(750))
        func colorComponents(_ nodeName: String) throws -> (CGFloat, CGFloat, CGFloat) {
            let node = try XCTUnwrap(modelView.scene?.rootNode.childNode(withName: nodeName, recursively: true))
            let color = try XCTUnwrap(node.geometry?.firstMaterial?.diffuse.contents as? UIColor)
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            XCTAssertTrue(color.getRed(&red, green: &green, blue: &blue, alpha: &alpha))
            return (red, green, blue)
        }
        XCTAssertFalse(coordinator.showsFatigueColors)
        XCTAssertEqual(recoveryVisibility.last, true)
        for name in ["obliques_left", "obliques_right"] {
            let (red, green, blue) = try colorComponents(name)
            XCTAssertGreaterThan(green, red)
            XCTAssertGreaterThan(green, blue)
        }
        let neutral = try colorComponents("abs_center")
        XCTAssertEqual(neutral.0, neutral.1, accuracy: 0.001)
        XCTAssertEqual(neutral.1, neutral.2, accuracy: 0.001)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Compact recovery overlay"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recovery-overlay-compact.png"))
        // Re-layout the same native page in a shorter viewport; the chart should yield
        // space to text and fixed actions rather than pushing the actions off-screen.
        window.frame.size.height = 740
        try await Task.sleep(for: .milliseconds(450))
        let compact = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let compactAttachment = XCTAttachment(image: compact); compactAttachment.name = "Adaptive recovery shorter viewport"; compactAttachment.lifetime = .keepAlways; add(compactAttachment)
        try compact.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recovery-overlay-short.png"))
        coordinator.onTap?()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(coordinator.showsFatigueColors)
        XCTAssertEqual(recoveryVisibility.last, false)
        let restored = try colorComponents("abs_center")
        XCTAssertGreaterThan(restored.1, restored.0)
    }

    @MainActor
    func testMuscleExercisesPageWithFocusedRightHeroInNativeNavigation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            MuscleInfoScreen(muscle: .obliques, relatedMuscles: [.obliques], regionNode: "obliques_left", showsBack: false)
        }.environment(data).preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        func model(in view: UIView) -> SCNView? {
            if let result = view as? SCNView { return result }
            return view.subviews.lazy.compactMap { model(in: $0) }.first
        }
        for _ in 0..<25 {
            if model(in: window)?.scene != nil { break }
            try await Task.sleep(for: .milliseconds(200))
        }
        let modelView = try XCTUnwrap(model(in: window))
        XCTAssertNotNil(modelView.scene)
        let coordinator = try XCTUnwrap(modelView.gestureRecognizers?.compactMap { $0.delegate as? MuscleBody3DView.Coordinator }.first)
        XCTAssertEqual(coordinator.focusedRegionNode, "obliques_left")
        XCTAssertEqual(coordinator.highlightedRegionNode, "obliques_left")
        XCTAssertFalse(coordinator.showsFatigueColors)
        XCTAssertGreaterThan(modelView.bounds.width, 0)
        XCTAssertGreaterThan(modelView.bounds.height, 0)
        let modelFrame = modelView.convert(modelView.bounds, to: window)
        XCTAssertEqual(modelFrame.minY, 0, accuracy: 1)
        XCTAssertEqual(modelFrame.minX, 0, accuracy: 1)
        XCTAssertGreaterThanOrEqual(modelFrame.width, window.bounds.width)
        try await Task.sleep(for: .milliseconds(700))
        try modelView.snapshot().pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("muscle-focused-render.png"))
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Focused muscle hero aligned right"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("muscle-exercises-focused-right.png"))
    }

    @MainActor
    func testMuscleTrainingRequestPrefillsWithoutSendingOrChangingSavedPlans() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first { $0.isKeyWindow }
        let data = DataStore.makeMock()
        let savedIDs = data.plans.map(\.id)
        let messageCount = data.coachSession.messages.count
        let draftIDs = data.coachSession.currentRoutines.map(\.id)
        AppRouter.shared.pendingMuscleTraining = .obliques
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        window.rootViewController = UIHostingController(rootView: NavigationStack {
            CoachScreen(onStart: { _ in }, onNewPlan: {}, libraryRequested: .constant(false), routinePromptRequested: .constant(false))
        }.environment(data).preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        defer { AppRouter.shared.pendingMuscleTraining = nil; window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(1000))
        func textViews(in view: UIView) -> [UITextView] {
            (view as? UITextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
        }
        let composer = try XCTUnwrap(textViews(in: window).first { $0.isEditable })
        XCTAssertEqual(composer.text, AppRouter.muscleTrainingPrompt(for: .obliques))
        XCTAssertNil(AppRouter.shared.pendingMuscleTraining)
        XCTAssertFalse(data.coachSession.isGenerating)
        XCTAssertEqual(data.coachSession.messages.count, messageCount)
        XCTAssertEqual(data.plans.map(\.id), savedIDs)
        XCTAssertEqual(data.coachSession.currentRoutines.map(\.id), draftIDs)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        let attachment = XCTAttachment(image: image); attachment.name = "Muscle training Coach draft"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("muscle-training-coach.png"))
    }

    func testObliqueExercisesColorBothSidesAndRespectRecovery() throws {
        let now = Date()
        let bodyRegions = try regions().filter { $0.node.hasPrefix("obliques_") }
        XCTAssertEqual(bodyRegions.count, 2)
        for id in ["russian_twist", "plank_side", "cable_woodchopper", "plank_high", "plank_rkc", "dead_bug", "bird_dog", "mountain_climber"] {
            let exercise = try XCTUnwrap(ExerciseLibrary.byId[id])
            XCTAssertTrue(exercise.muscleGroups.contains(.obliques), id)
            let records = (0..<3).map { index in
                SetRecord(id: "oblique-\(index)", exerciseId: id, exerciseName: exercise.name,
                          category: .strength, reps: 10, performedAt: now)
            }
            let map = MuscleStatusCompute.muscleFatigueMap(sets: records, exById: [id: exercise], now: now)
            for region in bodyRegions {
                XCTAssertGreaterThan(region.fatigue(in: map), 0.35, id)
            }
            let expired = MuscleStatusCompute.muscleFatigueMap(sets: records, exById: [id: exercise], now: now.addingTimeInterval(6 * 86400))
            XCTAssertEqual(expired[.obliques] ?? 0, 0)
        }
        let curl = try XCTUnwrap(ExerciseLibrary.all.first { $0.id == "bicep_curl_dumbbell" } ?? ExerciseLibrary.all.first { $0.name == "Biceps Curl (Dumbbell)" })
        XCTAssertFalse(curl.muscleGroups.contains(.obliques))
    }

    @MainActor
    func testReplaceActiveExercisePreservesStepAndClearsPreviousLoad() {
        let old = Exercise(id: "old", name: "Old", category: .strength, tags: [], primaryMuscles: [.chest],
                           muscleGroups: [.chest], imageFolder: nil, instructions: [])
        let replacement = Exercise(id: "new", name: "New", category: .strength, tags: [], primaryMuscles: [.upperChest],
                                   muscleGroups: [.upperChest], imageFolder: nil, instructions: [])
        let library = [old.id: old, replacement.id: replacement]
        let step = PlanStep(id: "stable", exerciseId: old.id, sets: 3, reps: 10, weight: 20,
                            setReps: [8, 9, 10], setWeights: [20, 22, 24])
        let plan = Plan(id: "test-replace", name: "Test", steps: [step], createdAt: Date(), updatedAt: Date())
        let store = TrainingSessionStore()
        store.start(planId: plan.id, plan: plan,
                    segments: expandPlan(plan, exById: library, defaultRest: 60, defaultBetweenExerciseRest: 60))
        defer { store.end() }
        store.replaceStepExercise(step.id, newExerciseId: replacement.id, exById: library,
                                  defaultRest: 60, defaultBetweenExerciseRest: 60)
        XCTAssertEqual(store.plan?.steps.first?.exerciseId, replacement.id)
        XCTAssertEqual(store.plan?.steps.first?.setReps, [8, 9, 10])
        XCTAssertNil(store.plan?.steps.first?.setWeights)
        XCTAssertNil(store.plan?.steps.first?.weight)
        XCTAssertEqual(store.currentSegment?.stepId, step.id)
        XCTAssertFalse(store.segments.isEmpty)
        for index in 0..<20 {
            store.setIndex(max(0, store.segments.count - 1))
            store.replaceStepExercise(step.id, newExerciseId: index.isMultiple(of: 2) ? old.id : replacement.id,
                                      exById: library, defaultRest: 60, defaultBetweenExerciseRest: 60)
            XCTAssertNotNil(store.currentSegment)
        }
    }

    @MainActor
    func test3DMuscleShareExportContainsBothViews() throws {
        let image = try XCTUnwrap(ShareImageRenderer.render {
            ShareMuscleBody3D(muscles: [.upperChest]).frame(width: 350)
        })
        XCTAssertGreaterThan(image.size.height, 200)
        let bytes = try XCTUnwrap(image.pngData())
        XCTAssertGreaterThan(bytes.count, 15000)
        try bytes.write(to: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("share-3d-qa.png"))
    }

    private func regions() throws -> [MuscleBodyRegion] {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MuscleBodyMapping", withExtension: "json"))
        return try JSONDecoder().decode([MuscleBodyRegion].self, from: Data(contentsOf: url))
    }

    func testBundledModelMatchesEveryTrainingRegion() throws {
        let mapping = try regions()
        let url = try XCTUnwrap(Bundle.main.url(forResource: "MuscleBody", withExtension: "scn"))
        let scene = try SCNScene(url: url)
        XCTAssertEqual(mapping.count, 37)
        XCTAssertEqual(mapping.filter(\.fatigueEligible).count, 32)
        XCTAssertEqual(Set(scene.rootNode.childNodes.compactMap(\.name)), Set(mapping.map(\.node)))
        let used = Set(mapping.flatMap(\.muscles))
        XCTAssertEqual(Set(MuscleGroup.allCases).subtracting(used), [.arms, .legs, .core, .back, .fullBody])
        XCTAssertEqual(scene.rootNode.childNodes.reduce(0) { $0 + ($1.geometry?.elements.first?.primitiveCount ?? 0) }, 773882)
    }

    func testMergedMuscleUsesStrongestMemberAndLandmarksStayNeutral() throws {
        let mapping = try regions()
        let map: [MuscleGroup: Double] = [.upperChest: 0.8, .lowerChest: 0.15, .quads: 0.45]
        for region in mapping where region.node.hasPrefix("chest_") {
            XCTAssertEqual(region.fatigue(in: map), 0.8)
            XCTAssertEqual(region.fatigue(in: [:]), 0)
        }
        let allFatigued = Dictionary(uniqueKeysWithValues: MuscleGroup.allCases.map { ($0, 1.0) })
        for region in mapping where !region.fatigueEligible {
            XCTAssertTrue(region.muscles.isEmpty)
            XCTAssertEqual(region.fatigue(in: allFatigued), 0)
        }
    }

    func testActualSetRecordsDriveNativeMuscleColorsAndDecay() throws {
        let exercise = Exercise(id: "test-chest", name: "Chest press", category: .strength,
                                tags: [], primaryMuscles: [.chest], muscleGroups: [.chest],
                                imageFolder: nil, instructions: [])
        func fatigue(age: TimeInterval) -> [MuscleGroup: Double] {
            let sets = (0..<5).map { i in
                SetRecord(id: "set-\(i)", exerciseId: exercise.id, exerciseName: exercise.name,
                          category: .strength, reps: 10, performedAt: Date().addingTimeInterval(-age))
            }
            return MuscleStatusCompute.muscleFatigueMap(sets: sets, exById: [exercise.id: exercise])
        }
        let chest = try XCTUnwrap(regions().first { $0.node == "chest_left" })
        let recent = chest.fatigue(in: fatigue(age: 60))
        let recovered = chest.fatigue(in: fatigue(age: 3 * 86400))
        XCTAssertGreaterThan(recent, 0.9)
        XCTAssertLessThan(recovered, 0.35)
        XCTAssertEqual(MasoColor.recoveryHeatStyle(fatigue: recent)?.1, 1.0)
        XCTAssertEqual(MasoColor.recoveryHeatStyle(fatigue: recovered)?.1, 0.3)
        XCTAssertNil(MasoColor.recoveryHeatStyle(fatigue: chest.fatigue(in: fatigue(age: 6 * 86400))))
        let legs = try XCTUnwrap(regions().first { $0.node == "quads_left" })
        XCTAssertEqual(legs.fatigue(in: fatigue(age: 60)), 0)
    }

    @MainActor
    func testRotationSurvivesFatigueUpdatesAndVerticalPanIsRejected() {
        final class Pan: UIPanGestureRecognizer {
            var speed = CGPoint.zero
            var delta = CGPoint.zero
            override func velocity(in view: UIView?) -> CGPoint { speed }
            override func translation(in view: UIView?) -> CGPoint { delta }
        }
        let view = SCNView()
        let coordinator = MuscleBody3DView.Coordinator()
        coordinator.view = view
        coordinator.load()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in view.scene != nil }, object: nil)
        wait(for: [ready], timeout: 10)
        let pan = Pan()
        pan.speed = CGPoint(x: 5, y: 100)
        XCTAssertFalse(coordinator.gestureRecognizerShouldBegin(pan))
        pan.speed = CGPoint(x: 100, y: 5)
        XCTAssertTrue(coordinator.gestureRecognizerShouldBegin(pan))
        pan.delta = CGPoint(x: 100, y: 0)
        coordinator.rotate(pan)
        let body = view.scene?.rootNode.childNodes.first { $0.childNode(withName: "chest_left", recursively: false) != nil }
        XCTAssertEqual(body?.eulerAngles.y ?? 0, 1.2, accuracy: 0.001)
        coordinator.fatigueMap = [.upperChest: 0.9]
        coordinator.updateColors()
        XCTAssertEqual(body?.eulerAngles.y ?? 0, 1.2, accuracy: 0.001)
        XCTAssertNotNil(body?.childNode(withName: "chest_left", recursively: false)?.geometry?.firstMaterial?.diffuse.contents)
        coordinator.setFacing(true)
        XCTAssertEqual(body?.simdTransform.columns.0.x ?? 0, -1, accuracy: 0.001)
        pan.delta = CGPoint(x: 30, y: 0)
        coordinator.rotate(pan)
        let rotated = body?.simdTransform
        coordinator.setFacing(true) // Re-rendering a selected segment must not reset a drag.
        XCTAssertEqual(body?.simdTransform, rotated)
        coordinator.setFacing(false)
        XCTAssertEqual(body?.simdTransform.columns.0.x ?? 0, 1, accuracy: 0.001)
        coordinator.active = false
    }

    @MainActor
    func testWalkthroughStopsOffscreenAndRestartsWithoutLosingFatigue() throws {
        let view = SCNView()
        let coordinator = MuscleBody3DView.Coordinator()
        coordinator.view = view
        coordinator.walkthrough = true
        coordinator.fatigueMap = [.chest: 0.9]
        coordinator.setAutoRotation(true)
        coordinator.load()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in view.scene != nil }, object: nil)
        wait(for: [ready], timeout: 10)
        let body = try XCTUnwrap(view.scene?.rootNode.childNodes.first {
            $0.childNode(withName: "chest_left", recursively: false) != nil
        })
        XCTAssertTrue(view.isPlaying)
        XCTAssertFalse(body.actionKeys.isEmpty)
        let visibleTransform = body.presentation.simdTransform
        coordinator.setAutoRotation(false)
        XCTAssertFalse(view.isPlaying)
        XCTAssertTrue(body.actionKeys.isEmpty)
        XCTAssertEqual(body.simdTransform, visibleTransform)
        coordinator.setAutoRotation(true)
        XCTAssertTrue(view.isPlaying)
        XCTAssertFalse(body.actionKeys.isEmpty)
        XCTAssertEqual(coordinator.fatigueMap[.chest], 0.9)
        coordinator.setAutoRotation(false)
        coordinator.active = false
    }

}

@MainActor
final class FullPageExportTests: XCTestCase {
    func testLongImageIncludesContentBeyondTheViewport() throws {
        let result = try FullPageExporter.export(content:
            VStack(spacing: 0) {
                Text("First workout").frame(height: 1000)
                Text("Last workout").frame(height: 1000)
            }
        )
        let image = try XCTUnwrap(result.items.first as? UIImage)
        XCTAssertEqual(image.size.height, 2000, accuracy: 1)
        XCTAssertEqual(image.size.width, 390, accuracy: 1)
    }

    func testLargeArchiveExportsEveryPageInsteadOfTruncating() throws {
        let result = try FullPageExporter.export(content:
            VStack(spacing: 0) {
                ForEach(0..<12) { index in
                    Text("Workout \(index + 1)").frame(height: 780)
                }
            }
        )
        let url = try XCTUnwrap(result.items.first as? URL)
        defer { try? FileManager.default.removeItem(at: url) }
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        XCTAssertEqual(pdf.pageCount, 12)
        XCTAssertEqual(pdf.page(at: 11)?.bounds(for: .mediaBox).height, 780)
    }
}

final class ExerciseFamilyTests: XCTestCase {
    func testEveryBundledExerciseHasConsistentStructuredName() {
        XCTAssertEqual(ExerciseLibrary.all.count, 938)
        for exercise in ExerciseLibrary.all {
            guard let parts = exercise.nameParts else {
                XCTFail("Missing name parts: \(exercise.id)"); continue
            }
            let detail = [parts.equipment, parts.variation].compactMap { $0 }.joined(separator: " · ")
            let expected = parts.base + (detail.isEmpty ? "" : " (\(detail))")
            XCTAssertEqual(exercise.name, expected, exercise.id)
        }
    }

    func testPushUpVariantsAndEquipmentShareOneFamily() {
        let groups = ExerciseGrouping.group(ExerciseLibrary.all)
        let pushUps = groups.filter { $0.baseName == "Push-Up" }
        let ids = Set(pushUps.flatMap { $0.all.map(\.id) })
        for id in ["push_up", "push_up_decline", "push_up_diamond", "push_up_pike", "push_up_typewriter", "push_up_resistance_band", "trx_push_up"] {
            XCTAssertTrue(ids.contains(id), id)
        }
        XCTAssertFalse(ids.contains("soleus_pushup"))
    }

    func testRestoredEquipmentVariantsKeepTheirOwnIdentity() {
        for id in ["bicep_curl_barbell", "bicep_curl_cable", "bicep_curl_dumbbell", "bicep_curl_machine"] {
            let exercise = ExerciseLibrary.all.first { $0.id == id }!
            XCTAssertEqual(ExerciseLibrary.byId[id]?.id, id)
            XCTAssertEqual(exercise.nameParts?.base, "Bicep Curl")
        }
        let group = ExerciseGrouping.group(ExerciseLibrary.all).first { $0.baseName == "Bicep Curl" }!
        XCTAssertTrue(group.all.contains { $0.id == "bicep_curl_barbell" })
        XCTAssertTrue(group.all.contains { $0.id == "bicep_curl_cable" })
    }
}

final class HomePerformanceTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func record(_ days: Int, weight: Double, reps: Int = 8) -> SetRecord {
        SetRecord(id: UUID().uuidString, exerciseId: "bench", exerciseName: "Bench", category: .strength,
                  weight: weight, reps: reps, duration: nil, performedAt: now.addingTimeInterval(Double(-days) * 86400), planId: nil)
    }
    private func metrics(_ records: [SetRecord]) -> [HomePerformanceMetric] {
        HomePerformanceMetric.build(sets: records, names: [:], sections: ["bench": [.chest]],
                                    calendar: Calendar(identifier: .gregorian), now: now, unit: .kg)
    }
    func testNoComparableDataAndFlatOrDecliningBenchmarksFallBackToLegend() {
        XCTAssertTrue(metrics([]).isEmpty)
        XCTAssertTrue(metrics([record(7, weight: 60)]).isEmpty)
        XCTAssertTrue(metrics([record(7, weight: 60), record(1, weight: 60)]).isEmpty)
        XCTAssertTrue(metrics([record(7, weight: 60), record(1, weight: 50)]).isEmpty)
    }
    func testWeightProgressUsesSameRepBenchmark() {
        let result = metrics([record(7, weight: 60), record(1, weight: 65)])
        XCTAssertEqual(result.map(\.id), ["overview", "lift-bench"])
        XCTAssertEqual(result.last?.delta, "+5 kg")
        XCTAssertTrue(metrics([record(7, weight: 60, reps: 8), record(1, weight: 65, reps: 3)]).isEmpty)
    }
    func testVolumeRequiresHistoricalBaseline() {
        let result = metrics([record(60, weight: 60), record(40, weight: 60), record(10, weight: 60), record(2, weight: 60)])
        XCTAssertTrue(result.contains { $0.id == "consistency" && $0.delta == "+1" })
        XCTAssertTrue(result.contains { $0.id == "volume-chest" && $0.delta == "+1 " + NSLocalizedString("sets", comment: "") })
    }
}

final class MuscleRecoveryTimelineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 2_000_000)
    private var exercise: Exercise {
        Exercise(id: "chest", name: "Bench Press", category: .strength, tags: [], primaryMuscles: [.chest], muscleGroups: [.chest], imageFolder: nil, instructions: [])
    }
    private func record(_ date: Date) -> SetRecord {
        .init(id: UUID().uuidString, exerciseId: exercise.id, exerciseName: exercise.name,
              category: .strength, weight: 20, reps: 10, duration: nil, performedAt: date, planId: nil)
    }
    func testNoHistoryDoesNotInventPercentage() {
        XCTAssertTrue(MuscleStatusCompute.recoveryTimeline(muscles: [.chest], sets: [], exById: [exercise.id: exercise], now: now).isEmpty)
    }
    func testCurrentPointMatchesModelAndFutureRecordsAreExcluded() throws {
        let sets = [record(now.addingTimeInterval(-3600)), record(now.addingTimeInterval(86400))]
        let points = MuscleStatusCompute.recoveryTimeline(muscles: [.chest], sets: sets, exById: [exercise.id: exercise], now: now)
        let current = try XCTUnwrap(points.last)
        let fatigue = MuscleStatusCompute.muscleFatigueMap(sets: sets, exById: [exercise.id: exercise], now: now)[.upperChest] ?? 0
        XCTAssertEqual(current.date, now)
        XCTAssertEqual(current.recovered, 1 - fatigue, accuracy: 0.000001)
        XCTAssertTrue(points.allSatisfy { $0.date <= now && (0...1).contains($0.recovered) })
    }
    func testRecoveryDropsAtWorkoutAndThenRises() throws {
        let date = now.addingTimeInterval(-86400)
        let points = MuscleStatusCompute.recoveryTimeline(muscles: [.upperChest], sets: [record(date)], exById: [exercise.id: exercise], now: now)
        let before = try XCTUnwrap(points.first { $0.date == date.addingTimeInterval(-1) })
        let after = try XCTUnwrap(points.first { $0.date == date })
        XCTAssertGreaterThan(before.recovered, after.recovered)
        XCTAssertGreaterThan(try XCTUnwrap(points.last).recovered, after.recovered)
    }
    func testUnrelatedMuscleDoesNotReceiveChestHistory() {
        XCTAssertTrue(MuscleStatusCompute.recoveryTimeline(muscles: [.quads], sets: [record(now)], exById: [exercise.id: exercise], now: now).isEmpty)
    }
}

private struct MuscleBackNavigationFixture: View {
    @State private var path = [String]()
    var body: some View {
        AppNavigationStack(path: $path) {
            Color.black.navigationTitle("My Muscle Status")
                .navigationDestination(for: String.self) { _ in
                    MuscleInfoScreen(muscle: .obliques, relatedMuscles: [.obliques], regionNode: "obliques_left", showsBack: false)
                }
        }.task { path = ["muscle"] }
    }
}

private final class MuscleHandoffTestState: ObservableObject {
    @Published var path = [Int]()
}

private final class RecoveryListTestState: ObservableObject {
    @Published var path = [String]()
    var selected: MuscleSelection?
    var starts = 0
}

private struct RecoveryListTestFixture: View {
    @Environment(DataStore.self) private var data
    @ObservedObject var state: RecoveryListTestState
    var body: some View {
        AppNavigationStack(path: $state.path) {
            MuscleMapDetailScreen(fatigueMap: MuscleStatusCompute.muscleFatigueMap(sets: data.sets, exById: data.exById),
                gapMuscles: data.sets.isEmpty ? [] : [.quads], onStartGapWorkout: { state.starts += 1 })
                .navigationTitle("My Muscle Status").navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: String.self) { _ in
                    MuscleRecoveryListScreen(gapMuscles: data.sets.isEmpty ? [] : [.quads], onStartGapWorkout: {
                        state.path = []; state.starts += 1
                    }, onSelect: { state.selected = $0; state.path = [] })
                }
        }
    }
}
private struct MuscleHandoffNavigationFixture: View {
    @ObservedObject var state: MuscleHandoffTestState
    var body: some View {
        NavigationStack(path: $state.path) {
            VStack {
                MuscleBody3DView(fatigueMap: [:], autoRotates: true, walkthrough: true, navigationRole: .home)
                    .frame(height: 432).opacity(0.62)
                Spacer()
            }.background(MasoColor.background).navigationTitle("Masso")
                .navigationDestination(for: Int.self) { destination in
                    if destination == 1 {
                        MuscleMapDetailScreen(fatigueMap: [:], gapMuscles: [], onStartGapWorkout: {})
                            .navigationTitle("My Muscle Status").navigationBarTitleDisplayMode(.inline)
                    } else {
                        MuscleInfoScreen(muscle: .obliques, relatedMuscles: [.obliques], regionNode: "obliques_left", showsBack: false)
                    }
                }
        }
    }
}

@MainActor
final class RecordedWorkoutShareTests: XCTestCase {
    func testShareSnapshotIncludesOnlySelectedSessionActualSets() throws {
        let oldLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        defer { LanguageManager.shared.selectedLanguage = oldLanguage }
        let (data, session) = try fixture()
        let snapshot = RecordedWorkoutShareSnapshot(data: data, session: session)
        XCTAssertEqual(snapshot.records.map(\.id), ["selected-1", "selected-2"])
        XCTAssertEqual(snapshot.volumeKg, 376, accuracy: 0.01)
        XCTAssertEqual(snapshot.detail.count, 1)
        XCTAssertEqual(snapshot.detail.first?.sets.compactMap(\.weight), [20, 22])
        XCTAssertEqual(snapshot.detail.first?.sets.compactMap(\.reps), [10, 8])
        let image = try XCTUnwrap(ShareImageRenderer.render {
            RecordedWorkoutShareCard(session: session).environment(data)
        })
        XCTAssertGreaterThan(image.size.height, 350)
        let attachment = XCTAttachment(image: image); attachment.name = "Selected workout history export"; attachment.lifetime = .keepAlways; add(attachment)
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recorded-workout-share-export.png"))
    }
    func testHistorySharePreviewUsesNativeTogglesAndNoWeeklySections() async throws {
        let oldLanguage = LanguageManager.shared.selectedLanguage
        LanguageManager.shared.selectedLanguage = .en
        defer { LanguageManager.shared.selectedLanguage = oldLanguage }
        let (data, session) = try fixture()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.rootViewController = UIHostingController(rootView:
            ShareCustomizeSheet(previewTitle: "Share Workout", sheetTitle: "Share Workout",
                defaultSections: ShareSections(workout: true), initialPhoto: nil) { photo, onTap, mode in
                let editing: Bool = { if case .editing = mode { return true }; return false }()
                RecordedWorkoutShareCard(session: session, userPhoto: photo, onTapAddPhoto: editing ? onTap : nil)
            }.environment(data).environment(\.locale, Locale(identifier: "en"))
                .environment(\.layoutDirection, .leftToRight).preferredColorScheme(.dark))
        window.makeKeyAndVisible()
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        try await Task.sleep(for: .milliseconds(700))
        func switches(_ view: UIView) -> [UISwitch] { (view as? UISwitch).map { [$0] } ?? view.subviews.flatMap(switches) }
        let controls = switches(window)
        XCTAssertEqual(controls.count, 4, "Photo, trained muscles, this workout summary, and actual exercises only")
        let toggle = try XCTUnwrap(controls.first)
        let center = toggle.convert(CGPoint(x: toggle.bounds.midX, y: toggle.bounds.midY), to: window)
        let hit = try XCTUnwrap(window.hitTest(center, with: nil))
        XCTAssertTrue(hit === toggle || hit.isDescendant(of: toggle))
        toggle.setOn(false, animated: false); toggle.sendActions(for: .valueChanged)
        try await Task.sleep(for: .milliseconds(150))
        XCTAssertFalse(toggle.isOn)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in window.drawHierarchy(in: window.bounds, afterScreenUpdates: true) }
        try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("recorded-workout-share-preview.png"))
    }
    private func fixture() throws -> (DataStore, SessionSummary) {
        let data = DataStore.makeMock()
        let exercise = try XCTUnwrap(data.exById["bench_press_dumbbell"])
        let day = data.settings.calendar.startOfDay(for: Date().addingTimeInterval(-86400))
        let first = day.addingTimeInterval(3600), last = day.addingTimeInterval(4200)
        data.sets = [
            SetRecord(id: "selected-1", exerciseId: exercise.id, exerciseName: exercise.name, category: .strength, weight: 20, reps: 10, performedAt: first, planId: "selected"),
            SetRecord(id: "selected-2", exerciseId: exercise.id, exerciseName: exercise.name, category: .strength, weight: 22, reps: 8, performedAt: last, planId: "selected"),
            SetRecord(id: "other-workout", exerciseId: exercise.id, exerciseName: exercise.name, category: .strength, weight: 100, reps: 30, performedAt: last, planId: "other"),
            SetRecord(id: "other-day", exerciseId: exercise.id, exerciseName: exercise.name, category: .strength, weight: 100, reps: 30, performedAt: first.addingTimeInterval(-86400), planId: "selected")
        ]
        let session = SessionSummary(id: "selected-session", planId: "selected", day: day, planName: "Upper Body",
            exerciseCount: 1, setCount: 2, muscles: [.chest], categories: [.strength], firstPerformedAt: first, lastPerformedAt: last)
        return (data, session)
    }
}

@MainActor
final class SplashBrandCopyTests: XCTestCase {
    func testOnlySplashOmitsTerminalPeriodAcrossAllLanguages() {
        let old = LanguageManager.shared.selectedLanguage
        defer { LanguageManager.shared.selectedLanguage = old }
        for language in SupportedLanguage.allCases {
            LanguageManager.shared.selectedLanguage = language
            XCTAssertFalse(MasoBrand.splashSlogan.isEmpty)
            XCTAssertFalse(MasoBrand.splashSlogan.hasSuffix("."), language.rawValue)
            XCTAssertFalse(MasoBrand.splashSlogan.hasSuffix("。"), language.rawValue)
            if language == .en {
                XCTAssertEqual(MasoBrand.splashSlogan, "Train smart, your way")
                XCTAssertEqual(NSLocalizedString("Train smart, your way.", comment: ""), "Train smart, your way.")
            }
            if language == .zhHans { XCTAssertEqual(MasoBrand.splashSlogan, "聪明训练，适合自己") }
        }
    }
}

@MainActor
final class ApprovedSplashMotionTests: XCTestCase {
    func testBundledExportAndMilestonesMatchApprovedF() throws {
        let url = try XCTUnwrap(Bundle.main.url(forResource: "SplashMotion", withExtension: "json"))
        let source = try JSONDecoder().decode(SplashMotionConfiguration.self, from: Data(contentsOf: url))
        XCTAssertEqual(source.preset, "F")
        let c = SplashMotionConfiguration.approved
        XCTAssertEqual(c.motion.tagSize, 16)
        XCTAssertEqual(c.motion.logoGap, 56)
        XCTAssertEqual(c.motion.verticalOffset, -40)
        XCTAssertEqual(c.motion.response, 0.45)
        XCTAssertEqual(c.motion.damping, 0.92)
        XCTAssertEqual(c.duration(reducedMotion: false), 1.77, accuracy: 0.000001)
        XCTAssertEqual(c.exitStart, 1.55)
        for index in 0..<5 {
            XCTAssertEqual(c.layer(index, at: 0, reducedMotion: false).opacity, 0)
            XCTAssertEqual(c.layer(index, at: 0, reducedMotion: false).x, -18)
            XCTAssertEqual(c.layer(index, at: 1.2, reducedMotion: false).opacity, MasoBrandLogo.defaultOpacities[index])
            XCTAssertLessThan(abs(c.layer(index, at: 1.2, reducedMotion: false).x), 0.001)
            XCTAssertEqual(c.layer(index, at: 0.1, reducedMotion: true).x, 0)
        }
        XCTAssertGreaterThan(c.layer(2, at: 0.05, reducedMotion: false).opacity, c.layer(4, at: 0.05, reducedMotion: false).opacity)
        XCTAssertEqual(c.wordOpacity(at: 0.22, reducedMotion: false), 0)
        XCTAssertEqual(c.wordOpacity(at: 0.54, reducedMotion: false), 1)
        XCTAssertEqual(c.tag(at: 0.62, reducedMotion: false).y, 6)
        XCTAssertEqual(c.tag(at: 0.8, reducedMotion: false).opacity, 1)
        XCTAssertEqual(c.exit(at: 1.55, reducedMotion: false), 0)
        XCTAssertEqual(c.exit(at: 1.77, reducedMotion: false), 1, accuracy: 0.000001)
        XCTAssertEqual(c.duration(reducedMotion: true), 0.53)
        XCTAssertEqual(c.tag(at: 0.1, reducedMotion: true).y, 0)
    }

    func testNativeApprovedFramesAcrossLanguagesAndLargeText() throws {
        let oldLanguage = LanguageManager.shared.selectedLanguage
        defer { LanguageManager.shared.selectedLanguage = oldLanguage }
        for language in [SupportedLanguage.en, .zhHans, .fr, .ar] {
            LanguageManager.shared.selectedLanguage = language
            let image = try XCTUnwrap(ShareImageRenderer.render(width: 390) {
                SplashMotionFrame(time: 1.2)
                    .frame(width: 390, height: 844)
                    .environment(\.locale, Locale(identifier: language.rawValue))
                    .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
            })
            XCTAssertEqual(image.size.height, 844, accuracy: 1)
            let attachment = XCTAttachment(image: image); attachment.name = "Approved splash F \(language.rawValue)"; attachment.lifetime = .keepAlways; add(attachment)
            try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("approved-splash-\(language.rawValue).png"))
        }
        LanguageManager.shared.selectedLanguage = .fr
        let large = try XCTUnwrap(ShareImageRenderer.render(width: 375) {
            SplashMotionFrame(time: 0.3, reducedMotion: true).frame(width: 375, height: 667)
                .environment(\.dynamicTypeSize, .accessibility3)
        })
        try large.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("approved-splash-large-text.png"))
    }

    func testCompletionOrderReducedMotionAndCancellation() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        for reduce in [false, true] {
            var events: [String] = []
            var exitDate: Date?
            var exitDuration: TimeInterval = 0
            window.rootViewController = UIHostingController(rootView: SplashScreen(reducedMotionOverride: reduce, onPrepare: {
                events.append("prepare")
                if !reduce { Thread.sleep(forTimeInterval: 0.6) } // Simulate a slow home mount.
            }, onExit: { events.append("exit"); exitDate = Date() }) {
                events.append("done")
                exitDuration = exitDate.map { Date().timeIntervalSince($0) } ?? 0
            }
                .environment(\.scenePhase, .active))
            window.makeKeyAndVisible()
            for _ in 0..<35 {
                if events.last == "done" { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            XCTAssertEqual(events, ["prepare", "exit", "done"])
            XCTAssertGreaterThanOrEqual(exitDuration, reduce ? 0.16 : 0.20)
        }
        var cancelledEvents = 0
        window.rootViewController = UIHostingController(rootView: SplashScreen(onExit: { cancelledEvents += 1 }) { cancelledEvents += 1 }
            .environment(\.scenePhase, .active))
        try await Task.sleep(for: .milliseconds(100))
        window.rootViewController = UIHostingController(rootView: Color.black)
        try await Task.sleep(for: .seconds(1.9))
        XCTAssertEqual(cancelledEvents, 0)
    }
}
