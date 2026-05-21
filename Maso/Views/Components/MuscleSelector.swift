import SwiftUI

// MuscleSelector — 全 app "肌群偏好选择" 统一组件.
//
// 使用场景 (3 处共用同一份, 行为/视觉/分组一致):
//   1. Onboarding "你想加强的肌群"
//   2. Settings → Muscles to focus picker
//   3. QuickWorkout 创建训练 "Pick muscles" 步骤
//
// 设计原则:
//   - 两层选择 — major (大肌群) + sub (解剖学子分区), 各自独立 toggle.
//   - 同一行内, major chip 在左, sub chips 顺着排在右边换行.
//   - detailEnabled = false 时 sub chip 隐藏, 仅暴露 12 个 major. 进入时把 selected
//     里的 sub 折叠回 major (避免"看不见的幽灵选项").
//   - 协同肌 (synergists) 可选 — QuickWorkout 用 (显示训练目标会带到的肌肉), Settings/
//     Onboarding 不传 (它们是"偏好"语义, 没有"当前训练目标"概念).
//
// Bug 背景:
//   原来 DataStore 默认 wantStrengthen 包含 .lats (sub), 但 picker 只渲染 10 个 major,
//   用户怎么都点不到 .lats, 取消所有 major 后 count 还是 ≥ 1. 现在通过 sanitize 在每个
//   入口 (onAppear) 清掉"不在 picker 暴露层级里的孤儿值"根治.
struct MuscleSelector: View {
    /// 已选肌群 — 双绑. tap chip → toggle 对应肌群.
    @Binding var selected: Set<MuscleGroup>

    /// 是否显示 sub chip. false 时只显示 12 个 major chip.
    /// (跟 Settings.muscleDetailEnabled 联动 — caller 决定传哪个值.)
    var detailEnabled: Bool = true

    /// 协同肌 — 显示为半透色, 也可点击 (点击会加入 selected).
    /// QuickWorkout 传计算结果; Settings/Onboarding 传 [].
    var synergists: Set<MuscleGroup> = []

    /// 跟 QuickWorkout 当前同款的 12 行分组. 单一 source of truth — 全 app 用同一份.
    /// 排序基准: 推 / 拉 / 肩 / 臂 / 核心 / 腿 — 常见 split 顺序, 用户扫一眼能找到目标肌群.
    static let groupedRows: [(major: MuscleGroup, subs: [MuscleGroup])] = [
        (.chest,      [.upperChest, .midChest, .lowerChest]),
        (.back,       [.upperLats, .lowerLats, .upperTraps, .midTraps, .lowerTraps, .rhomboids, .teres, .lowerBack]),
        (.shoulders,  [.frontDelts, .sideDelts, .rearDelts, .rotatorCuff]),
        (.biceps,     [.bicepsLong, .bicepsShort, .brachialis]),
        (.triceps,    [.tricepsLong, .tricepsLateral, .tricepsMedial]),
        (.forearms,   [.forearmFlexors, .forearmExtensors, .brachioradialis]),
        (.core,       [.upperAbs, .lowerAbs, .obliques, .serratus]),
        (.quads,      [.rectusFemoris, .vastusLateralis, .vastusMedialis]),
        (.hamstrings, [.bicepsFemoris, .semitendinosus]),
        (.glutes,     [.gluteusMaximus, .gluteusMedius]),
        (.adductors,  []),
        (.calves,     [.gastrocnemius, .soleus, .tibialisAnterior]),
    ]

    /// 所有 picker 在 detailEnabled = true 时暴露的肌群集合.
    /// 凡是不在这里的肌肉值, 都会被 sanitize 当孤儿清掉.
    static let exposedMuscles: Set<MuscleGroup> = {
        var s = Set<MuscleGroup>()
        for r in groupedRows {
            s.insert(r.major)
            s.formUnion(r.subs)
        }
        return s
    }()

    /// 仅 major 集合 — detailEnabled = false 时合法值的全集.
    static let majorMuscles: Set<MuscleGroup> = Set(groupedRows.map(\.major))

    /// 把 selected 集合"洗干净":
    ///   1. 剔除不在 exposedMuscles 里的孤儿值 (e.g. legacy 默认值 .lats / .neck)
    ///   2. detailEnabled = false 时, 把所有 sub 折叠回它的 major
    /// 调用方应该在 picker onAppear / Save 时调一次, 保证 wantStrengthen 永远跟 UI 对齐.
    static func sanitize(_ raw: Set<MuscleGroup>, detailEnabled: Bool) -> Set<MuscleGroup> {
        // 1. 先剔除孤儿
        var out = raw.filter(exposedMuscles.contains)
        // 2. detailEnabled 关时把 sub 折叠到 major
        if !detailEnabled {
            var folded = Set<MuscleGroup>()
            for m in out { folded.insert(majorOf(m)) }
            out = folded
        }
        return out
    }

    /// muscle → 它所属的 picker major.
    ///   - major 自己返回自己
    ///   - sub 返回对应 major
    ///   - 中间层级 (e.g. .lats / .abs / .arms — 不是 picker row, 也不是某 row 的 sub)
    ///     按解剖学归到最合适的 picker major
    ///   - 完全没归属的 (e.g. .neck / .fullBody / .legs) 兜底返回原值
    /// 这是全 app "肌群归一" 的唯一入口 — BodyHint hit-test / Quick exercise grouping / sanitize
    /// 都走这一处, 任何分组规则修改只改这里一次.
    static func majorOf(_ muscle: MuscleGroup) -> MuscleGroup {
        // 1. 直接命中: major 或 sub
        for r in groupedRows {
            if r.major == muscle { return muscle }
            if r.subs.contains(muscle) { return r.major }
        }
        // 2. 中间层级 (anatomy 父概念, 但 picker 没把它当 row, 也没作为 sub)
        switch muscle {
        case .lats:     return .back     // lats 是 back 的子概念, 但 picker 用 upperLats/lowerLats
        case .abs:      return .core     // abs 是 core 的子概念
        case .arms:     return .biceps   // arms 是 biceps/triceps/forearms 的父; 落到 biceps 作为代表
        case .legs:     return .quads    // legs 同上 — 落到 quads 作为代表
        default:        return muscle    // .neck / .fullBody 等没归属的兜底原值
        }
    }

    /// 把一组 muscle 折叠到它们的 major 集合 + 数 sub 数. Settings 行用 ("Chest, Back +2 details").
    static func summary(_ selected: Set<MuscleGroup>) -> (majors: [MuscleGroup], extraSubCount: Int) {
        var majors: [MuscleGroup] = []
        var seen = Set<MuscleGroup>()
        var extraSub = 0
        // 按 groupedRows 顺序遍历, 让输出顺序稳定 (chest 永远在 back 前)
        for r in groupedRows {
            // 当前 major 自己被选, 进 majors
            if selected.contains(r.major) {
                if seen.insert(r.major).inserted { majors.append(r.major) }
            }
            // 当前 row 任何 sub 被选 — 若 major 没在 majors 里, 把 major 加进去 (展示用)
            // 同时把 sub 计入 extraSub.
            for sub in r.subs where selected.contains(sub) {
                if seen.insert(r.major).inserted { majors.append(r.major) }
                extraSub += 1
            }
        }
        return (majors, extraSub)
    }

    var body: some View {
        if detailEnabled {
            // 细分开启: 每行 = 1 major + 它的 subs, 行内 wrap, 不同 major 跨行.
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Self.groupedRows, id: \.major) { row in
                    muscleRow(major: row.major, subs: row.subs)
                }
            }
        } else {
            // 细分关闭: 只剩 12 个 major chip — 全部塞到同一个 FlowLayout,
            // 让它们横向 wrap 填满整行, 不再每个独占一行靠左.
            FlowLayout(spacing: 8, alignment: .leading) {
                ForEach(Self.groupedRows, id: \.major) { row in
                    majorChip(row.major)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func muscleRow(major: MuscleGroup, subs: [MuscleGroup]) -> some View {
        // FlowLayout 让 major + sub 自动 wrap, 跟 QuickWorkoutScreen 一致.
        FlowLayout(spacing: 6, alignment: .leading) {
            majorChip(major)
            if detailEnabled {
                ForEach(subs, id: \.self) { sub in
                    subChip(sub)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Chip 状态机

    /// 三档 chip 状态:
    ///   - selected: 用户主动选, accent 实色
    ///   - synergist: 被选中肌肉的协同肌 (QuickWorkout 专用), accent 半透
    ///   - idle: 未选, 灰底
    private enum ChipState { case selected, synergist, idle }

    private func state(for m: MuscleGroup) -> ChipState {
        if selected.contains(m) { return .selected }
        if synergists.contains(m) { return .synergist }
        return .idle
    }

    private func toggle(_ m: MuscleGroup) {
        if selected.contains(m) { selected.remove(m) }
        else { selected.insert(m) }
        Haptics.tap()
    }

    // MARK: - Major chip (14pt heavy)

    private func majorChip(_ m: MuscleGroup) -> some View {
        let st = state(for: m)
        return Button { toggle(m) } label: {
            Text(m.displayName)
                .font(.system(size: 14, weight: .heavy))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(majorBg(st))
                .foregroundStyle(majorFg(st))
                .overlay(majorBorder(st))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func majorBg(_ st: ChipState) -> Color {
        switch st {
        case .selected:  return MasoColor.accent
        case .synergist: return MasoColor.accent.opacity(0.18)
        case .idle:      return MasoColor.surface
        }
    }
    private func majorFg(_ st: ChipState) -> Color {
        switch st {
        case .selected:  return .black
        case .synergist: return MasoColor.accent
        case .idle:      return MasoColor.text
        }
    }
    @ViewBuilder
    private func majorBorder(_ st: ChipState) -> some View {
        if st == .synergist {
            Capsule().stroke(MasoColor.accent.opacity(0.5), lineWidth: 0.5)
        }
    }

    // MARK: - Sub chip (11pt bold, 视觉更轻)

    private func subChip(_ m: MuscleGroup) -> some View {
        let st = state(for: m)
        return Button { toggle(m) } label: {
            Text(m.displayName)
                .font(.system(size: 11, weight: .bold))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(subBg(st))
                .foregroundStyle(subFg(st))
                .overlay(subBorder(st))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func subBg(_ st: ChipState) -> Color {
        switch st {
        case .selected:  return MasoColor.accent.opacity(0.85)
        case .synergist: return MasoColor.accent.opacity(0.14)
        case .idle:      return MasoColor.surface.opacity(0.6)
        }
    }
    private func subFg(_ st: ChipState) -> Color {
        switch st {
        case .selected:  return .black
        case .synergist: return MasoColor.accent.opacity(0.85)
        case .idle:      return MasoColor.textDim
        }
    }
    @ViewBuilder
    private func subBorder(_ st: ChipState) -> some View {
        if st == .synergist {
            Capsule().stroke(MasoColor.accent.opacity(0.4), lineWidth: 0.5)
        }
    }
}
