import Foundation
import Network

enum ExerciseTutorialDestination: Equatable, Sendable {
    case youtube(String)
    case bilibili(String)
    case search(URL)

    var playerID: String? {
        switch self {
        case .youtube(let id): return id
        case .bilibili(let id): return "bili:" + id
        case .search: return nil
        }
    }
    var url: URL {
        switch self {
        case .youtube(let id): return URL(string: "https://www.youtube.com/watch?v=" + id)!
        case .bilibili(let id): return URL(string: "https://www.bilibili.com/video/" + id + "/")!
        case .search(let url): return url
        }
    }
    var label: String {
        switch self {
        case .youtube: return "Watch on YouTube"
        case .bilibili: return "Watch on bilibili"
        case .search: return "Search on bilibili"
        }
    }
}

/// Route using this device's network, never the language, GPS, IP geolocation or
/// VPN heuristics. Search only sends the public catalog action name, not user data.
@MainActor
final class ExerciseTutorialService {
    static let shared = ExerciseTutorialService()
    private let session: URLSession
    private var youtubeResult: (available: Bool, expires: Date)?
    private var probeTask: Task<Bool, Never>?
    private var searchCache: [String: (destination: ExerciseTutorialDestination, expires: Date)] = [:]
    private let pathMonitor: NWPathMonitor?

    init(session: URLSession = .shared, monitorNetwork: Bool = true) {
        self.session = session
        pathMonitor = monitorNetwork ? NWPathMonitor() : nil
        pathMonitor?.pathUpdateHandler = { [weak self] _ in
            Task { @MainActor in self?.youtubeResult = nil }
        }
        pathMonitor?.start(queue: DispatchQueue(label: "com.yumowu.maso.tutorial-network"))
    }
    deinit { pathMonitor?.cancel() }

    func resolve(_ exercise: Exercise, forceProbe: Bool = false) async -> ExerciseTutorialDestination {
        if let id = ExerciseMediaPolicy.youtubeID(exercise.videoURL),
           await youtubeAvailable(force: forceProbe) { return .youtube(id) }
        return await bilibili(for: exercise)
    }

    func youtubeAvailable(force: Bool = false) async -> Bool {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MASO_EXERCISE_UI_TEST_SCENE"] != nil,
           ProcessInfo.processInfo.environment["MASO_TEST_YOUTUBE_BLOCKED"] == "1" { return false }
        #endif
        if !force, let result = youtubeResult, result.expires > Date() { return result.available }
        if let probeTask { return await probeTask.value }
        let session = session
        let task = Task<Bool, Never> {
            var request = URLRequest(url: URL(string: "https://www.youtube.com/iframe_api")!)
            request.timeoutInterval = 3
            request.cachePolicy = .reloadIgnoringLocalCacheData
            do {
                let (data, response) = try await session.data(for: request)
                // A captive portal/HTML block page returning 200 is not YouTube.
                let text = String(decoding: data, as: UTF8.self)
                return (response as? HTTPURLResponse)?.statusCode == 200 &&
                    response.url?.host == "www.youtube.com" &&
                    (text.contains("YT") || text.contains("www-widgetapi")) && !text.lowercased().contains("<html")
            } catch { return false }
        }
        probeTask = task
        let available = await task.value
        probeTask = nil
        youtubeResult = (available, Date().addingTimeInterval(available ? 120 : 30))
        return available
    }

    func bilibili(for exercise: Exercise) async -> ExerciseTutorialDestination {
        if let cached = searchCache[exercise.id], cached.expires > Date() { return cached.destination }
        if let id = Self.reviewed[exercise.id] { return .bilibili(id) }
        let query = Self.query(for: exercise)
        var components = URLComponents(string: "https://api.bilibili.com/x/web-interface/search/type")!
        components.queryItems = [.init(name: "search_type", value: "video"), .init(name: "keyword", value: query + " 教学")]
        var request = URLRequest(url: components.url!)
        request.timeoutInterval = 5
        request.setValue("https://search.bilibili.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 Masso/3.0", forHTTPHeaderField: "User-Agent")
        if let (data, response) = try? await session.data(for: request),
           (response as? HTTPURLResponse)?.statusCode == 200,
           let root = try? JSONDecoder().decode(SearchResponse.self, from: data), root.code == 0 {
            for item in root.data?.result ?? [] where Self.matches(title: item.title, exercise: exercise) {
                guard Self.validBVID(item.bvid) else { continue }
                let result = ExerciseTutorialDestination.bilibili(item.bvid)
                searchCache[exercise.id] = (result, Date().addingTimeInterval(600))
                return result
            }
        }
        // Fail closed: unsupported/blocked search or an ambiguous variant must
        // not silently play a different action. Keep an honest search entry.
        var search = URLComponents(string: "https://search.bilibili.com/video")!
        search.queryItems = [.init(name: "keyword", value: query + " 教学")]
        let result = ExerciseTutorialDestination.search(search.url!)
        searchCache[exercise.id] = (result, Date().addingTimeInterval(30))
        return result
    }

    static func query(for exercise: Exercise) -> String {
        let name = exercise.localizedName?["zh-Hans"] ?? exercise.name
        return name.replacingOccurrences(of: "（", with: " ").replacingOccurrences(of: "）", with: "")
            .replacingOccurrences(of: "(", with: " ").replacingOccurrences(of: ")", with: "")
            .replacingOccurrences(of: "·", with: " ")
    }
    static func validBVID(_ id: String) -> Bool {
        id.count == 12 && id.hasPrefix("BV") && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }
    static func normalized(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .lowercased().filter { $0.isLetter || $0.isNumber }
    }
    static func matches(title: String, exercise: Exercise) -> Bool {
        let name = exercise.localizedName?["zh-Hans"] ?? exercise.name
        let parts = name.components(separatedBy: CharacterSet(charactersIn: "（）()·"))
            .map { normalized($0) }.filter { !$0.isEmpty }
        let title = normalized(title)
        guard !parts.isEmpty, parts.allSatisfy({ title.contains($0) }) else { return false }
        // Reject neighboring variants and compilations, even when all base words match.
        let query = normalized(name)
        let variants = ["上斜", "下斜", "单臂", "单腿", "反手", "窄握", "宽握", "跪姿", "坐姿", "站姿", "史密斯", "绳把", "直杆", "弹力带", "壶铃", "哑铃", "杠铃", "器械", "徒手", "合集", "全套", "跟练", "个动作", "种动作"]
        return !variants.contains { title.contains($0) && !query.contains($0) }
    }
    private struct SearchResponse: Decodable {
        let code: Int
        let data: Results?
        struct Results: Decodable { let result: [Item]? }
        struct Item: Decodable { let bvid: String; let title: String }
    }

    // Exact IDs only, never family-level substitutions. Source pages and dates
    // are preserved in docs/bilibili-tutorial-fallback-2026-10-28.
    static let reviewed: [String: String] = [
        "bench_press_barbell": "BV1GJmpYLE8A",
        "bench_press_dumbbell": "BV1mD421J7o3",
        "incline_bench_press_dumbbell": "BV1aa4y1o7XA",
        "incline_bench_press_barbell": "BV1u1421D7jk",
        "squat_barbell": "BV1Ma4y1u75E",
        "push_up": "BV1dt41187ih",
        "lat_pulldown": "BV1usAJeuEQa",
        "lateral_raise_dumbbell": "BV11U4y1r7Bh",
        "leg_curl_seated": "BV17zZvYjEYP",
        "plank": "BV1mD4y1d7NF",
        "face_pull": "BV1wZ421e7K2",
        "rdl_dumbbell": "BV1u84y1q795"
    ]
}
