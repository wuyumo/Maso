import UIKit
import Foundation

// 训练动图 (frame 0 / 1) 的共享 UIImage cache.
//
// 为什么不用 AsyncImage:
//   - AsyncImage 加载是 view-local 的, 同一张图在 list / player / minibar 出现就下载多次
//   - 两帧 cross-fade 时, frame 0 和 frame 1 是两个独立 AsyncImage, 加载时机不同步
//     → 切换那一刻可能出现 "frame 1 还没 ready, opacity 已经在动" 的空隙 → 闪
//   - AsyncImage 的 .frame / scaledToFill 算 sizing 是 SwiftUI 层的, 不同 intrinsic
//     size 的图被各自 scale 一次, 像素对齐有 1-2px 误差
//
// 这个 cache 的合约:
//   - 全 app 一份 (singleton), NSCache 自动 evict
//   - cached(folder:frame:) 同步返回 (命中或 nil)
//   - load(folder:frame:) async, 下载后写 cache
//   - 调用方先 cached 命中显示 / 没命中走 load
@MainActor
final class ExerciseImageCache {
    static let shared = ExerciseImageCache()

    private let cache: NSCache<NSString, UIImage>

    init() {
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = 240               // 训练库 873 动作 × 2 帧 ≈ 1746, 缓存 240 个最近用的
        cache.totalCostLimit = 64 * 1024 * 1024  // 64MB 上限, 自动驱逐 LRU
    }

    /// 同步查 cache — 命中返回, 没命中 nil. UI 启动时先调这个, 命中直接显示.
    func cached(folder: String, frame: Int) -> UIImage? {
        let key = "\(folder)/\(frame)" as NSString
        return cache.object(forKey: key)
    }

    /// async 加载 — 先查 cache, 没命中走 URLSession 下载后写入 cache.
    /// 失败返回 nil (网络断 / URL bad / 解码失败), 调用方走 placeholder.
    func load(folder: String, frame: Int) async -> UIImage? {
        let key = "\(folder)/\(frame)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let url = ExerciseImageURL.url(folder: folder, frame: frame) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let img = UIImage(data: data) else { return nil }
            cache.setObject(img, forKey: key, cost: data.count)
            return img
        } catch {
            return nil
        }
    }
}
