import SwiftUI
import AVFoundation
import ImageIO

/// Rendering ownership is independent of historical image-folder aliases.
/// A legacy two-frame asset belongs to one exact exercise; variants use their
/// own linked YouTube thumbnail instead of borrowing another movement's demo.
enum ExerciseMediaPolicy {
    static let legacyOwners: [String: String] = {
        let groups = Dictionary(grouping: ExerciseLibrary.all.filter { $0.imageFolder != nil }, by: { $0.imageFolder! })
        // Reviewed against the source database's equipment and execution instructions.
        let reviewed: [String: String] = [
            "Air_Bike": "crunch_bicycle",
            "Alternate_Hammer_Curl": "hammer_curl",
            "Arnold_Dumbbell_Press": "arnold_press_seated",
            "Around_The_Worlds": "around_the_world_dumbbell",
            "Axle_Deadlift": "deadlift",
            "Barbell_Bench_Press_-_Medium_Grip": "bench_press_barbell",
            "Barbell_Glute_Bridge": "glute_bridge_barbell",
            "Barbell_Hip_Thrust": "hip_thrust_barbell",
            "Barbell_Incline_Bench_Press_-_Medium_Grip": "incline_bench_press_barbell",
            "Barbell_Seated_Calf_Raise": "calf_raise_seated",
            "Barbell_Shrug": "shrug_barbell",
            "Barbell_Step_Ups": "step_up_barbell",
            "Barbell_Walking_Lunge": "lunge_walking_barbell",
            "Battling_Ropes": "battle_rope_alternating",
            "Bench_Dips": "bench_dip",
            "Bent-Arm_Barbell_Pullover": "barbell_pullover",
            "Bent-Arm_Dumbbell_Pullover": "dumbbell_pullover",
            "Bent_Over_Two-Dumbbell_Row": "dumbbell_row",
            "Bicycling": "cycling_outdoor",
            "Box_Squat": "squat_box",
            "Cable_Chest_Press": "chest_press_cable_bilateral_seated",
            "Cable_Crossover": "cable_crossover_high",
            "Cable_Preacher_Curl": "preacher_curl_cable",
            "Cable_Rear_Delt_Fly": "rear_delt_fly_cable",
            "Cable_Rope_Overhead_Triceps_Extension": "overhead_extension_cable_rope",
            "Cable_Wrist_Curl": "wrist_curl_cable",
            "Calf_Press_On_The_Leg_Press_Machine": "calf_raise_leg_press",
            "Childs_Pose": "childs_pose",
            "Straight-Arm_Pulldown": "straight_arm_pulldown",
            "Bent_Over_Two-Arm_Long_Bar_Row": "t_bar_row",
            "Chin-Up": "chin_up",
            "Close-Grip_Barbell_Bench_Press": "bench_press_close_grip",
            "Close-Grip_Front_Lat_Pulldown": "lat_pulldown",
            "Concentration_Curls": "concentration_curl",
            "Decline_Barbell_Bench_Press": "decline_bench_press_barbell",
            "Donkey_Calf_Raises": "calf_raise_donkey_partner",
            "Drag_Curl": "drag_curl",
            "Dumbbell_Alternate_Bicep_Curl": "bicep_curl_dumbbell",
            "Dumbbell_Incline_Row": "incline_dumbbell_row",
            "EZ-Bar_Curl": "bicep_curl_ez_bar",
            "EZ-Bar_Skullcrusher": "skullcrusher_ez_bar",
            "Elliptical_Trainer": "elliptical",
            "Face_Pull": "face_pull",
            "Farmers_Walk": "farmers_carry",
            "Freehand_Jump_Squat": "squat_jump",
            "Front_Cable_Raise": "front_raise_cable",
            "Glute_Kickback": "donkey_kick",
            "Hamstring_Stretch": "hamstring_stretch_supine",
            "Hyperextensions_Back_Extensions": "back_extension_45_degree",
            "Incline_Cable_Flye": "cable_fly_incline",
            "Inverted_Row": "inverted_row",
            "Jogging_Treadmill": "treadmill_run",
            "Jackknife_Sit-Up": "v_up",
            "Leg_Extensions": "leg_extension_machine",
            "Lying_T-Bar_Row": "t_bar_row_chest_supported",
            "Mountain_Climbers": "mountain_climber",
            "Pallof_Press": "pallof_press_cable",
            "Reverse_Barbell_Curl": "reverse_curl",
            "Romanian_Deadlift": "rdl_barbell",
            "Rope_Jumping": "jump_rope_basic",
            "Rope_Straight-Arm_Pulldown": "straight_arm_pulldown_rope",
            "Seated_Bent-Over_Rear_Delt_Raise": "rear_delt_fly_dumbbell_seated",
            "Side_Leg_Raises": "side_leg_raise",
            "Single-Leg_High_Box_Squat": "single_leg_squat_box",
            "Smith_Machine_Overhead_Shoulder_Press": "overhead_press_smith_seated",
            "Spider_Curl": "spider_curl",
            "Superman": "superman",
            "Thigh_Abductor": "abductor_machine",
            "Tricep_Dumbbell_Kickback": "kickback_dumbbell_both_arms",
            "Weighted_Crunches": "crunch_weighted",
            "Zercher_Squats": "squat_zercher",
        ]
        // Oct 23 visual audit: these six single-owner aliases depict different exercises.
        // Preserve historical aliases while resolving their current media through the normal fallback.
        let retired: Set<String> = ["Barbell_Seated_Calf_Raise", "Machine_Bicep_Curl", "Star_Jump", "Elevated_Cable_Rows", "Triceps_Pushdown", "Incline_Cable_Chest_Press", "Alternating_Floor_Press", "Neck_Press", "Cable_Seated_Lateral_Raise", "Crossover_Reverse_Lunge", "Kipping_Muscle_Up", "Kettlebell_Pistol_Squat", "Split_Squats", "Barbell_Side_Bend", "Barbell_Side_Split_Squat", "Kettlebell_Thruster", "Dumbbell_One-Arm_Upright_Row", "Barbell_Squat", "Round_The_World_Shoulder_Stretch", "Side_Laterals_to_Front_Raise", "Sit-Up", "Lying_Machine_Squat", "Sled_Row"]
        return groups.reduce(into: [:]) { result, group in
            let (folder, exercises) = group
            guard !retired.contains(folder) else { return }
            if let owner = reviewed[folder], exercises.contains(where: { $0.id == owner }) { result[folder] = owner }
            else if exercises.count == 1 { result[folder] = exercises[0].id }
            // An ambiguous new mapping must be reviewed, never chosen by name similarity.
        }
    }()

    static func ownsLegacy(_ id: String?, folder: String) -> Bool {
        guard let id, let exercise = ExerciseLibrary.byId[id] else { return false }
        return legacyOwners[folder] == exercise.id
    }

    static func youtubeThumbnail(for exercise: Exercise?) -> URL? {
        guard let id = youtubeID(exercise?.videoURL) else { return nil }
        return URL(string: "https://img.youtube.com/vi/\(id)/mqdefault.jpg")
    }

    /// Match the actual hero fallback order, rather than treating every video link as a YouTube cover.
    @MainActor static func usesYouTubeThumbnail(for exercise: Exercise) -> Bool {
        guard exercise.customImageData == nil,
              ExerciseDemoService.shared.files[exercise.id] == nil,
              CoreExerciseDemos.assets[exercise.id] == nil else { return false }
        if let folder = exercise.imageFolder, ownsLegacy(exercise.id, folder: folder) { return false }
        return youtubeThumbnail(for: exercise) != nil
    }

    static func youtubeID(_ url: URL?) -> String? {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = c.host?.lowercased(), ["https", "http"].contains(c.scheme?.lowercased() ?? "") else { return nil }
        let id: String?
        if host == "youtu.be" { id = c.path.split(separator: "/").first.map(String.init) }
        else if host == "youtube.com" || host.hasSuffix(".youtube.com") {
            let parts = c.path.split(separator: "/")
            id = c.queryItems?.first(where: { $0.name == "v" })?.value
                ?? (parts.count >= 2 && ["embed", "shorts", "live"].contains(String(parts[0])) ? String(parts[1]) : nil)
        } else { return nil }
        guard let id, id.count == 11,
              id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else { return nil }
        return id
    }
}

/// The player and both exercise-detail heroes share measured bounds, centered
/// aspect-fill cropping, and media loading. Screen-specific fades stay outside.
struct FullBleedExerciseImage: View {
    let exercise: Exercise
    var playbackEnabled = true
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(colors: [Color(white: 0.18), MasoColor.background],
                               startPoint: .top, endPoint: .bottom)
                if let bytes = exercise.customImageData, let image = UIImage(data: bytes) {
                    ExerciseAspectFillPhoto(image: image, contentMode: contentMode)
                } else if let url = ExerciseDemoService.shared.files[exercise.id] {
                    if url.pathExtension.lowercased() == "gif" {
                        GeneratedExerciseGIF(url: url, playbackEnabled: playbackEnabled, contentMode: contentMode)
                    } else {
                        GeneratedExerciseVideo(url: url, playbackEnabled: playbackEnabled, contentMode: contentMode)
                    }
                } else if let thumbnail = CoreExerciseDemos.thumbnail(exercise.id) {
                    ExerciseAspectFillPhoto(image: thumbnail, contentMode: contentMode)
                } else if let folder = exercise.imageFolder, ExerciseMediaPolicy.ownsLegacy(exercise.id, folder: folder) {
                    CrossFadeFrames(folder: folder, animated: playbackEnabled, contentMode: contentMode)
                } else if let thumbnail = ExerciseMediaPolicy.youtubeThumbnail(for: exercise) {
                    CachedPhotoImage(urlString: thumbnail.absoluteString, contentMode: contentMode)
                } else if let photoURL = exercise.photoURL {
                    CachedPhotoImage(urlString: photoURL, contentMode: contentMode)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .overlay(alignment: .topLeading) {
                if exercise.customImageData == nil && CoreExerciseDemos.isUnverified(exercise.id) {
                    Text("exercise.media.unverified")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(.black.opacity(0.72), in: Capsule())
                        .padding(8)
                }
            }
            .clipped()
        }
        .task(id: "\(exercise.id)|\(ExerciseDemoService.shared.remoteAssets[exercise.id]?.sha256 ?? "")") {
            guard exercise.customImageData == nil else { return }
            await ExerciseDemoService.shared.loadMedia(exercise.id)
            // A transient network failure should not leave the poster in place
            // for the entire time the detail/player remains visible.
            guard CoreExerciseDemos.assets[exercise.id] != nil || ExerciseDemoService.shared.remoteAssets[exercise.id] != nil else { return }
            for _ in 0..<3 {
                guard !Task.isCancelled, ExerciseDemoService.shared.files[exercise.id] == nil else { return }
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, ExerciseDemoService.shared.files[exercise.id] == nil else { return }
                await ExerciseDemoService.shared.loadMedia(exercise.id, force: true)
            }
        }
    }
}

// Spotify "album cover" 风格的动作缩略图 — DESIGN §3.3
//   - 两帧 cross-fade (yuhonas/free-exercise-db 的 0.jpg + 1.jpg)
//   - 加载中 / 失败时回退到 category 渐变
//   - 用 jsdelivr CDN URL (比 GitHub raw 稳)
//   - animated=true (默认): TimelineView 驱动 2s 周期切换两帧
//   - animated=false: 只显示 0.jpg (列表 / 缩略图用)
struct ExerciseImage: View {
    @Environment(\.displayScale) private var displayScale
    let category: ExerciseCategory
    var exerciseID: String? = nil
    /// 来自 Exercise.imageFolder; 为 nil 时直接用渐变占位
    var imageFolder: String? = nil
    /// 单图缩略图完整 URL (Pexels 来源动作). imageFolder 为 nil 时回退到这里, 单张静态图.
    var photoURL: String? = nil
    /// 用户自创动作的图片 bytes — 优先于 imageFolder. 自创动作 imageFolder 永远 nil.
    /// caller (Library Browser / Picker 列表行) 把 Exercise.customImageData 传进来.
    var customImageData: Data? = nil
    var cornerRadius: CGFloat = 4
    var size: CGFloat = 48
    /// 是否做两帧 cross-fade 动画
    var animated: Bool = true
    /// Detail heroes preserve the original photo colors.
    var appliesCategoryTint: Bool = true

    /// A bundled poster is safe only while its adopted asset matches the live catalog.
    private var currentBundledPoster: UIImage? {
        guard let id = exerciseID, let bundled = CoreExerciseDemos.assets[id] else { return nil }
        let service = ExerciseDemoService.shared
        if service.hasRemoteCatalog && service.remoteAssets[id]?.sha256 != bundled.sha256 { return nil }
        return CoreExerciseDemos.thumbnail(id)
    }

    private var hasAdoptedMedia: Bool {
        guard let id = exerciseID else { return false }
        let service = ExerciseDemoService.shared
        return service.hasRemoteCatalog ? service.remoteAssets[id] != nil : CoreExerciseDemos.assets[id] != nil
    }

    var body: some View {
        ZStack {
            // 底层 — category 渐变 (作为加载中 / 失败的兜底)
            LinearGradient(colors: [Color(white: 0.20), Color(white: 0.12)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(
                    Image(systemName: iconName)
                        .foregroundStyle(.white.opacity(0.35))
                        .font(.system(size: size * 0.4, weight: .semibold))
                )

            // 自创动作图片 — 优先级最高. PhotosPicker 拿到的 JPEG bytes, 直接 UIImage(data:).
            if let imageData = customImageData, let ui = UIImage(data: imageData) {
                ExerciseAspectFillPhoto(image: ui)
            } else if let id = exerciseID, let url = ExerciseDemoService.shared.files[id] {
                if url.pathExtension.lowercased() == "gif" && animated {
                    GeneratedExerciseGIF(url: url, maxPixelSize: max(120, Int(size * displayScale)))
                } else {
                    ExerciseDemoThumbnail(url: url, fallback: currentBundledPoster).id(url)
                }
            } else if let thumbnail = currentBundledPoster {
                ExerciseAspectFillPhoto(image: thumbnail)
            } else if hasAdoptedMedia {
                // An approved newer image is loading: never show an older unrelated fallback.
                Color.clear
            } else if let folder = imageFolder, ExerciseMediaPolicy.ownsLegacy(exerciseID, folder: folder) {
                // bundle 动作两帧 cross-fade.
                // CrossFadeFrames: 共享 UIImage cache + 严格 frame 锚定, 解决两帧
                // intrinsic size 略不同时 scaledToFill 算出不同 scale → 像素抖动的问题.
                CrossFadeFrames(folder: folder, animated: animated)
                    .id(folder)
                    .overlay(
                        // 强调色调染 — 类似 Spotify album cover 的多色叠加
                        gradient.opacity(appliesCategoryTint ? 0.35 : 0).blendMode(.multiply)
                    )
            } else if let id = exerciseID, let thumbnail = ExerciseMediaPolicy.youtubeThumbnail(for: ExerciseLibrary.byId[id]) {
                CachedPhotoImage(urlString: thumbnail.absoluteString).id(thumbnail.absoluteString)
            } else if let photoURL {
                // Pexels 单张静态图 — 走共享 ExerciseImageCache (磁盘缓存 + CDN 镜像故障切换),
                // 不再用 view-local AsyncImage (重复下载 + 无镜像切换 → 列表加载慢的主因之一).
                // 轻一点的色染 (0.18 vs 0.35), 真实照片重叠太多会脏.
                CachedPhotoImage(urlString: photoURL).id(photoURL)
                    .overlay(gradient.opacity(appliesCategoryTint ? 0.18 : 0).blendMode(.multiply))
            }
        }
        .frame(width: size, height: size)
        .overlay(alignment: .topTrailing) {
            if customImageData == nil && CoreExerciseDemos.isUnverified(exerciseID) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.system(size: max(10, size * 0.2)))
                    .foregroundStyle(.white, .orange)
                    .padding(3)
                    .accessibilityLabel(Text("exercise.media.unverified"))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .task(id: "\(exerciseID ?? "")|\(ExerciseDemoService.shared.remoteAssets[exerciseID ?? ""]?.sha256 ?? "")") {
            guard customImageData == nil, let id = exerciseID,
                  CoreExerciseDemos.assets[id] != nil || ExerciseDemoService.shared.remoteAssets[id] != nil else { return }
            await ExerciseDemoService.shared.loadMedia(id)
        }
    }

    private var gradient: LinearGradient {
        let colors: [Color] = {
            switch category {
            case .strength, .hypertrophyFocus, .calisthenics:
                return [MasoColor.accent.opacity(0.55), MasoColor.accent.opacity(0.9)]   // 品牌绿, 非系统绿 (统一 accent)
            case .cardio, .plyometric:
                return [Color.pink.opacity(0.6), Color.pink.opacity(0.95)]
            case .flexibility, .stretching, .mobility:
                return [Color.orange.opacity(0.6), Color.orange.opacity(0.95)]
            }
        }()
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    private var iconName: String {
        switch category {
        case .strength, .hypertrophyFocus, .calisthenics:
            return "dumbbell.fill"
        case .cardio:
            return "figure.run"
        case .plyometric:
            return "figure.jumprope"
        case .flexibility, .stretching, .mobility:
            return "figure.flexibility"
        }
    }
}

// AnimatedFrameImage 已废弃 — 改用共享的 CrossFadeFrames (见 Views/Components/CrossFadeFrames.swift).
// 旧实现的问题: AsyncImage 两帧独立加载, 加载完成时机不同步, 切换那一刻闪烁;
//             scaledToFill 在两张 intrinsic size 不同时算出不同 scale, 像素位置抖动.
// 新实现: 共享 ExerciseImageCache 预加载 UIImage, 严格 GeometryReader + .frame 锚定 size.

// MARK: - CachedPhotoImage — photoURL 单图, 走共享 ExerciseImageCache

/// Pexels 单图加载 view — 同步先查内存 cache (无闪烁), miss 再 async 下载 (磁盘缓存 + 镜像切换).
/// 出现/URL 变化时各触发一次加载; 失败静默 (底层 category 渐变兜底).
private struct CachedPhotoImage: View {
    let urlString: String
    var contentMode: ContentMode = .fill

    @State private var image: UIImage? = nil

    init(urlString: String, contentMode: ContentMode = .fill) {
        self.urlString = urlString
        self.contentMode = contentMode
        _image = State(initialValue: ExerciseImageCache.shared.cachedURL(urlString))
    }

    var body: some View {
        ZStack {
            if let image {
                ExerciseAspectFillPhoto(image: image, contentMode: contentMode).transition(.opacity)
            }
        }
        .task(id: urlString) {
            if let hit = ExerciseImageCache.shared.cachedURL(urlString) {
                image = hit
                return
            }
            let loaded = await ExerciseImageCache.shared.loadURL(urlString)
            withAnimation(.easeOut(duration: 0.2)) { image = loaded }
        }
    }
}


/// Measure the actual tile/hero/player bounds before scaling; oversized intrinsic
/// photo dimensions must not enlarge the layout or leave an inner fit container.
struct ExerciseAspectFillPhoto: View {
    let image: UIImage
    var contentMode: ContentMode = .fill
    var body: some View {
        GeometryReader { geometry in
            Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .clipped()
        }
    }
}


/// Static poster from the same SHA-addressed asset used by the detail hero.
/// URL identity invalidates the frame when an adopted demo is replaced.
struct ExerciseDemoThumbnail: View {
    let url: URL
    let fallback: UIImage?
    @State private var image: UIImage?
    @State private var imageURL: URL?
    private static let cache = NSCache<NSURL, UIImage>()

    var body: some View {
        ZStack {
            // Keep a mounted task host even when this new asset has no bundled
            // fallback; an empty conditional Group can never start decoding.
            Color.clear
            if let image = (imageURL == url ? image : nil) ?? Self.cache.object(forKey: url as NSURL) ?? fallback {
                ExerciseAspectFillPhoto(image: image)
            }
        }
        .task(id: url) {
            image = nil; imageURL = nil
            if let cached = Self.cache.object(forKey: url as NSURL) { imageURL = url; image = cached; return }
            if url.pathExtension.lowercased() == "gif" {
                guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let frame = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: 240
                      ] as CFDictionary), !Task.isCancelled else { return }
                let poster = UIImage(cgImage: frame)
                Self.cache.countLimit = 160
                Self.cache.setObject(poster, forKey: url as NSURL)
                imageURL = url; image = poster
                return
            }
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 240, height: 240)
            do {
                let frame = try await generator.image(at: .zero).image
                guard !Task.isCancelled else { return }
                let poster = UIImage(cgImage: frame)
                Self.cache.countLimit = 160
                Self.cache.setObject(poster, forKey: url as NSURL)
                imageURL = url; image = poster
            } catch { /* Preserve the bundled poster if decoding is unavailable. */ }
        }
    }
}
