import SwiftUI

// 紧凑的双视图肌肉示意图 (正面 + 背面)
//
// 2026-05-24 — 撤回 MuscleMap SDK 路径, 改回 polygon Canvas 自渲染.
// SDK 渲染的真人解剖图视觉太硬, 用户要的是低多边形 / 大肌群优先 / sub-muscle 作为切分而不是独立块.
// 这个版本的"生成方式":
//   - 直接 fill `ANTERIOR` / `POSTERIOR` 里的 polygon (react-body-highlighter 数据, 17 大肌群)
//   - 每个 polygon = 一个 major muscle 的形状 (chest / lats / biceps...), 没有 sub-muscle 独立块
//   - sub-muscle 命中通过 `expandAnatomyMuscles` 反向触发对应 major polygon 高亮 — 视觉是"切分", 不是另一块
//   - 描边用极淡灰 (#1F1F1F, 0.25pt) 当作肌肉之间的分隔线, 不抢戏
//   - 圆角 2.5pt — 让低多边形不那么尖锐
//
// 行为:
//   - 默认 (square=false): 每个 panel 宽度按 region viewBox 的自然 aspect 计算 (~0.5 wide × tall)
//   - square=true: 每个 panel 锁定为 height × height (列表 / player thumbnail 用)
//   - region: full / upper / lower 控制 viewBox 裁剪
//   - opacityFor: per-muscle opacity 回调 (history 衰减热图模式)
//   - panelSpacing: 前后 panel 间距 (默认 6, MuscleVisualBlock 通常传 0)
//   - onMuscleTap: 用户点击身体某块肌肉时触发 — ray-cast point-in-polygon hit test
struct BodyHint: View {
    let muscles: [MuscleGroup]
    /// 协同肌 — 渲染成 35% 透明的 accent ("带到的肌肉").
    var synergists: [MuscleGroup] = []
    var color: Color = MasoColor.accent
    var height: CGFloat = 110
    var region: BodyRegion = .full
    /// true = 每个 panel 锁成 height × height 的正方形 slot (列表 / player 用)
    var square: Bool = false
    /// 可选 per-muscle opacity 回调 (history 衰减模式). 传了之后 muscles / synergists 被忽略.
    var opacityFor: ((MuscleGroup) -> Double?)? = nil
    /// 可选 tap 回调 — 用户点身体某块肌肉时触发.
    var onMuscleTap: ((MuscleGroup) -> Void)? = nil
    /// "粗颗粒模式" — true 时不画 sub muscle 之间的细分描边, 让同一 major 的 polygon 视觉合并成一整块.
    var coarseOnly: Bool = false
    /// 前 / 后 panel 之间的间距 (像素). 默认 6, MuscleVisualBlock 通常传 0 (锁正方形 slot).
    var panelSpacing: CGFloat = 6

    private var expanded: Set<MuscleGroup> { expandAnatomyMuscles(muscles) }
    private var synergistsExpanded: Set<MuscleGroup> {
        expandAnatomyMuscles(synergists).subtracting(expanded)
    }

    /// 单 panel 在 "理想 anatomy 坐标系" 下的宽度
    private var panelUnitWidth: CGFloat {
        if square { return region.viewBox.height }
        return AnatomyView.width
    }

    /// 显示像素下的单 panel 宽
    private var displayPanelW: CGFloat {
        square ? height : height * (AnatomyView.width / region.viewBox.height)
    }
    private var displayTotalW: CGFloat {
        displayPanelW * 2 + panelSpacing
    }
    private var aspectRatio: CGFloat {
        displayTotalW / height
    }

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in
                draw(ctx: ctx, size: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
                guard let onMuscleTap else { return }
                if let m = hitTest(location: location, canvasSize: geo.size) {
                    onMuscleTap(m)
                }
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .frame(maxHeight: height)
    }

    // MARK: - Hit test (point-in-polygon)

    private func hitTest(location p: CGPoint, canvasSize size: CGSize) -> MuscleGroup? {
        let scale = size.height / height
        let panelHpx = size.height
        let panelWpx = displayPanelW * scale
        let gapPx = panelSpacing * scale
        let view = region.viewBox

        let scaleX = panelWpx / AnatomyView.width
        let scaleY = panelHpx / view.height
        let s = min(scaleX, scaleY)
        let drawW = AnatomyView.width * s
        let drawH = view.height * s

        if p.x < panelWpx {
            let dx = (panelWpx - drawW) / 2
            let dy = (panelHpx - drawH) / 2
            let anatX = (p.x - dx) / s
            let anatY = (p.y - dy) / s + view.yMin
            return pointInPolygons(CGPoint(x: anatX, y: anatY), polys: ANTERIOR)
        } else if p.x > panelWpx + gapPx {
            let originX = panelWpx + gapPx
            let dx = originX + (panelWpx - drawW) / 2
            let dy = (panelHpx - drawH) / 2
            let anatX = (p.x - dx) / s
            let anatY = (p.y - dy) / s + view.yMin
            return pointInPolygons(CGPoint(x: anatX, y: anatY), polys: POSTERIOR)
        }
        return nil
    }

    /// 反向遍历 polygon (后画的在上层, 优先 hit). 跳过 fullBody (装饰头).
    private func pointInPolygons(_ p: CGPoint, polys: [AnatomyPolygon]) -> MuscleGroup? {
        for poly in polys.reversed() where poly.muscle != .fullBody {
            if pointInPolygon(p, polygon: poly.points) {
                return poly.muscle
            }
        }
        return nil
    }

    /// 标准 ray-casting point-in-polygon
    private func pointInPolygon(_ p: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            if (pi.y > p.y) != (pj.y > p.y) {
                let x = pi.x + (p.y - pi.y) * (pj.x - pi.x) / (pj.y - pi.y)
                if p.x < x { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    // MARK: - 绘制

    private func draw(ctx: GraphicsContext, size: CGSize) {
        let scale = size.height / height
        let panelHpx = size.height
        let panelWpx = displayPanelW * scale
        let gapPx = panelSpacing * scale

        drawAnatomy(
            ctx: ctx,
            polys: ANTERIOR,
            origin: CGPoint(x: 0, y: 0),
            panelSize: CGSize(width: panelWpx, height: panelHpx)
        )
        drawAnatomy(
            ctx: ctx,
            polys: POSTERIOR,
            origin: CGPoint(x: panelWpx + gapPx, y: 0),
            panelSize: CGSize(width: panelWpx, height: panelHpx)
        )
    }

    private func drawAnatomy(
        ctx: GraphicsContext,
        polys: [AnatomyPolygon],
        origin: CGPoint,
        panelSize: CGSize
    ) {
        let view = region.viewBox
        let scaleX = panelSize.width / AnatomyView.width
        let scaleY = panelSize.height / view.height
        let s = min(scaleX, scaleY)
        let drawW = AnatomyView.width * s
        let drawH = view.height * s
        let dx = origin.x + (panelSize.width - drawW) / 2
        let dy = origin.y + (panelSize.height - drawH) / 2

        // 圆角 — anatomy 单位 2.5 缩放到像素
        let cornerRadius = 2.5 * s

        // 静息(非绿)肌肉: 半透明白, 不是固定不透明灰 (owner). 底纹现在是会变化的 pastel 灰阶,
        // 固定 #2A 灰在某些背景灰度上会糊掉; 半透明白始终比"局部背景"亮固定一档 (screen 式加亮),
        // 任何灰阶上剪影都看得清 — 尤其是这些暗的非绿部分. 绿色高亮仍是最亮的焦点.
        let idleGray = Color.white.opacity(0.22)
        let synergistColor = color.opacity(0.35)
        let isCombinedMode = (opacityFor != nil) && !muscles.isEmpty
        for poly in polys {
            guard poly.points.count >= 3 else { continue }
            let fillColor: Color
            if poly.muscle == .fullBody {
                fillColor = idleGray
            } else if isCombinedMode, let opacityFor {
                let isSelected = expanded.contains(poly.muscle)
                let isSyn = !isSelected && synergistsExpanded.contains(poly.muscle)
                let op = opacityFor(poly.muscle) ?? 0
                if isSelected {
                    fillColor = op >= 0.95 ? Color.white : color
                } else if isSyn {
                    fillColor = synergistColor
                } else {
                    fillColor = op > 0 ? color.opacity(op) : idleGray
                }
            } else if let opacityFor {
                let op = opacityFor(poly.muscle) ?? 0
                fillColor = op > 0 ? color.opacity(op) : idleGray
            } else {
                let isHit = expanded.contains(poly.muscle)
                let isSyn = !isHit && synergistsExpanded.contains(poly.muscle)
                if isHit { fillColor = color }
                else if isSyn { fillColor = synergistColor }
                else { fillColor = idleGray }
            }
            let pts = poly.points.map { p -> CGPoint in
                CGPoint(
                    x: dx + p.x * s,
                    y: dy + (p.y - view.yMin) * s
                )
            }
            let path = roundedPolygonPath(pts, radius: cornerRadius)
            ctx.fill(path, with: .color(fillColor))
            // 暗灰描边 (0.25pt) 作为 sub-muscle 切分线. coarseOnly 模式下不画,
            // 同 major 的 polygon 视觉合并成一整块.
            if !coarseOnly {
                ctx.stroke(path, with: .color(Color(white: 0.122)), lineWidth: 0.25)
            }
        }
    }
}

// MARK: - 圆角 polygon helper

/// 给闭合多边形做圆角处理 — 每个顶点用 quadCurve 替换直角.
/// radius 单位 = 跟传入 pts 同一坐标系.
private func roundedPolygonPath(_ pts: [CGPoint], radius: CGFloat) -> Path {
    let n = pts.count
    var path = Path()
    guard n >= 3 else {
        if let first = pts.first { path.move(to: first) }
        for p in pts.dropFirst() { path.addLine(to: p) }
        path.closeSubpath()
        return path
    }
    var enterPoints: [CGPoint] = []
    var exitPoints: [CGPoint] = []
    for i in 0..<n {
        let prev = pts[(i + n - 1) % n]
        let cur = pts[i]
        let next = pts[(i + 1) % n]
        let dxPrev = prev.x - cur.x
        let dyPrev = prev.y - cur.y
        let dxNext = next.x - cur.x
        let dyNext = next.y - cur.y
        let lenPrev = max(0.0001, sqrt(dxPrev * dxPrev + dyPrev * dyPrev))
        let lenNext = max(0.0001, sqrt(dxNext * dxNext + dyNext * dyNext))
        let r = min(radius, min(lenPrev, lenNext) * 0.5)
        let enter = CGPoint(x: cur.x + dxPrev / lenPrev * r,
                            y: cur.y + dyPrev / lenPrev * r)
        let exit = CGPoint(x: cur.x + dxNext / lenNext * r,
                           y: cur.y + dyNext / lenNext * r)
        enterPoints.append(enter)
        exitPoints.append(exit)
    }
    path.move(to: exitPoints[0])
    for i in 0..<n {
        let next = (i + 1) % n
        path.addLine(to: enterPoints[next])
        path.addQuadCurve(to: exitPoints[next], control: pts[next])
    }
    path.closeSubpath()
    return path
}

// MARK: - Previews

#Preview("Full body — h 200") {
    BodyHint(muscles: [.chest, .frontDelts], height: 200)
        .padding()
        .background(MasoColor.background)
}

#Preview("Square slot — 100") {
    HStack(spacing: 16) {
        BodyHint(muscles: [.chest], height: 100, region: .full, square: true)
        BodyHint(muscles: [.hamstrings, .glutes], height: 100, region: .full, square: true)
        BodyHint(muscles: [.lats, .triceps], height: 100, region: .full, square: true)
    }
    .padding()
    .background(MasoColor.background)
}
