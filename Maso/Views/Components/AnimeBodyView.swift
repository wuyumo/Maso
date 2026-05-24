import SwiftUI

// 动漫风格 SwiftUI Path 渲染的肌肉图 — 替代 MuscleMap SDK 的真人解剖学 polygon.
//
// 设计哲学:
//   - 简化, 不画 sub-muscle (无 upperChest/midChest 区分, 一块胸就是一块胸)
//   - 圆润 bezier 曲线, 不要锐角
//   - 粗黑描边 + flat fill (cel-shaded 平涂动漫风)
//   - 大块色块, 黑底辨识度高
//
// 坐标系: 每个 panel viewBox 100×210. 前后两 panel 横向并排 (panelSpacing 控制间距).
//
// 当前覆盖的 major muscle groups (各折叠到大肌群, 不分 sub):
//   Front: chest / abs / shoulders / biceps / forearms / quads / hipFlexors
//   Back:  traps / lats / lowerBack / rearShoulders / triceps / glutes / hamstrings / calves
//
// 集成方式: 通过 MuscleVisualBlock 调用. 跟旧 BodyHint API 兼容 (muscles / opacityFor /
// region 等参数). region zoom + clipping 还是 MuscleVisualBlock 外层做.
struct AnimeBodyView: View {
    /// 高亮的肌肉群 — 这些填 accent, 其它填 idle 色
    let muscles: Set<MuscleGroup>
    /// 协同肌 — 半透 accent (35%)
    var synergists: Set<MuscleGroup> = []
    var color: Color = MasoColor.accent
    /// 整体高度 (= 单个 panel 的高度). 宽度 = height × ~1.05 (2 panels + 间距)
    var height: CGFloat = 200
    /// 前后 panel 间距 (默认 10pt, 跟 MuscleVisualBlock 里 BodyHint.panelSpacing 一致)
    var panelSpacing: CGFloat = 10
    /// 衰减热图模式 — 每个肌群单独 opacity, 跟 BodyHint.opacityFor 同款语义.
    var opacityFor: ((MuscleGroup) -> Double?)? = nil

    var body: some View {
        HStack(spacing: panelSpacing) {
            panel(side: .front)
            panel(side: .back)
        }
        .frame(maxHeight: height)
    }

    @ViewBuilder
    private func panel(side: BodySide) -> some View {
        let panelWidth = height * 0.5  // 单个 panel 宽高比 1:2 (viewBox 100x210)
        ZStack {
            // 1. 身体轮廓 — 整身的剪影描边. 给每块肌肉一个上下文.
            BodySilhouette(side: side)
                .fill(MasoColor.surface)
                .overlay(
                    BodySilhouette(side: side)
                        .stroke(Color.black.opacity(0.55), lineWidth: 1.2)
                )

            // 2. 头顶圆圈
            HeadShape()
                .fill(MasoColor.surface)
                .overlay(
                    HeadShape().stroke(Color.black.opacity(0.55), lineWidth: 1.2)
                )

            // 3. 肌群叠层 — 每块肌肉一个 Path, 命中时 fill accent, 否则透明.
            //    都加细描边突出"块感". 这是 cel-shading 灵魂.
            ForEach(MuscleGroupShape.cases(for: side), id: \.self) { mg in
                muscleShape(mg, side: side)
            }
        }
        .frame(width: panelWidth, height: height)
    }

    @ViewBuilder
    private func muscleShape(_ mg: MuscleGroupShape, side: BodySide) -> some View {
        let opacity = resolvedOpacity(for: mg)
        let shape = mg.makeShape(side: side)
        // 命中态: 实色 fill + 同色描边
        // 闲置态: 透明 fill, 只描边 — 让肌肉块依然有"块感"但不抢戏
        ZStack {
            if opacity > 0 {
                shape.fill(color.opacity(opacity))
            }
            shape.stroke(Color.black.opacity(0.45), lineWidth: 0.8)
        }
    }

    /// 算给定肌群最终渲染的 opacity. 顺序:
    ///   - opacityFor 模式 → 直接走 caller 决定 (Recovery 卡)
    ///   - muscles 命中 → 1.0
    ///   - synergists 命中 → 0.35
    ///   - 其它 → 0
    private func resolvedOpacity(for mg: MuscleGroupShape) -> Double {
        if let opacityFor {
            // 取该形状覆盖的所有 MuscleGroup 里最高的 opacity
            return mg.coveredGroups.compactMap { opacityFor($0) }.max() ?? 0
        }
        let covered = Set(mg.coveredGroups)
        if !covered.isDisjoint(with: muscles) { return 1.0 }
        if !covered.isDisjoint(with: synergists) { return 0.35 }
        return 0
    }
}

// MARK: - Side

enum BodySide {
    case front, back
}

// MARK: - MuscleGroupShape

/// 一块"肌群" — 跟 SDK 的 sub-muscle 不同, 这里折叠到 6-8 个大块, 跟"动漫感"匹配.
enum MuscleGroupShape: Hashable {
    // Front
    case chest, abs, frontShoulders, biceps, forearmsFront, quads, hipFlexors
    // Back
    case traps, lats, lowerBack, rearShoulders, triceps, forearmsBack, glutes, hamstrings, calves

    static func cases(for side: BodySide) -> [MuscleGroupShape] {
        switch side {
        case .front: return [.frontShoulders, .chest, .biceps, .abs, .forearmsFront, .quads, .hipFlexors]
        case .back:  return [.rearShoulders, .traps, .lats, .triceps, .lowerBack, .forearmsBack, .glutes, .hamstrings, .calves]
        }
    }

    /// 该形状覆盖 MuscleGroup enum 里的哪些值. 折叠 sub-muscle 进来 (e.g. chest 覆盖
    /// upperChest/midChest/lowerChest), 这样 caller 传 .upperChest 也能命中胸的形状.
    var coveredGroups: [MuscleGroup] {
        switch self {
        case .chest:          return [.chest, .upperChest, .midChest, .lowerChest]
        case .abs:            return [.core, .abs, .upperAbs, .lowerAbs, .obliques, .serratus]
        case .frontShoulders: return [.shoulders, .frontDelts, .sideDelts, .rotatorCuff]
        case .biceps:         return [.biceps, .bicepsLong, .bicepsShort, .brachialis, .arms]
        case .forearmsFront:  return [.forearms, .forearmFlexors, .forearmExtensors, .brachioradialis]
        case .quads:          return [.quads, .rectusFemoris, .vastusLateralis, .vastusMedialis, .legs]
        case .hipFlexors:     return [.adductors]
        case .traps:          return [.upperTraps, .midTraps]
        case .lats:           return [.back, .lats, .upperLats, .lowerLats, .teres, .rhomboids]
        case .lowerBack:      return [.lowerBack, .lowerTraps]
        case .rearShoulders:  return [.rearDelts]
        case .triceps:        return [.triceps, .tricepsLong, .tricepsLateral, .tricepsMedial]
        case .forearmsBack:   return [.forearms, .forearmFlexors, .forearmExtensors, .brachioradialis]
        case .glutes:         return [.glutes, .gluteusMaximus, .gluteusMedius]
        case .hamstrings:     return [.hamstrings, .bicepsFemoris, .semitendinosus]
        case .calves:         return [.calves, .gastrocnemius, .soleus, .tibialisAnterior]
        }
    }

    /// 返回 AnyShape — switch 里每个 case 是不同 Shape 类型, 用 AnyShape 擦类型, 让 caller 能调 fill/stroke.
    /// iOS 16+ 有 AnyShape, 我们 deploymentTarget iOS 18 没问题.
    func makeShape(side: BodySide) -> AnyShape {
        switch self {
        case .chest:          return AnyShape(ChestShape())
        case .abs:            return AnyShape(AbsShape())
        case .frontShoulders: return AnyShape(ShouldersShape(side: .front))
        case .biceps:         return AnyShape(ArmShape(part: .biceps, side: .front))
        case .forearmsFront:  return AnyShape(ArmShape(part: .forearms, side: .front))
        case .quads:          return AnyShape(LegShape(part: .quads))
        case .hipFlexors:     return AnyShape(HipFlexorsShape())
        case .traps:          return AnyShape(TrapsShape())
        case .lats:           return AnyShape(LatsShape())
        case .lowerBack:      return AnyShape(LowerBackShape())
        case .rearShoulders:  return AnyShape(ShouldersShape(side: .back))
        case .triceps:        return AnyShape(ArmShape(part: .triceps, side: .back))
        case .forearmsBack:   return AnyShape(ArmShape(part: .forearms, side: .back))
        case .glutes:         return AnyShape(GlutesShape())
        case .hamstrings:     return AnyShape(LegShape(part: .hamstrings))
        case .calves:         return AnyShape(LegShape(part: .calves))
        }
    }
}

// MARK: - Coord helpers — 100×210 viewBox per panel

private func sx(_ x: CGFloat, _ rect: CGRect) -> CGFloat { rect.width * x / 100 }
private func sy(_ y: CGFloat, _ rect: CGRect) -> CGFloat { rect.height * y / 210 }
private func pt(_ x: CGFloat, _ y: CGFloat, _ rect: CGRect) -> CGPoint {
    CGPoint(x: sx(x, rect), y: sy(y, rect))
}

// MARK: - Silhouette + Head

/// 整身轮廓 — 头之外的所有身体外形作为一个闭合 Path. 给每块肌肉一个"上下文".
struct BodySilhouette: Shape, @unchecked Sendable {
    let side: BodySide
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 起点 — 颈底左侧
        p.move(to: pt(44, 36, rect))
        // 颈右
        p.addLine(to: pt(44, 42, rect))
        // 左肩外伸 (略带弧度)
        p.addCurve(
            to: pt(20, 48, rect),
            control1: pt(38, 42, rect),
            control2: pt(26, 44, rect)
        )
        // 左臂外 — 肩到肘 (轻微外弧)
        p.addCurve(
            to: pt(15, 108, rect),
            control1: pt(17, 70, rect),
            control2: pt(16, 90, rect)
        )
        // 肘到腕
        p.addCurve(
            to: pt(12, 148, rect),
            control1: pt(14, 122, rect),
            control2: pt(13, 138, rect)
        )
        // 手底
        p.addCurve(
            to: pt(19, 156, rect),
            control1: pt(11, 154, rect),
            control2: pt(14, 157, rect)
        )
        // 内臂往上回 — 腋下
        p.addCurve(
            to: pt(28, 90, rect),
            control1: pt(22, 130, rect),
            control2: pt(25, 110, rect)
        )
        // 腋下到腰部
        p.addCurve(
            to: pt(34, 132, rect),
            control1: pt(33, 105, rect),
            control2: pt(34, 120, rect)
        )
        // 腰收窄
        p.addCurve(
            to: pt(32, 148, rect),
            control1: pt(33, 140, rect),
            control2: pt(31, 144, rect)
        )
        // 髋张开
        p.addCurve(
            to: pt(30, 158, rect),
            control1: pt(32, 152, rect),
            control2: pt(30, 156, rect)
        )
        // 左腿外侧
        p.addCurve(
            to: pt(30, 200, rect),
            control1: pt(30, 175, rect),
            control2: pt(30, 190, rect)
        )
        // 小腿外
        p.addCurve(
            to: pt(34, 208, rect),
            control1: pt(30, 205, rect),
            control2: pt(32, 208, rect)
        )
        // 脚底
        p.addLine(to: pt(46, 208, rect))
        // 内腿上
        p.addCurve(
            to: pt(46, 158, rect),
            control1: pt(46, 190, rect),
            control2: pt(46, 170, rect)
        )
        // 裆部 — 中线
        p.addLine(to: pt(54, 158, rect))
        // 内腿往下
        p.addCurve(
            to: pt(54, 208, rect),
            control1: pt(54, 170, rect),
            control2: pt(54, 190, rect)
        )
        p.addLine(to: pt(66, 208, rect))
        p.addCurve(
            to: pt(70, 200, rect),
            control1: pt(68, 208, rect),
            control2: pt(70, 205, rect)
        )
        // 右腿外
        p.addCurve(
            to: pt(70, 158, rect),
            control1: pt(70, 190, rect),
            control2: pt(70, 175, rect)
        )
        // 髋右
        p.addCurve(
            to: pt(68, 148, rect),
            control1: pt(70, 156, rect),
            control2: pt(68, 152, rect)
        )
        // 腰右
        p.addCurve(
            to: pt(66, 132, rect),
            control1: pt(69, 144, rect),
            control2: pt(67, 140, rect)
        )
        // 腋下右
        p.addCurve(
            to: pt(72, 90, rect),
            control1: pt(66, 120, rect),
            control2: pt(67, 105, rect)
        )
        // 内臂右往下
        p.addCurve(
            to: pt(81, 156, rect),
            control1: pt(75, 110, rect),
            control2: pt(78, 130, rect)
        )
        p.addCurve(
            to: pt(88, 148, rect),
            control1: pt(86, 157, rect),
            control2: pt(89, 154, rect)
        )
        // 腕到肘
        p.addCurve(
            to: pt(85, 108, rect),
            control1: pt(87, 138, rect),
            control2: pt(86, 122, rect)
        )
        // 肘到右肩
        p.addCurve(
            to: pt(80, 48, rect),
            control1: pt(84, 90, rect),
            control2: pt(83, 70, rect)
        )
        // 右肩到颈右
        p.addCurve(
            to: pt(56, 42, rect),
            control1: pt(74, 44, rect),
            control2: pt(62, 42, rect)
        )
        // 颈右下
        p.addLine(to: pt(56, 36, rect))
        // 颈底中横 (脖根)
        p.addLine(to: pt(44, 36, rect))
        p.closeSubpath()

        // 头独立画
        return p
    }
}

/// 头顶圆 — 不跟身体轮廓连, 单独一个 Path 避免颈部"塞"在头里.
struct HeadShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        let cx = sx(50, rect)
        let cy = sy(18, rect)
        let rx = sx(11.5, rect)
        let ry = sy(13, rect)
        var p = Path()
        p.addEllipse(in: CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2))
        return p
    }
}

// MARK: - Front muscle shapes

/// 胸 — bowtie 形, 两 pec 在中线相接
struct ChestShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 左 pec — 从腋下到中线再到胸下
        p.move(to: pt(30, 52, rect))
        p.addCurve(to: pt(48, 56, rect), control1: pt(35, 50, rect), control2: pt(44, 51, rect))
        p.addCurve(to: pt(50, 88, rect), control1: pt(49, 65, rect), control2: pt(50, 78, rect))
        p.addCurve(to: pt(32, 85, rect), control1: pt(44, 92, rect), control2: pt(36, 90, rect))
        p.addCurve(to: pt(30, 52, rect), control1: pt(30, 76, rect), control2: pt(29, 62, rect))
        p.closeSubpath()
        // 右 pec — 镜像
        p.move(to: pt(70, 52, rect))
        p.addCurve(to: pt(52, 56, rect), control1: pt(65, 50, rect), control2: pt(56, 51, rect))
        p.addCurve(to: pt(50, 88, rect), control1: pt(51, 65, rect), control2: pt(50, 78, rect))
        p.addCurve(to: pt(68, 85, rect), control1: pt(56, 92, rect), control2: pt(64, 90, rect))
        p.addCurve(to: pt(70, 52, rect), control1: pt(70, 76, rect), control2: pt(71, 62, rect))
        p.closeSubpath()
        return p
    }
}

/// 腹 — 中线 column, 圆角矩形感
struct AbsShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(42, 92, rect))
        p.addCurve(to: pt(58, 92, rect), control1: pt(46, 90, rect), control2: pt(54, 90, rect))
        p.addCurve(to: pt(58, 130, rect), control1: pt(60, 105, rect), control2: pt(60, 120, rect))
        p.addCurve(to: pt(42, 130, rect), control1: pt(54, 134, rect), control2: pt(46, 134, rect))
        p.addCurve(to: pt(42, 92, rect), control1: pt(40, 120, rect), control2: pt(40, 105, rect))
        p.closeSubpath()
        return p
    }
}

/// 肩 — 左右两个圆 blob, 前后差不多形状, side 决定填色位置
struct ShouldersShape: Shape, @unchecked Sendable {
    let side: BodySide
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 左肩
        p.move(to: pt(20, 48, rect))
        p.addCurve(to: pt(32, 46, rect), control1: pt(23, 44, rect), control2: pt(28, 44, rect))
        p.addCurve(to: pt(33, 62, rect), control1: pt(34, 51, rect), control2: pt(34, 57, rect))
        p.addCurve(to: pt(20, 64, rect), control1: pt(28, 65, rect), control2: pt(23, 66, rect))
        p.addCurve(to: pt(20, 48, rect), control1: pt(17, 58, rect), control2: pt(17, 52, rect))
        p.closeSubpath()
        // 右肩
        p.move(to: pt(80, 48, rect))
        p.addCurve(to: pt(68, 46, rect), control1: pt(77, 44, rect), control2: pt(72, 44, rect))
        p.addCurve(to: pt(67, 62, rect), control1: pt(66, 51, rect), control2: pt(66, 57, rect))
        p.addCurve(to: pt(80, 64, rect), control1: pt(72, 65, rect), control2: pt(77, 66, rect))
        p.addCurve(to: pt(80, 48, rect), control1: pt(83, 58, rect), control2: pt(83, 52, rect))
        p.closeSubpath()
        return p
    }
}

/// 手臂 — biceps / triceps / forearms 共用. part 决定 y 范围.
struct ArmShape: Shape, @unchecked Sendable {
    enum Part { case biceps, triceps, forearms }
    let part: Part
    let side: BodySide  // front (biceps/forearms) vs back (triceps/forearms)

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (yTop, yBottom): (CGFloat, CGFloat)
        switch part {
        case .biceps:   (yTop, yBottom) = (66, 105)
        case .triceps:  (yTop, yBottom) = (66, 105)
        case .forearms: (yTop, yBottom) = (110, 148)
        }
        // 左臂
        p.move(to: pt(16, yTop, rect))
        p.addCurve(
            to: pt(26, yTop, rect),
            control1: pt(18, yTop - 2, rect),
            control2: pt(24, yTop - 2, rect)
        )
        p.addCurve(
            to: pt(27, yBottom, rect),
            control1: pt(27, yTop + (yBottom - yTop) * 0.4, rect),
            control2: pt(28, yBottom - 4, rect)
        )
        p.addCurve(
            to: pt(15, yBottom, rect),
            control1: pt(24, yBottom + 2, rect),
            control2: pt(18, yBottom + 2, rect)
        )
        p.addCurve(
            to: pt(16, yTop, rect),
            control1: pt(13, yBottom - 4, rect),
            control2: pt(14, yTop + (yBottom - yTop) * 0.4, rect)
        )
        p.closeSubpath()
        // 右臂 (镜像)
        p.move(to: pt(84, yTop, rect))
        p.addCurve(
            to: pt(74, yTop, rect),
            control1: pt(82, yTop - 2, rect),
            control2: pt(76, yTop - 2, rect)
        )
        p.addCurve(
            to: pt(73, yBottom, rect),
            control1: pt(73, yTop + (yBottom - yTop) * 0.4, rect),
            control2: pt(72, yBottom - 4, rect)
        )
        p.addCurve(
            to: pt(85, yBottom, rect),
            control1: pt(76, yBottom + 2, rect),
            control2: pt(82, yBottom + 2, rect)
        )
        p.addCurve(
            to: pt(84, yTop, rect),
            control1: pt(87, yBottom - 4, rect),
            control2: pt(86, yTop + (yBottom - yTop) * 0.4, rect)
        )
        p.closeSubpath()
        return p
    }
}

/// 腿 — quads / hamstrings / calves 共用
struct LegShape: Shape, @unchecked Sendable {
    enum Part { case quads, hamstrings, calves }
    let part: Part

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let (yTop, yBottom): (CGFloat, CGFloat)
        switch part {
        case .quads:      (yTop, yBottom) = (155, 188)
        case .hamstrings: (yTop, yBottom) = (158, 188)
        case .calves:     (yTop, yBottom) = (188, 205)
        }
        // 左腿
        p.move(to: pt(32, yTop, rect))
        p.addCurve(to: pt(48, yTop, rect), control1: pt(36, yTop - 2, rect), control2: pt(44, yTop - 2, rect))
        p.addCurve(to: pt(46, yBottom, rect), control1: pt(48, yTop + (yBottom - yTop) * 0.5, rect), control2: pt(47, yBottom - 2, rect))
        p.addCurve(to: pt(34, yBottom, rect), control1: pt(42, yBottom + 2, rect), control2: pt(38, yBottom + 2, rect))
        p.addCurve(to: pt(32, yTop, rect), control1: pt(31, yBottom - 2, rect), control2: pt(31, yTop + (yBottom - yTop) * 0.5, rect))
        p.closeSubpath()
        // 右腿
        p.move(to: pt(68, yTop, rect))
        p.addCurve(to: pt(52, yTop, rect), control1: pt(64, yTop - 2, rect), control2: pt(56, yTop - 2, rect))
        p.addCurve(to: pt(54, yBottom, rect), control1: pt(52, yTop + (yBottom - yTop) * 0.5, rect), control2: pt(53, yBottom - 2, rect))
        p.addCurve(to: pt(66, yBottom, rect), control1: pt(58, yBottom + 2, rect), control2: pt(62, yBottom + 2, rect))
        p.addCurve(to: pt(68, yTop, rect), control1: pt(69, yBottom - 2, rect), control2: pt(69, yTop + (yBottom - yTop) * 0.5, rect))
        p.closeSubpath()
        return p
    }
}

/// 髋屈肌 — V 形, 腹下方
struct HipFlexorsShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(36, 134, rect))
        p.addCurve(to: pt(50, 148, rect), control1: pt(40, 140, rect), control2: pt(46, 146, rect))
        p.addCurve(to: pt(64, 134, rect), control1: pt(54, 146, rect), control2: pt(60, 140, rect))
        p.addCurve(to: pt(58, 132, rect), control1: pt(62, 132, rect), control2: pt(60, 131, rect))
        p.addCurve(to: pt(50, 142, rect), control1: pt(54, 138, rect), control2: pt(52, 141, rect))
        p.addCurve(to: pt(42, 132, rect), control1: pt(48, 141, rect), control2: pt(46, 138, rect))
        p.addCurve(to: pt(36, 134, rect), control1: pt(40, 131, rect), control2: pt(38, 132, rect))
        p.closeSubpath()
        return p
    }
}

// MARK: - Back muscle shapes

/// 斜方肌 (上) — 颈到肩, 三角形带弧度
struct TrapsShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(44, 38, rect))
        p.addCurve(to: pt(56, 38, rect), control1: pt(48, 36, rect), control2: pt(52, 36, rect))
        p.addCurve(to: pt(68, 56, rect), control1: pt(60, 44, rect), control2: pt(65, 50, rect))
        p.addCurve(to: pt(58, 64, rect), control1: pt(64, 58, rect), control2: pt(60, 62, rect))
        p.addCurve(to: pt(50, 56, rect), control1: pt(56, 60, rect), control2: pt(52, 56, rect))
        p.addCurve(to: pt(42, 64, rect), control1: pt(48, 56, rect), control2: pt(44, 60, rect))
        p.addCurve(to: pt(32, 56, rect), control1: pt(40, 62, rect), control2: pt(36, 58, rect))
        p.addCurve(to: pt(44, 38, rect), control1: pt(35, 50, rect), control2: pt(40, 44, rect))
        p.closeSubpath()
        return p
    }
}

/// 背阔肌 — 倒 V 大块
struct LatsShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 左
        p.move(to: pt(30, 64, rect))
        p.addCurve(to: pt(48, 70, rect), control1: pt(36, 66, rect), control2: pt(44, 68, rect))
        p.addCurve(to: pt(50, 105, rect), control1: pt(49, 80, rect), control2: pt(50, 95, rect))
        p.addCurve(to: pt(42, 115, rect), control1: pt(46, 110, rect), control2: pt(44, 113, rect))
        p.addCurve(to: pt(32, 105, rect), control1: pt(38, 113, rect), control2: pt(34, 110, rect))
        p.addCurve(to: pt(30, 64, rect), control1: pt(30, 90, rect), control2: pt(29, 75, rect))
        p.closeSubpath()
        // 右
        p.move(to: pt(70, 64, rect))
        p.addCurve(to: pt(52, 70, rect), control1: pt(64, 66, rect), control2: pt(56, 68, rect))
        p.addCurve(to: pt(50, 105, rect), control1: pt(51, 80, rect), control2: pt(50, 95, rect))
        p.addCurve(to: pt(58, 115, rect), control1: pt(54, 110, rect), control2: pt(56, 113, rect))
        p.addCurve(to: pt(68, 105, rect), control1: pt(62, 113, rect), control2: pt(66, 110, rect))
        p.addCurve(to: pt(70, 64, rect), control1: pt(70, 90, rect), control2: pt(71, 75, rect))
        p.closeSubpath()
        return p
    }
}

/// 下背 (竖脊肌) — 中线竖条
struct LowerBackShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: pt(44, 115, rect))
        p.addCurve(to: pt(56, 115, rect), control1: pt(48, 113, rect), control2: pt(52, 113, rect))
        p.addCurve(to: pt(56, 138, rect), control1: pt(58, 122, rect), control2: pt(58, 130, rect))
        p.addCurve(to: pt(44, 138, rect), control1: pt(52, 140, rect), control2: pt(48, 140, rect))
        p.addCurve(to: pt(44, 115, rect), control1: pt(42, 130, rect), control2: pt(42, 122, rect))
        p.closeSubpath()
        return p
    }
}

/// 臀 — 两个圆 blob
struct GlutesShape: Shape, @unchecked Sendable {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        // 左臀
        p.move(to: pt(33, 140, rect))
        p.addCurve(to: pt(48, 140, rect), control1: pt(37, 138, rect), control2: pt(45, 138, rect))
        p.addCurve(to: pt(50, 162, rect), control1: pt(50, 148, rect), control2: pt(52, 158, rect))
        p.addCurve(to: pt(33, 158, rect), control1: pt(44, 165, rect), control2: pt(37, 163, rect))
        p.addCurve(to: pt(33, 140, rect), control1: pt(31, 152, rect), control2: pt(31, 145, rect))
        p.closeSubpath()
        // 右臀
        p.move(to: pt(67, 140, rect))
        p.addCurve(to: pt(52, 140, rect), control1: pt(63, 138, rect), control2: pt(55, 138, rect))
        p.addCurve(to: pt(50, 162, rect), control1: pt(50, 148, rect), control2: pt(48, 158, rect))
        p.addCurve(to: pt(67, 158, rect), control1: pt(56, 165, rect), control2: pt(63, 163, rect))
        p.addCurve(to: pt(67, 140, rect), control1: pt(69, 152, rect), control2: pt(69, 145, rect))
        p.closeSubpath()
        return p
    }
}

// MARK: - Preview

#Preview("Anime Body — selected muscles") {
    VStack(spacing: 20) {
        // 全部高亮 — 看完整覆盖
        AnimeBodyView(
            muscles: [.chest, .core, .shoulders, .biceps, .forearms, .quads,
                      .lats, .lowerBack, .rearDelts, .triceps, .glutes, .hamstrings, .calves]
        )
        .frame(height: 240)

        // 上半身 — 看 region 是否合理 (没接 region zoom, 但目测上半身高亮)
        AnimeBodyView(
            muscles: [.chest, .biceps, .frontDelts]
        )
        .frame(height: 240)

        // 下半身
        AnimeBodyView(
            muscles: [.quads, .glutes, .hamstrings, .calves]
        )
        .frame(height: 240)
    }
    .padding(20)
    .background(Color.black)
}
