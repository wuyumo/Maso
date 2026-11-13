import SwiftUI
import SceneKit

/// One approved surface can represent several training muscles. Use its most
/// fatigued member so a trained sub-muscle is not diluted by untrained neighbors.
struct MuscleBodyRegion: Decodable {
    let node: String
    let muscles: [MuscleGroup]
    let fatigueEligible: Bool

    private static let bundledMapping: Result<[MuscleBodyRegion], Error> = Result {
        guard let url = Bundle.main.url(forResource: "MuscleBodyMapping", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try JSONDecoder().decode([MuscleBodyRegion].self, from: Data(contentsOf: url))
    }

    static func loadBundled() throws -> [MuscleBodyRegion] { try bundledMapping.get() }

    func fatigue(in map: [MuscleGroup: Double]) -> Double {
        guard fatigueEligible else { return 0 }
        return expandAnatomyMuscles(muscles).compactMap { map[$0] }.filter(\.isFinite).max().map { min(1, max(0, $0)) } ?? 0
    }

    /// Every 3D scene and its legend share the same one-percent recovery palette.
    func applyRecoveryColor(to material: SCNMaterial, fatigueMap: [MuscleGroup: Double], showsFatigueColors: Bool = true) {
        let value = showsFatigueColors && fatigueEligible ? fatigue(in: fatigueMap) : 0
        let rgb = MasoColor.recoverySurfaceRGB(fatigue: value)
        let red = CGFloat(fatigueEligible ? rgb.red : 0.32)
        let green = CGFloat(fatigueEligible ? rgb.green : 0.32)
        let blue = CGFloat(fatigueEligible ? rgb.blue : 0.32)
        let emission: CGFloat = showsFatigueColors && fatigueEligible ? 0.7 : 0
        material.emission.contents = UIColor(red: red * emission, green: green * emission, blue: blue * emission, alpha: 1)
        material.diffuse.contents = UIColor(red: red * (1-emission), green: green * (1-emission), blue: blue * (1-emission), alpha: 1)
    }

}

/// Native, offline model. Horizontal drags rotate; vertical drags belong to Today.
struct MuscleBody3DView: UIViewRepresentable {
    /// Keep the home renderer and its navigation handoff at the same opacity.
    static func homeOpacity(reduceTransparency: Bool) -> Double {
        reduceTransparency ? 0.35 : 0.85
    }

    let fatigueMap: [MuscleGroup: Double]
    var showsBack: Bool? = nil
    var autoRotates = false
    var walkthrough = false
    var highlightedRegionNode: String? = nil
    /// nil preserves recovery presentation; a set is a multi-select preference scene.
    var selectedMuscles: Set<MuscleGroup>? = nil
    /// Opt-in framing for the onboarding backdrop; recovery/detail scenes keep 1×.
    var allowsZoom = false
    var initialZoom: Double = 1
    var highlightColor: UIColor = UIColor(red: 30.0 / 255, green: 215.0 / 255, blue: 96.0 / 255, alpha: 1)
    var focusedRegionNode: String? = nil
    var focusShowsBack = false
    var focusVisibleFraction: CGFloat = 1
    var focusTopInsetFraction: CGFloat = 0
    var showsFatigueColors = true
    var navigationRole: MuscleNavigationRole? = nil
    var navigationOcclusionTop: CGFloat? = nil
    var accessibilityID = "today.muscleBody3D"
    var selectionHint: String? = nil
    var onTap: (() -> Void)? = nil
    var onMuscleTap: ((MuscleBodyRegion, Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        view.backgroundColor = .clear
        view.isOpaque = false
        view.antialiasingMode = .multisampling4X
        view.preferredFramesPerSecond = 60
        view.rendersContinuously = false
        view.allowsCameraControl = false
        view.accessibilityIdentifier = accessibilityID
        view.isAccessibilityElement = true
        view.accessibilityLabel = NSLocalizedString(selectedMuscles == nil ? "Muscle Status" : "Muscles to focus", comment: "")
        let isInteractive = onTap != nil || onMuscleTap != nil
        view.accessibilityHint = selectionHint.map { NSLocalizedString($0, comment: "") } ?? NSLocalizedString(onMuscleTap != nil ? "Drag sideways to rotate. Tap a muscle to learn more." : (onTap == nil ? "Drag sideways to rotate" : "Drag sideways to rotate. Tap for recovery details."), comment: "")
        view.accessibilityTraits = isInteractive ? [.button] : [.image]
        let coordinator = context.coordinator
        coordinator.view = view
        coordinator.navigationRole = navigationRole
        coordinator.navigationOcclusionTop = navigationOcclusionTop
        if let navigationRole {
            MuscleNavigationBridge.shared.register(coordinator, as: navigationRole)
            coordinator.navigationTransfer = MuscleNavigationBridge.shared.take(for: navigationRole)
            coordinator.navigationTransfer?.receiver = coordinator
        }
        coordinator.selectedMuscles = selectedMuscles
        coordinator.initialZoom = initialZoom
        coordinator.fatigueMap = fatigueMap
        coordinator.onTap = onTap
        coordinator.onMuscleTap = onMuscleTap
        coordinator.highlightedRegionNode = highlightedRegionNode
        coordinator.highlightColor = highlightColor
        coordinator.focusedRegionNode = focusedRegionNode
        coordinator.focusShowsBack = focusShowsBack
        coordinator.focusVisibleFraction = focusVisibleFraction
        coordinator.focusTopInsetFraction = focusTopInsetFraction
        coordinator.showsFatigueColors = showsFatigueColors
        coordinator.setFacing(showsBack)
        coordinator.walkthrough = walkthrough
        coordinator.setAutoRotation(autoRotates)
        let pan = UIPanGestureRecognizer(target: coordinator, action: #selector(Coordinator.rotate(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = coordinator
        view.addGestureRecognizer(pan)
        if allowsZoom {
            let pinch = UIPinchGestureRecognizer(target: coordinator, action: #selector(Coordinator.zoom(_:)))
            view.addGestureRecognizer(pinch)
        }
        if isInteractive {
            let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.openDetails(_:)))
            tap.require(toFail: pan)
            for pinch in view.gestureRecognizers?.compactMap({ $0 as? UIPinchGestureRecognizer }) ?? [] {
                tap.require(toFail: pinch)
            }
            view.addGestureRecognizer(tap)
        }
        view.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: NSLocalizedString("Body front", comment: ""), target: coordinator, selector: #selector(Coordinator.showFront)),
            UIAccessibilityCustomAction(name: NSLocalizedString("Body back", comment: ""), target: coordinator, selector: #selector(Coordinator.showBack))
        ]
        coordinator.load()
        return view
    }

    func updateUIView(_ view: SCNView, context: Context) {
        context.coordinator.navigationOcclusionTop = navigationOcclusionTop
        context.coordinator.onTap = onTap
        context.coordinator.onMuscleTap = onMuscleTap
        let selectionChanged = context.coordinator.selectedMuscles != selectedMuscles
        view.accessibilityValue = selectedMuscles.map { selected in MuscleSelector.focusSections.filter(selected.contains).map(\.displayName).joined(separator: ", ") }
        context.coordinator.selectedMuscles = selectedMuscles
        let highlightChanged = context.coordinator.highlightedRegionNode != highlightedRegionNode || !context.coordinator.highlightColor.isEqual(highlightColor)
        let focusChanged = context.coordinator.focusedRegionNode != focusedRegionNode
            || context.coordinator.focusVisibleFraction != focusVisibleFraction
            || context.coordinator.focusShowsBack != focusShowsBack
            || context.coordinator.focusTopInsetFraction != focusTopInsetFraction
        let colorModeChanged = context.coordinator.showsFatigueColors != showsFatigueColors
        context.coordinator.highlightedRegionNode = highlightedRegionNode
        context.coordinator.highlightColor = highlightColor
        context.coordinator.focusedRegionNode = focusedRegionNode
        context.coordinator.focusShowsBack = focusShowsBack
        context.coordinator.focusVisibleFraction = focusVisibleFraction
        context.coordinator.focusTopInsetFraction = focusTopInsetFraction
        context.coordinator.showsFatigueColors = showsFatigueColors
        context.coordinator.setFacing(showsBack)
        context.coordinator.walkthrough = walkthrough
        context.coordinator.setAutoRotation(autoRotates)
        let colorsChanged = context.coordinator.fatigueMap != fatigueMap || highlightChanged || colorModeChanged || selectionChanged
        context.coordinator.fatigueMap = fatigueMap
        if colorsChanged { context.coordinator.updateColors() }
        if focusChanged && context.coordinator.navigationTransfer == nil { context.coordinator.focusOnSelectedRegion() }
    }

    static func dismantleUIView(_ view: SCNView, coordinator: Coordinator) {
        coordinator.active = false
        coordinator.cancelNavigationHandoff()
        coordinator.setAutoRotation(false)
        coordinator.onTap = nil
        coordinator.onMuscleTap = nil
        view.scene = nil
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate, SCNSceneRendererDelegate {
        weak var view: SCNView?
        var navigationRole: MuscleNavigationRole?
        var navigationOcclusionTop: CGFloat?
        var navigationTransfer: MuscleNavigationBridge.Transfer?
        private(set) var completedNavigationHandoffs = 0
        private var navigationDestinationPose: (position: SCNVector3, scale: Float, angle: SCNVector3)?
        private var interruptedNavigationFraming: (position: SCNVector3, scale: Float)?
        private var navigationRevealCompletion: (() -> Void)?
        var fatigueMap: [MuscleGroup: Double] = [:]
        var selectedMuscles: Set<MuscleGroup>? = nil
        var initialZoom: Double = 1
        private var pinchStartScale = 1.02
        var onTap: (() -> Void)? = nil
        var onMuscleTap: ((MuscleBodyRegion, Bool) -> Void)? = nil
        var highlightedRegionNode: String? = nil
        var highlightColor: UIColor = UIColor(red: 30.0 / 255, green: 215.0 / 255, blue: 96.0 / 255, alpha: 1)
        var focusedRegionNode: String? = nil
        var focusShowsBack = false
        var focusVisibleFraction: CGFloat = 1
        var focusTopInsetFraction: CGFloat = 0
        private var unfocusedPose: (position: SCNVector3, scale: CGFloat, angle: SCNVector3)?
        var showsFatigueColors = true
        var active = true
        private var body: SCNNode?
        private var regions: [MuscleBodyRegion] = []
        private var requestedBack: Bool?
        private var yaw: Float = 0
        private var dragStart: Float = 0
        var walkthrough = false
        private var autoRotationEnabled = false
        private var isDragging = false
        private static let rotationKey = "muscleBody.autoRotation"
        private static let loader = DispatchQueue(label: "com.yumowu.maso.muscle-scene", qos: .userInitiated)

        func load() {
            // Reuse the already decoded source meshes for these two forward routes.
            let seed = navigationTransfer?.seedScene
            let seedRegions = navigationTransfer?.regions
            Self.loader.async { [weak self] in
                do {
                    let scene: SCNScene
                    let regions: [MuscleBodyRegion]
                    if let seed, let seedRegions {
                        scene = seed
                        regions = seedRegions
                    } else {
                        guard let sceneURL = Bundle.main.url(forResource: "MuscleBody", withExtension: "scn") else {
                            throw CocoaError(.fileNoSuchFile)
                        }
                        scene = try SCNScene(url: sceneURL, options: nil)
                        regions = try MuscleBodyRegion.loadBundled()
                    }
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.active, let view = self.view else { return }
                        let body = SCNNode()
                        for node in scene.rootNode.childNodes { body.addChildNode(node) }
                        scene.rootNode.addChildNode(body)
                        self.body = body
                        body.isHidden = self.navigationTransfer != nil
                        body.eulerAngles.y = self.yaw
                        self.regions = regions
                        let camera = SCNNode()
                        camera.camera = SCNCamera()
                        camera.camera?.usesOrthographicProjection = true
                        camera.camera?.orthographicScale = 1.02 / min(3, max(1, self.initialZoom))
                        camera.camera?.zNear = 0.01
                        camera.camera?.zFar = 20
                        camera.position = SCNVector3(0, 0, 4)
                        scene.rootNode.addChildNode(camera)
                        view.pointOfView = camera
                        self.addLight(to: scene, type: .ambient, intensity: 450, position: SCNVector3(0, 0, 0))
                        self.addLight(to: scene, type: .directional, intensity: 1000, position: SCNVector3(-3, 4, 5))
                        self.addLight(to: scene, type: .directional, intensity: 500, position: SCNVector3(3, 1, 2))
                        self.addLight(to: scene, type: .directional, intensity: 650, position: SCNVector3(1, 3, -4))
                        view.scene = scene
                        self.updateColors()
                        self.focusOnSelectedRegion(animated: false)
                        if self.navigationTransfer != nil { self.beginNavigationHandoff() }
                        else { self.resumeAutoRotation() }
                        // A still body renders one frame. Leaving playback running keeps a 60fps
                        // display link up, and XCTest then never sees an idle event loop.
                        if !self.autoRotationEnabled && self.navigationTransfer == nil && body.actionKeys.isEmpty {
                            view.isPlaying = false
                            view.setNeedsDisplay()
                        }
                    }
                } catch {
                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.active, let view = self.view else { return }
                        self.cancelNavigationHandoff()
                        let label = UILabel()
                        label.text = NSLocalizedString(self.onTap == nil ? "3D model unavailable" : "Tap to view muscle recovery", comment: "")
                        label.textColor = .secondaryLabel
                        label.font = .preferredFont(forTextStyle: .footnote)
                        label.textAlignment = .center
                        label.frame = view.bounds
                        label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                        view.addSubview(label)
                    }
                }
            }
        }

        func prepareNavigation(to destination: MuscleNavigationRole) {
            guard let body, let view, view.window != nil else { return }
            cancelNavigationHandoff()
            let pose = body.presentation.transform
            stopAutoRotation()
            body.removeAction(forKey: "muscleBody.focus")
            body.transform = pose
            yaw = body.eulerAngles.y
            MuscleNavigationBridge.shared.capture(from: self, destination: destination, pose: body, regions: regions)
        }

        private func beginNavigationHandoff() {
            guard let transfer = navigationTransfer, let view, let body,
                  active, view.window != nil, !transfer.finished else {
                cancelNavigationHandoff(settle: true); return
            }
            focusOnSelectedRegion(animated: false)
            let destinationAngle = navigationRole == .status ? transfer.angle : body.eulerAngles
            navigationDestinationPose = (body.position, body.scale.x, destinationAngle)
            body.eulerAngles = destinationAngle
            // UIKit's destination container may still be horizontally translated during
            // the native push. Use its final frame, without waiting for that push to finish.
            var frame = view.convert(view.bounds, to: view.window)
            if let navigation = view.muscleNavigationController,
               let root = navigation.topViewController?.view {
                let rootFrame = root.convert(root.bounds, to: view.window)
                let navigationFrame = navigation.view.convert(navigation.view.bounds, to: view.window)
                frame.origin.x -= rootFrame.minX - navigationFrame.minX
            }
            let cameraScale = CGFloat(view.pointOfView?.camera?.orthographicScale ?? 1.02)
            transfer.animate(to: body, frame: frame, cameraScale: cameraScale) { [weak self] in
                guard let self, self.navigationTransfer === transfer else { return }
                // Reveal only after a real destination frame has rendered. The full-screen
                // renderer stays in place while GPU work completes, so no viewport edge flashes.
                self.body?.isHidden = false
                self.navigationRevealCompletion = { [weak self] in
                    guard let self, self.navigationTransfer === transfer else { return }
                    UIView.animate(withDuration: 0.14, animations: { transfer.liveView.alpha = 0 }) { _ in
                        guard self.navigationTransfer === transfer else { return }
                        self.navigationTransfer = nil
                        self.navigationDestinationPose = nil
                        transfer.finish()
                        self.yaw = destinationAngle.y
                        self.completedNavigationHandoffs += 1
                        self.resumeAutoRotation()
                    }
                }
                self.view?.delegate = self
                self.view?.isPlaying = true
            }
        }

        func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.body?.isHidden == false, let completion = self.navigationRevealCompletion else { return }
                self.navigationRevealCompletion = nil
                self.view?.delegate = nil
                completion()
            }
        }

        func cancelNavigationHandoff(settle: Bool = false, preserveFraming: Bool = false) {
            guard let transfer = navigationTransfer else { return }
            navigationRevealCompletion = nil
            view?.delegate = nil
            if preserveFraming, let pose = navigationDestinationPose {
                interruptedNavigationFraming = (pose.position, pose.scale)
            }
            if let body, let view {
                if !settle, transfer.liveView.window != nil {
                    transfer.applyVisiblePose(to: body, in: view)
                } else if let pose = navigationDestinationPose {
                    body.position = pose.position
                    body.scale = SCNVector3(pose.scale, pose.scale, pose.scale)
                    body.eulerAngles = pose.angle
                }
                body.isHidden = false
                yaw = body.eulerAngles.y
            }
            navigationDestinationPose = nil
            navigationTransfer = nil
            transfer.finish()
            resumeAutoRotation()
        }

        private func addLight(to scene: SCNScene, type: SCNLight.LightType, intensity: CGFloat, position: SCNVector3) {
            let node = SCNNode()
            node.light = SCNLight()
            node.light?.type = type
            node.light?.intensity = intensity
            node.position = position
            if type != .ambient { node.look(at: SCNVector3Zero) }
            scene.rootNode.addChildNode(node)
        }

        /// The training model identifies muscle groups, not left/right body sides.
        private func matchingRegionNodes(for selectedNode: String) -> Set<String> {
            guard let selected = regions.first(where: { $0.node == selectedNode }),
                  !selected.muscles.isEmpty else { return [selectedNode] }
            let muscles = Set(selected.muscles)
            return Set(regions.filter { Set($0.muscles) == muscles }.map(\.node))
        }

        func updateColors() {
            guard let body else { return }
            SCNTransaction.begin()
            SCNTransaction.disableActions = true
            let highlightedNodes = highlightedRegionNode.map { matchingRegionNodes(for: $0) } ?? []
            for region in regions {
                guard let material = body.childNode(withName: region.node, recursively: false)?.geometry?.firstMaterial else { continue }
                if highlightedNodes.contains(region.node) || (region.fatigueEligible && selectedMuscles.map { selected in region.muscles.contains { selected.contains($0.section ?? $0) } } == true) {
                    material.diffuse.contents = highlightColor
                    material.emission.contents = UIColor.black
                    continue
                }
                region.applyRecoveryColor(to: material, fatigueMap: fatigueMap, showsFatigueColors: showsFatigueColors)
            }
            SCNTransaction.commit()
        }

        /// Frame the selected muscle within the same full-body scene, using the node's
        /// real mesh bounds so muscles of different sizes receive a useful zoom level.
        func focusOnSelectedRegion(animated: Bool = true) {
            guard let body, let view else { return }
            let duration = animated && !UIAccessibility.isReduceMotionEnabled ? 0.55 : 0
            guard let focusedRegionNode else {
                guard let pose = unfocusedPose else { return }
                body.removeAction(forKey: "muscleBody.focus")
                let restore = SCNAction.group([
                    .move(to: pose.position, duration: duration), .scale(to: pose.scale, duration: duration),
                    .rotateTo(x: CGFloat(pose.angle.x), y: CGFloat(pose.angle.y), z: CGFloat(pose.angle.z), duration: duration, usesShortestUnitArc: true)
                ])
                restore.timingMode = .easeInEaseOut
                body.runAction(restore, forKey: "muscleBody.focus") { [weak self] in
                    DispatchQueue.main.async {
                        guard let self, self.focusedRegionNode == nil else { return }
                        self.unfocusedPose = nil
                        self.yaw = pose.angle.y
                        self.resumeAutoRotation()
                    }
                }
                view.isPlaying = true
                return
            }
            if unfocusedPose == nil {
                unfocusedPose = (body.position, CGFloat(body.scale.x), body.eulerAngles)
            }
            let nodes = matchingRegionNodes(for: focusedRegionNode).compactMap {
                body.childNode(withName: $0, recursively: false)
            }
            guard !nodes.isEmpty else { return }
            var lower = SCNVector3(Float.infinity, Float.infinity, Float.infinity)
            var upper = SCNVector3(-Float.infinity, -Float.infinity, -Float.infinity)
            for node in nodes {
                let bounds = node.boundingBox
                for x in [bounds.min.x, bounds.max.x] {
                    for y in [bounds.min.y, bounds.max.y] {
                        for z in [bounds.min.z, bounds.max.z] {
                            let point = node.convertPosition(SCNVector3(x, y, z), to: body)
                            lower = SCNVector3(min(lower.x, point.x), min(lower.y, point.y), min(lower.z, point.z))
                            upper = SCNVector3(max(upper.x, point.x), max(upper.y, point.y), max(upper.z, point.z))
                        }
                    }
                }
            }
            let center = SCNVector3((lower.x + upper.x) / 2, (lower.y + upper.y) / 2, (lower.z + upper.z) / 2)
            let size = max(upper.y - lower.y, max(upper.x - lower.x, upper.z - lower.z))
            guard size.isFinite, size > 0 else { return }
            let topInset = min(0.45, max(0, focusTopInsetFraction))
            let fraction = min(1 - topInset, max(0.05, focusVisibleFraction))
            let cameraScale = view.pointOfView?.camera?.orthographicScale ?? 1.02
            let height = max(CGFloat(upper.y - lower.y), 0.01)
            let width = max(CGFloat(upper.x - lower.x), 0.01)
            let aspect = max(0.1, view.bounds.width / max(1, view.bounds.height))
            let zoom = fraction < 1
                ? min(3.2, max(1, min(cameraScale * 2 * fraction * 0.82 / height, cameraScale * 2 * aspect * 0.82 / width)))
                : min(3.2, max(1.0, 0.72 / CGFloat(size)))
            // Rotate mesh-local bounds without including the previous translation/scale.
            // This prevents framing drift when selecting another region while zoomed.
            let angle: Float = focusShowsBack ? .pi : 0
            let target = SCNVector3(center.x * cos(angle) + center.z * sin(angle), center.y,
                                    -center.x * sin(angle) + center.z * cos(angle))
            let upperViewportCenter = Float(cameraScale * (1 - 2 * topInset - fraction))
            let destination = SCNVector3(-target.x * Float(zoom), upperViewportCenter - target.y * Float(zoom), -target.z * Float(zoom))
            body.removeAction(forKey: "muscleBody.focus")
            let frame = SCNAction.group([
                .move(to: destination, duration: duration),
                .scale(to: zoom, duration: duration),
                .rotateTo(x: 0, y: CGFloat(angle), z: 0, duration: duration, usesShortestUnitArc: true)
            ])
            frame.timingMode = .easeInEaseOut
            if duration == 0 {
                // Immediate framing is also the navigation handoff's destination pose.
                body.position = destination
                body.scale = SCNVector3(Float(zoom), Float(zoom), Float(zoom))
                body.eulerAngles = SCNVector3(0, angle, 0)
                view.setNeedsDisplay()
            } else {
                body.runAction(frame, forKey: "muscleBody.focus")
                view.isPlaying = true
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: view)
            return abs(velocity.x) > abs(velocity.y)
        }

        @objc func zoom(_ gesture: UIPinchGestureRecognizer) {
            guard let camera = view?.pointOfView?.camera else { return }
            if gesture.state == .began {
                pinchStartScale = camera.orthographicScale
                stopAutoRotation()
            }
            // Change the projection rather than the mesh, keeping selection hit tests exact.
            camera.orthographicScale = min(1.02, max(0.34, pinchStartScale / max(0.01, Double(gesture.scale))))
            view?.setNeedsDisplay()
            if [.ended, .cancelled, .failed].contains(gesture.state) { resumeAutoRotation(after: 4) }
        }

        @objc func rotate(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began {
                cancelNavigationHandoff(preserveFraming: true)
                isDragging = true
                stopAutoRotation()
                dragStart = yaw
            }
            yaw = dragStart + Float(gesture.translation(in: view).x) * 0.012
            body?.eulerAngles.y = yaw
            if [.ended, .cancelled, .failed].contains(gesture.state) {
                isDragging = false
                if let pose = interruptedNavigationFraming, let body {
                    interruptedNavigationFraming = nil
                    let settle = SCNAction.group([.move(to: pose.position, duration: 0.25), .scale(to: CGFloat(pose.scale), duration: 0.25)])
                    settle.timingMode = .easeInEaseOut
                    body.runAction(settle, forKey: "muscleBody.focus")
                    view?.isPlaying = true
                }
                resumeAutoRotation(after: 4)
            }
        }
        /// Apply explicit view changes once; normal SwiftUI updates preserve a drag.
        func setFacing(_ back: Bool?) {
            guard let back, back != requestedBack else { return }
            requestedBack = back
            face(back: back)
        }

        func setAutoRotation(_ enabled: Bool) {
            guard enabled != autoRotationEnabled else { return }
            autoRotationEnabled = enabled
            if enabled { if unfocusedPose == nil { resumeAutoRotation() } }
            else { cancelNavigationHandoff(settle: true); stopAutoRotation() }
        }

        private func resumeAutoRotation(after delay: TimeInterval = 0) {
            guard navigationTransfer == nil else { return }
            guard active, autoRotationEnabled, !isDragging, let body else { return }
            let motion: SCNAction
            if walkthrough {
                // Derive focus points from the actual mesh, so framing follows the asset.
                let chestY = centerY(of: ["chest_left", "abs_center"])
                let shoulderY = centerY(of: ["shoulders_left", "biceps_left"])
                let backY = centerY(of: ["lats_left", "upperTraps_center"])
                let legY = centerY(of: ["quads_left", "calves_left"])
                motion = .repeatForever(.sequence([
                    tourStop(y: chestY, zoom: 1.65 * 1.5, angle: -0.20),
                    tourStop(y: shoulderY, zoom: 1.5 * 1.5, angle: -1.0),
                    tourStop(y: backY, zoom: 1.6 * 1.5, angle: -.pi),
                    tourStop(y: legY, zoom: 1.4 * 1.5, angle: -.pi * 1.85)
                ]))
            } else {
                let turn = SCNAction.rotateBy(x: 0, y: -.pi * 2, z: 0, duration: 28)
                turn.timingMode = .linear
                motion = .repeatForever(turn)
            }
            body.runAction(.sequence([.wait(duration: delay), motion]), forKey: Self.rotationKey)
            view?.isPlaying = true
        }

        private func centerY(of names: [String]) -> Float {
            guard let body else { return 0 }
            let bounds = names.compactMap { body.childNode(withName: $0, recursively: false)?.boundingBox }
            guard let low = bounds.map({ $0.min.y }).min(),
                  let high = bounds.map({ $0.max.y }).max() else { return 0 }
            return (low + high) / 2
        }

        /// Return to the full body before approaching and holding on the next region.
        private func tourStop(y: Float, zoom: CGFloat, angle: CGFloat) -> SCNAction {
            let zoomOut = SCNAction.group([
                .move(to: SCNVector3Zero, duration: 0.6),
                .scale(to: 1, duration: 0.6)
            ])
            zoomOut.timingMode = .easeInEaseOut
            return .sequence([
                zoomOut,
                .wait(duration: 0.2),
                tourFrame(y: y, zoom: zoom, angle: angle, duration: 1.0),
                .wait(duration: 1.2)
            ])
        }

        private func tourFrame(y: Float, zoom: CGFloat, angle: CGFloat, duration: TimeInterval) -> SCNAction {
            let frame = SCNAction.group([
                .move(to: SCNVector3(0, -y * Float(zoom), 0), duration: duration),
                .scale(to: zoom, duration: duration),
                .rotateTo(x: 0, y: angle, z: 0, duration: duration, usesShortestUnitArc: true)
            ])
            frame.timingMode = .easeInEaseOut
            return frame
        }

        private func stopAutoRotation() {
            if let body, body.action(forKey: Self.rotationKey) != nil {
                // Preserve the visible angle when a drag interrupts SceneKit's animation.
                let transform = body.presentation.transform
                yaw = atan2(transform.m31, transform.m11)
                body.removeAction(forKey: Self.rotationKey)
                // Preserve zoom and framing too when interrupting the walkthrough.
                body.transform = transform
                // Normalize the yaw representation before a horizontal drag takes over.
                body.eulerAngles = SCNVector3(0, yaw, 0)
            }
            view?.isPlaying = false
        }

        private func face(back: Bool) {
            stopAutoRotation()
            yaw = back ? .pi : 0
            body?.eulerAngles.y = yaw
            resumeAutoRotation(after: 4)
            if autoRotationEnabled == false { view?.setNeedsDisplay() }
        }

        @objc func openDetails(_ gesture: UITapGestureRecognizer) {
            if let onMuscleTap, let view, let region = muscleRegion(at: gesture.location(in: view)) {
                let transform = body?.presentation.transform
                let visibleYaw = transform.map { atan2($0.m31, $0.m11) } ?? yaw
                onMuscleTap(region, Foundation.cos(Double(visibleYaw)) < 0)
            } else {
                if navigationRole == .home, onTap != nil {
                    Haptics.selection()
                    prepareNavigation(to: .status)
                }
                onTap?()
            }
        }

        private func muscleRegion(at point: CGPoint) -> MuscleBodyRegion? {
            guard let view else { return nil }
            let byNode = Dictionary(uniqueKeysWithValues: regions.map { ($0.node, $0) })
            let options: [SCNHitTestOption: Any] = [
                .searchMode: SCNHitTestSearchMode.all.rawValue,
                .boundingBoxOnly: false
            ]
            for hit in view.hitTest(point, options: options) {
                var node: SCNNode? = hit.node
                while let current = node {
                    if let name = current.name, let region = byNode[name], region.fatigueEligible, !region.muscles.isEmpty {
                        return region
                    }
                    node = current.parent
                }
            }
            return nil
        }
        @objc func showFront() -> Bool { face(back: false); return true }
        @objc func showBack() -> Bool { face(back: true); return true }
    }
}


/// Four semantic labels sample the finer shared surface palette.
struct MuscleRecoveryLegend: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var twoColumns = false
    var compact = false

    var body: some View {
        if twoColumns && !dynamicTypeSize.isAccessibilitySize {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 2),
                      alignment: .leading, spacing: 12) {
                rows
            }
        } else {
            VStack(alignment: .leading, spacing: twoColumns ? 12 : (compact ? 7 : 9)) {
                rows
            }
        }
    }

    @ViewBuilder
    private var rows: some View {
        row("Fatigued", fatigue: 1)
        row("Recovering", fatigue: 0.5)
        row("Ready", fatigue: 0.2)
        row("Fresh", fatigue: 0)
    }

    private func row(_ title: LocalizedStringKey, fatigue: Double) -> some View {
        HStack(spacing: compact ? 6 : 8) {
            RoundedRectangle(cornerRadius: 3)
                .fill(MasoColor.recoverySurfaceColor(fatigue: fatigue))
                .frame(width: compact ? 8 : 10, height: compact ? 8 : 10)
            Text(title)
                .font(compact ? .caption2 : .caption)
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }
}

// Only the two approved forward routes participate; native navigation owns back gestures.
enum MuscleNavigationRole: Hashable { case home, status, exercises }

final class MuscleNavigationBridge {
    static let shared = MuscleNavigationBridge()
    private final class WeakRenderer {
        weak var value: MuscleBody3DView.Coordinator?
        init(_ value: MuscleBody3DView.Coordinator) { self.value = value }
    }
    final class Transfer: NSObject, SCNSceneRendererDelegate {
        let destination: MuscleNavigationRole
        let frame: CGRect
        let angle: SCNVector3
        let cameraScale: CGFloat
        let imageView: UIImageView
        let liveView: SCNView
        let liveBody: SCNNode
        let seedScene: SCNScene
        let regions: [MuscleBodyRegion]
        private let mask = CAGradientLayer()
        private let rightFade = CAGradientLayer()
        weak var source: SCNView?
        weak var receiver: MuscleBody3DView.Coordinator?
        private(set) var finished = false
        private var screenshotVisible = true
        private var pendingAnimation: (() -> Void)?
        private var sourceOpacity: CGFloat = 1

        init(destination: MuscleNavigationRole, frame: CGRect, pose: SCNNode, source: SCNView,
             host: UIView, role: MuscleNavigationRole?, occlusionTop: CGFloat?, regions: [MuscleBodyRegion]) {
            self.destination = destination; self.frame = frame; angle = pose.eulerAngles
            cameraScale = CGFloat(source.pointOfView?.camera?.orthographicScale ?? 1.02)
            self.source = source; self.regions = regions
            imageView = UIImageView(image: source.snapshot())
            liveView = SCNView(frame: host.bounds)
            liveBody = pose.clone()
            liveBody.isHidden = false
            // Geometry buffers stay shared; destination materials are independent so
            // recoloring one page cannot alter the other page or the bridge renderer.
            seedScene = SCNScene()
            for node in pose.childNodes {
                let copy = node.clone()
                copy.geometry = node.geometry?.copy() as? SCNGeometry
                copy.geometry?.materials = node.geometry?.materials.compactMap { $0.copy() as? SCNMaterial } ?? []
                seedScene.rootNode.addChildNode(copy)
            }
            super.init()
            liveView.backgroundColor = .clear; liveView.isOpaque = false
            liveView.isUserInteractionEnabled = false
            liveView.isAccessibilityElement = false
            liveView.accessibilityIdentifier = "muscle.navigation.live"
            liveView.antialiasingMode = .multisampling4X
            liveView.preferredFramesPerSecond = 60
            let scene = SCNScene()
            scene.rootNode.addChildNode(liveBody)
            if let original = source.scene {
                for node in original.rootNode.childNodes where node !== pose {
                    let copy = node.clone()
                    scene.rootNode.addChildNode(copy)
                    if node === source.pointOfView { liveView.pointOfView = copy }
                }
            }
            liveView.scene = scene
            liveView.delegate = self
            liveView.isPlaying = true
            imageView.isUserInteractionEnabled = false
            imageView.isAccessibilityElement = false
            imageView.accessibilityIdentifier = "muscle.navigation.snapshot"
            imageView.frame = host.convert(frame, from: source.window)
            imageView.contentMode = .scaleToFill
            let fullFrame = host.convert(host.bounds, to: source.window)
            let ratio = frame.height / max(1, fullFrame.height)
            let units = 2 * cameraScale / max(1, fullFrame.height)
            liveBody.scale = SCNVector3(pose.scale.x * Float(ratio), pose.scale.x * Float(ratio), pose.scale.x * Float(ratio))
            liveBody.position = SCNVector3(pose.position.x * Float(ratio) + Float((frame.midX-fullFrame.midX)*units),
                                          pose.position.y * Float(ratio) - Float((frame.midY-fullFrame.midY)*units), pose.position.z * Float(ratio))
            mask.frame = liveView.bounds
            let opacity: CGFloat = role == .home ? CGFloat(MuscleBody3DView.homeOpacity(reduceTransparency: UIAccessibility.isReduceTransparencyEnabled)) : 1
            sourceOpacity = opacity
            liveView.alpha = 0.01; imageView.alpha = opacity
            var alphas: [CGFloat] = Array(repeating: 1, count: 8)
            var stops: [CGFloat] = [0, 0.32, 0.44, 0.57, 0.70, 0.83, 0.94, 1]
            if role == .home {
                alphas = [0.30, 0.798, 0.824, 0.80, 0.58, 0.32, 0.10, 0]
            } else if let occlusionTop {
                let cutoff = min(1, max(0, (occlusionTop - frame.minY) / max(1, frame.height)))
                stops = [0, cutoff * 0.2, cutoff * 0.4, cutoff * 0.6, cutoff * 0.8, max(0, cutoff-0.03), cutoff, 1]
                alphas = [1,1,1,1,1,1,0,0]
            }
            mask.colors = alphas.map { UIColor.white.withAlphaComponent($0).cgColor }
            mask.locations = stops.map { NSNumber(value: Double(min(1, max(0, (frame.minY-fullFrame.minY+frame.height*$0)/max(1, fullFrame.height))))) }
            liveView.layer.mask = mask
            rightFade.startPoint = CGPoint(x: 0, y: 0.5)
            rightFade.endPoint = CGPoint(x: 1, y: 0.5)
            rightFade.colors = [UIColor(MasoColor.background).withAlphaComponent(0).cgColor,
                                UIColor(MasoColor.background).withAlphaComponent(0).cgColor,
                                UIColor(MasoColor.background).cgColor]
            rightFade.locations = [0, 0.6, 1]
            rightFade.opacity = 0
            liveView.layer.addSublayer(rightFade)
            let imageMask = CAGradientLayer()
            imageMask.frame = imageView.bounds
            imageMask.colors = mask.colors
            imageMask.locations = stops.map { NSNumber(value: Double($0)) }
            imageView.layer.mask = imageMask
            if let nav = source.muscleNavigationController, nav.navigationBar.superview === host {
                host.insertSubview(liveView, belowSubview: nav.navigationBar)
                host.insertSubview(imageView, aboveSubview: liveView)
            } else { host.addSubview(liveView); host.addSubview(imageView) }
        }

        func renderer(_ renderer: any SCNSceneRenderer, didRenderScene scene: SCNScene, atTime time: TimeInterval) {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.finished, self.screenshotVisible else { return }
                self.screenshotVisible = false
                self.liveView.delegate = nil
                // The first warm live frame has the same pose, mask and opacity as the
                // screenshot. Swap them directly instead of compositing two translucent bodies.
                self.liveView.alpha = self.sourceOpacity
                self.imageView.removeFromSuperview(); self.imageView.image = nil
                let animation = self.pendingAnimation
                self.pendingAnimation = nil
                animation?()
            }
        }

        func animate(to pose: SCNNode, frame target: CGRect, cameraScale targetCamera: CGFloat, completion: @escaping () -> Void) {
            if screenshotVisible {
                pendingAnimation = { [weak self, weak pose] in
                    guard let self, let pose, !self.finished else { return }
                    self.animate(to: pose, frame: target, cameraScale: targetCamera, completion: completion)
                }
                return
            }
            guard let window = liveView.window else { finish(); return }
            let fullFrame = liveView.convert(liveView.bounds, to: window)
            let ratio = target.height / max(1, fullFrame.height) * cameraScale / targetCamera
            let units = 2 * cameraScale / max(1, fullFrame.height)
            let position = SCNVector3(pose.position.x * Float(ratio) + Float((target.midX-fullFrame.midX)*units),
                                      pose.position.y * Float(ratio) - Float((target.midY-fullFrame.midY)*units), pose.position.z * Float(ratio))
            let scale = CGFloat(pose.scale.x) * ratio
            let duration = UIAccessibility.isReduceMotionEnabled ? 0.18 : 0.55
            let action = SCNAction.group([
                .move(to: position, duration: duration), .scale(to: scale, duration: duration),
                .rotateTo(x: CGFloat(pose.eulerAngles.x), y: CGFloat(pose.eulerAngles.y), z: CGFloat(pose.eulerAngles.z), duration: duration, usesShortestUnitArc: true)
            ])
            action.timingMode = .easeInEaseOut
            if UIAccessibility.isReduceMotionEnabled {
                liveBody.position = position; liveBody.scale = SCNVector3(Float(scale), Float(scale), Float(scale)); liveBody.eulerAngles = pose.eulerAngles
            }
            let alphas: [CGFloat] = destination == .status ? Array(repeating: 1, count: 8) : [1,1,0.96,0.92,0.733,0.6,0.2,0]
            let fade = min(192, target.height)
            let locations: [CGFloat] = destination == .status ? [0,0.2,0.35,0.5,0.65,0.8,0.9,1] :
                [0,max(0,target.maxY-fade),target.maxY-fade*0.85,target.maxY-fade*0.7,target.maxY-fade*0.5,target.maxY-fade*0.4,target.maxY-fade*0.15,target.maxY].map { ($0-fullFrame.minY)/max(1,fullFrame.height) }
            if destination == .exercises {
                CATransaction.begin(); CATransaction.setDisableActions(true)
                rightFade.frame = CGRect(x: target.minX-fullFrame.minX, y: target.minY-fullFrame.minY,
                                         width: min(target.width, fullFrame.width), height: target.height)
                CATransaction.commit()
            }
            CATransaction.begin(); CATransaction.setAnimationDuration(duration)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
            mask.colors = alphas.map { UIColor.white.withAlphaComponent($0).cgColor }
            rightFade.opacity = destination == .exercises ? 1 : 0
            mask.locations = locations.map { NSNumber(value: Double(min(1,max(0,$0)))) }
            CATransaction.commit()
            UIView.animate(withDuration: duration, delay: 0, options: [.beginFromCurrentState, .curveEaseInOut]) { self.liveView.alpha = 1 }
            if UIAccessibility.isReduceMotionEnabled { DispatchQueue.main.asyncAfter(deadline: .now()+duration, execute: completion) }
            else { liveBody.runAction(action) { DispatchQueue.main.async(execute: completion) } }
        }

        func applyVisiblePose(to body: SCNNode, in view: SCNView) {
            let sourceFrame = liveView.convert(liveView.bounds, to: view.window)
            let target = view.convert(view.bounds, to: view.window)
            let targetCamera = CGFloat(view.pointOfView?.camera?.orthographicScale ?? 1.02)
            let ratio = sourceFrame.height / max(1,target.height) * targetCamera / cameraScale
            let units = 2 * targetCamera / max(1,target.height)
            let visible = liveBody.presentation
            body.scale = SCNVector3(visible.scale.x * Float(ratio), visible.scale.x * Float(ratio), visible.scale.x * Float(ratio))
            body.eulerAngles = visible.eulerAngles
            body.position = SCNVector3(visible.position.x * Float(ratio) + Float((sourceFrame.midX-target.midX)*units),
                                      visible.position.y * Float(ratio) - Float((sourceFrame.midY-target.midY)*units),visible.position.z * Float(ratio))
        }

        func finish() {
            guard !finished else { return }
            finished = true
            pendingAnimation = nil
            liveBody.removeAllActions()
            liveView.delegate = nil; liveView.isPlaying = false; liveView.scene = nil
            liveView.layer.removeAllAnimations(); liveView.removeFromSuperview()
            imageView.layer.removeAllAnimations(); imageView.removeFromSuperview(); imageView.image = nil
            source?.alpha = 1
        }
    }
    private var renderers: [MuscleNavigationRole: WeakRenderer] = [:]
    private var pending: Transfer?
    func register(_ renderer: MuscleBody3DView.Coordinator, as role: MuscleNavigationRole) { renderers[role] = WeakRenderer(renderer) }
    func prepare(from source: MuscleNavigationRole, to destination: MuscleNavigationRole) { renderers[source]?.value?.prepareNavigation(to: destination) }
    func take(for role: MuscleNavigationRole) -> Transfer? {
        guard let transfer = pending, transfer.destination == role, !transfer.finished else { return nil }
        pending = nil; return transfer
    }
    func capture(from renderer: MuscleBody3DView.Coordinator, destination: MuscleNavigationRole, pose: SCNNode, regions: [MuscleBodyRegion]) {
        guard let view = renderer.view, let window = view.window, view.bounds.height > 0 else { return }
        pending?.finish()
        let frame = view.convert(view.bounds, to: window)
        let host = view.muscleNavigationController?.view ?? window
        let transfer = Transfer(destination: destination, frame: frame, pose: pose, source: view, host: host,
                                role: renderer.navigationRole, occlusionTop: renderer.navigationOcclusionTop, regions: regions)
        pending = transfer; view.alpha = 0
        DispatchQueue.main.asyncAfter(deadline: .now()+3) { [weak transfer] in
            guard let transfer, !transfer.finished else { return }
            if let receiver = transfer.receiver { receiver.cancelNavigationHandoff(settle: true) }
            else { transfer.finish() }
        }
    }
}

private extension UIView {
    var muscleNavigationController: UINavigationController? {
        var responder: UIResponder? = self
        while let current = responder {
            if let controller = current as? UIViewController, let navigation = controller.navigationController { return navigation }
            responder = current.next
        }
        return nil
    }
}
