import SwiftUI

/// 杠铃配重计算器 — 给一个目标重量 + 杠铃杆重, 算出每侧需要哪些片.
///
/// 为什么做这个: 商业健身房用户每组都要心算"100kg 用 20kg 杆,每侧多少片?".
/// Strong / Hevy 都没做好这个,极简单但每天都用 — 高频质量-of-life feature.
///
/// 视觉风格: 中间一根杆 + 每侧片按大小排列 (大片靠近杆心, 小片在外侧).
/// 每个片标记重量 (e.g. "20"),颜色 IPF/IWF 国际标准:
///   红 25kg / 蓝 20kg / 黄 15kg / 绿 10kg / 白 5kg / 灰 2.5kg / 黑 1.25kg
///
/// 杆重支持 (unit == .kg, 国际标准):
///   - 20kg (标准奥林匹克杆,大部分健身房) — 默认
///   - 15kg (女子奥林匹克杆)
///   - 10kg (技术杆 / 练习杆 / 短杆)
///   - 7kg (EZ 曲杆)
/// unit == .lb (美式健身房): 45lb 奥杆 (默认) / 35lb 女杆 / 15lb 技术杆,
/// 片库 45/35/25/10/5/2.5 lb — lb 用户看到的是自己健身房里真实存在的片 (P1#21).
struct PlateCalculatorSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// 用户输入的目标总重 — canonical kg (全 app 重量都按 kg 落库, caller 直接透传).
    let targetWeight: Double

    /// 杆重 (当前 unit 的数值, 非 canonical) — 杆/片都是"实物", 按显示单位取整数才对得上现实.
    @State private var barWeight: Double

    /// 单位 — 决定杆重选项 + 片库 + 全部数字的显示. 内部计算也在该单位下做
    /// (lb 片库按 kg 算会得出 20.41kg 这种不存在的片).
    let unit: WeightUnit

    init(targetWeight: Double, unit: WeightUnit) {
        self.targetWeight = targetWeight
        self.unit = unit
        // 默认杆 = 该单位的标准奥杆.
        self._barWeight = State(initialValue: unit == .kg ? 20.0 : 45.0)
    }

    /// 目标总重换算到显示单位 — 后续全部计算/显示都用它.
    private var target: Double { unit.fromKg(targetWeight) }

    /// 该单位下可选的杆重.
    private var barOptions: [Double] { unit == .kg ? [20, 15, 10, 7] : [45, 35, 15] }

    /// 每侧片重量 + 数量 (从大到小排)
    private var perSidePlates: [(weight: Double, count: Int)] {
        Self.calculatePlates(target: target, bar: barWeight, unit: unit)
    }

    /// 每侧总重 (= (target - bar) / 2)
    private var perSideTotal: Double {
        max(0, (target - barWeight) / 2)
    }

    /// 实际能凑出的总重 (跟 target 比看差多少)
    private var achievableTotal: Double {
        barWeight + 2 * perSidePlates.reduce(0) { $0 + Double($1.count) * $1.weight }
    }

    /// target - achievable, 通常是 0 (能凑齐), 偶尔剩个零头 (最小片以下)
    private var remainder: Double {
        target - achievableTotal
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // 顶部: target weight 大字
                    VStack(spacing: 4) {
                        Text("Target")
                            .font(.system(size: 11, weight: .heavy))
                            .tracking(2)
                            .textCase(.uppercase)
                            .foregroundStyle(MasoColor.textDim)
                        Text("\(formatWeight(target)) \(unit.rawValue)")
                            .font(.system(size: 48, weight: .black))
                            .foregroundStyle(MasoColor.text)
                        if abs(remainder) > 0.01 {
                            Text(String(format: NSLocalizedString("Achievable: %@ %@  (off by %@)", comment: ""), formatWeight(achievableTotal), unit.rawValue, formatWeight(abs(remainder))))
                                .font(.system(size: 12))
                                .foregroundStyle(MasoColor.negative)
                        }
                    }
                    .padding(.top, 16)

                    // 杠铃可视化
                    barbellView
                        .frame(height: 140)
                        .padding(.horizontal, 8)

                    // 每侧片列表
                    plateList
                        .padding(.horizontal, MasoMetrics.cardPadding)

                    // 杆重选择
                    barSelector
                        .padding(.horizontal, MasoMetrics.cardPadding)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .navigationTitle("Plate calculator")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .tint(MasoColor.text)
        }
    }

    // MARK: - Barbell visualization

    /// 中央杠铃杆 + 两侧片 — 大片靠近杆心 (跟实际加片顺序一致)
    private var barbellView: some View {
        GeometryReader { geo in
            let cx = geo.size.width / 2
            let barLength = geo.size.width * 0.92
            let barTop = geo.size.height / 2 - 6

            ZStack {
                // 杠铃杆 — 长方形 + 两端套袖
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.7))
                    .frame(width: barLength, height: 12)
                    .position(x: cx, y: barTop + 6)

                // 套袖 (sleeve) — 杆两端粗的部分
                ForEach([-1, 1], id: \.self) { side in
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.85))
                        .frame(width: 24, height: 28)
                        .position(
                            x: cx + CGFloat(side) * (barLength / 2 - 12),
                            y: barTop + 6
                        )
                }

                // 每侧片 — 按 weight 从大到小, 越大越靠近杆心
                ForEach([-1, 1], id: \.self) { side in
                    plateStack(side: side, cx: cx, cy: barTop + 6, barLength: barLength)
                }
            }
        }
    }

    private func plateStack(side: Int, cx: CGFloat, cy: CGFloat, barLength: CGFloat) -> some View {
        // 累积 plate 宽度计算位置 — 大片在内 (近杆心), 小片在外
        let sleeveOuterX = cx + CGFloat(side) * (barLength / 2 - 24)
        var offset: CGFloat = 0
        let allPlates: [(Double, Int)] = perSidePlates  // 已按从大到小排
        var flat: [Double] = []
        for (w, c) in allPlates {
            for _ in 0..<c { flat.append(w) }
        }

        return ZStack {
            ForEach(Array(flat.enumerated()), id: \.offset) { idx, w in
                let info = Self.plateInfo(forWeight: w, unit: unit)
                let plateW = info.thickness
                let plateH = info.height
                let xPos = sleeveOuterX + CGFloat(side) * (offset + plateW / 2)
                PlateView(weight: w, color: info.color, width: plateW, height: plateH, unit: unit)
                    .position(x: xPos, y: cy)
                let _ = (offset += plateW + 2)  // dummy assignment to track inside ForEach (compiles)
            }
        }
        .compositingGroup()
    }

    // MARK: - Plate list

    private var plateList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Per side")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
            if perSidePlates.isEmpty {
                Text("Bar only — no plates needed")
                    .font(.system(size: 13))
                    .foregroundStyle(MasoColor.textDim)
                    .padding(.vertical, 12)
            } else {
                ForEach(perSidePlates, id: \.weight) { item in
                    HStack {
                        Circle()
                            .fill(Self.plateInfo(forWeight: item.weight, unit: unit).color)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white.opacity(0.3), lineWidth: 0.5))
                        Text("\(formatWeight(item.weight)) \(unit.rawValue)")
                            .font(.system(size: 14, weight: .semibold).monospacedDigit())
                            .foregroundStyle(MasoColor.text)
                        Spacer()
                        Text("× \(item.count)")
                            .font(.system(size: 14, weight: .bold).monospacedDigit())
                            .foregroundStyle(MasoColor.accent)
                    }
                    .padding(.horizontal, MasoMetrics.cardPadding)
                    .padding(.vertical, 12)
                    .background(MasoColor.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
            Text(String(format: NSLocalizedString("%@ %@ per side", comment: ""), formatWeight(perSideTotal), unit.rawValue))
                .font(.system(size: 11))
                .foregroundStyle(MasoColor.textFaint)
                .padding(.top, 4)
        }
    }

    // MARK: - Bar selector

    private var barSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bar weight")
                .font(.system(size: 11, weight: .heavy))
                .tracking(2)
                .textCase(.uppercase)
                .foregroundStyle(MasoColor.textDim)
            HStack(spacing: 8) {
                ForEach(barOptions, id: \.self) { bw in
                    Button(action: { barWeight = bw }) {
                        Text("\(formatWeight(bw)) \(unit.rawValue)")
                            .font(.system(size: 13, weight: .heavy).monospacedDigit())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(barWeight == bw ? MasoColor.accent : MasoColor.surfaceHi)
                            .foregroundStyle(barWeight == bw ? .black : MasoColor.textDim)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Plate calculation (greedy)

    /// 该单位的健身房标配片库 (从大到小):
    ///   kg: 25 / 20 / 15 / 10 / 5 / 2.5 / 1.25 / 0.5 (IPF/IWF)
    ///   lb: 45 / 35 / 25 / 10 / 5 / 2.5 (美式健身房标配)
    static func standardPlates(for unit: WeightUnit) -> [Double] {
        unit == .kg ? [25, 20, 15, 10, 5, 2.5, 1.25, 0.5] : [45, 35, 25, 10, 5, 2.5]
    }

    /// 贪心算法: 从最大的片开始往下凑. target/bar 都是当前 unit 的数值.
    static func calculatePlates(target: Double, bar: Double, unit: WeightUnit) -> [(weight: Double, count: Int)] {
        let perSide = max(0, (target - bar) / 2)
        var remaining = perSide
        var result: [(weight: Double, count: Int)] = []
        for plate in standardPlates(for: unit) {
            // 每个 weight 通常最多 4 片 (杆套袖装不下太多)
            let count = min(4, Int(remaining / plate))
            if count > 0 {
                result.append((weight: plate, count: count))
                remaining -= Double(count) * plate
            }
        }
        return result
    }

    // MARK: - Plate visual info (IPF/IWF color standard)

    struct PlateInfo {
        let color: Color
        let thickness: CGFloat
        let height: CGFloat
    }

    static func plateInfo(forWeight w: Double, unit: WeightUnit) -> PlateInfo {
        switch unit {
        case .kg:
            // IPF/IWF 国际颜色标准
            switch w {
            case 25:    return PlateInfo(color: Color(red: 0.85, green: 0.20, blue: 0.20), thickness: 18, height: 116)
            case 20:    return PlateInfo(color: Color(red: 0.20, green: 0.40, blue: 0.85), thickness: 16, height: 112)
            case 15:    return PlateInfo(color: Color(red: 0.95, green: 0.80, blue: 0.20), thickness: 14, height: 108)
            case 10:    return PlateInfo(color: Color(red: 0.20, green: 0.65, blue: 0.30), thickness: 12, height: 100)
            case 5:     return PlateInfo(color: Color(red: 0.92, green: 0.92, blue: 0.92), thickness: 10, height: 84)
            case 2.5:   return PlateInfo(color: Color(red: 0.55, green: 0.55, blue: 0.55), thickness: 8,  height: 68)
            case 1.25:  return PlateInfo(color: Color(red: 0.25, green: 0.25, blue: 0.25), thickness: 6,  height: 56)
            default:    return PlateInfo(color: Color(red: 0.45, green: 0.45, blue: 0.45), thickness: 5,  height: 48)
            }
        case .lb:
            // 按 kg 等值片沿用同一套颜色 (45lb≈20kg 蓝 / 35lb≈15kg 黄 / 25lb≈10kg 绿 …),
            // 让两种单位下"越大越显眼"的视觉序一致.
            switch w {
            case 45:    return PlateInfo(color: Color(red: 0.20, green: 0.40, blue: 0.85), thickness: 16, height: 112)
            case 35:    return PlateInfo(color: Color(red: 0.95, green: 0.80, blue: 0.20), thickness: 14, height: 108)
            case 25:    return PlateInfo(color: Color(red: 0.20, green: 0.65, blue: 0.30), thickness: 12, height: 100)
            case 10:    return PlateInfo(color: Color(red: 0.92, green: 0.92, blue: 0.92), thickness: 10, height: 84)
            case 5:     return PlateInfo(color: Color(red: 0.55, green: 0.55, blue: 0.55), thickness: 8,  height: 68)
            case 2.5:   return PlateInfo(color: Color(red: 0.25, green: 0.25, blue: 0.25), thickness: 6,  height: 56)
            default:    return PlateInfo(color: Color(red: 0.45, green: 0.45, blue: 0.45), thickness: 5,  height: 48)
            }
        }
    }

    /// 数字格式化 — 整数 100 而不是 100.00; 小数 2.5 而不是 2.50
    private func formatWeight(_ w: Double) -> String {
        if w == w.rounded() { return "\(Int(w))" }
        return String(format: "%.2f", w).trimmingCharacters(in: CharacterSet(charactersIn: "0"))
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }
}

/// 一片杠铃片的 SwiftUI 视图 — 矩形圆角 + 颜色 + 中心重量数字
private struct PlateView: View {
    let weight: Double
    let color: Color
    let width: CGFloat
    let height: CGFloat
    let unit: WeightUnit

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .stroke(.black.opacity(0.4), lineWidth: 0.5)
                )
                .frame(width: width, height: height)
            // 重量数字 — 极小, 旋转 90 度贴片表面
            Text(weight == weight.rounded() ? "\(Int(weight))" : "\(weight, specifier: "%.1f")")
                .font(.system(size: min(width * 0.6, 10), weight: .black).monospacedDigit())
                .foregroundStyle(.white)
                .rotationEffect(.degrees(-90))
        }
    }
}
