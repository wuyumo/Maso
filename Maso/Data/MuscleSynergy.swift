import Foundation

// 协同肌群 (synergists / "带到的肌肉") 表
// 来源:
//   1. web 端 src/lib/muscleKnowledge.ts 的 ASSOCIATED_MUSCLES (主要)
//   2. 补充了几个 web 未覆盖的 sub-muscle (iOS 现在 picker 暴露了更细的子细分, 跟随父级)
//
// 网上常见的健身解剖资料 (Bret Contreras / Strength & Conditioning Research) 都把
// 协同肌定义为"在主动作中辅助 prime mover 完成动作"的肌群. 这里取行业共识级别的关联.
enum MuscleSynergy {
    static let table: [MuscleGroup: [MuscleGroup]] = [
        // ─── 胸 ───
        .chest:       [.frontDelts, .triceps],
        .upperChest:  [.frontDelts, .tricepsLong],
        .midChest:    [.frontDelts, .triceps],
        .lowerChest:  [.tricepsLateral, .frontDelts],
        // ─── 背 ───
        .back:        [.biceps, .rearDelts],
        .lats:        [.biceps, .teres, .rearDelts],
        .upperLats:   [.biceps, .teres, .rearDelts],
        .lowerLats:   [.biceps, .teres],
        .upperTraps:  [.rearDelts, .midTraps],
        .midTraps:    [.rhomboids, .rearDelts],
        .lowerTraps:  [.rhomboids, .lats],
        .lowerBack:   [.glutes, .hamstrings, .core],
        // ─── 肩 ───
        .shoulders:   [.upperChest, .triceps],
        .frontDelts:  [.upperChest, .triceps],
        .sideDelts:   [.upperTraps],
        .rearDelts:   [.midTraps, .rhomboids],
        // ─── 手臂 ───
        .biceps:           [.brachialis, .brachioradialis, .forearmFlexors],
        .bicepsLong:       [.brachialis, .forearms],
        .bicepsShort:      [.brachialis],
        .brachialis:       [.biceps, .brachioradialis],
        .triceps:          [.frontDelts, .chest],
        .tricepsLong:      [.rearDelts, .chest],
        .tricepsLateral:   [.frontDelts, .chest],
        .tricepsMedial:    [.frontDelts],
        .forearms:         [.biceps, .brachioradialis],
        // ─── 核心 ───
        .core:        [.glutes, .lowerBack],
        .upperAbs:    [.core, .obliques],
        .lowerAbs:    [.core],
        .obliques:    [.core, .lowerBack],
        // ─── 腿 ───
        .quads:              [.glutes, .core],
        .rectusFemoris:      [.glutes, .quads],
        .vastusLateralis:    [.quads],
        .vastusMedialis:     [.quads],
        .hamstrings:         [.glutes, .lowerBack],
        .bicepsFemoris:      [.glutes, .hamstrings],
        .semitendinosus:     [.glutes, .hamstrings],
        .glutes:             [.hamstrings, .lowerBack, .quads],
        .gluteusMaximus:     [.hamstrings, .lowerBack],
        .gluteusMedius:      [.gluteusMaximus, .glutes],
        // ─── 小腿 ───
        .calves:             [.hamstrings, .tibialisAnterior],
        .gastrocnemius:      [.hamstrings, .soleus],
        .soleus:             [.gastrocnemius],
        .tibialisAnterior:   [.calves],
    ]

    /// 给定一组 primary muscles, 返回它们的协同肌 (展开后排除 primary 本身)
    /// 这是给 BodyHint 渲染用的"淡绿色"列表
    static func synergists(for primaries: Set<MuscleGroup>) -> Set<MuscleGroup> {
        var out: Set<MuscleGroup> = []
        for m in primaries {
            guard let syns = table[m] else { continue }
            for s in syns where !primaries.contains(s) {
                out.insert(s)
            }
        }
        return out
    }
}
