import SwiftUI

// 两帧 cross-fade 的稳定渲染组件 — 训练动图唯一渲染入口.
//
// 设计目标: 让"大部分静止像素稳定", 用户的眼睛只感知"人体动作变化", 不感知"画面抖动".
//
// 解决的稳定性问题:
//   1. AsyncImage 各帧独立加载 → 改用 ExerciseImageCache 预加载 UIImage,
//      两张都 ready 才开始 cross-fade, 不存在 "frame 1 还在 loading" 的窗口期
//   2. scaledToFill 在不同 intrinsic 上 sizing 不一致 → 用 GeometryReader 拿到精确 size,
//      两张图都用同一 .frame(width:height:).aspectRatio(.fill).clipped() 严格锚定
//   3. timer 太快 (1s 周期, 0.8s 过渡) → 改 2.5s 周期, 0.9s 过渡, 1.6s 稳定占大头
//
// 接口: animated=false 时只渲染 frame 0, 不挂 timer, 不加载 frame 1 — 列表用静态图省 CPU+带宽.
struct CrossFadeFrames: View {
    let folder: String
    let animated: Bool

    @State private var frame0: UIImage?
    @State private var frame1: UIImage?
    @State private var showFrame1 = false

    /// Ken Burns 微动相位 — 跟 showFrame1 同步翻转, 让两帧切换时伴随极轻 scale + 位移,
    /// 制造"画面在运动"感而非"两张图在切换"感. 调研结论: 干净免费的真视频/GIF 数据集不存在
    /// (yuhonas public domain 只有 2 帧; 其他 GIF 库都 non-commercial / AGPL / 付费),
    /// 所以最经济的"动起来"路径是给 cross-fade 加微动.
    ///
    /// 数值刻意做得极小 (scale ±1%, offset ±1pt) — 之前用户多次抱怨"闪 / 抖", 这里只要
    /// "刚好能感受到运动, 不到察觉位移"的程度.
    private var motionPhase: CGFloat { showFrame1 ? 1 : 0 }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 底层: frame 0 — 一直全不透明, 给整张图当"地板", 不被 cross-fade 改透明度.
                // 加微 scale: 默认 1.0 → cross-fade 后 1.01 (轻微 zoom in 1%).
                // 加微 offset: 默认 0 → cross-fade 后 +1pt x. 制造"镜头在跟动作"的感觉.
                frameView(image: frame0, size: geo.size)
                    .scaleEffect(1.0 + motionPhase * 0.01)
                    .offset(x: motionPhase * 1.0)

                // 上层: frame 1 — 通过 opacity cross-fade. 微动跟 frame 0 反向 — frame 1
                // 从 zoom-in 状态过渡到 base, 视觉上像"动作完成时回到中心位置".
                if animated {
                    frameView(image: frame1, size: geo.size)
                        .scaleEffect(1.0 + (1 - motionPhase) * 0.01)
                        .offset(x: (1 - motionPhase) * -1.0)
                        .opacity(showFrame1 ? 1 : 0)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .clipped()  // 外层再 clip 一次, 防边缘抖动透出 ZStack 兜底 (微 scale 1% 会让边缘略凸, 必须 clip)
        }
        // task(id:) 确保 folder 切换时重新加载. animated 切换不需要重 task,
        // 因为 animated=false 只是不显示 frame 1, 加载它没害.
        .task(id: folder) {
            await loadFrames()
        }
        // 1.5s 周期 + 0.5s 过渡 — 接近真实动作节奏 (蹲起 ~2s, 推拉 ~1-2s).
        // 历史试错: 1.0s 周期/0.8s 过渡用户嫌闪; 2.5s/0.9s 用户嫌慢; 1.5s/0.5s 是 sweet spot
        // (稳定 1.0s + 过渡 0.5s, 像动作"完成一半暂停一下再继续"的自然节奏).
        // guard 检查两帧都 ready, 没都 ready 不开始动画 — 避免"frame 1 是 nil 时 cross-fade 出空白".
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            guard animated, frame0 != nil, frame1 != nil else { return }
            withAnimation(.easeInOut(duration: 0.5)) {
                showFrame1.toggle()
                // motionPhase 跟 showFrame1 联动 (computed property), 自动跟随动画
            }
        }
    }

    /// 单帧渲染 — 严格锚定 size, 用 aspectRatio(.fill) 让两张图按完全相同方式 scale.
    /// 同一 size + 同一 contentMode + 同一 clipped() → 两帧像素位置严格一致.
    @ViewBuilder
    private func frameView(image: UIImage?, size: CGSize) -> some View {
        if let img = image {
            Image(uiImage: img)
                .resizable()
                .interpolation(.high)
                .antialiased(true)
                .aspectRatio(contentMode: .fill)
                .frame(width: size.width, height: size.height)
                .clipped()
        } else {
            Color.clear
                .frame(width: size.width, height: size.height)
        }
    }

    private func loadFrames() async {
        // 同步先查 cache — 命中则立即填上, 视觉上"秒开"
        let cache = ExerciseImageCache.shared
        frame0 = cache.cached(folder: folder, frame: 0)
        if animated { frame1 = cache.cached(folder: folder, frame: 1) }

        // 把 @MainActor-isolated 的 state 提到 nonisolated 局部, 再传进 async let.
        // (直接在 async let autoclosure 里读 frame1 触发 actor-isolation warning.)
        let needs0 = (frame0 == nil)
        let needs1 = (animated && frame1 == nil)
        let folderCopy = folder
        async let f0task: UIImage? = needs0 ? cache.load(folder: folderCopy, frame: 0) : nil
        async let f1task: UIImage? = needs1 ? cache.load(folder: folderCopy, frame: 1) : nil
        let (loaded0, loaded1) = await (f0task, f1task)
        if needs0, let img = loaded0 { frame0 = img }
        if needs1, let img = loaded1 { frame1 = img }
    }
}
