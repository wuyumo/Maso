import SwiftUI
import PhotosUI

// MARK: - AddExerciseChoiceSheet
//
// Library Browser 顶部 "+" 触发的两路选择 sheet:
//   1. Create your own — 自己定义 name + photo, 用户视角"我自己的动作".
//   2. Browse rare exercises — 从我们收纳的 58 个 niche 动作里采纳 (Foam Roll / Battle Rope /
//      Hip Abduction Machine / Grip Crusher etc.). 不是新建, 而是把已在数据库里但默认隐藏的
//      动作"挪进自己的库".
//
// 两条路径都最终让动作出现在主 picker 里 (创建 plan 时能选到).

struct AddExerciseChoiceSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onCreateCustom: () -> Void
    let onBrowseNiche: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                VStack(spacing: 12) {
                    Text("Pick how to add an exercise. Either build your own from scratch, or adopt one from our specialized library.")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                        .multilineTextAlignment(.leading)
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                        .padding(.top, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Button(action: { Haptics.tap(); onCreateCustom() }) {
                        choiceCard(
                            icon: "plus.rectangle.on.rectangle",
                            title: "Create your own",
                            subtitle: "Add a name, an image, and tag it to a muscle. Best for moves we don't have."
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    Button(action: { Haptics.tap(); onBrowseNiche() }) {
                        choiceCard(
                            icon: "questionmark.diamond",
                            title: "Browse rare exercises",
                            subtitle: "Foam rolls, battle ropes, machine isolations and other specialized moves we corralled."
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)

                    Spacer()
                }
            }
            .navigationTitle("Add exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
        .presentationBackground(MasoColor.background)
    }

    private func choiceCard(icon: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .heavy))
                .foregroundStyle(MasoColor.accent)
                .frame(width: 36, height: 36)
                .background(MasoColor.accent.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(MasoColor.textDim)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(MasoColor.textFaint)
        }
        .padding(MasoMetrics.cardPadding)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
    }
}

// MARK: - CustomExerciseFormSheet
//
// 自创动作表单. 必填 name + primaryMuscle; 可选 image + equipment. Save → DataStore.addCustomExercise.
// 不要求所有字段 — 用户视角"快速给一个动作命个名 + 选条边", 90 秒能加完一个.

struct CustomExerciseFormSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var selectedMuscle: MuscleGroup = .chest
    @State private var selectedEquipment: String = "body_only"
    @State private var photoItem: PhotosPickerItem? = nil
    @State private var imageData: Data? = nil
    @State private var showingError: String? = nil

    /// "primary muscle" 给用户选的几个大肌群 — 跟 ExercisePickerSheet 顶部分类一致.
    private static let muscleOptions: [MuscleGroup] = [
        .chest, .back, .shoulders, .arms, .core, .legs,
    ]

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                Form {
                    // 图片 — 顶部 hero 区. 跟 share card 的 photo placeholder 同款样式:
                    //   - 没图: 虚线描边 + photo.badge.plus icon (light 字重, textDim) + "Add a photo"
                    //          整块都是 PhotosPicker tap 目标 — 一步到位, 不需要额外按钮
                    //   - 有图: 实色描边 (borderSoft) + 右上角小"Change" 胶囊 (灰底,
                    //          不再用 accent 绿) 给用户重新选的入口
                    Section {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            photoArea
                        }
                        .buttonStyle(.plain)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(MasoColor.surface)

                    // 名称 — 必填
                    Section {
                        TextField(NSLocalizedString("Exercise name", comment: ""), text: $name)
                            .foregroundStyle(MasoColor.text)
                            .submitLabel(.done)
                    } footer: {
                        Text("Required. Shown in plans and history.")
                            .font(.system(size: 11))
                            .foregroundStyle(MasoColor.textFaint)
                    }
                    .listRowBackground(MasoColor.surface)

                    // 主肌群
                    Section {
                        Picker(NSLocalizedString("Primary muscle", comment: ""), selection: $selectedMuscle) {
                            ForEach(Self.muscleOptions, id: \.self) { m in
                                Text(LocalizedStringKey(m.displayName))
                                    .tag(m)
                            }
                        }
                        .foregroundStyle(MasoColor.text)
                    }
                    .listRowBackground(MasoColor.surface)

                    // 器械
                    Section {
                        Picker(NSLocalizedString("Equipment", comment: ""), selection: $selectedEquipment) {
                            ForEach(Exercise.knownEquipments, id: \.self) { eq in
                                Text(Exercise.equipmentDisplayName(for: eq))
                                    .tag(eq)
                            }
                        }
                        .foregroundStyle(MasoColor.text)
                    }
                    .listRowBackground(MasoColor.surface)

                    Section {
                        Text("Custom exercises live only on this device. You can use them in plans and they'll appear in all your pickers.")
                            .font(.system(size: 12))
                            .foregroundStyle(MasoColor.textDim)
                    }
                    .listRowBackground(MasoColor.surface)
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("New exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.bold)
                        .disabled(!canSave)
                }
            }
            .tint(MasoColor.text)
        }
        .presentationBackground(MasoColor.background)
        .onChange(of: photoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                if let raw = try? await newItem.loadTransferable(type: Data.self),
                   let ui = UIImage(data: raw),
                   // 压缩成 JPEG 0.7 — settings.customExercises 进 maso-data.json, 一张图 ~100KB.
                   let jpeg = ui.jpegData(compressionQuality: 0.7) {
                    await MainActor.run { imageData = jpeg }
                }
            }
        }
        .alert("Couldn't save exercise", isPresented: Binding(
            get: { showingError != nil }, set: { if !$0 { showingError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(showingError ?? "")
        }
    }

    /// 图片区 — PhotosPicker 的 label. 两态:
    ///   - 没图: 跟 UnifiedShareCard.photoContent 同款 — 虚线 dashed border + photo.badge.plus
    ///     icon (light 字重) + "Add a photo" 文案, surface 0.4 半透底.
    ///   - 有图: 实色细描边 + 右上角灰底胶囊 "Change" (中性, 不再用 accent 绿).
    /// 比例锁在 160pt 高度 (用户保留这个 ratio 不变).
    @ViewBuilder
    private var photoArea: some View {
        Group {
            if let imageData, let ui = UIImage(data: imageData) {
                ZStack(alignment: .topTrailing) {
                    Color.clear
                        .overlay {
                            Image(uiImage: ui)
                                .resizable()
                                .scaledToFill()
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(MasoColor.borderSoft, lineWidth: 1)
                        )

                    // 右上角 "Change" 胶囊 — 黑底半透 + 白字 (跟 accent 绿无关), 不抢戏.
                    // tap 不需要单独绑 action: 整块 photoArea 已经是 PhotosPicker label,
                    // tap 任意位置 (含这个胶囊) 都会拉相册.
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 10, weight: .heavy))
                        Text("Change")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .padding(10)
                    .allowsHitTesting(false)  // 让 tap 直接命中外层 PhotosPicker, 不被胶囊吃
                }
            } else {
                // 没图: 虚线 + photo.badge.plus + "Add a photo" — UnifiedShareCard 同款.
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(
                            MasoColor.borderSoft,
                            style: StrokeStyle(lineWidth: 1.5, dash: [6, 4])
                        )
                    VStack(spacing: 10) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 38, weight: .light))
                            .foregroundStyle(MasoColor.textDim)
                        Text("Add a photo")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(MasoColor.textDim)
                    }
                }
                .background(MasoColor.surface.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 160)  // 用户要求保留这个比例
        .contentShape(Rectangle())
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // id 用 "custom-{uuid}" 防跟 bundle ID 冲突. exById lookup 透明命中.
        let newId = "custom-\(UUID().uuidString.lowercased().prefix(8))"
        let ex = Exercise(
            id: newId,
            name: trimmed,
            category: .strength,
            tags: [selectedMuscle.displayName],
            primaryMuscles: [selectedMuscle],
            muscleGroups: [selectedMuscle],
            imageFolder: nil,
            level: nil,
            force: nil,
            equipment: selectedEquipment,
            equipmentAll: [selectedEquipment],
            instructions: [],
            movementPattern: nil,
            mechanic: nil,
            unilateral: nil,
            tempo: nil,
            videoURL: nil,
            caloriesEstimate: nil,
            dangerWarnings: nil,
            localizedInstructions: nil,
            localizedName: ["en": trimmed],
            localizedDangerWarnings: nil,
            isNiche: false,
            customImageData: imageData
        )
        data.addCustomExercise(ex)
        Haptics.tap()
        dismiss()
    }
}

// MARK: - NicheLibraryBrowseSheet
//
// 浏览 58 个 niche 动作 (减去用户已采纳的) + 一键采纳. 区别于 ExercisePickerSheet 的 niche 模式:
//   - 这里语义是"加入我的库" (curation), 不是"选进 plan" (pick for use)
//   - 每行右侧有 "Add" 按钮, tap = adoptNicheExercise → 立刻视觉变成 "✓ Added"
//   - 同一 sheet 里能连续采纳多个 — Add 后该项淡出 (从 unadopted 集合移除), 用户继续往下挑

struct NicheLibraryBrowseSheet: View {
    @Environment(DataStore.self) private var data
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    /// 这一 session 里刚 adopt 的 ID — 让 row 短暂显示 "✓ Added" 然后淡出.
    @State private var justAdopted: Set<String> = []

    private var filtered: [Exercise] {
        // 不要在 view 内 mutate data.adoptedNicheExerciseIds — 让 data.unadoptedNicheExercises
        // 自己反应. 这里只过滤 justAdopted (淡出动画) + 搜索关键词.
        var arr = data.unadoptedNicheExercises
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            arr = arr.filter { ex in
                ex.name.lowercased().contains(q) ||
                ex.displayName.lowercased().contains(q)
            }
        }
        return arr
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MasoColor.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    SearchBar(query: $query)
                        .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                        .padding(.vertical, 8)

                    if filtered.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: query.isEmpty ? "checkmark.circle" : "magnifyingglass")
                                .font(.system(size: 32, weight: .heavy))
                                .foregroundStyle(MasoColor.textFaint)
                            Text(query.isEmpty
                                 ? NSLocalizedString("You've adopted everything in the rare library", comment: "")
                                 : NSLocalizedString("No rare exercises match", comment: ""))
                                .font(.system(size: 13))
                                .foregroundStyle(MasoColor.textDim)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .padding(40)
                    } else {
                        List {
                            ForEach(filtered, id: \.id) { ex in
                                row(for: ex)
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .listRowInsets(EdgeInsets(
                                        top: 3, leading: MasoMetrics.pagePaddingHorizontal,
                                        bottom: 3, trailing: MasoMetrics.pagePaddingHorizontal))
                            }
                        }
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .navigationTitle("Rare exercises")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(MasoColor.background, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
        .presentationBackground(MasoColor.background)
    }

    private func row(for ex: Exercise) -> some View {
        let adopted = justAdopted.contains(ex.id)
        return HStack(spacing: 14) {
            ExerciseImage(
                category: ex.category,
                imageFolder: ex.imageFolder,
                cornerRadius: 8,
                size: 48,
                animated: false
            )
            VStack(alignment: .leading, spacing: 4) {
                Text(ex.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(MasoColor.text)
                    .lineLimit(1)
                ExerciseTagsRow(
                    muscleGroups: ex.muscleGroups,
                    equipment: ex.equipment,
                    muscleLimit: 1
                )
            }
            Spacer(minLength: 0)
            Button(action: { adopt(ex) }) {
                HStack(spacing: 4) {
                    Image(systemName: adopted ? "checkmark" : "plus")
                        .font(.system(size: 11, weight: .heavy))
                    Text(adopted ? NSLocalizedString("Added", comment: "")
                                 : NSLocalizedString("Add", comment: ""))
                        .font(.system(size: 12, weight: .heavy))
                }
                .foregroundStyle(adopted ? MasoColor.textDim : .black)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(adopted ? MasoColor.surfaceHi : MasoColor.accent)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(adopted)
        }
        .padding(.horizontal, MasoMetrics.rowPaddingH)
        .padding(.vertical, 10)
        .background(MasoColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func adopt(_ ex: Exercise) {
        Haptics.tap()
        // 闪 "✓ Added" 半秒, 再真正从 unadopted 集合移除 → 自然淡出.
        justAdopted.insert(ex.id)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeOut(duration: 0.25)) {
                data.adoptNicheExercise(ex.id)
            }
            // adoptedNicheExerciseIds 改了, filtered 自动重算, row 消失. justAdopted 残留无影响.
        }
    }
}

// MARK: - 内部小组件: 简单 Search Bar (Library 自己也有一份, 这里独立避免依赖)

private struct SearchBar: View {
    @Binding var query: String
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MasoColor.textDim)
            TextField(NSLocalizedString("Search", comment: ""), text: $query)
                .foregroundStyle(MasoColor.text)
                .submitLabel(.search)
            if !query.isEmpty {
                Button(action: { query = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(MasoColor.textFaint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(MasoColor.surface)
        .clipShape(Capsule())
    }
}
