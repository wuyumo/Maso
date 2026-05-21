import SwiftUI

// 紧凑的双视图肌肉示意图 (正面 + 背面)
// DESIGN §3.1: 跟 web 端 BodyHint.tsx 1:1
//   - 用解剖图 polygon, 命中的肌肉用强调色, 其他灰底
//   - region 控制 viewBox 裁剪 (full / upper / lower)
//
// 关于 panel slot 一致性:
//   - 默认 (square=false): 每个 panel 宽度按 region viewBox 的自然 aspect 计算
//   - square=true:        每个 panel 锁定为 height × height (列表 / player 用)
//
// 防溢出:
//   - 用单 Canvas 绘制两个 panel + 中间 gap
//   - aspectRatio(contentMode: .fit) 让 BodyHint 跟随父容器宽度自动缩放
//   - height 是"理想"高度; 容器若不够宽, 整体等比缩小 (不会切到 body)
struct BodyHint: View {
    let muscles: [MuscleGroup]
    /// 协同肌 — 渲染成 35% 透明的 accent ("带到的肌肉"). 通常由 caller 用
    /// `MuscleSynergy.synergists(for: Set(muscles))` 算出再传进来.
    var synergists: [MuscleGroup] = []
    var color: Color = MasoColor.accent
    var height: CGFloat = 110
    var region: BodyRegion = .full
    /// true = 每个 panel 锁成 height × height 的正方形 slot
    var square: Bool = false
    /// 可选 per-muscle opacity 回调. 返回值含义:
    ///   - 1.0 / 0.7 / 0.4 ... → 用该 opacity 填 accent 色 (history 衰减模式)
    ///   - 0 / nil               → 走默认灰底 (idle)
    /// 传了这个 callback 后, `muscles` / `synergists` 参数被忽略 (caller 决定一切).
    var opacityFor: ((MuscleGroup) -> Double?)? = nil
    /// 可选 tap 回调 — 用户点击身体某块肌肉时触发. 没传则 BodyHint 是纯展示组件.
    /// hit-test 走 anatomy polygon 的 point-in-polygon 测试 (ray casting).
    var onMuscleTap: ((MuscleGroup) -> Void)? = nil
    /// "粗颗粒模式" — true 时不画 sub muscle 之间的细分描边, 让同一 major 的 polygon 视觉合并成一整块.
    /// 配合 Settings.muscleDetailEnabled = false 使用. fill 颜色不变 (caller 通常传 major,
    /// 由 expandAnatomyMuscles 展开到 sub fill 上, 视觉上一整块都点亮).
    var coarseOnly: Bool = false

    private var expanded: Set<MuscleGroup> { expandAnatomyMuscles(muscles) }
    /// 协同肌也走 `expandAnatomyMuscles` 展开 — 比如 synergist 包含 `triceps`,
    /// 展开后 tricepsLong/Lateral/Medial 三块都会被淡绿点亮.
    private var synergistsExpanded: Set<MuscleGroup> {
        // 排除已经是 primary 的, 避免冲突
        expandAnatomyMuscles(synergists).subtracting(expanded)
    }

    private static let panelGap: CGFloat = 6

    /// 单 panel 在 "理想 anatomy 坐标系" 下的宽度
    /// 注意:不带 height 缩放;由 Canvas 内部按 size 计算实际像素
    private var panelUnitWidth: CGFloat {
        if square {
            // square: 正方形 slot, 宽 = viewBox.height (= panel 显示高度 in anatomy 单位)
            return region.viewBox.height
        }
        // 非 square: 跟 viewBox 自然 aspect 一致 → 宽 = AnatomyView.width
        return AnatomyView.width
    }

    /// 两 panel + gap 在 anatomy 单位下的总宽
    /// gap 在 anatomy 单位下要换算 — 6 像素 / (height 像素 / viewBox.height 单位) = 6 * viewBox.height / height
    /// 简化: 我们直接在 Canvas 里以"显示像素"为基准画即可, 这里只算 aspect ratio
    private var displayPanelW: CGFloat {
        square ? height : height * (AnatomyView.width / region.viewBox.height)
    }
    private var displayTotalW: CGFloat {
        displayPanelW * 2 + Self.panelGap
    }
    /// w/h 自然比例 — 给 aspectRatio modifier 用
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

    /// 把 tap location 反推到 anatomy 坐标, 找到命中的肌肉.
    /// 路径: 屏幕像素 → 哪个 panel (anterior / posterior / gap) → 减去 centering offset →
    /// 除以 scale + 加 viewBox.yMin → anatomy 坐标 → 遍历 polygon point-in-polygon.
    private func hitTest(location p: CGPoint, canvasSize size: CGSize) -> MuscleGroup? {
        // 用 size.height 反推每 panel 的像素尺寸 (跟 draw() 里的逻辑一致)
        let scale = size.height / height
        let panelHpx = size.height
        let panelWpx = displayPanelW * scale
        let gapPx = Self.panelGap * scale
        let view = region.viewBox

        // 在 panel 内 anatomy 实际绘制区的 scale
        let scaleX = panelWpx / AnatomyView.width
        let scaleY = panelHpx / view.height
        let s = min(scaleX, scaleY)
        let drawW = AnatomyView.width * s
        let drawH = view.height * s

        if p.x < panelWpx {
            // anterior 面板
            let dx = (panelWpx - drawW) / 2
            let dy = (panelHpx - drawH) / 2
            let anatX = (p.x - dx) / s
            let anatY = (p.y - dy) / s + view.yMin
            return pointInPolygons(CGPoint(x: anatX, y: anatY), polys: ANTERIOR)
        } else if p.x > panelWpx + gapPx {
            // posterior 面板
            let originX = panelWpx + gapPx
            let dx = originX + (panelWpx - drawW) / 2
            let dy = (panelHpx - drawH) / 2
            let anatX = (p.x - dx) / s
            let anatY = (p.y - dy) / s + view.yMin
            return pointInPolygons(CGPoint(x: anatX, y: anatY), polys: POSTERIOR)
        }
        return nil  // gap, miss
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

    private func draw(ctx: GraphicsContext, size: CGSize) {
        // 实际 canvas 像素 = size; 计算每 panel 的像素尺寸
        // 渲染区按 aspectRatio.fit 给出 — size 已经匹配比例 (size.width / size.height == aspectRatio)
        // 所以 panelHeightPx = size.height, gapPx 按比例缩放
        let scale = size.height / height
        let panelHpx = size.height
        let panelWpx = displayPanelW * scale
        let gapPx = Self.panelGap * scale

        // 前面 (anterior) — 左 panel
        drawAnatomy(
            ctx: ctx,
            polys: ANTERIOR,
            origin: CGPoint(x: 0, y: 0),
            panelSize: CGSize(width: panelWpx, height: panelHpx)
        )
        // 背面 (posterior) — 右 panel
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

        // 圆角半径 — anatomy 单位下 2.5, 比 web 端 1.4 更柔和.
        // 转到 pixel 坐标乘以 scale.
        let cornerRadius = 2.5 * s

        let idleGray = Color(red: 0.165, green: 0.165, blue: 0.165)  // #2A2A2A
        // 协同肌的填色 — 35% 透明的 accent, 跟 web 的 rgba(30,215,96,0.35) 对齐.
        // 用 opacity 表达即可, Canvas 会做 alpha blend.
        let synergistColor = color.opacity(0.35)
        // 是否复合模式 (decay 底 + selected overlay) — caller 同时传 opacityFor 和 muscles 时启用
        let isCombinedMode = (opacityFor != nil) && !muscles.isEmpty
        for poly in polys {
            guard poly.points.count >= 3 else { continue }
            let fillColor: Color
            if poly.muscle == .fullBody {
                fillColor = idleGray
            } else if isCombinedMode, let opacityFor {
                // 复合模式: 衰减底 + 选中 overlay.
                // - 选中 + 满 opacity (刚练完) → 白色警告
                // - 选中 + 部分衰减 → accent (正常选中)
                // - 协同肌 → synergistColor
                // - 未选 → 衰减 opacity (history mode 同款)
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
                // 纯衰减模式 (没 selected): caller 决定每个 muscle 的 opacity.
                let op = opacityFor(poly.muscle) ?? 0
                fillColor = op > 0 ? color.opacity(op) : idleGray
            } else {
                let isHit = expanded.contains(poly.muscle)
                let isSyn = !isHit && synergistsExpanded.contains(poly.muscle)
                if isHit {
                    fillColor = color
                } else if isSyn {
                    fillColor = synergistColor
                } else {
                    fillColor = idleGray
                }
            }
            let pts = poly.points.map { p -> CGPoint in
                CGPoint(
                    x: dx + p.x * s,
                    y: dy + (p.y - view.yMin) * s
                )
            }
            let path = roundedPolygonPath(pts, radius: cornerRadius)
            ctx.fill(path, with: .color(fillColor))
            // 粗颗粒模式下不画描边 → sub 之间的分隔线消失, 同一 major 的 polygon 视觉合并成一整块.
            // 默认模式画 0.25pt 暗灰描边, 暴露解剖学分区给追求精度的用户.
            if !coarseOnly {
                ctx.stroke(path, with: .color(Color(white: 0.122)), lineWidth: 0.25)
            }
        }
    }
}

/// 给闭合多边形做圆角处理 — 每个顶点用 quadCurve 替换直角 (跟 web 端 roundedPath 等效)
/// radius 单位 = 跟传入 pts 同一坐标系
///
/// v3.5 起 anatomy 数据用 sub polygon 共享 major 外轮廓 vertex (而不是 splitHorizontalY 切片),
/// 所以不再需要识别"水平切割边". 每个顶点统一施加圆角 (受相邻 edge 长度限制).
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

#Preview("Full body — h 200 (container wide)") {
    BodyHint(muscles: [.chest, .frontDelts], height: 200)
        .padding()
        .background(MasoColor.background)
}

#Preview("Constrained narrow container") {
    // 模拟容器很窄 — BodyHint 应自动缩小
    BodyHint(muscles: [.chest, .frontDelts], height: 200)
        .frame(width: 120)
        .padding()
        .background(MasoColor.background)
}

#Preview("Player slot — square 72") {
    HStack(spacing: 16) {
        BodyHint(muscles: [.chest], height: 72, region: .upper, square: true)
        BodyHint(muscles: [.hamstrings], height: 72, region: .lower, square: true)
        BodyHint(muscles: [.chest, .hamstrings], height: 72, region: .full, square: true)
    }
    .padding()
    .background(MasoColor.background)
}
