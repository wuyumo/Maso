import SwiftUI
import Charts

/// 单面板、缩放到某肌肉大区 bbox 的精细局部图 (右侧分区索引的图标).
/// 背部用 POSTERIOR, 其余用 ANTERIOR; 取该区肌群 polygon 的包围盒 + 留白 (带出周边肌群),
/// 整体不再画前后两个小人, 而是聚焦那块区域的精细分块.
// (internal, 非 private — WorkoutCard 的动作 chip "肌肉图示"模式复用它当部位前缀小图,
//  settings.exerciseChipMuscleIcon 开关控制. 改这里两处同步影响.)
struct MuscleRegionIcon: View {
    let region: MuscleGroup
    /// 该区肌群的填色 (主体).
    var focusColor: Color
    /// 周边肌群的填色 (衬托, 通常更弱).
    var surroundColor: Color
    var size: CGFloat = 24

    private var polys: [AnatomyPolygon] { region == .back ? POSTERIOR : ANTERIOR }
    private var focus: Set<MuscleGroup> { expandAnatomyMuscles([region]) }

    /// 该区肌群 polygon 的包围盒, pad 后取正方形 (anatomy 坐标). 没命中 → 全身兜底.
    private var box: (x: CGFloat, y: CGFloat, side: CGFloat) {
        var minX = CGFloat.greatestFiniteMagnitude, minY = minX
        var maxX = -CGFloat.greatestFiniteMagnitude, maxY = maxX
        for poly in polys where focus.contains(poly.muscle) {
            for p in poly.points {
                minX = min(minX, p.x); maxX = max(maxX, p.x)
                minY = min(minY, p.y); maxY = max(maxY, p.y)
            }
        }
        guard minX <= maxX else { return (0, 0, 100) }
        let cx = (minX + maxX) / 2, cy = (minY + maxY) / 2
        let side = max(maxX - minX, maxY - minY) * 1.55   // ×1.55 → 带出周边肌群
        return (cx - side / 2, cy - side / 2, side)
    }

    var body: some View {
        Canvas { ctx, sz in
            let b = box
            guard b.side > 0 else { return }
            let s = sz.width / b.side
            func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: (p.x - b.x) * s, y: (p.y - b.y) * s) }
            for poly in polys where poly.points.count >= 3 {
                var path = Path()
                path.move(to: pt(poly.points[0]))
                for q in poly.points.dropFirst() { path.addLine(to: pt(q)) }
                path.closeSubpath()
                let fill: Color = (poly.muscle != .fullBody && focus.contains(poly.muscle)) ? focusColor : surroundColor
                ctx.fill(path, with: .color(fill))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

// Shared curated family browser; full catalog and precise search retain every ID.
// 跟 ExercisePicker 类似 UI (search + chip + list), 但 tap 一项不是"加进 plan",
// 而是展开/弹出动作详情 (instructions / muscles / category) — 纯浏览模式.
struct ExerciseLibraryBrowser: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss
    /// 作为底部 tab 嵌入时 true — 去掉 "Done"(tab 不需要 dismiss).
    var asTab: Bool = false
    /// 嵌在 Train tab 里时 true — 不自带 NavigationStack / 大标题 / +按钮 (Train 统一导航栏接管).
    var embedded: Bool = false
    /// embedded 时由 Train 的右上角 "+" 触发: 翻 true → 打开"加动作"选择 sheet.
    var addRequested: Binding<Bool>? = nil

    @State private var query: String = ""
    @State private var searchExpanded = false
    @State private var muscleFilter: MuscleGroup? = nil
    @State private var equipmentFilter: String? = nil
    @State private var movementFilter: MovementFacet? = nil
    @State private var selected: Exercise? = nil
    /// 当前展开的"变种组" key (= ExerciseGroup.id). 一次只展开一组 — 跟 picker 同一收折语义.
    @State private var expandedGroupKey: String? = nil
    /// "+ Add exercise" → 两条路径的选择 sheet (Create your own / Browse rare).
    @State private var addChoiceOpen: Bool = false
    /// 路径 1: 自创动作表单 sheet (name + photo + 元数据).
    @State private var customFormOpen: Bool = false
    /// 路径 2: 小众库浏览 sheet (从 niche stash 采纳到自己的库).
    @State private var nicheBrowseOpen: Bool = false
    /// P0-6: 删自创动作的二次确认.
    @State private var pendingDeleteCustom: Exercise? = nil
    /// 正在编辑的自创动作 — 非 nil 时弹 CustomExerciseFormSheet 的编辑模式.
    @State private var editingCustom: Exercise? = nil
    /// 自创动作被 plan/历史 引用 → 不能删, 弹说明 alert.
    @State private var deleteBlockedRef: Exercise? = nil
    /// P1-7: 自创动作是 Pro 功能 (付费墙广告语承诺) — 免费用户走这弹 paywall.
    @State private var paywallOpen: Bool = false
    private static let muscleSections: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    private var sourceExercises: [Exercise] {
        data.visibleExerciseLibrary
    }

    private func applyFilters(_ exercises: [Exercise]) -> [Exercise] {
        var arr = exercises
        if let m = muscleFilter {
            // 严格筛选 — 只看 primaryMuscles (主练肌), 跟 ExercisePickerSheet 同一行为.
            // 不再因为某个动作 secondary 含 m 就出现 (e.g. deadlift secondary 含 core 也不算 core 动作).
            arr = arr.filter { ex in
                ex.primaryMuscles.contains(where: { $0.section == m })
            }
        }
        if let eq = equipmentFilter {
            arr = arr.filter { ex in
                if eq == "other" { return ex.equipment == "other" || ex.equipment == nil }
                return ex.equipment == eq
            }
        }
        if let mv = movementFilter {
            arr = arr.filter { $0.movementFacet == mv }
        }
        let words = exerciseSearchWords(query)
        if !words.isEmpty {
            // 多维分词搜索 — 动作家族 / 部位 / 器械 / 变体 任意组合都能命中.
            arr = arr.filter { $0.matchesSearch(words) }
        }
        // 收藏置顶 — 在 filter 之后排序, 让收藏的动作在当前 filter 结果里排最前.
        // 不截断 (曾经 prefix(200)): List 是 lazy 的, 700+ 行无性能问题; 截断会把字母序
        // 靠后的 pull-up / overhead press 全家和 append 在库末尾的自创动作静默切掉.
        return ExerciseSelectionPolicy.shared.sorted(arr, favoriteIDs: data.canonicalFavoriteExerciseIDs,
                                                     recentIDs: data.recentExerciseIDs)
    }

    private var filtered: [Exercise] { applyFilters(sourceExercises) }

    private var previewExercises: [Exercise] {
        // Hide rare variants keeps rare-only groups out of default browsing;
        // explicit “more versions” still makes every matching family member reachable.
        applyFilters(data.visibleExerciseLibrary)
    }

    /// 把 filtered 折叠成变种组 — 跟 ExercisePickerSheet 同一份 ExerciseGrouping.group(...).
    /// 排序: 收藏组置顶 (沿用置顶语义), 其余按"组代表的显示名"字母序 (中文走 locale 排序) —
    /// 列表上看到什么名字就按什么排, 不按 JSON 内部顺序.
    private var filteredGroups: [ExerciseGroup] {
        let preferred = ExerciseGrouping.exactSearchIDs(in: filtered, query: query)
        let groups = ExerciseGrouping.group(filtered, preferredExerciseIDs: preferred, fullLibrary: data.visibleExerciseLibrary,
                                            previewLibrary: previewExercises, groupByName: true)
        return groups.sorted { a, b in
            if a.entryTitle == b.entryTitle { return a.id < b.id }
            return ExerciseNameSort.precedes(a.entryTitle, b.entryTitle)
        }
    }

    /// Search reaches every exact version; a broad family query stays compact.
    private var searchActive: Bool {
        !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Broad queries and equipment filters keep families collapsed until requested.
    private func isGroupExpanded(_ group: ExerciseGroup) -> Bool {
        expandedGroupKey == group.id
    }

    /// 单行 — 共用 GroupedExerciseRow (跟 picker 同款展示), tap → 详情, 右滑 → 置顶 / 删除 / 移回冷门库.
    @ViewBuilder
    private func libraryRow(_ ex: Exercise, isVariant: Bool, group: ExerciseGroup) -> some View {
        GroupedExerciseRow(
            exercise: ex,
            isVariant: isVariant,
            group: group,
            isExpanded: isGroupExpanded(group),
            showDisclosure: !group.isSingleton,
            showVariantCategoryLabel: false,
            trailing: { EmptyView() },
            onTap: { selected = ex },
            onToggleExpand: {
                Haptics.tap()
                withAnimation(.easeOut(duration: 0.2)) {
                    expandedGroupKey = (expandedGroupKey == group.id) ? nil : group.id
                }
            }
        )
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                data.toggleFavorite(ex.id)
                Haptics.tap()
            } label: {
                Image(systemName: data.isFavorite(ex.id) ? "pin.slash.fill" : "pin.fill")
            }
            .tint(MasoColor.accent)
            .accessibilityLabel(NSLocalizedString(data.isFavorite(ex.id) ? "Unpin" : "Pin to top", comment: ""))

            // P0-6: 自创动作 → 编辑 + 删除 (引用检查); 已采纳 niche → 移回冷门库.
            if ex.id.hasPrefix("custom-") {
                // 自创动作存完之前**改不了** —— 名字打错只能删了重建, 而一旦被 plan/历史引用
                // 连删都不让 (下面的 isExerciseReferenced), 等于永久将错就错。补上编辑入口。
                Button {
                    editingCustom = ex
                    Haptics.tap()
                } label: {
                    Image(systemName: "pencil")
                }
                .tint(MasoColor.textDim)
                .accessibilityLabel(NSLocalizedString("Edit", comment: ""))

                Button(role: .destructive) {
                    if data.isExerciseReferenced(ex.id) {
                        deleteBlockedRef = ex
                    } else {
                        pendingDeleteCustom = ex
                    }
                    Haptics.tap()
                } label: {
                    Image(systemName: "trash.fill")
                }
                .tint(MasoColor.negative)
                .accessibilityLabel(NSLocalizedString("Delete", comment: ""))
            }
        }
    }

    private func matchesEquipment(_ ex: Exercise, _ eq: String) -> Bool {
        eq == "other" ? (ex.equipment == "other" || ex.equipment == nil) : ex.equipment == eq
    }

    /// 当前 (equipment + movement + text) filter 下还有动作的 muscle section. menu 里 dim disabled.
    private var availableMuscles: Set<MuscleGroup> {
        var out: Set<MuscleGroup> = []
        let words = exerciseSearchWords(query)
        for ex in sourceExercises {
            if let eq = equipmentFilter, !matchesEquipment(ex, eq) { continue }
            if let mv = movementFilter, ex.movementFacet != mv { continue }
            if !words.isEmpty, !ex.matchesSearch(words) { continue }
            for sec in Self.muscleSections where ex.primaryMuscles.contains(where: { $0.section == sec }) {
                out.insert(sec)
            }
        }
        return out
    }

    /// 当前 (muscle + movement + text) filter 下还有动作的 equipment set. menu 里 dim disabled.
    private var availableEquipments: Set<String> {
        var out: Set<String> = []
        let words = exerciseSearchWords(query)
        for ex in sourceExercises {
            if let m = muscleFilter, !ex.primaryMuscles.contains(where: { $0.section == m }) { continue }
            if let mv = movementFilter, ex.movementFacet != mv { continue }
            if !words.isEmpty, !ex.matchesSearch(words) { continue }
            out.insert(ex.equipment ?? "other")
        }
        return out
    }

    /// 给定肌群 section 下当前 (equipment + text) 还有动作的 movement family (有序) — 肌群子菜单用.
    private func movementsForSection(_ sec: MuscleGroup) -> [MovementFacet] {
        let words = exerciseSearchWords(query)
        var set = Set<MovementFacet>()
        for ex in sourceExercises {
            guard ex.primaryMuscles.contains(where: { $0.section == sec }) else { continue }
            if let eq = equipmentFilter, !matchesEquipment(ex, eq) { continue }
            if !words.isEmpty, !ex.matchesSearch(words) { continue }
            if let mf = ex.movementFacet { set.insert(mf) }
        }
        return MovementFacet.ordered.filter { set.contains($0) }
    }

    /// 零搜索结果空状态 — 提示 + "添加动作/浏览冷门库"入口 (取代之前的空白死路).
    @ViewBuilder
    private var emptyResultsRow: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(MasoColor.textFaint)
            Text("No exercises match your search")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(MasoColor.textDim)
            Button(action: { addChoiceOpen = true }) {
                // 空态小实心钮 → 次级玻璃 (映射表②同类归置): iOS 26 低浓度玻璃 + accent 字,
                // 旧系统保留实心 accent + 黑字.
                Text("Add exercise")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(systemGlassAvailable ? MasoColor.accent : .black)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .glassCapsuleButtonBackground(tint: MasoColor.accent.opacity(0.25), fallback: MasoColor.accent)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    /// 常驻搜索 + 筛选条 — 用全 app 共享的 ExerciseSearchFilterBar (跟训练 picker 同一组件,
    /// 调一处两边都变). 钉在列表上方 (不随列表滚动).
    private var searchFilterBar: some View {
        VStack(spacing: 8) {
          ExerciseSearchFilterBar(
            query: $query, muscleFilter: $muscleFilter, movementFilter: $movementFilter,
            equipmentFilter: $equipmentFilter, muscleSections: Self.muscleSections,
            availableMuscles: availableMuscles, movementsFor: movementsForSection,
            availableEquipments: availableEquipments, systemStyle: true
          )
          .accessibilityIdentifier("exercise.library.filters")
        }.padding(.top, 6)
    }

    private var personalShortcutExercises: [Exercise] {
        let ids = data.canonicalFavoriteExerciseIDs.union(data.recentExerciseIDs)
        return ExerciseSelectionPolicy.shared.sorted(filtered.filter { ids.contains($0.id) },
            favoriteIDs: data.canonicalFavoriteExerciseIDs, recentIDs: data.recentExerciseIDs)
    }

    private var personalShortcutsLink: some View {
        NavigationLink {
            ExerciseFamilyVersionsPage(title: NSLocalizedString("Pinned and recent", comment: ""),
                                       exercises: personalShortcutExercises) { exercise in
                let group = ExerciseGroup(baseName: exercise.name, canonical: exercise, variants: [])
                libraryRow(exercise, isVariant: true, group: group)
            }
        } label: {
            Label("Pinned and recent", systemImage: "pin")
                .foregroundStyle(MasoColor.text)
                .padding(.vertical, 4)
        }
        .listRowBackground(Color.clear)
        .accessibilityIdentifier("exercise.personal")
    }

    /// 动作列表 List 本体 — headerFilter=true 时把筛选条放进 plain List 的 pinned section header
    /// (iOS 18-25: 系统自动给吸顶毛玻璃); =false 时 header 留空 (iOS 26: 筛选条改由外层 .safeAreaBar 提供).
    @ViewBuilder
    private func exerciseList(headerFilter: Bool) -> some View {
        List {
                // iOS 18-25: 筛选条放进 plain List 吸顶 header (系统给毛玻璃). iOS 26 走 safeAreaBar.
                if headerFilter {
                    Section { EmptyView() } header: {
                        searchFilterBar
                            .textCase(nil)
                            .listRowInsets(EdgeInsets())
                    }
                }
                if !searchActive, !personalShortcutExercises.isEmpty {
                    personalShortcutsLink
                }
                if filteredGroups.isEmpty {
                    // 零结果不再空白死路 — 给提示 + 入口 (跟 picker 的空状态一致).
                    Section { emptyResultsRow }
                } else {
                    ForEach(filteredGroups) { group in
                        libraryRow(group.canonical, isVariant: false, group: group)
                        if !group.isSingleton, isGroupExpanded(group) {
                            groupedVariantSections(for: group, showAll: true, onCollapse: { expandedGroupKey = nil }) { variant in
                                libraryRow(variant, isVariant: true, group: group)
                            }
                        }
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
            // 最小行高降到 1 — 否则 groupedVariantSections 的 1pt"终结行"(撑住动画 diff 防崩) 会被默认最小行高
            // (~44pt) 撑大, 让"最后一个变种 ↔ 下一个母动作"间距过宽. 普通动作行有图片, 内容高远大于 1, 不受影响.
            .environment(\.defaultMinListRowHeight, 1)
            .scrollContentBackground(.hidden)
            .background(MasoColor.background.ignoresSafeArea())
            .onChange(of: query) { _, _ in
                if let key = expandedGroupKey, filteredGroups.contains(where: { $0.id == key }) { return }
                expandedGroupKey = nil
            }
            .onChange(of: muscleFilter) { _, _ in expandedGroupKey = nil }
            .onChange(of: equipmentFilter) { _, _ in expandedGroupKey = nil }
            .onChange(of: movementFilter) { _, _ in expandedGroupKey = nil }
    }

    var body: some View {
        NavStackIf(embedded: embedded) {
            // The native filter bar participates in the shared app header's soft
            // scroll edge. Earlier iOS versions retain their pinned section header.
            Group {
                if #available(iOS 26.0, *) {
                    exerciseList(headerFilter: false)
                        // 筛选 + 搜索条常显 (不再随上划隐藏); 放进 safeAreaBar 跟导航栏共享同一片系统毛玻璃.
                        .safeAreaBar(edge: .top, spacing: 0) {
                            searchFilterBar
                        }
                        // inline 标题: 带搜索/筛选条的页面原生就是 inline (e.g. 设置/邮件), 跟筛选条同一片玻璃.
                        .navigationBarTitleDisplayMode(.large)
                } else {
                    exerciseList(headerFilter: true)
                }
              }
                .searchable(text: $query, isPresented: $searchExpanded,
                            placement: .navigationBarDrawer(displayMode: .automatic), prompt: Text("Search"))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: searchExpanded) { _, presented in
                    if !presented { query = "" }
                }
                // embedded 时跳过自己的大标题 / +按钮 (Train 统一导航栏接管); 非 embedded 保持原样.
                .applyIf(!embedded) { v in
                    v.screenHeader(NSLocalizedString("Exercises", comment: "")) {
                        Button { searchExpanded = true } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Search")
                        Button(action: { addChoiceOpen = true }) {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel(NSLocalizedString("Add exercise", comment: ""))
                    }
                    // sheet 用法 (非 tab) 的关闭按钮按 iOS sheet 惯例放左上角 —
                    // 之前跟 "+" 挤在同一侧, 关闭/添加两个语义相反的操作贴在一起易误触 (owner 反馈).
                    .toolbar {
                        if !asTab {
                            ToolbarItem(placement: .topBarLeading) {
                                Button(action: { dismiss() }) {
                                    Image(systemName: "xmark")
                                }
                                .accessibilityLabel("Done")
                            }
                        }
                    }
                }
                // embedded: Train 的右上角 "+" 经 addRequested 触发"加动作"选择 sheet.
                .onChange(of: addRequested?.wrappedValue ?? false) { _, v in
                    if v { addChoiceOpen = true; addRequested?.wrappedValue = false }
                }
            .tint(MasoColor.text)
            .sheet(item: $selected) { ex in
                ExerciseDetailSheet(exercise: ex)
                .presentationDragIndicator(.visible)
            }
            // "+" → 选两条路径
            .sheet(isPresented: $addChoiceOpen) {
                AddExerciseChoiceSheet(
                    onCreateCustom: {
                        addChoiceOpen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            if data.canCreateCustomExercise { customFormOpen = true } else { paywallOpen = true }
                        }
                    },
                    onBrowseNiche: {
                        addChoiceOpen = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.32) {
                            nicheBrowseOpen = true
                        }
                    }
                )
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
            }
            // 路径 1: 自创动作 (name + photo + muscle/equipment).
            .sheet(isPresented: $customFormOpen) {
                CustomExerciseFormSheet()
                .presentationDragIndicator(.visible)
            }
            // 编辑已保存的自创动作 — 同一个表单, 预填 + save 走 updateCustomExercise (id 不变).
            .sheet(item: $editingCustom) { ex in
                CustomExerciseFormSheet(editing: ex)
                .presentationDragIndicator(.visible)
            }
            // P1-7: 免费用户点"自己创建"→ paywall
            .sheet(isPresented: $paywallOpen) {
                PaywallScreen()
                .presentationDragIndicator(.visible)
            }
            // 路径 2: 浏览 niche stash + 一键采纳.
            .sheet(isPresented: $nicheBrowseOpen) {
                NicheLibraryBrowseSheet()
                .presentationDragIndicator(.visible)
            }
            // P0-6: 删自创动作二次确认
            .alert(NSLocalizedString("Delete exercise?", comment: ""),
                   isPresented: Binding(get: { pendingDeleteCustom != nil },
                                        set: { if !$0 { pendingDeleteCustom = nil } })) {
                Button(NSLocalizedString("Delete", comment: ""), role: .destructive) {
                    if let ex = pendingDeleteCustom { data.deleteCustomExercise(ex.id) }
                    pendingDeleteCustom = nil
                }
                Button(NSLocalizedString("Cancel", comment: ""), role: .cancel) { pendingDeleteCustom = nil }
            } message: {
                Text(pendingDeleteCustom.map {
                    String(format: NSLocalizedString("“%@” will be permanently removed.", comment: ""), $0.displayName)
                } ?? "")
            }
            // 自创动作被 plan / 历史引用 → 不能删
            .alert(NSLocalizedString("Can't delete — in use", comment: ""),
                   isPresented: Binding(get: { deleteBlockedRef != nil },
                                        set: { if !$0 { deleteBlockedRef = nil } })) {
                Button("OK", role: .cancel) { deleteBlockedRef = nil }
            } message: {
                Text("This exercise is used by a plan or your workout history. Remove it from those first.")
            }
        }
    }
}

// MARK: - Detail (共用 — ExercisePicker / Library Browser 都用这套展示)

struct ExerciseDetailSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let exercise: Exercise
    /// 可选 — 传了就显示底部 "Add to workout" 按钮, tap 时调用并 dismiss.
    /// 没传 → 纯浏览模式 (Library Browser 路径).
    var onAdd: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    /// 是否展开"完整原文" 说明. 默认折叠 — 只显示简化版.
    @State private var showFullInstructions: Bool = false
    @State private var relatedExercises: [Exercise] = []
    @State private var selectedRelatedExercise: Exercise?
    @State private var demoVideoUnavailable = false
    @State private var progressionPresented = false
    @State private var mediaReportPresented = false
    @State private var mediaReportSent = false

    /// Prefer a verified direct demonstration. Search is reserved for unmapped or confirmed unavailable videos.
    /// Transient connection failures and embedding restrictions preserve the direct watch link.
    private var watchDemoURL: URL? {
        if !demoVideoUnavailable, let u = exercise.videoURL { return u }
        let query = "\(exercise.name) exercise how to"
        guard let enc = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return nil }
        return URL(string: "https://www.youtube.com/results?search_query=\(enc)")
    }

    /// YouTube provides a public thumbnail for curated video links; search results have no reliable single preview.
    private var videoThumbnailURL: URL? {
        demoVideoUnavailable ? nil : ExerciseMediaPolicy.youtubeThumbnail(for: exercise)
    }

    @ViewBuilder
    private var watchDemoControl: some View {
        if let url = watchDemoURL {
            if videoThumbnailURL == nil {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Text("Find demo")
                        Image(systemName: "arrow.up.right")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .fixedSize(horizontal: true, vertical: false)
                .tint(MasoColor.text)
            } else {
            Link(destination: url) {
                MasoColor.surfaceHi
                    .aspectRatio(16.0 / 9.0, contentMode: .fit)
                    .overlay {
                        if let thumbnailURL = videoThumbnailURL {
                            GeometryReader { geometry in
                                AsyncImage(url: thumbnailURL) { phase in
                                    if case .success(let image) = phase {
                                        image.resizable().scaledToFill()
                                            .frame(width: geometry.size.width, height: geometry.size.height)
                                            .clipped()
                                    }
                                }
                            }
                        }
                    }
                    .overlay {
                        Image(systemName: "play.fill")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
                    .contentShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(NSLocalizedString("Watch demo", comment: ""))
            .padding(.top, 8)
            }
        }
    }

    /// 是否值得显示"展开"按钮 — 仅当原 instructions 比简化版有"多余信息" 时.
    /// 多余 = 条目更多 / 任意一条被截断 (字符差).
    private var hasMoreDetail: Bool {
        let simp = exercise.simplifiedInstructions
        if exercise.instructions.count > simp.count { return true }
        // 同步条数下, 简化版任意一行被截断 (含 …) 或长度比原文短 → 有"多余"
        let origJoined = exercise.instructions.joined(separator: "\n")
        let simpJoined = simp.joined(separator: "\n")
        return origJoined.count > simpJoined.count
    }

    /// VARIANT 区 — 名字拆解出 variant 前缀时显示: [标签] vs [基础动作] + 对比说明.
    /// e.g. "High Face Pull (Cable)" → High · vs Face Pull · "锚点更高 … 更偏后束与上背".
    @ViewBuilder
    private var variantSection: some View {
        // #nameParts 优先 (名字带 " · " 分隔符后老的字符串解析不再可靠); 自创动作回退老启发式.
        if let label = exercise.nameParts?.variation ?? ExerciseGrouping.extractedModifier(of: exercise) {
            let base = exercise.nameParts?.base ?? ExerciseGrouping.baseName(of: exercise)
            let comparison = ExerciseGrouping.variantComparison(forLabel: label)
            VStack(alignment: .leading, spacing: 8) {
                Text("Variant")
                    .font(.headline)
                    .foregroundStyle(MasoColor.text)
                HStack(spacing: 8) {
                    Text(label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MasoColor.text)
                    Text(String(format: NSLocalizedString("vs %@", comment: "variant compared with base move"), base))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !comparison.isEmpty {
                    Text(comparison)
                        .font(.body)
                        .foregroundStyle(MasoColor.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .lineSpacing(2)
                }
            }
        }
    }

    @ViewBuilder
    private var equipmentSection: some View {
        let raws = exercise.equipmentAll?.isEmpty == false ? exercise.equipmentAll! : [exercise.equipment].compactMap { $0 }
        let names = Array(Set(raws)).sorted().map(Exercise.equipmentDisplayName(for:))
        if !names.isEmpty {
            Text(verbatim: names.joined(separator: " · "))
                .font(.caption.weight(.medium))
                .foregroundStyle(MasoColor.textDim)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// 关联动作区 — 基础动作显示所有变种；变种动作显示基础动作和同组变种。
    /// 当前动作从入口列表中排除，避免重复打开自身。
    @ViewBuilder
    private var relatedExercisesSection: some View {
        if !relatedExercises.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Related exercises").font(.headline).foregroundStyle(.primary)
                InlineExerciseList(exercises: relatedExercises) {
                    selectedRelatedExercise = $0
                }
            }
        }
    }

    /// 将分组计算放到后台，避免大动作库在详情页打开时阻塞首帧。
    @MainActor
    private func loadRelatedExercises() async {
        let library = data.userLibrary + data.unadoptedNicheExercises
        var seenIDs = Set<String>()
        let uniqueLibrary = library.filter { seenIDs.insert($0.id).inserted }
        let currentID = exercise.id
        let matches = await Task.detached(priority: .userInitiated) {
            ExerciseGrouping.group(uniqueLibrary)
                .first(where: { $0.all.contains(where: { $0.id == currentID }) })?
                .all.filter { $0.id != currentID } ?? []
        }.value
        guard !Task.isCancelled else { return }
        relatedExercises = matches
    }

    /// 顶部 metadata chip row — level / mechanic / movement / tempo / unilateral / equipment.
    /// 每条都 nil-skip, 没有的字段不渲染 (老 schema 数据可能缺很多).
    @ViewBuilder
    private var metadataChipsRow: some View {
        let chips = exerciseMetadataChips()
        if !chips.isEmpty {
            Text(chips.joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    /// 把 Exercise 的 metadata 字段转成 localized chip 文案数组.
    /// 顺序固定: level → mechanic → movement → tempo → unilateral → equipment.
    private func exerciseMetadataChips() -> [String] {
        var out: [String] = []
        // Level
        if let lvl = exercise.level {
            let key: String = {
                switch lvl {
                case .beginner: return "Beginner"
                case .intermediate: return "Intermediate"
                case .expert, .advanced: return "Advanced"
                }
            }()
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Mechanic
        if let mech = exercise.mechanic {
            let key = mech == .compound ? "Compound" : "Isolation"
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Movement pattern
        if let mp = exercise.movementPattern {
            let key: String = {
                switch mp {
                case .pushHorizontal: return "Horizontal push"
                case .pushVertical:   return "Vertical push"
                case .pullHorizontal: return "Horizontal pull"
                case .pullVertical:   return "Vertical pull"
                case .hinge:          return "Hinge"
                case .squat:          return "Squat"
                case .lunge:          return "Lunge"
                case .rotation:       return "Rotation"
                }
            }()
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Tempo
        if let t = exercise.tempo {
            let key: String = {
                switch t {
                case .strength:    return "Strength tempo"
                case .hypertrophy: return "Hypertrophy tempo"
                case .endurance:   return "Endurance tempo"
                case .explosive:   return "Explosive tempo"
                case .isometric:   return "Isometric hold"
                }
            }()
            out.append(NSLocalizedString(key, comment: ""))
        }
        // Unilateral
        if exercise.unilateral == true {
            out.append(NSLocalizedString("Unilateral", comment: ""))
        }
        // Equipment — 仅显示首选 (Library 已经有 equipment filter, 详情页这里只补一个 chip)
        if let eq = exercise.equipment {
            out.append(Exercise.equipmentDisplayName(for: eq))
        }
        return out
    }

    // MARK: - Your history (该动作的个人训练记录 — "我上次推了多重")

    /// 一天一条: 当日最佳组 (有负重 → e1RM 最大那组; 纯自重/次数 → reps 最多那组). 时间升序.
    private struct DayBest: Identifiable {
        let day: Date
        let weight: Double?   // nil = 无负重记录 (只显示 reps)
        let reps: Int
        let e1rm: Double?     // 仅负重组有
        var id: Date { day }
    }

    /// 该动作在 data.sets 的按天最佳记录. Epley e1RM = w*(1+r/30), 跟 Insights 同口径.
    private var historyDayBests: [DayBest] {
        let cal = Calendar.current
        var weighted: [Date: (w: Double, r: Int, e: Double)] = [:]
        var repsOnly: [Date: Int] = [:]
        for s in data.sets where s.exerciseId == exercise.id {
            let day = cal.startOfDay(for: s.performedAt)
            if let w = s.weight, let r = s.reps, w > 0, r > 0 {
                let e = w * (1 + Double(r) / 30)
                if e > (weighted[day]?.e ?? 0) { weighted[day] = (w, r, e) }
            } else if let r = s.reps, r > 0 {
                repsOnly[day] = max(repsOnly[day] ?? 0, r)
            }
        }
        var out: [DayBest] = weighted.map { DayBest(day: $0.key, weight: $0.value.w, reps: $0.value.r, e1rm: $0.value.e) }
        // 该天没有负重组才用纯次数兜底 (混合时负重组更有信息量)
        out += repsOnly.filter { weighted[$0.key] == nil }.map { DayBest(day: $0.key, weight: nil, reps: $0.value, e1rm: nil) }
        return out.sorted { $0.day < $1.day }
    }

    /// "Your history" 小节 — 有记录才渲染: 历史最佳 e1RM + 迷你 sparkline + 最近 3 次训练的当日最佳组.
    /// 库入口 / picker 入口 / History 详情入口共用本 sheet, 一处生效三处可见.
    @ViewBuilder
    private var historySection: some View {
        let bests = historyDayBests
        if !bests.isEmpty {
            let rmSeries = bests.filter { $0.e1rm != nil }
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Your history")
                        .font(.headline)
                        .foregroundStyle(MasoColor.text)
                    Spacer()
                    // 历史最佳 (max e1RM) — 单位走 weightLabel 管线, 跟随 kg/lb 设置.
                    if let top = rmSeries.compactMap(\.e1rm).max() {
                        Text(String(format: NSLocalizedString("Best e1RM %@", comment: "exercise detail history"),
                                    weightLabel(top)))
                            .font(.system(size: 11, weight: .bold).monospacedDigit())
                            .foregroundStyle(MasoColor.accent)
                    }
                }
                // 迷你 e1RM 趋势 (≥2 个负重日才画 — 单点画不成线)
                if rmSeries.count >= 2 {
                    Chart(rmSeries) { p in
                        LineMark(
                            x: .value("Date", p.day),
                            y: .value("e1RM", p.e1rm ?? 0)
                        )
                        .foregroundStyle(MasoColor.accent)
                        .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                        .interpolationMethod(.monotone)
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    // y 轴不从 0 起 — sparkline 只看趋势, 留一点上下呼吸空间
                    .chartYScale(domain: sparklineDomain(rmSeries.compactMap(\.e1rm)))
                    .frame(height: 40)
                }
                // 最近 3 次训练: 日期 · 当日最佳组
                ForEach(bests.suffix(3).reversed()) { b in
                    HStack {
                        Text(relativeDay(b.day))
                            .font(.system(size: 13))
                            .foregroundStyle(MasoColor.textDim)
                        Spacer()
                        Text(b.weight.map { "\(weightLabel($0)) × \(b.reps)" }
                             ?? String(format: NSLocalizedString("%d reps", comment: ""), b.reps))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .foregroundStyle(MasoColor.text)
                    }
                }
            }
            .padding(MasoMetrics.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
        }
    }

    /// sparkline y 域: [min, max] 各留 10% padding; 全部同值时给 ±1 防零高度域.
    private func sparklineDomain(_ values: [Double]) -> ClosedRange<Double> {
        guard let lo = values.min(), let hi = values.max() else { return 0...1 }
        if lo == hi { return (lo - 1)...(hi + 1) }
        let pad = (hi - lo) * 0.1
        return (lo - pad)...(hi + pad)
    }

    var body: some View {
        AppNavigationStack {
            GeometryReader { geometry in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        ExerciseMediaHero(exercise: exercise, width: geometry.size.width, allowsYouTubePlayback: !demoVideoUnavailable, showsTutorial: false)
                        .padding(.horizontal, -MasoMetrics.pagePaddingHorizontal)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(exercise.displayName)
                            .font(.title2.weight(.bold))
                            .foregroundStyle(MasoColor.text)
                    }

                    HStack(alignment: .top, spacing: 12) {
                        if !exercise.muscleGroups.isEmpty {
                            MuscleVisualBlock(muscles: exercise.muscleGroups, sideLength: 56)
                                .frame(width: 56, height: 56)
                                .accessibilityHidden(true)
                        }
                        VStack(alignment: .leading, spacing: 8) {
                            let primary = exercise.primaryMuscles.filter { exercise.muscleGroups.contains($0) }
                            let secondary = exercise.muscleGroups.filter { !primary.contains($0) }
                            if !primary.isEmpty || !secondary.isEmpty {
                                let first = Text(verbatim: primary.map(\.displayName).joined(separator: " · "))
                                    .fontWeight(.semibold).foregroundColor(MasoColor.text)
                                let rest = Text(verbatim: (primary.isEmpty || secondary.isEmpty ? "" : " · ") + secondary.map(\.displayName).joined(separator: " · "))
                                    .foregroundColor(MasoColor.textDim)
                                (first + rest).font(.subheadline).fixedSize(horizontal: false, vertical: true)
                            }
                            equipmentSection
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Button {
                        mediaReportPresented = true
                    } label: {
                        Label("Report exercise media", systemImage: "flag")
                            .font(.caption.weight(.medium))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(MasoColor.accent)
                    .accessibilityIdentifier("exercise.media.report")

                    if ExerciseWeightReference.expectsLoad(exercise) {
                        Button("Weight progression") { progressionPresented = true }
                            .buttonStyle(.bordered).controlSize(.small)
                            .accessibilityIdentifier("exercise.progression.open")
                    }

                    // Instructions — 默认显示简化版 (LLM 提取的 2-3 个关键要点 / fallback 截断).
                    // 用户想看完整原文 → 点 "Show full instructions" 展开.
                    if !exercise.instructions.isEmpty || (!demoVideoUnavailable && ExerciseMediaPolicy.youtubeID(exercise.videoURL) != nil) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(alignment: .center, spacing: 8) {
                                Text("How to do it")
                                    .font(.headline).foregroundStyle(MasoColor.text)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                if !demoVideoUnavailable, ExerciseMediaPolicy.youtubeID(exercise.videoURL) != nil, let url = exercise.videoURL {
                                    ExerciseYouTubeLink(url: url, exercise: exercise, compact: true)
                                        .accessibilityIdentifier("exercise.youtube")
                                }
                            }

                            // 展示数据源: 折叠状态 = simplified; 展开 = 原 instructions
                            let lines = showFullInstructions
                                ? exercise.instructions
                                : exercise.simplifiedInstructions
                            ForEach(Array(lines.enumerated()), id: \.offset) { idx, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(idx + 1).")
                                        .font(.body.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                        .frame(minWidth: 22, alignment: .leading)
                                    Text(line)
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }

                            // 仅当原文比简化版有"多余" (条目数更多 / 单条更长被截断) 时显示折叠按钮
                            if hasMoreDetail {
                                Button {
                                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) {
                                        showFullInstructions.toggle()
                                    }
                                } label: {
                                    Label(showFullInstructions
                                          ? NSLocalizedString("Show less", comment: "")
                                          : NSLocalizedString("Show full instructions", comment: ""),
                                          systemImage: showFullInstructions ? "chevron.up" : "chevron.down")
                                }
                                .buttonStyle(.borderless)
                                .foregroundStyle(.secondary)
                            }

                            // Video preview sits below the instructions and aligns to the section's leading edge.
                            if demoVideoUnavailable || ExerciseMediaPolicy.youtubeID(exercise.videoURL) == nil {
                                watchDemoControl
                            }
                        }
                    }


                    // Safety / form cues — 来自 danger_warnings 字段 (新 schema).
                    // 高难度动作 (deadlift / squat / OHP / etc.) 才会有, isolation 通常空.
                    let warnings = exercise.localizedDangers
                    if !warnings.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Form cues")
                                .font(.headline)
                                .foregroundStyle(MasoColor.text)
                            ForEach(Array(warnings.enumerated()), id: \.offset) { _, line in
                                HStack(alignment: .top, spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.body)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 3)
                                    Text(line)
                                        .font(.body)
                                        .foregroundStyle(MasoColor.text)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }

                    // Your history — 该动作的个人记录 (最近 3 次最佳组 + 历史最佳 e1RM + 趋势).
                    // 个人记录位于动作说明之后、关联动作之前。
                    historySection

                    // 选择训练 CTA (ExercisePicker 路径传 onAdd 时显示)
                    if let onAdd {
                        Button(action: {
                            onAdd()
                            dismiss()
                        }) {
                            Label("Add to workout", systemImage: "plus")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }

                    // Keep the variant explanation next to related exercises.
                    variantSection

                    // Show all related variants at the bottom.
                    relatedExercisesSection
                }
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                    .padding(.bottom, MasoMetrics.pagePaddingHorizontal)
                }
                .scrollIndicators(.hidden)
                .ignoresSafeArea(edges: .top)

            }
            .ignoresSafeArea(edges: .top)
            }
            .ignoresSafeArea(edges: .top)
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .appUnobstructedMediaHeader()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    let favorited = data.isFavorite(exercise.id)
                    Button {
                        data.toggleFavorite(exercise.id)
                        Haptics.tap()
                    } label: {
                        Image(systemName: favorited ? "pin.fill" : "pin")
                    }
                    .accessibilityLabel(favorited
                                        ? NSLocalizedString("Unpin", comment: "")
                                        : NSLocalizedString("Pin to top", comment: ""))
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
            .task(id: exercise.id) {
                await loadRelatedExercises()
            }
            .task(id: exercise.videoURL) {
                demoVideoUnavailable = false
                if let url = exercise.videoURL {
                    let unavailable = await ExerciseDemoVideoValidator.shared.isUnavailable(url)
                    if !Task.isCancelled { demoVideoUnavailable = unavailable }
                }
            }
            .sheet(isPresented: $progressionPresented) {
                ExerciseLoadProgressionSheet(exercise: exercise)
            }
            .sheet(isPresented: $mediaReportPresented) {
                FeedbackSheet(onSuccess: { mediaReportSent = true }, exercise: exercise)
                    .presentationDragIndicator(.visible)
            }
            .alert("Report received", isPresented: $mediaReportSent) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Report received. It will be included in the next weekly digest.")
            }
            .sheet(item: $selectedRelatedExercise) { related in
                ExerciseDetailSheet(exercise: related)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }
}


/// Only confirmed removed/private videos fall back to search; network failures retain the direct link.
private actor ExerciseDemoVideoValidator {
    static let shared = ExerciseDemoVideoValidator()
    private var cache: [URL: (date: Date, unavailable: Bool)] = [:]

    func isUnavailable(_ url: URL) async -> Bool {
        if let cached = cache[url], Date().timeIntervalSince(cached.date) < 6 * 3600 {
            return cached.unavailable
        }
        guard let host = url.host?.lowercased(),
              host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com") else { return false }
        var components = URLComponents(string: "https://www.youtube.com/oembed")!
        components.queryItems = [URLQueryItem(name: "url", value: url.absoluteString), URLQueryItem(name: "format", value: "json")]
        guard let endpoint = components.url else { return false }
        do {
            let (_, response) = try await URLSession.shared.data(for: URLRequest(url: endpoint, timeoutInterval: 8))
            guard let response = response as? HTTPURLResponse else { return false }
            var unavailable = [404, 410].contains(response.statusCode)
            // An oEmbed 401 can also mean embedding is disabled while the watch link still works.
            // Inspect the watch page before treating it as a private/removed video.
            if response.statusCode == 401 {
                unavailable = await watchPageConfirmsUnavailable(url)
            }
            if response.statusCode == 200 || unavailable { cache[url] = (Date(), unavailable) }
            return unavailable
        } catch {
            return false
        }
    }

    private func watchPageConfirmsUnavailable(_ url: URL) async -> Bool {
        do {
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var query = components?.queryItems ?? []
            query.append(URLQueryItem(name: "hl", value: "en"))
            components?.queryItems = query
            guard let watchURL = components?.url else { return false }
            let (bytes, _) = try await URLSession.shared.data(for: URLRequest(url: watchURL, timeoutInterval: 8))
            guard let html = String(data: bytes, encoding: .utf8),
                  let pattern = try? NSRegularExpression(pattern: #"(?:var )?ytInitialPlayerResponse\s*=\s*(\{.*?\});"#, options: [.dotMatchesLineSeparators]),
                  let match = pattern.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                  let range = Range(match.range(at: 1), in: html),
                  let json = String(html[range]).data(using: .utf8),
                  let player = try JSONSerialization.jsonObject(with: json) as? [String: Any],
                  let playability = player["playabilityStatus"] as? [String: Any],
                  let status = playability["status"] as? String,
                  status != "OK",
                  let reason = playability["reason"] as? String else { return false }
            let message = reason.lowercased()
            return ["private", "removed", "deleted", "video unavailable", "no longer available"].contains(where: message.contains)
        } catch {
            return false
        }
    }

}
