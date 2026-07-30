import SwiftUI

// 肌肉恢复详情 — 点 Today 顶部肌肉图打开.
//
// 跟 MuscleStatusOverviewCard (那张小图) 的区别:
//   - 单面板放大 (正面 / 背面切换), 不再前后并排挤在正方形 slot 里
//   - 每档图例引**一条**虚线折线到该档里最有代表性的那块肌肉 → 不用对照色块猜.
//     (owner: 每块肌肉都引线太满, 图例只要一根线; 直线太呆板, 用折线虚线.)
//   - 顶部 [分享] ——— [完成], 底部单独一条 Train the gaps 主 CTA
//
// 分档精度 (引线 + 四档图例) 跟卡片同一个 gate: 免费 = coarseOnly 大图 + 锁住的图例,
// Pro = 精细逐肌群 + 引线. 免费用户点进来仍拿到"更大的图 + 前后切换 + CTA", 不是空页.
struct MuscleMapDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let fatigueMap: [MuscleGroup: Double]
    let gapMuscles: [MuscleGroup]
    let onStartGapWorkout: () -> Void
    var onUnlock: () -> Void = {}

    @State private var showBack = false

    /// 引线的候选肌肉 (自上而下) — 故意不是 polygon 里的全部 muscle:
    /// 颈 / 内收 / 胫前 / 比目鱼 / 臀中 这些块太小, 当代表点读不出东西.
    private static let frontCandidates: [MuscleGroup] = [
        .frontDelts, .chest, .biceps, .abs, .obliques, .forearms, .quads
    ]
    private static let backCandidates: [MuscleGroup] = [
        .upperTraps, .rearDelts, .upperLats, .triceps, .lowerBack, .glutes, .hamstrings, .calves
    ]

    var body: some View {
        let isPro = data.settings.isPro
        // 留白优先: 不用 ScrollView + 固定高度堆叠 (owner 报"界面太满"), 改成
        // 撐满 large detent, 靠 Spacer 把 map / 切换 / CTA 三块拉开.
        VStack(spacing: 0) {
            topBar

            Spacer(minLength: 16)

            AnnotatedBodyMap(
                polys: showBack ? POSTERIOR : ANTERIOR,
                candidates: showBack ? Self.backCandidates : Self.frontCandidates,
                fatigueMap: fatigueMap,
                coarseOnly: isPro ? !data.settings.muscleDetailEnabled : true,
                showLeaders: isPro && !fatigueMap.isEmpty,
                blurLegend: !isPro
            )
            .frame(maxHeight: .infinity)

            Spacer(minLength: 28)

            sideToggle

            Spacer(minLength: 28)

            if !isPro {
                // 图例被模糊, 这里给解锁入口 (跟卡上那颗 "Unlock per-muscle recovery" 同款).
                Button(action: { dismiss(); onUnlock() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 11, weight: .heavy))
                        Text("Unlock per-muscle recovery with Pro")
                            .font(.system(size: 12, weight: .heavy))
                    }
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                  fallback: MasoColor.accent.opacity(0.16))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 20)
            }

            primaryCTA
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
        .padding(.bottom, 30)
        .background(MasoColor.background)
        // large — 留白是 owner 明确要的, 内容摊在整屏上比塞在 0.66 里舒服.
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        // ⚠️ 别漏 — 不挂这个的 sheet 会用系统半透明材质, 底下 TabBar 玻璃会透上来变成一条色带.
        .presentationBackground(MasoColor.background)
    }

    /// 顶栏: [分享] ——— 标题 ——— [完成] (owner 指定分享在左上, 完成在右上).
    private var topBar: some View {
        ZStack {
            Text("Muscle Status")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MasoColor.text)
            HStack {
                shareButton
                Spacer()
                Button(action: { dismiss() }) {
                    Text("Done")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(MasoColor.accent)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(height: 34)
    }

    /// 正面 / 背面切换 — 两段胶囊, 选中段填 accent 低浓度.
    private var sideToggle: some View {
        HStack(spacing: 0) {
            segment(title: "Front view", selected: !showBack) { showBack = false }
            segment(title: "Back view", selected: showBack) { showBack = true }
        }
        .padding(3)
        .background(MasoColor.surface, in: Capsule())
    }

    private func segment(title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: { withAnimation(.easeInOut(duration: 0.18)) { action() } }) {
            Text(LocalizedStringKey(title))
                .font(.system(size: 13, weight: .heavy))
                .foregroundStyle(selected ? MasoColor.accent : MasoColor.textDim)
                .padding(.horizontal, 24)
                .padding(.vertical, 9)
                .background {
                    if selected {
                        Capsule().fill(MasoColor.accent.opacity(0.16))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// 底部主 CTA — 满宽 Train the gaps (owner 指定放最下面).
    /// 没 gap (健康状态) → 正向"全部跟上"标签, 不给一颗点不动的按钮.
    @ViewBuilder
    private var primaryCTA: some View {
        if gapMuscles.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .heavy))
                Text("All caught up")
                    .font(.system(size: 14, weight: .heavy))
            }
            .foregroundStyle(MasoColor.textDim)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        } else {
            Button(action: { dismiss(); onStartGapWorkout() }) {
                HStack(spacing: 7) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .heavy))
                    Text("Train the gaps")
                        .font(.system(size: 15, weight: .heavy))
                }
                .foregroundStyle(MasoColor.accent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                              fallback: MasoColor.accent.opacity(0.16))
            }
            .buttonStyle(.plain)
        }
    }

    /// 分享 — 复用 MuscleStatusShareCard, 口径跟 MuscleStatusOverviewCard.shareButton 一致.
    private var shareButton: some View {
        let isPro = data.settings.isPro
        let coarse = isPro ? !data.settings.muscleDetailEnabled : true
        let fatigue = fatigueMap
        let cal = Calendar.current
        let cutoff = cal.startOfDay(for: cal.date(byAdding: .day, value: -6, to: Date())!)
        let weekSets = data.sets.filter { $0.performedAt >= cutoff }
        let days = Set(weekSets.map { cal.startOfDay(for: $0.performedAt) }).count
        var sections = Set<MuscleGroup>()
        for set in weekSets {
            guard let ex = data.exById[set.exerciseId] else { continue }
            for m in ex.muscleGroups where m.section != nil {
                sections.insert(m.section!)
            }
        }
        let sectionsHit = sections.count
        return ShareImageButton(
            previewTitle: NSLocalizedString("Muscle Status", comment: ""),
            defaultSections: ShareSections(),
            shareContent: { photo, onTapAdd, _ in
                MuscleStatusShareCard(
                    muscleStyle: { m in MasoColor.recoveryHeatStyle(muscle: m, fatigueMap: fatigue) },
                    workoutsThisWeek: days,
                    totalSetsThisWeek: weekSets.count,
                    muscleSectionsHit: sectionsHit,
                    coarseOnly: coarse,
                    userPhoto: photo,
                    onTapAddPhoto: onTapAdd
                )
            },
            shareSurface: "muscle_status_detail",
            label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(width: 32, height: 32)
                    .glassCircleButtonBackground()
            }
        )
        .accessibilityLabel("Share")
    }
}

// MARK: - 单面板 + 每档一根引线

/// 单面板人体图 (正面**或**背面) + 每档图例一根虚线折线指到该档的代表肌肉.
///
/// 为什么不复用 BodyHint: BodyHint 恒画前后两个 panel, 且引线需要跟 polygon 共享同一套
/// 坐标变换 (才能把线钉在肌肉上). 这里自己画一个 panel, 变换公式跟 BodyHint.drawAnatomy 同源.
private struct AnnotatedBodyMap: View {
    let polys: [AnatomyPolygon]
    /// 引线代表点的候选池 (自上而下), 每档从里面挑一块.
    let candidates: [MuscleGroup]
    let fatigueMap: [MuscleGroup: Double]
    let coarseOnly: Bool
    let showLeaders: Bool
    let blurLegend: Bool

    /// 四档色块 (自上而下 = 累 → 没练), 跟 MasoColor.recoveryHeatStyle 逐一对齐.
    private static let tiers: [(swatch: Color, label: String, tier: MuscleStatusCompute.RecoveryTier)] = [
        (MasoColor.accent.opacity(1.00), "Heavy fatigue", .fatigued),
        (MasoColor.accent.opacity(0.60), "Recovering", .recovering),
        (MasoColor.accent.opacity(0.30), "Mostly recovered", .mostlyRecovered),
        (Color(red: 0.165, green: 0.165, blue: 0.165), "Fresh", .fresh),
    ]

    private let chipW: CGFloat = 138
    private let gutter: CGFloat = 18
    /// 折线两端的水平短脚 — 有这段"出脚"才像标注引线, 不是一根斜杠.
    private let stub: CGFloat = 15

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let bodyW = min(H * (AnatomyView.width / AnatomyView.height) * 1.05,
                            max(80, geo.size.width - chipW - gutter))
            let bodyX = max(0, (geo.size.width - chipW - gutter - bodyW) / 2)
            let chipX = geo.size.width - chipW
            let chipYs = (0..<Self.tiers.count).map { i in H * (0.14 + 0.24 * CGFloat(i)) }
            // 每档挑一个代表肌肉 (owner: 图例只要一根线). 该档在本面板没有肌肉 → 不画线 + 色块压暗.
            let reps = Self.tiers.map { representative(for: $0.tier) }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let t = transform(bodyX: bodyX, bodyW: bodyW, H: H)
                    drawBody(ctx: ctx, t: t)
                    guard showLeaders else { return }
                    for (i, rep) in reps.enumerated() {
                        guard let m = rep, let a = anchorPoint(for: m, t: t) else { continue }
                        let end = CGPoint(x: chipX - 7, y: chipYs[i])
                        let color = Self.tiers[i].swatch
                        // 折线: 肌肉侧短横脚 → 斜段 → 图例侧短横脚.
                        var p = Path()
                        p.move(to: a)
                        p.addLine(to: CGPoint(x: a.x + stub, y: a.y))
                        p.addLine(to: CGPoint(x: end.x - stub, y: end.y))
                        p.addLine(to: end)
                        ctx.stroke(p, with: .color(color.opacity(0.7)),
                                   style: StrokeStyle(lineWidth: 1, lineCap: .round,
                                                      lineJoin: .round, dash: [2.5, 3.5]))
                        ctx.fill(Path(ellipseIn: CGRect(x: a.x - 2.5, y: a.y - 2.5,
                                                        width: 5, height: 5)),
                                 with: .color(color.opacity(0.95)))
                    }
                }

                // 四档色块 — 引线的终点. 用 .position 钉在跟 Canvas 同一坐标系的点上.
                ForEach(Array(Self.tiers.enumerated()), id: \.offset) { i, t in
                    let present = reps[i] != nil || !showLeaders
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(t.swatch)
                            .frame(width: 12, height: 12)
                        Text(LocalizedStringKey(t.label))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .opacity(present ? 1 : 0.35)
                    .frame(width: chipW, alignment: .leading)
                    .position(x: chipX + chipW / 2, y: chipYs[i])
                }
                .blur(radius: blurLegend ? 4.5 : 0)
                .allowsHitTesting(false)
            }
        }
    }

    /// 该档的代表肌肉 = 候选池里落在这一档、且 fatigue 最高的那块
    /// (.fresh 档 fatigue 都 ~0 → 自然退化成候选池里最靠前的一块, 顺序即显眼度).
    private func representative(for tier: MuscleStatusCompute.RecoveryTier) -> MuscleGroup? {
        var best: MuscleGroup? = nil
        var bestFatigue = -1.0
        for m in candidates
        where MuscleStatusCompute.tierFor(muscle: m, fatigueMap: fatigueMap) == tier {
            let f = fatigueMap[m] ?? 0
            if f > bestFatigue { bestFatigue = f; best = m }
        }
        return best
    }

    // MARK: 坐标变换 (跟 BodyHint.drawAnatomy 同源)

    private struct T { let s: CGFloat; let dx: CGFloat; let dy: CGFloat }

    private func transform(bodyX: CGFloat, bodyW: CGFloat, H: CGFloat) -> T {
        let s = min(bodyW / AnatomyView.width, H / AnatomyView.height)
        return T(s: s,
                 dx: bodyX + (bodyW - AnatomyView.width * s) / 2,
                 dy: (H - AnatomyView.height * s) / 2)
    }

    private func drawBody(ctx: GraphicsContext, t: T) {
        let idleGray = Color.white.opacity(0.22)
        for poly in polys where poly.points.count >= 3 {
            let fill: Color
            if poly.muscle == .fullBody {
                fill = idleGray
            } else if let (c, o) = MasoColor.recoveryHeatStyle(muscle: poly.muscle, fatigueMap: fatigueMap) {
                fill = c.opacity(o)
            } else {
                fill = idleGray
            }
            let pts = poly.points.map { CGPoint(x: t.dx + $0.x * t.s, y: t.dy + $0.y * t.s) }
            let path = roundedPolygonPath(pts, radius: 2.5 * t.s)
            ctx.fill(path, with: .color(fill))
            if !coarseOnly {
                ctx.stroke(path, with: .color(Color(white: 0.122)), lineWidth: 0.25)
            }
        }
    }

    /// 引线起点 = 该肌肉**最右侧**那块 polygon 的**内部**代表点.
    /// 取最右 (而不是所有 polygon 合并) 是为了让线从靠图例那一侧出发, 不横穿身体.
    /// ⚠️ 不能用包围盒中心: 斜方肌 / 阔背这类 L 形或凹多边形, bbox 中心会落在肌肉**外面**
    ///    (实测斜方的点跑到旁边灰色的后束上, "Heavy fatigue" 指了一块没练的肌肉).
    private func anchorPoint(for m: MuscleGroup, t: T) -> CGPoint? {
        var bestPts: [CGPoint]? = nil
        var bestX = -CGFloat.infinity
        for poly in polys where poly.muscle == m && poly.points.count >= 3 {
            let xs = poly.points.map(\.x)
            let cx = (xs.min()! + xs.max()!) / 2
            if cx > bestX { bestX = cx; bestPts = poly.points }
        }
        guard let pts = bestPts, let p = interiorPoint(of: pts) else { return nil }
        return CGPoint(x: t.dx + p.x * t.s, y: t.dy + p.y * t.s)
    }
}

// MARK: - polygon 内部代表点

/// 面积质心; 若质心落在凹多边形外面, 沿"质心→各顶点"收 50% 再试, 取最靠右的可行点.
private func interiorPoint(of pts: [CGPoint]) -> CGPoint? {
    guard pts.count >= 3 else { return nil }
    var a: CGFloat = 0, cx: CGFloat = 0, cy: CGFloat = 0
    for i in 0..<pts.count {
        let p = pts[i], q = pts[(i + 1) % pts.count]
        let cross = p.x * q.y - q.x * p.y
        a += cross
        cx += (p.x + q.x) * cross
        cy += (p.y + q.y) * cross
    }
    if abs(a) > 0.0001 {
        let c = CGPoint(x: cx / (3 * a), y: cy / (3 * a))
        if pointInside(c, pts) { return c }
        // 质心在外 → 朝各顶点收一半找落在内部的点, 取最右那个 (线从靠图例一侧出发).
        var best: CGPoint? = nil
        for v in pts {
            let cand = CGPoint(x: (c.x + v.x) / 2, y: (c.y + v.y) / 2)
            if pointInside(cand, pts), best == nil || cand.x > best!.x { best = cand }
        }
        if let best { return best }
    }
    let xs = pts.map(\.x), ys = pts.map(\.y)
    return CGPoint(x: (xs.min()! + xs.max()!) / 2, y: (ys.min()! + ys.max()!) / 2)
}

/// 标准 ray-casting (BodyHint 里那份是 private 实例方法, 这里独立一份, 逻辑相同).
private func pointInside(_ p: CGPoint, _ polygon: [CGPoint]) -> Bool {
    var inside = false
    var j = polygon.count - 1
    for i in 0..<polygon.count {
        let pi = polygon[i], pj = polygon[j]
        if (pi.y > p.y) != (pj.y > p.y) {
            let x = pi.x + (p.y - pi.y) * (pj.x - pi.x) / (pj.y - pi.y)
            if p.x < x { inside.toggle() }
        }
        j = i
    }
    return inside
}
