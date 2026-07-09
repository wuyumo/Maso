import Foundation

// 肌群枚举 — 跟 web 端的 MuscleGroup type 1:1 对齐
// 父类(如 chest) = 用户在 SVG 上点的级别
// 子类(如 upperChest) = 通过 refine chips 精细化, 用于动作精确匹配
// 胸只保留三个解剖头 (上 / 中 / 下), 不再有 inner/outer (跟 web 同步)
enum MuscleGroup: String, Codable, CaseIterable, Hashable, Sendable {
    // 胸
    case chest
    case upperChest
    case midChest
    case lowerChest

    // 背
    case back
    case lats
    case upperLats
    case lowerLats
    case upperTraps
    case midTraps
    case lowerTraps
    case rhomboids
    case teres
    case lowerBack

    // 肩
    case shoulders
    case frontDelts
    case sideDelts
    case rearDelts
    case rotatorCuff   // 肩袖 (Supraspinatus / Infraspinatus / Teres Minor / Subscapularis)

    // 二头
    case biceps
    case bicepsLong
    case bicepsShort
    case brachialis
    case brachioradialis

    // 三头
    case triceps
    case tricepsLong
    case tricepsLateral
    case tricepsMedial

    // 前臂
    case forearms
    case forearmFlexors
    case forearmExtensors

    // 手臂 (聚合)
    case arms

    // 躯干
    case core
    case abs
    case upperAbs
    case lowerAbs
    case obliques
    case serratus
    case neck

    // 腿 (聚合)
    case legs
    case quads
    case rectusFemoris
    case vastusLateralis
    case vastusMedialis
    case hamstrings
    case bicepsFemoris
    case semitendinosus
    case glutes
    case gluteusMaximus
    case gluteusMedius
    case calves
    case gastrocnemius
    case soleus
    case tibialisAnterior
    case adductors

    // 整身 (画图占位用, 不参与匹配)
    case fullBody
}

// Localized display names — keys live in Localizable.strings (en + zh-Hans)
extension MuscleGroup {
    var displayName: String {
        NSLocalizedString(rawDisplayKey, comment: "Muscle name")
    }

    /// 非本地化英文名 — AI prompt (英文语境) 的动作目录肌肉标注用; UI 一律走 displayName.
    /// .back 的 i18n key 是 "Back muscle" (避开导航 "Back" 撞 key), prompt 里用自然的 "Back".
    var englishName: String {
        self == .back ? "Back" : rawDisplayKey
    }

    /// The English source string used as the i18n key for this muscle.
    /// (Looked up at runtime against the active locale's Localizable.strings.)
    private var rawDisplayKey: String {
        switch self {
        case .chest: return "Chest"
        case .upperChest: return "Upper Chest"
        case .midChest: return "Mid Chest"
        case .lowerChest: return "Lower Chest"
        // 用 "Back muscle" 而不是 "Back" — 后者已经被导航 "Back (返回)" 占用,
        // 同 key 不同语义会翻错 (中文 chip 显示"返回" 而不是"背部").
        case .back: return "Back muscle"
        case .lats: return "Lats"
        case .upperLats: return "Upper Lats"
        case .lowerLats: return "Lower Lats"
        case .upperTraps: return "Upper Traps"
        case .midTraps: return "Mid Traps"
        case .lowerTraps: return "Lower Traps"
        case .rhomboids: return "Rhomboids"
        case .teres: return "Teres"
        case .lowerBack: return "Lower Back"
        case .shoulders: return "Shoulders"
        case .frontDelts: return "Front Delts"
        case .sideDelts: return "Side Delts"
        case .rearDelts: return "Rear Delts"
        case .rotatorCuff: return "Rotator Cuff"
        case .biceps: return "Biceps"
        case .bicepsLong: return "Biceps (Long)"
        case .bicepsShort: return "Biceps (Short)"
        case .brachialis: return "Brachialis"
        case .brachioradialis: return "Brachioradialis"
        case .triceps: return "Triceps"
        case .tricepsLong: return "Triceps (Long)"
        case .tricepsLateral: return "Triceps (Lateral)"
        case .tricepsMedial: return "Triceps (Medial)"
        case .forearms: return "Forearms"
        case .forearmFlexors: return "Forearm Flexors"
        case .forearmExtensors: return "Forearm Extensors"
        case .arms: return "Arms"
        case .core: return "Core"
        case .abs: return "Abs"
        case .upperAbs: return "Upper Abs"
        case .lowerAbs: return "Lower Abs"
        case .obliques: return "Obliques"
        case .serratus: return "Serratus"
        case .neck: return "Neck"
        case .legs: return "Legs"
        case .quads: return "Quads"
        case .rectusFemoris: return "Rectus Femoris"
        case .vastusLateralis: return "Vastus Lateralis"
        case .vastusMedialis: return "Vastus Medialis"
        case .hamstrings: return "Hamstrings"
        case .bicepsFemoris: return "Biceps Femoris"
        case .semitendinosus: return "Semitendinosus"
        case .glutes: return "Glutes"
        case .gluteusMaximus: return "Gluteus Maximus"
        case .gluteusMedius: return "Gluteus Medius"
        case .calves: return "Calves"
        case .gastrocnemius: return "Gastrocnemius"
        case .soleus: return "Soleus"
        case .tibialisAnterior: return "Tibialis Anterior"
        case .adductors: return "Adductors"
        case .fullBody: return ""
        }
    }

    /// 顶层"筛选用"分组 — 一个细分肌肉返回它所属的大类 (chest/back/shoulders/arms/core/legs).
    /// 给 ExercisePicker 这种"按肌肉群筛动作" 的 UI 用. fullBody → nil.
    ///
    /// 注意:这个不同于 directToMajor — 那个把 biceps 当 parent (level 1),
    /// 这里把 biceps 进一步归到 arms (level 2 / section).
    var section: MuscleGroup? {
        switch self {
        case .chest, .upperChest, .midChest, .lowerChest:
            return .chest
        case .back, .lats, .upperLats, .lowerLats,
             .upperTraps, .midTraps, .lowerTraps,
             .rhomboids, .teres, .lowerBack:
            return .back
        case .shoulders, .frontDelts, .sideDelts, .rearDelts, .rotatorCuff:
            return .shoulders
        case .arms,
             .biceps, .bicepsLong, .bicepsShort, .brachialis,
             .triceps, .tricepsLong, .tricepsLateral, .tricepsMedial,
             .forearms, .forearmFlexors, .forearmExtensors, .brachioradialis:
            return .arms
        case .core, .abs, .upperAbs, .lowerAbs, .obliques, .serratus, .neck:
            return .core
        case .legs,
             .quads, .rectusFemoris, .vastusLateralis, .vastusMedialis,
             .hamstrings, .bicepsFemoris, .semitendinosus,
             .glutes, .gluteusMaximus, .gluteusMedius,
             .calves, .gastrocnemius, .soleus, .tibialisAnterior,
             .adductors:
            return .legs
        case .fullBody:
            return nil
        }
    }

    /// 这个大肌群作为 ExercisePicker section 选中时, 第二行展示的"子分块"chip 列表.
    /// 跟 section 是反向: section 是 child → parent, 这个是 parent → children.
    ///
    /// 注意 arms / legs 故意只展开一层 (biceps/triceps/forearms 而不是 9 个解剖学细分,
    /// quads/hams/glutes/adductors/calves 而不是 15 个细分), 避免单行 chip 太挤.
    /// 想精选到长头 / 短头 / 股直肌 → 留给"按肌群浏览" UI (QuickWorkout chip 全展开版).
    var sectionSubs: [MuscleGroup] {
        switch self {
        case .chest:     return [.upperChest, .midChest, .lowerChest]
        case .back:      return [.upperLats, .lowerLats, .upperTraps, .midTraps, .lowerTraps, .rhomboids, .teres, .lowerBack]
        case .shoulders: return [.frontDelts, .sideDelts, .rearDelts, .rotatorCuff]
        case .arms:      return [.biceps, .triceps, .forearms]
        case .core:      return [.upperAbs, .lowerAbs, .obliques, .serratus]
        case .legs:      return [.quads, .hamstrings, .glutes, .adductors, .calves]
        default:         return []
        }
    }
}
