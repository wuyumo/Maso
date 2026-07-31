import SwiftUI

// 肌肉恢复详情 — 点 Today 顶部肌肉图打开.
//
// 用系统默认控件搭 (owner 拍板): NavigationStack + 系统导航栏按钮 + .segmented Picker +
// .borderedProminent 按钮. 除了人体图本身 (自绘 Canvas) 不做自定义样式.
//
// 跟 MuscleStatusOverviewCard (那张小图) 的区别:
//   - 单面板 (正面 / 背面切换), 不再前后并排挤在正方形 slot 里
//   - 只有 "Heavy fatigue" 一档引一条虚线折线指到该档最累的那块肌肉 (owner: 其余三档不画线)
//
// 分档精度跟卡片同一个 gate: 免费 = coarseOnly + 图例模糊 + 解锁入口 (不画引线),
// Pro = 精细逐肌群 + 引线.
struct MuscleMapDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    let fatigueMap: [MuscleGroup: Double]
    let gapMuscles: [MuscleGroup]
    let onStartGapWorkout: () -> Void
    var onUnlock: () -> Void = {}

    @State private var showBack = false

    /// 引线代表点的候选池 (自上而下) — 故意不是 polygon 里的全部 muscle:
    /// 颈 / 内收 / 胫前 / 比目鱼 / 臀中 这些块太小, 当代表点读不出东西.
    private static let frontCandidates: [MuscleGroup] = [
        .frontDelts, .chest, .biceps, .abs, .obliques, .forearms, .quads
    ]
    private static let backCandidates: [MuscleGroup] = [
        .upperTraps, .rearDelts, .upperLats, .triceps, .lowerBack, .glutes, .hamstrings, .calves
    ]

    var body: some View {
        let isPro = data.settings.isPro
        NavigationStack {
            VStack(spacing: 18) {
                AnnotatedBodyMap(
                    polys: showBack ? POSTERIOR : ANTERIOR,
                    candidates: showBack ? Self.backCandidates : Self.frontCandidates,
                    fatigueMap: fatigueMap,
                    coarseOnly: isPro ? !data.settings.muscleDetailEnabled : true,
                    showLeader: isPro && !fatigueMap.isEmpty,
                    blurLegend: !isPro
                )
                // 弹性高度: medium 档约 240 (留白够), 上拖到 large 时长到 380 (owner: 全屏时图要大一点).
                .frame(minHeight: 190, maxHeight: 380)
                // 换面板 = 重建, 清掉上一面板选中的肌肉 (它在这一面板没有 polygon, 引线会消失).
                .id(showBack)

                // ⚠️ key 不能直接用 "Back" —— 那个 key 已被导航的"返回"占用 (见 MuscleGroup.swift
                //    同款注释), 中文会显示成"返回". 用独立的 Body front / Body back.
                Picker("", selection: $showBack) {
                    Text("Body front").tag(false)
                    Text("Body back").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)

                if !isPro {
                    // 图例被模糊, 这里给解锁入口 (跟卡上那颗 "Unlock per-muscle recovery" 同款).
                    Button("Unlock per-muscle recovery with Pro", systemImage: "lock.fill") {
                        dismiss(); onUnlock()
                    }
                    .buttonStyle(.bordered)
                }

                primaryCTA
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxHeight: .infinity, alignment: .center)
            .navigationTitle("Muscle Status")
            .navigationBarTitleDisplayMode(.inline)
            // 跟 HistoryScreen 的 session 详情 sheet / SettingsScreen 同一套工具栏写法.
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { shareButton }
                ToolbarItem(placement: .confirmationAction) {
                    // .tint(MasoColor.text) = 白色 Done, 跟 SettingsScreen 一致
                    // (app 的 AccentColor 资源是品牌绿, 不覆盖会是绿的).
                    Button("Done") { dismiss() }
                        .tint(MasoColor.text)
                }
            }
        }
        // 标准 sheet 尺寸, 不是整页 (owner). 需要看细节可以上拖到 large.
        .presentationDetents([.medium, .large])
        // ⚠️ 别漏 — 不挂这个的 sheet 会用系统半透明材质, 底下 TabBar 玻璃会透上来变成一条色带.
        .presentationBackground(MasoColor.background)
    }

    /// 底部主 CTA — 规格照抄 PlansScreen.startWorkoutCTA ("Start workout" 那颗大胶囊),
    /// 全 app 主操作按钮共用这一套: 包住内容的胶囊 + accent 玻璃底 + 黑字.
    @ViewBuilder
    private var primaryCTA: some View {
        if gapMuscles.isEmpty {
            Label("All caught up", systemImage: "checkmark.circle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
        } else {
            Button {
                dismiss(); onStartGapWorkout()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "play.fill")
                        .font(.system(size: 14, weight: .heavy))
                    Text("Train the gaps")
                        .font(.system(size: 15, weight: .heavy))
                }
                .padding(.vertical, 13)
                .padding(.horizontal, 28)
                .foregroundStyle(.black)
                .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.85), fallback: MasoColor.accent)
                .shadow(color: systemGlassAvailable ? .clear : .black.opacity(0.3), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
        }
    }

    /// 分享 — 复用 MuscleStatusShareCard, 口径跟 MuscleStatusOverviewCard.shareButton 一致.
    /// label 规格照抄 HistoryScreen session 详情 sheet 的分享按钮.
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
            // 规格跟 HistoryScreen session 详情 sheet 的分享按钮一致.
            label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(MasoColor.textDim)
            }
        )
        .accessibilityLabel("Share")
    }
}

// MARK: - 单面板 + Heavy fatigue 引线

/// 单面板人体图 (正面**或**背面) + 四档图例.
/// 只有最累那档 (Heavy fatigue) 引一条虚线折线到该档最累的肌肉 —— 其余三档只做色块图例
/// (owner: 四根线太满, 只留最需要提醒的那根).
///
/// 为什么不复用 BodyHint: BodyHint 恒画前后两个 panel, 且引线需要跟 polygon 共享同一套
/// 坐标变换 (才能把线钉在肌肉上). 这里自己画一个 panel, 变换公式跟 BodyHint.drawAnatomy 同源.
private struct AnnotatedBodyMap: View {
    let polys: [AnatomyPolygon]
    /// 引线代表点的候选池 (自上而下).
    let candidates: [MuscleGroup]
    let fatigueMap: [MuscleGroup: Double]
    let coarseOnly: Bool
    let showLeader: Bool
    let blurLegend: Bool

    /// 用户点中的肌肉 — 连线的起点. nil = 还没点过, 用默认 (最累那块).
    /// ⚠️ 前后切换要清空, 否则会留着上一面板没有的肌肉 → 引线消失.
    /// 由调用方给本 view 挂 `.id(showBack)` 重建来清 (见 MuscleMapDetailSheet).
    @State private var selected: MuscleGroup? = nil

    /// 四档色块 (自上而下 = 累 → 没练), 跟 MasoColor.recoveryHeatStyle 逐一对齐.
    /// 第 0 档 (.fatigued) 是唯一画引线的那档.
    private static let tiers: [(swatch: Color, label: String, tier: MuscleStatusCompute.RecoveryTier)] = [
        (MasoColor.accent.opacity(1.00), "Heavy fatigue", .fatigued),
        (MasoColor.accent.opacity(0.60), "Recovering", .recovering),
        (MasoColor.accent.opacity(0.30), "Mostly recovered", .mostlyRecovered),
        (Color(red: 0.165, green: 0.165, blue: 0.165), "Fresh", .fresh),
    ]

    private let chipW: CGFloat = 132
    private let gutter: CGFloat = 16
    /// 折线两端的水平短脚 — 有这段"出脚"才像标注引线, 不是一根斜杠.
    private let stub: CGFloat = 13

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let bodyW = min(H * (AnatomyView.width / AnatomyView.height) * 1.05,
                            max(70, geo.size.width - chipW - gutter))
            let bodyX = max(0, (geo.size.width - chipW - gutter - bodyW) / 2)
            let chipX = geo.size.width - chipW
            let chipYs = (0..<Self.tiers.count).map { i in H * (0.14 + 0.24 * CGFloat(i)) }

            // 连线的那块肌肉: 用户点过就是点的那块, 没点过默认最累的那块.
            let linked = selected ?? representative(for: .fatigued)

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let t = transform(bodyX: bodyX, bodyW: bodyW, H: H)
                    drawBody(ctx: ctx, t: t)
                    guard showLeader,
                          let m = linked,
                          let a = anchorPoint(for: m, t: t),
                          let i = tierIndex(of: m) else { return }
                    let end = CGPoint(x: chipX - 6, y: chipYs[i])
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
                    ctx.fill(Path(ellipseIn: CGRect(x: a.x - 2.5, y: a.y - 2.5, width: 5, height: 5)),
                             with: .color(color.opacity(0.95)))
                }
                // 点身体任意一块肌肉 → 连线换到那块 (owner: 点哪里就在哪里连线, 全图始终只有一根).
                // 图例那层挂了 allowsHitTesting(false), 点击能穿过去, 所以这个手势收得到整块区域.
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { loc in
                    guard showLeader else { return }
                    let t = transform(bodyX: bodyX, bodyW: bodyW, H: H)
                    if let m = muscleAt(loc, t: t) {
                        withAnimation(.easeInOut(duration: 0.18)) { selected = m }
                    }
                }

                // 四档色块 — 用 .position 钉在跟 Canvas 同一坐标系的点上 (引线终点要对得上).
                ForEach(Array(Self.tiers.enumerated()), id: \.offset) { i, t in
                    HStack(spacing: 8) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(t.swatch)
                            .frame(width: 11, height: 11)
                        Text(LocalizedStringKey(t.label))
                            .font(.caption2)
                            .foregroundStyle(MasoColor.text)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .frame(width: chipW, alignment: .leading)
                    .position(x: chipX + chipW / 2, y: chipYs[i])
                }
                .blur(radius: blurLegend ? 4.5 : 0)
                .allowsHitTesting(false)
            }
        }
    }

    /// 这块肌肉落在四档里的第几档 (= 引线该连到哪一行图例).
    private func tierIndex(of m: MuscleGroup) -> Int? {
        let tier = MuscleStatusCompute.tierFor(muscle: m, fatigueMap: fatigueMap)
        return Self.tiers.firstIndex { $0.tier == tier }
    }

    /// 点击命中: 屏幕点 → anatomy 坐标 → 反向遍历 polygon (后画的在上层优先命中), 跳过装饰头.
    private func muscleAt(_ p: CGPoint, t: T) -> MuscleGroup? {
        let a = CGPoint(x: (p.x - t.dx) / t.s, y: (p.y - t.dy) / t.s)
        for poly in polys.reversed()
        where poly.muscle != .fullBody && poly.points.count >= 3 {
            if pointInside(a, poly.points) { return poly.muscle }
        }
        return nil
    }

    /// 该档的代表肌肉 = 候选池里落在这一档、且 fatigue 最高的那块.
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
