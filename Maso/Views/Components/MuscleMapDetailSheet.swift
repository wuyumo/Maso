import SwiftUI

// 肌肉恢复详情 — 点 Today 顶部肌肉图打开.
//
// 跟 MuscleStatusOverviewCard (那张小图) 的区别:
//   - 单面板放大 (正面 / 背面切换), 不再前后并排挤在正方形 slot 里
//   - 肌肉上引一条线到右侧四档色块 → 不用对照图例猜, 直接读"这块肌肉在哪一档"
//   - 底部沿用同一组 CTA (Train the gaps / Share), 语义跟卡上一致
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

    /// 画引线的肌肉 (自上而下) — 故意不是 polygon 里的全部 muscle:
    /// 颈 / 内收 / 胫前 / 比目鱼 / 臀中 这些块太小, 引线挤成一团反而读不出东西.
    private static let frontAnnotated: [MuscleGroup] = [
        .frontDelts, .chest, .biceps, .abs, .obliques, .forearms, .quads
    ]
    private static let backAnnotated: [MuscleGroup] = [
        .upperTraps, .rearDelts, .upperLats, .triceps, .lowerBack, .glutes, .hamstrings, .calves
    ]

    var body: some View {
        let isPro = data.settings.isPro
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 20) {
                    AnnotatedBodyMap(
                        polys: showBack ? POSTERIOR : ANTERIOR,
                        annotated: showBack ? Self.backAnnotated : Self.frontAnnotated,
                        fatigueMap: fatigueMap,
                        coarseOnly: isPro ? !data.settings.muscleDetailEnabled : true,
                        showLeaders: isPro && !fatigueMap.isEmpty,
                        blurLegend: !isPro
                    )
                    .frame(height: 330)
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    sideToggle

                    if !isPro {
                        // 图例被模糊, 这里给解锁入口 (跟卡上那颗 "Unlock per-muscle recovery" 同款).
                        Button(action: { dismiss(); onUnlock() }) {
                            HStack(spacing: 5) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 11, weight: .heavy))
                                Text("Unlock per-muscle recovery with Pro")
                                    .font(.system(size: 12, weight: .heavy))
                            }
                            .foregroundStyle(MasoColor.accent)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                          fallback: MasoColor.accent.opacity(0.16))
                        }
                        .buttonStyle(.plain)
                    }

                    actionRow
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    Spacer(minLength: 20)
                }
                .padding(.top, 12)
            }
        }
        .background(MasoColor.background)
        // 内容自然高 ≈ header 44 + map 330 + toggle 46 + CTA 44 + 间距 ≈ 560pt.
        // 不给 detent 会占满 large → 底下一大片死白; 0.72 刚好贴住 CTA 行, 仍可上拖到 large.
        .presentationDetents([.fraction(0.66), .large])
        .presentationDragIndicator(.visible)
        // ⚠️ 别漏 — 不挂这个的 sheet 会用系统半透明材质, 底下 TabBar 玻璃会透上来变成一条色带.
        .presentationBackground(MasoColor.background)
    }

    private var header: some View {
        HStack {
            Text("Muscle Status")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(MasoColor.text)
            Spacer()
            Button(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(MasoColor.textDim)
                    .frame(width: 30, height: 30)
                    .glassCircleButtonBackground()
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.top, 14)
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
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background {
                    if selected {
                        Capsule().fill(MasoColor.accent.opacity(0.16))
                    }
                }
        }
        .buttonStyle(.plain)
    }

    /// 底部动作行 — 跟卡片同结构: [Train the gaps / All caught up] ——— [Share].
    private var actionRow: some View {
        HStack(spacing: 10) {
            if gapMuscles.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .heavy))
                    Text("All caught up")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(MasoColor.textDim)
            } else {
                Button(action: { dismiss(); onStartGapWorkout() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 12, weight: .heavy))
                        Text("Train the gaps")
                            .font(.system(size: 13, weight: .heavy))
                    }
                    .foregroundStyle(MasoColor.accent)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25),
                                                  fallback: MasoColor.accent.opacity(0.16))
                }
                .buttonStyle(.plain)
            }
            Spacer(minLength: 0)
            shareButton
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
                HStack(spacing: 6) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Share")
                        .font(.system(size: 13, weight: .heavy))
                }
                .foregroundStyle(MasoColor.textDim)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .glassCapsuleButtonBackground()
            }
        )
        .accessibilityLabel("Share")
    }
}

// MARK: - 单面板 + 引线

/// 单面板人体图 (正面**或**背面) + 从肌肉引线到右侧四档色块.
///
/// 为什么不复用 BodyHint: BodyHint 恒画前后两个 panel, 且引线需要跟 polygon 共享同一套
/// 坐标变换 (才能把线钉在肌肉上). 这里自己画一个 panel, 变换公式跟 BodyHint.drawAnatomy 同源.
private struct AnnotatedBodyMap: View {
    let polys: [AnatomyPolygon]
    let annotated: [MuscleGroup]
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

    private let chipW: CGFloat = 132
    private let gutter: CGFloat = 14

    var body: some View {
        GeometryReader { geo in
            let H = geo.size.height
            let bodyW = min(H * (AnatomyView.width / AnatomyView.height) * 1.05,
                            max(80, geo.size.width - chipW - gutter))
            let bodyX = max(0, (geo.size.width - chipW - gutter - bodyW) / 2)
            let chipXs = geo.size.width - chipW
            let chipYs = (0..<Self.tiers.count).map { i in
                H * (0.14 + 0.24 * CGFloat(i))
            }

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    let t = transform(bodyX: bodyX, bodyW: bodyW, H: H)
                    drawBody(ctx: ctx, t: t)
                    guard showLeaders else { return }
                    for m in annotated {
                        guard let anchor = anchorPoint(for: m, t: t) else { continue }
                        let tier = MuscleStatusCompute.tierFor(muscle: m, fatigueMap: fatigueMap)
                        guard let idx = Self.tiers.firstIndex(where: { $0.tier == tier }) else { continue }
                        let end = CGPoint(x: chipXs - 5, y: chipYs[idx])
                        let color = Self.tiers[idx].swatch
                        var line = Path()
                        line.move(to: anchor)
                        line.addLine(to: end)
                        ctx.stroke(line, with: .color(color.opacity(0.55)), lineWidth: 0.8)
                        ctx.fill(Path(ellipseIn: CGRect(x: anchor.x - 2, y: anchor.y - 2,
                                                        width: 4, height: 4)),
                                 with: .color(color.opacity(0.9)))
                    }
                }

                // 四档色块 — 引线的终点. 用 .position 钉在跟 Canvas 同一坐标系的点上.
                ForEach(Array(Self.tiers.enumerated()), id: \.offset) { i, t in
                    HStack(spacing: 7) {
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
                    .frame(width: chipW, alignment: .leading)
                    .position(x: chipXs + chipW / 2, y: chipYs[i])
                }
                .blur(radius: blurLegend ? 4.5 : 0)
                .allowsHitTesting(false)
            }
        }
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

    /// 引线起点 = 该肌肉**最右侧**那块 polygon 的包围盒中心.
    /// 取最右 (而不是所有 polygon 合并) 是为了让线从靠图例那一侧出发, 不横穿身体.
    private func anchorPoint(for m: MuscleGroup, t: T) -> CGPoint? {
        var best: (cx: CGFloat, cy: CGFloat)? = nil
        for poly in polys where poly.muscle == m && poly.points.count >= 3 {
            let xs = poly.points.map(\.x), ys = poly.points.map(\.y)
            let cx = (xs.min()! + xs.max()!) / 2
            let cy = (ys.min()! + ys.max()!) / 2
            if best == nil || cx > best!.cx { best = (cx, cy) }
        }
        guard let b = best else { return nil }
        return CGPoint(x: t.dx + b.cx * t.s, y: t.dy + b.cy * t.s)
    }
}
