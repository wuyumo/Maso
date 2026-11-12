import SwiftUI
import UIKit
import XCTest
@testable import Maso

@MainActor
final class HomeHeaderBlurTests: XCTestCase {
    private final class Route: ObservableObject { @Published var path: [Int] = [] }
    private struct Detail: View {
        var body: some View {
            ScrollView { Text("Other page").frame(height: 1500) }
                .navigationTitle("Detail").navigationBarTitleDisplayMode(.inline)
        }
    }
    private struct Fixture: View {
        @ObservedObject var route: Route
        var body: some View {
            AppNavigationStack(path: $route.path) {
                ScrollView {
                    VStack {
                        ForEach(0..<40) { index in
                            Text("Content \(index)").frame(maxWidth: .infinity).padding()
                        }
                    }
                }
                .background(Color.green.opacity(0.2))
                .navigationTitle("Home")
                .navigationBarTitleDisplayMode(.inline)
                .navigationDestination(for: Int.self) { _ in
                    Detail()
                }
            }
        }
    }

    private struct PresentedSheet: View {
        let page: AnyView
        var medium = false
        @State private var presented = false
        var body: some View {
            AppNavigationStack { Text("Home").navigationTitle("Home") }
                .sheet(isPresented: $presented) {
                    page.presentationDetents(medium ? [.medium, .large] : [.large])
                        .presentationDragIndicator(.visible)
                }
                .task { presented = true }
        }
    }

    func testNativeSoftEdgeSurvivesScrollPushAndReturn() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native soft edges require iOS 26") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; previous?.makeKeyAndVisible() }
        let route = Route()
        let host = UIHostingController(rootView: Fixture(route: route).preferredColorScheme(.dark))
        window.rootViewController = host
        window.makeKeyAndVisible()
        try await Task.sleep(for: .milliseconds(400))
        let navigation = try XCTUnwrap(navigationController(in: host))
        let home = try XCTUnwrap(verticalScroll(in: try XCTUnwrap(navigation.topViewController).view))
        XCTAssertEqual(home.topEdgeEffect.style, .soft)
        XCTAssertFalse(home.topEdgeEffect.isHidden)
        XCTAssertFalse(navigation.isNavigationBarHidden)
        home.setContentOffset(CGPoint(x: 0, y: 240), animated: true)
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertGreaterThan(home.contentOffset.y, 200)
        XCTAssertEqual(home.topEdgeEffect.style, .soft)

        route.path = [1]
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(navigation.viewControllers.count, 2)
        let detail = try XCTUnwrap(verticalScroll(in: try XCTUnwrap(navigation.topViewController).view))
        XCTAssertFalse(detail === home)
        XCTAssertEqual(detail.topEdgeEffect.style, .soft, "Pushed pages inherit the shared header without a local modifier")
        XCTAssertFalse(detail.topEdgeEffect.isHidden)
        XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true)
        route.path = []
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(navigation.viewControllers.count, 1)
        let restored = try XCTUnwrap(verticalScroll(in: try XCTUnwrap(navigation.topViewController).view))
        XCTAssertEqual(restored.topEdgeEffect.style, .soft)
        XCTAssertFalse(restored.topEdgeEffect.isHidden)
    }

    func testSharedHeaderInActualAppDestinationsAndLanguages() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native soft edges require iOS 26") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let oldLanguage = LanguageManager.shared.selectedLanguage
        let window = UIWindow(windowScene: scene)
        defer {
            AppRouter.shared.requestedDestination = nil
            LanguageManager.shared.selectedLanguage = oldLanguage
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        let pages: [(String, AppDestination)] = [
            ("home", .today), ("settings", .settings), ("workout", .history),
            ("insights", .insights), ("diet", .diet), ("sleep", .sleep),
            ("exercises", .exerciseLibrary), ("classics", .classicRoutines),
            ("coach", .coach), ("muscles", .muscleStatus),
            ("muscle-exercises", .muscleInfo(.init(muscle: .obliques, relatedMuscles: [.obliques], regionNode: "obliques_left", showsBack: false)))
        ]
        for language in [SupportedLanguage.en, .zhHans, .de, .ar] {
            LanguageManager.shared.selectedLanguage = language
            let data = DataStore.makeMock()
            data.aiTodayPlanEditedAt = Date()
            let host = UIHostingController(rootView: RootView()
                .environment(data).environment(TrainingSessionStore()).environment(SubscriptionManager())
                .environment(\.locale, Locale(identifier: language.rawValue))
                .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                .preferredColorScheme(.dark))
            window.rootViewController = host
            window.makeKeyAndVisible()
            try await Task.sleep(for: .milliseconds(450))
            for (name, destination) in pages where language == .en || ["settings", "exercises"].contains(name) {
                AppRouter.shared.requestedDestination = destination
                try await Task.sleep(for: .milliseconds(650))
                window.layoutIfNeeded()
                let navigation = try XCTUnwrap(navigationController(in: host))
                XCTAssertFalse(navigation.isNavigationBarHidden, name)
                if destination != .today {
                    XCTAssertTrue(navigation.interactivePopGestureRecognizer?.isEnabled == true, name)
                }
                let page = try XCTUnwrap(navigation.topViewController).view!
                let scrolls = scrollViews(in: page).filter {
                    // The composer's UIKit text editor scrolls independently;
                    // it is not a page edge beneath the navigation bar.
                    !($0 is UITextView) && $0.bounds.width > window.bounds.width * 0.8
                        && $0.contentSize.width <= $0.bounds.width + 1
                }
                for scroll in scrolls {
                    XCTAssertEqual(scroll.topEdgeEffect.style, .soft, "\(language.rawValue) \(name)")
                    XCTAssertFalse(scroll.topEdgeEffect.isHidden, name)
                }
                for position in ["top", "scrolled"] {
                    if position == "scrolled", let scroll = scrolls.max(by: { $0.bounds.height < $1.bounds.height }) {
                        let maximum = max(-scroll.adjustedContentInset.top,
                                          scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        scroll.setContentOffset(CGPoint(x: 0, y: min(220, maximum)), animated: false)
                        try await Task.sleep(for: .milliseconds(120))
                    }
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let name = "shared-header-\(language.rawValue)-\(name)-\(position)"
                    let attachment = XCTAttachment(image: image)
                    attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
                    try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(name + ".png"))
                }
            }
        }
    }

    func testNativeSoftHeadersInPresentedSheets() async throws {
        guard #available(iOS 26.0, *) else { throw XCTSkip("Native soft edges require iOS 26") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let oldLanguage = LanguageManager.shared.selectedLanguage
        let window = UIWindow(windowScene: scene)
        defer {
            LanguageManager.shared.selectedLanguage = oldLanguage
            window.isHidden = true
            previous?.makeKeyAndVisible()
        }
        for language in [SupportedLanguage.en, .de, .ar] {
            LanguageManager.shared.selectedLanguage = language
            let data = DataStore.makeMock()
            let exercise = try XCTUnwrap(data.exById["bench_press_barbell"])
            let plan = try XCTUnwrap(data.plans.first)
            let pages: [(String, AnyView, Bool)] = [
                ("training", AnyView(TrainingPreferencesSheet(onConfirm: {})), false),
                ("diet", AnyView(DietPreferencesSheet(initial: DietPreferences(), settings: data.settings, save: { _ in })), false),
                ("sleep", AnyView(SleepScheduleSheet(initial: SleepPreferences(), save: { _ in })), false),
                ("language", AnyView(LanguagePickerSheet(manager: .shared)), false),
                ("workout", AnyView(PlanDetailSheet(initialPlan: plan, onStart: { _ in })), false),
                ("exercise", AnyView(ExerciseDetailSheet(exercise: exercise)), false),
                ("parameters", AnyView(EditCurrentStepSheet(exercise: exercise, initialSets: 3,
                    initialReps: 8, initialWeight: 40, initialDuration: nil, onSave: { _, _, _, _, _, _ in })), true),
                ("day", AnyView(DailyRecordSheet(day: Date(), onReplay: { _ in })), false)
            ]
            for (name, page, medium) in pages where language == .en || ["training", "diet", "sleep"].contains(name) {
                let host = UIHostingController(rootView: PresentedSheet(page: page, medium: medium)
                    .environment(data).environment(TrainingSessionStore()).environment(SubscriptionManager())
                    .environment(\.locale, Locale(identifier: language.rawValue))
                    .environment(\.layoutDirection, language == .ar ? .rightToLeft : .leftToRight)
                    .preferredColorScheme(.dark))
                window.rootViewController = host
                window.makeKeyAndVisible()
                try await Task.sleep(for: .milliseconds(650))
                let sheet = try XCTUnwrap(host.presentedViewController, name)
                let navigation = try XCTUnwrap(navigationController(in: sheet), name)
                XCTAssertFalse(navigation.isNavigationBarHidden, name)
                let scrolls = scrollViews(in: try XCTUnwrap(navigation.topViewController).view).filter {
                    !($0 is UITextView) && $0.bounds.width > window.bounds.width * 0.8
                        && $0.contentSize.width <= $0.bounds.width + 1
                }
                XCTAssertFalse(scrolls.isEmpty, name)
                for scroll in scrolls {
                    XCTAssertEqual(scroll.topEdgeEffect.style, .soft, "\(language.rawValue) \(name)")
                    XCTAssertEqual(scroll.topEdgeEffect.isHidden, name == "exercise", name)
                }
                if medium { XCTAssertLessThan(sheet.view.bounds.height, window.bounds.height * 0.85) }
                for position in ["top", "scrolled"] {
                    if position == "scrolled", let scroll = scrolls.max(by: { $0.bounds.height < $1.bounds.height }) {
                        let maximum = max(-scroll.adjustedContentInset.top,
                                          scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)
                        scroll.setContentOffset(CGPoint(x: 0, y: min(220, maximum)), animated: false)
                        try await Task.sleep(for: .milliseconds(100))
                    }
                    let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                        window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                    }
                    let filename = "sheet-header-\(language.rawValue)-\(name)-\(position)"
                    let attachment = XCTAttachment(image: image)
                    attachment.name = filename; attachment.lifetime = .keepAlways; add(attachment)
                    try image.pngData()?.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename + ".png"))
                }
                host.dismiss(animated: false)
                window.isHidden = true
            }
        }
    }

    private func scrollViews(in view: UIView) -> [UIScrollView] {
        (view as? UIScrollView).map { [$0] } ?? []
            + view.subviews.flatMap { scrollViews(in: $0) }
    }

    private func navigationController(in controller: UIViewController) -> UINavigationController? {
        if let value = controller as? UINavigationController { return value }
        return controller.children.lazy.compactMap { self.navigationController(in: $0) }.first
    }
    private func verticalScroll(in view: UIView) -> UIScrollView? {
        if let value = view as? UIScrollView, value.contentSize.height > value.bounds.height { return value }
        return view.subviews.lazy.compactMap { self.verticalScroll(in: $0) }.first
    }
}
