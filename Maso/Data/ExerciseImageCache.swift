import UIKit
import Foundation

// 训练动图 (frame 0 / 1) + Pexels 单图 的共享 UIImage cache.
//
// 为什么不用 AsyncImage:
//   - AsyncImage 加载是 view-local 的, 同一张图在 list / player / minibar 出现就下载多次
//   - 两帧 cross-fade 时, frame 0 和 frame 1 是两个独立 AsyncImage, 加载时机不同步
//     → 切换那一刻可能出现 "frame 1 还没 ready, opacity 已经在动" 的空隙 → 闪
//
// 性能合约 (#images-slow 修复):
//   1. **磁盘缓存**: 专用 URLSession + 512MB URLCache — jsdelivr 带 immutable/长 max-age,
//      第二次启动直接读盘, 不再全量重下 (之前 NSCache 纯内存, 杀 app 即失).
//   2. **多 CDN 故障切换**: cdn → fastly → gcore.jsdelivr.net 逐个试, 成功的主机记住
//      (UserDefaults 跨启动), 后续请求直接走它 — 大陆 cdn.jsdelivr.net 抽风时自动落到可用镜像.
//   3. **准确内存计费**: NSCache cost 用解码后字节 (w×h×4) 而不是下载字节 (差 ~25×),
//      128MB 上限真实可控, 不再频繁驱逐 → 列表回滚不重新下载.
@MainActor
final class ExerciseImageCache {
    static let shared = ExerciseImageCache()

    private let cache: NSCache<NSString, UIImage>

    /// 专用 session — 大 URLCache (32MB 内存 / 512MB 磁盘) 持久化图片字节.
    /// jsdelivr 响应自带长缓存头, URLCache 按标准 HTTP 语义存取, 不需要自己管过期.
    nonisolated private static let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.urlCache = URLCache(
            memoryCapacity: 32 * 1024 * 1024,
            diskCapacity: 512 * 1024 * 1024,
            diskPath: "exercise-images"
        )
        cfg.requestCachePolicy = .useProtocolCachePolicy
        cfg.timeoutIntervalForRequest = 12
        return URLSession(configuration: cfg)
    }()

    /// jsdelivr 镜像列表 — 按序故障切换. gcore/fastly 在大陆通常比主域稳.
    nonisolated private static let cdnHosts = ["cdn.jsdelivr.net", "fastly.jsdelivr.net", "gcore.jsdelivr.net"]
    /// 验证过可用的主机下标 — 后续请求优先走它 (UserDefaults 跨启动记忆).
    private static var preferredHostIndex: Int {
        get { UserDefaults.standard.integer(forKey: "maso.imageCDNHostIndex") }
        set { UserDefaults.standard.set(newValue, forKey: "maso.imageCDNHostIndex") }
    }

    init() {
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = 1000
        cache.totalCostLimit = 128 * 1024 * 1024  // 按解码后字节计费 (见 decodedCost)
    }

    /// 同步查 cache — 命中返回, 没命中 nil. UI 启动时先调这个, 命中直接显示.
    func cached(folder: String, frame: Int) -> UIImage? {
        cache.object(forKey: "\(folder)/\(frame)" as NSString)
    }

    /// 同步查 photoURL cache.
    func cachedURL(_ urlString: String) -> UIImage? {
        cache.object(forKey: urlString as NSString)
    }

    /// async 加载两帧动图 (free-exercise-db). 失败返回 nil, 调用方走 placeholder.
    func load(folder: String, frame: Int) async -> UIImage? {
        let key = "\(folder)/\(frame)" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = ExerciseImageURL.url(folder: folder, frame: frame) else { return nil }
        guard let img = await Self.fetchWithFailover(url) else { return nil }
        cache.setObject(img, forKey: key, cost: Self.decodedCost(img))
        return img
    }

    /// async 加载单图 (photoURL — Pexels 来源, 绝对 URL). 同样走镜像切换 + 磁盘缓存.
    func loadURL(_ urlString: String) async -> UIImage? {
        let key = urlString as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let url = URL(string: urlString) else { return nil }
        guard let img = await Self.fetchWithFailover(url) else { return nil }
        cache.setObject(img, forKey: key, cost: Self.decodedCost(img))
        return img
    }

    // MARK: - fetch + failover (nonisolated: 下载/解码不绑主 actor)

    /// 对 jsdelivr URL 逐镜像重试; 非 jsdelivr URL 原样请求. 成功的镜像记为 preferred.
    nonisolated private static func fetchWithFailover(_ url: URL) async -> UIImage? {
        guard let host = url.host, host.hasSuffix("jsdelivr.net") else {
            return await fetchOnce(url)
        }
        let start = await MainActor.run { preferredHostIndex }
        let n = cdnHosts.count
        for offset in 0..<n {
            let idx = (start + offset) % n
            guard let mirrored = rewriting(url, host: cdnHosts[idx]) else { continue }
            if let img = await fetchOnce(mirrored) {
                if idx != start { await MainActor.run { preferredHostIndex = idx } }
                return img
            }
        }
        return nil
    }

    nonisolated private static func rewriting(_ url: URL, host: String) -> URL? {
        var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        comps?.host = host
        return comps?.url
    }

    nonisolated private static func fetchOnce(_ url: URL) async -> UIImage? {
        do {
            let (data, resp) = try await session.data(from: url)
            guard (resp as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true else { return nil }
            return UIImage(data: data)
        } catch {
            return nil
        }
    }

    /// 解码后内存占用估算 — NSCache 计费用. RGBA 4 bytes/px.
    nonisolated private static func decodedCost(_ img: UIImage) -> Int {
        let px = Int(img.size.width * img.scale) * Int(img.size.height * img.scale)
        return px * 4
    }
}
