import Lottie
import SwiftUI

// Lottie 动画的 SwiftUI 包装器 — DESIGN §3 后续 Lottie 接入入口
//
// 资源放在 Maso/Resources/<name>.json (或 .lottie)
// 通过 Bundle.main 加载, 不联网, 包大小自己控制
//
// 用法:
//   LottieView(name: "lottie-pulse")
//   LottieView(name: "completed", loopMode: .playOnce)
//
// 想加新动画:
//   1. 去 LottieFiles 挑一个免费的 → 下载 .json 或 .lottie
//   2. 放到 Maso/Resources/
//   3. xcodegen generate (新文件需要重生 project)
//   4. LottieView(name: "yourfile") 即可
struct LottieView: UIViewRepresentable {
    let name: String
    var loopMode: LottieLoopMode = .loop
    var speed: CGFloat = 1.0
    var contentMode: UIView.ContentMode = .scaleAspectFit

    func makeUIView(context: Context) -> LottieAnimationView {
        let view = LottieAnimationView()
        view.contentMode = contentMode
        view.loopMode = loopMode
        view.animationSpeed = speed
        loadAnimation(into: view)
        return view
    }

    func updateUIView(_ view: LottieAnimationView, context: Context) {
        if view.animation == nil {
            loadAnimation(into: view)
        }
        view.loopMode = loopMode
        view.animationSpeed = speed
    }

    private func loadAnimation(into view: LottieAnimationView) {
        // 先按文件名找 .json (我们的 hand-written), 后续兼容 .lottie (dotLottie 新格式)
        if let url = Bundle.main.url(forResource: name, withExtension: "json") {
            view.animation = LottieAnimation.filepath(url.path)
            view.play()
        } else if let url = Bundle.main.url(forResource: name, withExtension: "lottie") {
            DotLottieFile.loadedFrom(url: url) { result in
                if case .success(let dot) = result {
                    view.loadAnimation(from: dot)
                    view.play()
                }
            }
        }
    }
}
