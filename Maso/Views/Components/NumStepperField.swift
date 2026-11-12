import SwiftUI
import UIKit

extension Binding where Value == Double {
    /// canonical-kg 的 binding → 当前单位 (kg/lb) 的 binding: get 把 kg 换成单位值, set 把单位值换回 kg.
    /// 让重量步进器按用户设置的单位展示/编辑, 存储仍是 kg.
    func inUnit(_ unit: WeightUnit) -> Binding<Double> {
        Binding<Double>(
            get: { unit.fromKg(wrappedValue) },
            set: { wrappedValue = unit.toKg($0) }
        )
    }
}

// 统一的数字步进 + 输入控件
//
// 布局: [ − | 47.5 kg | + ] — 一体化圆角矩形, 按钮和输入区共用同一块底, 无缝相接
//   - 左右 − / + 段 36×36 点击热区
//   - 中间是可点击的输入框, 调出数字键盘可直接输入
//   - 输入框宽度: **整数版 58pt**(组/次/秒), 数字区按 4 位排 (owner) —— 15pt monospacedDigit
//     一位 ~9pt, "1000" ≈ 36pt + 13pt 单位 ~18pt + spacing 2 → 56pt, 取 58 留一点余量;
//     **小数版 (重量) 70pt** —— 重量按 kg 存, 切 lb 会换算出小数 ("137.8 lb" ~57pt,
//     lb 上限 1100 时 "1012.5 lb" 更长), 58 会被裁. 同类行各自统一宽度, 视觉对齐
//   - 单位后缀 (kg / s / 秒…) 永远右贴数字
//
// 用法:
//   NumStepperField(intValue: $settings.defaultRestSeconds, range: 15...300, step: 15, suffix: "s")
//   NumStepperField(doubleValue: $step.weight, range: 0...300, step: 2.5, suffix: "kg", decimal: true)
struct NumStepperField: View {
    @Binding private var doubleValue: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let suffix: String?
    private let decimal: Bool
    /// 输入框宽度 (含 suffix)
    private let fieldWidth: CGFloat

    // MARK: - Init: Double 版本 (e.g. 重量)
    init(
        doubleValue: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        suffix: String? = nil,
        decimal: Bool = true,
        // ⚠️ 小数版**不能**跟 Int 版一样收到 58: 重量按 kg 存, 切 lb 后换算出小数 —
        //    62.5 kg → "137.8 lb" 已经 ~57pt, lb 上限 1100 时 "1012.5 lb" 直接溢出被裁.
        //    整数版 (组/次/秒) 才走 58 的 4 位宽.
        fieldWidth: CGFloat = 70
    ) {
        self._doubleValue = doubleValue
        self.range = range
        self.step = step
        self.suffix = suffix
        self.decimal = decimal
        self.fieldWidth = fieldWidth
    }

    // MARK: - Init: Int 版本 (组数 / 次数 / 休息秒…)
    init(
        intValue: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String? = nil,
        fieldWidth: CGFloat = 58
    ) {
        self._doubleValue = Binding(
            get: { Double(intValue.wrappedValue) },
            set: { intValue.wrappedValue = Int($0.rounded()) }
        )
        self.range = Double(range.lowerBound)...Double(range.upperBound)
        self.step = Double(step)
        self.suffix = suffix
        self.decimal = false
        self.fieldWidth = fieldWidth
    }

    private var canDecrement: Bool { doubleValue - step >= range.lowerBound - 0.0001 }
    private var canIncrement: Bool { doubleValue + step <= range.upperBound + 0.0001 }

    var body: some View {
        // 一体化胶囊: [ − | 47.5 kg | + ] 共用同一块 surfaceHi 圆角矩形底 —
        // 按钮不再是独立圆钮, 数字区不再有自己的背景, 三段无缝相接.
        HStack(spacing: 0) {
            // − 按钮
            Button(action: decrement) {
                stepIcon("minus", enabled: canDecrement)
            }
            .buttonStyle(.plain)
            .disabled(!canDecrement)

            // 数字输入框 (含 suffix)
            inputField

            // + 按钮
            Button(action: increment) {
                stepIcon("plus", enabled: canIncrement)
            }
            .buttonStyle(.plain)
            .disabled(!canIncrement)
        }
        .background(MasoColor.surfaceHi)
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    /// +/- 按钮段 — 无独立底 (整体共底), 36pt 高给足点击热区.
    private func stepIcon(_ name: String, enabled: Bool) -> some View {
        Image(systemName: name)
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(enabled ? MasoColor.text : MasoColor.textFaint)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
    }

    private var inputField: some View {
        HStack(spacing: 2) {
            NumericValueField(value: $doubleValue, range: range, allowsDecimal: decimal,
                              font: .monospacedDigitSystemFont(ofSize: 15, weight: .bold),
                              textColor: UIColor(MasoColor.text))
                .frame(minWidth: 24)
            if let suffix {
                Text(suffix)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(MasoColor.textDim)
            }
        }
        .padding(.vertical, 7)
        .frame(width: fieldWidth, alignment: .center)
        .contentShape(Rectangle())
    }

    private func increment() {
        let next = min(range.upperBound, doubleValue + step)
        doubleValue = next
    }
    private func decrement() {
        let next = max(range.lowerBound, doubleValue - step)
        doubleValue = next
    }
}

#Preview("NumStepperField — variants") {
    @Previewable @State var sets = 3
    @Previewable @State var reps = 10
    @Previewable @State var weight = 47.5
    @Previewable @State var rest = 90
    VStack(spacing: 12) {
        NumStepperField(intValue: $sets, range: 1...10)
        NumStepperField(intValue: $reps, range: 0...50)
        NumStepperField(doubleValue: $weight, range: 0...300, step: 2.5, suffix: "kg")
        NumStepperField(intValue: $rest, range: 15...300, step: 15, suffix: "s")
    }
    .padding()
    .background(MasoColor.surface)
}
