import SwiftUI

// FilterMenuButton — 全 app exercise filter 用的"菜单按钮".
//
// 替代之前的"chip 行水平滚动"模式 — chip 行占很多纵向空间 (12 个器械 chip 一行,
// + 6 个 muscle chip 一行, + 8 个 sub-muscle chip 一行 = 3 行筛选条占近 100pt),
// 改成菜单后:
//   - 一排小按钮 "[Muscle ▾] [Sub ▾] [Equipment ▾]" — 占 ~32pt 高
//   - 点开拉起 iOS 原生 Menu 下拉, 列表式选择
//   - 选中后按钮文字变成具体值 + accent 色 — 用户一眼能看到当前 filter 状态
//
// 单选模式 (T: Hashable). 多选场景目前不需要 (filter 维度都是 narrow 单值).
struct FilterMenuOption<T: Hashable>: Identifiable {
    let value: T
    let label: String
    /// false → 菜单里显示但不可点 (e.g. 当前 filter 组合下该 value 没匹配)
    var enabled: Bool = true

    var id: T { value }
}

/// 按钮外观:
///   - .capsule: 自定义胶囊 (默认 — picker sheet / Community filter 等沿用)
///   - .systemMenu: iOS 系统默认的菜单选择器样式 (tinted 文字 + chevron.up.chevron.down,
///     无胶囊底). 给已用系统原生搜索栏的 Exercises 页用, 视觉一致.
enum FilterMenuStyle {
    case capsule
    case systemMenu
}

struct FilterMenuButton<T: Hashable>: View {
    /// 未选时按钮显示的占位文案 ("Muscle" / "Equipment" / "Sub-muscle")
    let title: String
    /// 菜单第一行 "全部" 选项的文案 ("All muscles" / "Any equipment")
    let allLabel: String
    /// 当前选中. nil = "All"
    @Binding var selected: T?
    /// 可选项列表 + 各自的 enabled 状态 + 显示文案
    let options: [FilterMenuOption<T>]
    /// 按钮外观. 默认胶囊, Exercises 页传 .systemMenu 走系统默认样式.
    var style: FilterMenuStyle = .capsule
    /// 可选前导 SF Symbol — capsule 样式下显示在文字左侧, 加强视觉存在感 (Exercises 页用).
    var icon: String? = nil

    var body: some View {
        Menu {
            // "All / Any" 顶部入口 — 永远 enabled
            Button(action: { selected = nil }) {
                HStack {
                    Text(allLabel)
                    if selected == nil {
                        Spacer()
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            // 各选项 — disabled 的还显示但不可点
            ForEach(options) { opt in
                Button(action: { selected = opt.value }) {
                    HStack {
                        Text(opt.label)
                        if selected == opt.value {
                            Spacer()
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .disabled(!opt.enabled)
            }
        } label: {
            label
        }
        // 让 menu 跟随 button 位置弹出 (默认行为, 这里显式声明)
        .menuOrder(.fixed)
    }

    /// 按钮 label — 按 style 切两种外观.
    @ViewBuilder
    private var label: some View {
        switch style {
        case .capsule:      capsuleLabel
        case .systemMenu:   systemMenuLabel
        }
    }

    /// 胶囊样式 — 未选时灰底 + title, 选中时 accent 描边 + 具体值.
    @ViewBuilder
    private var capsuleLabel: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
            }
            Text(currentLabel)
                .font(.system(size: 12, weight: .heavy))
                .lineLimit(1)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .heavy))
        }
        .foregroundStyle(selected == nil ? MasoColor.textDim : MasoColor.accent)
        .padding(.horizontal, 12)
        .frame(height: 32)   // 固定高 — 跟 ExerciseSearchFilterBar 的搜索框完全等高
        .background(selected == nil ? MasoColor.surface : MasoColor.accent.opacity(0.16))
        .overlay(
            Capsule().stroke(
                selected == nil ? MasoColor.borderSoft : MasoColor.accent.opacity(0.5),
                lineWidth: 0.5
            )
        )
        .clipShape(Capsule())
    }

    /// 系统默认菜单选择器样式 — tinted 文字 + chevron.up.chevron.down (= iOS Picker(.menu) 的指示符),
    /// 无胶囊底. 未选灰字, 选中 accent. 跟系统原生搜索栏摆一起更一致.
    @ViewBuilder
    private var systemMenuLabel: some View {
        HStack(spacing: 3) {
            Text(currentLabel)
                .font(.system(size: 15))
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(selected == nil ? MasoColor.textDim : MasoColor.accent)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    /// 按钮当前显示的文字: 未选 → title; 选中 → 具体值的 label.
    /// 找不到选中值对应的 label (不应该发生) → fallback 到 title.
    private var currentLabel: String {
        guard let s = selected else { return title }
        return options.first(where: { $0.value == s })?.label ?? title
    }
}

// MARK: - ExerciseSearchFilterBar — 搜索 + Muscle/Equipment 筛选 合成一行的常驻条
//
// 全 app 唯一的"动作搜索+筛选"控件. 两处共用 (调一处两边都变):
//   1. Exercises 子页 (ExerciseLibraryBrowser)
//   2. 训练中"选动作" picker (ExercisePickerSheet — 替换 / + 加动作)
// 搜索框 flex 占主宽度, 右侧两个 filter 用 .capsule + 前导图标 (figure / dumbbell) 加强存在感;
// 搜索框字号/内边距跟 filter 胶囊对齐 → 三者等高、视觉成一组. caller 把它钉在 List 上方.
struct ExerciseSearchFilterBar: View {
    @Binding var query: String
    @Binding var muscleFilter: MuscleGroup?
    @Binding var equipmentFilter: String?
    /// 动作家族筛选 (Press / Row / Fly / Curl / Dip / …). nil = 全部.
    @Binding var movementFilter: MovementFacet?
    let muscleSections: [MuscleGroup]
    /// 当前 (equipment + text) 约束下还有动作的 muscle section — 菜单里其余 dim disabled.
    let availableMuscles: Set<MuscleGroup>
    /// 当前 (muscle + text) 约束下还有动作的 equipment — 菜单里其余 dim disabled.
    let availableEquipments: Set<String>
    /// 当前 (muscle + equipment + text) 约束下还有动作的 movement — 菜单里其余 dim disabled.
    let availableMovements: Set<MovementFacet>

    var body: some View {
        // 顺序: 左 = 两个筛选入口 (Muscle / Equipment), 右 = 搜索框 (flex 占满剩余宽度).
        HStack(spacing: 8) {
            FilterMenuButton(
                title: NSLocalizedString("Muscle", comment: "filter button placeholder"),
                allLabel: NSLocalizedString("All muscles", comment: ""),
                selected: $muscleFilter,
                options: muscleSections.map { m in
                    FilterMenuOption(value: m, label: m.displayName,
                                     enabled: availableMuscles.contains(m) || muscleFilter == m)
                },
                style: .capsule,
                icon: "figure.arms.open"
            )
            FilterMenuButton(
                title: NSLocalizedString("Equipment", comment: "filter button placeholder"),
                allLabel: NSLocalizedString("Any equipment", comment: ""),
                selected: $equipmentFilter,
                options: Exercise.knownEquipments.map { eq in
                    FilterMenuOption(value: eq, label: Exercise.equipmentDisplayName(for: eq),
                                     enabled: availableEquipments.contains(eq) || equipmentFilter == eq)
                },
                style: .capsule,
                icon: "dumbbell.fill"
            )
            // 动作家族 (Press / Row / Fly / Curl / Dip …) — 选 Dip → 所有 dip; Press+Chest → 胸推.
            FilterMenuButton(
                title: NSLocalizedString("Movement", comment: "filter button placeholder"),
                allLabel: NSLocalizedString("Any movement", comment: ""),
                selected: $movementFilter,
                options: MovementFacet.ordered.map { mv in
                    FilterMenuOption(value: mv, label: mv.displayName,
                                     enabled: availableMovements.contains(mv) || movementFilter == mv)
                },
                style: .capsule,
                icon: "figure.strengthtraining.traditional"
            )

            // 搜索框 — iOS 搜索框观感 (放大镜 + 圆角 + 清除), flex 占满剩余宽度, 放最右.
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(MasoColor.textFaint)
                TextField(NSLocalizedString("Search", comment: "search field placeholder"), text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                if !query.isEmpty {
                    Button(action: { query = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 32)   // 固定高 — 跟左侧 Muscle / Equipment 筛选胶囊完全等高
            .background(MasoColor.surface)
            .clipShape(Capsule())
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        .padding(.vertical, 8)
        .background(MasoColor.background)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(MasoColor.textFaint.opacity(0.15))
                .frame(height: 0.5)
        }
    }
}
