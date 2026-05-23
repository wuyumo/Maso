import SwiftUI
import MuscleMap

// 紧凑的双视图肌肉示意图 (正面 + 背面)
//
// 2026-05 重做 — 改用 MuscleMap SwiftUI SDK 渲染. 前 4 次 Claude 手画 polygon 都被毙了
// (低多边形 / 边缘生硬), 这次改用真人插画家画的 bezier polygon, 36 个肌群含 14 个 sub.
// 详见 docs/exercise-db-overhaul-plan.md §0.6 + _anatomy-research.md
//
// 对外 API 跟旧 BodyHint 一致 — 所有 caller 不用改.
//
// 行为:
//   - 默认 (square=false): aspect ratio 由 MuscleMap 内部决定 (~0.57:1), 自适应父容器
//   - square=true: 锁正方形 (列表 / player thumbnail 用)
//   - region: full / upper / lower — 走 mask 裁剪显示区
//   - opacityFor: 给 history 衰减模式用 (caller 控制每块肌肉的 opacity)
//   - onMuscleTap: 用户点身体某块肌肉, MuscleMap 帮我们做 hit-test 走 callback
struct BodyHint: View {
    let muscles: [MuscleGroup]
    /// 协同肌 — 渲染成更淡的 accent. 通常 caller 传 secondary muscles.
    var synergists: [MuscleGroup] = []
    var color: Color = MasoColor.accent
    var height: CGFloat = 110
    var region: BodyRegion = .full
    /// true = 锁正方形 slot. MuscleMap BodyView 不强制 aspect, 我们用 frame + clipped 自己锁.
    var square: Bool = false
    /// 可选 per-muscle opacity 回调. 传了之后忽略 muscles / synergists 参数.
    var opacityFor: ((MuscleGroup) -> Double?)? = nil
    /// 可选 tap 回调 — 用户点身体某块肌肉时触发.
    var onMuscleTap: ((MuscleGroup) -> Void)? = nil
    /// "粗颗粒模式" — 关闭 sub-muscle 分块显示. (目前实现没区分; v3 可加.)
    var coarseOnly: Bool = false
    /// 前 / 后两个 panel 之间的间距. 默认 6pt; 紧凑 hero 卡片想拉近可传 0 甚至负值.
    var panelSpacing: CGFloat = 6

    // MARK: - Body

    var body: some View {
        HStack(spacing: panelSpacing) {
            panel(side: .front)
            panel(side: .back)
        }
        .frame(maxHeight: height)
        .modifier(RegionClipModifier(region: region))
    }

    @ViewBuilder
    private func panel(side: MuscleMap.BodySide) -> some View {
        // 纯链式调用 — 跟 MuscleMap demo 1:1 风格.
        // 之前用 var view = ...; view = view.showSubGroups() 形式时高亮没出来,
        // 怀疑跟 SwiftUI ViewBuilder 对 var 局部变量的处理有关.
        let primaries = primaryMuscleMapMuscles
        let synergists = synergistMuscleMapMuscles

        if let onTap = onMuscleTap {
            MuscleMap.BodyView(gender: .male, side: side, style: bodyStyle)
                .showSubGroups()
                .highlight(synergists, color: color, opacity: 0.35)
                .highlight(primaries, color: color, opacity: 1.0)
                .onMuscleSelected { muscle, _ in onTap(muscle.masoMuscleGroup) }
                .frame(width: square ? height : nil, height: height)
        } else {
            MuscleMap.BodyView(gender: .male, side: side, style: bodyStyle)
                .showSubGroups()
                .highlight(synergists, color: color, opacity: 0.35)
                .highlight(primaries, color: color, opacity: 1.0)
                .frame(width: square ? height : nil, height: height)
        }
    }

    /// 展开后 primary muscles → MuscleMap.Muscle 数组 (去重). opacityFor 模式留空 (callsite handles).
    private var primaryMuscleMapMuscles: [Muscle] {
        var out: Set<Muscle> = []
        for mg in expanded { out.formUnion(mg.mmMuscles) }
        return Array(out)
    }

    private var synergistMuscleMapMuscles: [Muscle] {
        var out: Set<Muscle> = []
        for mg in synergistsExpanded { out.formUnion(mg.mmMuscles) }
        return Array(out)
    }


    // MARK: - Highlight application

    private func applyHighlights(to view: MuscleMap.BodyView) -> MuscleMap.BodyView {
        var result = view

        if let opacityFor {
            // 每肌群单独 opacity 模式 — 用于 history 衰减
            for mg in MuscleGroup.allCases {
                guard let op = opacityFor(mg), op > 0 else { continue }
                let mms = mg.mmMuscles
                if !mms.isEmpty {
                    result = result.highlight(mms, color: color, opacity: op)
                }
            }
            return result
        }

        // 标准模式: primary 全 opacity, synergists 35% opacity
        var primaryMms: [Muscle] = []
        var synergistMms: [Muscle] = []
        for mg in expanded { primaryMms.append(contentsOf: mg.mmMuscles) }
        for mg in synergistsExpanded { synergistMms.append(contentsOf: mg.mmMuscles) }
        primaryMms = Array(Set(primaryMms))
        synergistMms = Array(Set(synergistMms))

        // 先涂 synergists (低 opacity) 再涂 primary — primary 覆盖共有的
        if !synergistMms.isEmpty {
            result = result.highlight(synergistMms, color: color, opacity: 0.35)
        }
        if !primaryMms.isEmpty {
            result = result.highlight(primaryMms, color: color, opacity: 1.0)
        }
        return result
    }

    // MARK: - Helpers

    private var expanded: Set<MuscleGroup> { expandAnatomyMuscles(muscles) }
    private var synergistsExpanded: Set<MuscleGroup> {
        expandAnatomyMuscles(synergists).subtracting(expanded)
    }

    /// MuscleMap 风格 — 黑底 + 深灰 idle + 透明边. 跟 MasoColor.background / .surface 视觉对齐.
    private var bodyStyle: MuscleMap.BodyViewStyle {
        MuscleMap.BodyViewStyle(
            defaultFillColor: Color(red: 0.165, green: 0.165, blue: 0.165),  // ~MasoColor.surface
            strokeColor: .clear,
            strokeWidth: 0,
            selectionColor: color,
            selectionStrokeColor: .clear,
            selectionStrokeWidth: 0,
            headColor: Color(red: 0.165, green: 0.165, blue: 0.165),
            hairColor: Color(red: 0.122, green: 0.122, blue: 0.122),          // ~MasoColor.background
            shadowColor: .clear,
            shadowRadius: 0,
            shadowOffset: .zero
        )
    }
}

// MARK: - Region clipping

/// 用 mask 裁剪 BodyHint 的上半 / 下半显示.
/// MuscleMap 没原生 region, 我们用 GeometryReader + 透明矩形 mask.
private struct RegionClipModifier: ViewModifier {
    let region: BodyRegion

    func body(content: Content) -> some View {
        switch region {
        case .full:
            content
        case .upper:
            // 显示上半 (head + chest + back + shoulders + arms): 留上 55%
            content
                .mask {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width, height: geo.size.height * 0.55)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.275)
                    }
                }
        case .lower:
            // 显示下半 (waist + glutes + legs): 留下 55%
            content
                .mask {
                    GeometryReader { geo in
                        Rectangle()
                            .frame(width: geo.size.width, height: geo.size.height * 0.55)
                            .position(x: geo.size.width / 2, y: geo.size.height * 0.725)
                    }
                }
        }
    }
}

// MARK: - Preview
// (BodyRegion 在 Maso/Data/Anatomy.swift 里定义, 这里不重复)

#Preview {
    VStack(spacing: 16) {
        BodyHint(muscles: [.chest, .triceps], synergists: [.frontDelts], height: 200)
        HStack {
            BodyHint(muscles: [.chest], height: 72, region: .upper, square: true)
            BodyHint(muscles: [.hamstrings], height: 72, region: .lower, square: true)
        }
    }
    .padding()
    .background(MasoColor.background)
    .preferredColorScheme(.dark)
}
