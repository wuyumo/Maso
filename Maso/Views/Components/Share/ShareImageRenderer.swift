import SwiftUI
import UIKit

// SwiftUI view → UIImage 渲染 helper, 给 share 卡片用.
//
// 用 ImageRenderer (iOS 16+) — Apple 官方 SwiftUI-to-Image API, 比 UIHostingController + snapshot
// 更可靠 (snapshot 经常拍到空白 / 缩略 / 未初始化 size).
//
// 输出 scale = 3 — 给 4:5 比例的 share card 输出 1200×1500 高清图, 在 IG / Twitter / WeChat
// 都不会因为分辨率不够被压缩成糊图.

@MainActor
enum ShareImageRenderer {
    /// 给定 view 渲染出 UIImage. fixedWidth = 390 (约 iPhone 标准宽度).
    /// 高度由 view 自适应; share card 设计时用 4:5 比例 (390×488 左右).
    static func render<Content: View>(width: CGFloat = 390, @ViewBuilder _ content: () -> Content) -> UIImage? {
        let renderer = ImageRenderer(content:
            content()
                .frame(width: width)
                .background(MasoColor.background)  // explicit 底色避免透明
        )
        renderer.scale = 3.0
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        // 不透明输出 — 自适应高度常是小数, 位图末行会留一条透明缝, 微信等白底里
        // 显示成"卡片底部一条白线" (owner 实机反馈). 不透明后缝隙渲染为深色, 不可见.
        renderer.isOpaque = true
        return renderer.uiImage
    }
}
