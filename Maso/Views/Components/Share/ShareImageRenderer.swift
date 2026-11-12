import SwiftUI
import UIKit
import SceneKit

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

/// SceneKit is rasterized before SwiftUI export so exported cards include the model.
@MainActor
struct ShareMuscleBody3D: View {
    var muscles: [MuscleGroup] = []
    var muscleStyle: ((MuscleGroup) -> (Color, Double)?)? = nil
    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        HStack(spacing: -12) {
            model(back: false).offset(x: 10)
            model(back: true).offset(x: -10)
        }
        .frame(height: 300)
        .opacity(0.65)
        .accessibilityLabel("Front and back muscle coverage")
    }

    @ViewBuilder private func model(back: Bool) -> some View {
        if let image = snapshot(back: back) {
            Image(uiImage: image).resizable().scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func snapshot(back: Bool) -> UIImage? {
        guard let url = Bundle.main.url(forResource: "MuscleBody", withExtension: "scn"),
              let mapping = Bundle.main.url(forResource: "MuscleBodyMapping", withExtension: "json"),
              let bytes = try? Data(contentsOf: mapping),
              let regions = try? JSONDecoder().decode([MuscleBodyRegion].self, from: bytes) else { return nil }
        let selected = Set(muscles)
        let colors: [UIColor] = regions.map { region in
            if region.muscles.contains(where: selected.contains) { return UIColor(MasoColor.accent) }
            if let muscleStyle, let style = region.muscles.compactMap({ muscleStyle($0) }).max(by: { $0.1 < $1.1 }) {
                let color = UIColor(style.0)
                let gray = UIColor(white: 0.24, alpha: 1)
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                color.getRed(&r, green: &g, blue: &b, alpha: &a)
                let blend = CGFloat(min(1, max(0, style.1)))
                if blend == 0 { return gray }
                return UIColor(red: 0.24 + (r-0.24)*blend, green: 0.24 + (g-0.24)*blend,
                               blue: 0.24 + (b-0.24)*blend, alpha: 1)
            }
            return UIColor(white: region.fatigueEligible ? 0.24 : 0.32, alpha: 1)
        }
        let key = (String(back) + colors.map { $0.description }.joined()) as NSString
        if let hit = Self.cache.object(forKey: key) { return hit }
        guard let scene = try? SCNScene(url: url) else { return nil }
        scene.background.contents = UIColor.clear
        let body = SCNNode()
        for node in scene.rootNode.childNodes { body.addChildNode(node) }
        scene.rootNode.addChildNode(body)
        body.eulerAngles.y = back ? .pi : 0
        for (region, color) in zip(regions, colors) {
            guard let node = body.childNode(withName: region.node, recursively: false),
                  let material = node.geometry?.firstMaterial else { continue }
            material.diffuse.contents = color
            material.emission.contents = UIColor.black
        }
        let camera = SCNNode()
        camera.camera = SCNCamera()
        camera.camera?.usesOrthographicProjection = true
        camera.camera?.orthographicScale = 1.02
        camera.camera?.zNear = 0.01
        camera.camera?.zFar = 20
        camera.position = SCNVector3(0, 0, 4)
        scene.rootNode.addChildNode(camera)
        for (type, intensity, position) in [(SCNLight.LightType.ambient, CGFloat(450), SCNVector3Zero),
                                            (.directional, 1000, SCNVector3(-3, 4, 5)),
                                            (.directional, 650, SCNVector3(1, 3, -4))] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = type
            light.light?.intensity = intensity
            light.position = position
            if type != .ambient { light.look(at: SCNVector3Zero) }
            scene.rootNode.addChildNode(light)
        }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 360, height: 750), antialiasingMode: .multisampling4X)
        Self.cache.countLimit = 12
        Self.cache.setObject(image, forKey: key)
        return image
    }
}

/// Compact two-view muscle map for share cards.
struct ShareMuscleMap2D: View {
    var muscles: [MuscleGroup] = []
    var muscleStyle: ((MuscleGroup) -> (Color, Double)?)? = nil
    var height: CGFloat = 148

    var body: some View {
        BodyHint(
            muscles: muscles,
            height: height,
            region: .full,
            heatStyleFor: muscleStyle,
            coarseOnly: true,
            panelSpacing: 3
        )
        .frame(height: height)
        .accessibilityLabel("Front and back muscle coverage")
    }
}

/// Focused model detail for workout cards that have no personal photo.
@MainActor
struct ShareMuscleFocus3D: View {
    let muscles: [MuscleGroup]
    private static let cache = NSCache<NSString, UIImage>()
    private static var sideCache: [String: [(back: Bool, nodes: [String])]] = [:]

    private var focusedSides: [(back: Bool, nodes: [String])] {
        let cacheKey = muscles.map(\.rawValue).sorted().joined(separator: ",")
        if let cached = Self.sideCache[cacheKey] { return cached }
        let expanded = expandAnatomyMuscles(muscles)
        guard let mapping = Bundle.main.url(forResource: "MuscleBodyMapping", withExtension: "json"),
              let bytes = try? Data(contentsOf: mapping),
              let regions = try? JSONDecoder().decode([MuscleBodyRegion].self, from: bytes),
              let sceneURL = Bundle.main.url(forResource: "MuscleBody", withExtension: "scn"),
              let scene = try? SCNScene(url: sceneURL) else { return [] }
        let body = SCNNode()
        for node in scene.rootNode.childNodes { body.addChildNode(node) }
        scene.rootNode.addChildNode(body)
        var front: [String] = []
        var back: [String] = []
        for region in regions where region.muscles.contains(where: expanded.contains) {
            guard let node = body.childNode(withName: region.node, recursively: false) else { continue }
            let bounds = node.boundingBox
            let center = node.convertPosition(SCNVector3((bounds.min.x + bounds.max.x) / 2,
                                                         (bounds.min.y + bounds.max.y) / 2,
                                                         (bounds.min.z + bounds.max.z) / 2), to: body)
            if center.z >= 0 { front.append(region.node) } else { back.append(region.node) }
        }
        let result = [(false, front.sorted()), (true, back.sorted())].filter { !$0.1.isEmpty }
            .map { (back: $0.0, nodes: $0.1) }
        Self.sideCache[cacheKey] = result
        return result
    }

    @ViewBuilder
    var body: some View {
        Group {
            if focusedSides.isEmpty {
                ShareMuscleMap2D(muscles: muscles)
            } else {
                GeometryReader { proxy in
                    let tileWidth = proxy.size.width * (focusedSides.count == 1 ? 0.72 : 0.54)
                    HStack(spacing: -proxy.size.width * 0.06) {
                        ForEach(focusedSides.indices, id: \.self) { index in
                            if let image = snapshot(back: focusedSides[index].back, selectedNodes: focusedSides[index].nodes) {
                                Image(uiImage: image).resizable().scaledToFit()
                                    .frame(width: tileWidth, height: proxy.size.height)
                            }
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                }
                .opacity(0.86)
            }
        }
        .accessibilityLabel("3D close-up of the muscles trained")
    }

    private func snapshot(back: Bool, selectedNodes: [String]) -> UIImage? {
        guard let sceneURL = Bundle.main.url(forResource: "MuscleBody", withExtension: "scn"),
              let mappingURL = Bundle.main.url(forResource: "MuscleBodyMapping", withExtension: "json"),
              let bytes = try? Data(contentsOf: mappingURL),
              let regions = try? JSONDecoder().decode([MuscleBodyRegion].self, from: bytes) else { return nil }
        let selectedSet = Set(selectedNodes)
        let key = ("focus|\(back)|" + selectedNodes.joined(separator: ",")) as NSString
        if let image = Self.cache.object(forKey: key) { return image }
        guard let scene = try? SCNScene(url: sceneURL) else { return nil }
        scene.background.contents = UIColor.clear
        let body = SCNNode()
        for node in scene.rootNode.childNodes { body.addChildNode(node) }
        scene.rootNode.addChildNode(body)
        body.eulerAngles.y = back ? .pi : 0

        var focusedNodes: [SCNNode] = []
        for region in regions {
            guard let node = body.childNode(withName: region.node, recursively: false),
                  let material = node.geometry?.firstMaterial else { continue }
            let matches = selectedSet.contains(region.node)
            material.diffuse.contents = matches
                ? UIColor(MasoColor.accent)
                : UIColor(white: region.fatigueEligible ? 0.24 : 0.32, alpha: 1)
            material.emission.contents = UIColor.black
            if matches { focusedNodes.append(node) }
        }
        guard !focusedNodes.isEmpty else { return nil }

        var lower = SCNVector3(Float.infinity, Float.infinity, Float.infinity)
        var upper = SCNVector3(-Float.infinity, -Float.infinity, -Float.infinity)
        for node in focusedNodes {
            let bounds = node.boundingBox
            for x in [bounds.min.x, bounds.max.x] {
                for y in [bounds.min.y, bounds.max.y] {
                    for z in [bounds.min.z, bounds.max.z] {
                        let point = node.convertPosition(SCNVector3(x, y, z), to: scene.rootNode)
                        lower = SCNVector3(min(lower.x, point.x), min(lower.y, point.y), min(lower.z, point.z))
                        upper = SCNVector3(max(upper.x, point.x), max(upper.y, point.y), max(upper.z, point.z))
                    }
                }
            }
        }
        let center = SCNVector3((lower.x + upper.x) / 2, (lower.y + upper.y) / 2, (lower.z + upper.z) / 2)
        let extent = max(upper.x - lower.x, upper.y - lower.y)
        guard extent.isFinite, extent > 0 else { return nil }

        let camera = SCNNode()
        let lens = SCNCamera()
        lens.usesOrthographicProjection = true
        lens.orthographicScale = min(0.82, max(0.18, CGFloat(extent) * 1.45))
        lens.zNear = 0.01
        lens.zFar = 20
        camera.camera = lens
        camera.position = SCNVector3(center.x, center.y, center.z + (back ? -4 : 4))
        camera.look(at: center)
        scene.rootNode.addChildNode(camera)
        for (type, intensity, position) in [(SCNLight.LightType.ambient, CGFloat(450), SCNVector3Zero),
                                            (.directional, 1000, SCNVector3(-3, 4, 5)),
                                            (.directional, 650, SCNVector3(1, 3, -4))] {
            let light = SCNNode()
            light.light = SCNLight()
            light.light?.type = type
            light.light?.intensity = intensity
            light.position = position
            if type != .ambient { light.look(at: SCNVector3Zero) }
            scene.rootNode.addChildNode(light)
        }
        let renderer = SCNRenderer(device: nil, options: nil)
        renderer.scene = scene
        renderer.pointOfView = camera
        let image = renderer.snapshot(atTime: 0, with: CGSize(width: 480, height: 720), antialiasingMode: .multisampling4X)
        Self.cache.countLimit = 24
        Self.cache.setObject(image, forKey: key)
        return image
    }
}
