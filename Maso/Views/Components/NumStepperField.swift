import SwiftUI

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
//   - 输入框宽度固定 (默认 70pt = 容纳 3 位数字 + 2 字母单位, e.g. "100 kg"/"62.5 kg"),
//     全 app 所有同款行统一这一个宽度, 视觉对齐
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

    @FocusState private var focused: Bool
    /// 输入框显示的字符串 — 跟 doubleValue 双向 sync, 但允许"中间态"为空字符串.
    /// 这是让用户能 "全删后重输" 的关键: 用 String binding 而不是 value binding,
    /// 失焦/Done 时再 parse 写回 doubleValue.
    @State private var text: String = ""

    // MARK: - Init: Double 版本 (e.g. 重量)
    init(
        doubleValue: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        suffix: String? = nil,
        decimal: Bool = true,
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
        fieldWidth: CGFloat = 70
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
        // 全局键盘 toolbar — 给 decimalPad/numberPad 加 "完成"
        .toolbar {
            if focused {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                        .foregroundStyle(MasoColor.accent)
                }
            }
        }
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
            // String binding — 允许用户随便编辑 (包括清空). 失焦/Done 时 commit 才写回数值.
            TextField("", text: $text)
                .keyboardType(decimal ? .decimalPad : .numberPad)
                .multilineTextAlignment(.trailing)
                .font(.system(size: 15, weight: .bold).monospacedDigit())
                .foregroundStyle(MasoColor.text)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { commit() }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
                .onAppear { text = format(doubleValue) }
                .onChange(of: doubleValue) { _, newValue in
                    // 外部 (e.g. +/- 按钮 / 父 view) 改了 value → 同步显示, 但不动当前正在输入的内容
                    if !focused { text = format(newValue) }
                }
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
        .onTapGesture { focused = true }
    }

    /// 用户结束输入时调 — 失焦 / onSubmit / 键盘"完成".
    /// 解析 text → clamp 到 range → 写回 doubleValue, 同时把 text 重置为标准化格式.
    /// 空串或 garbage → 恢复成上一次的合法值 (不会变成 0 或留空状态).
    private func commit() {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let parsed = Double(trimmed.replacingOccurrences(of: ",", with: ".")) {
            let clamped = min(max(parsed, range.lowerBound), range.upperBound)
            doubleValue = clamped
            text = format(clamped)
        } else {
            // parse 失败 (e.g. 全清空) → 回到当前合法值的字符串
            text = format(doubleValue)
        }
    }

    /// 跟 numberFormat 同义, 但直接给 String 用 (避免 FloatingPointFormatStyle 走两遍).
    private func format(_ v: Double) -> String {
        if decimal {
            if v.truncatingRemainder(dividingBy: 1) == 0 { return String(Int(v)) }
            return String(format: "%.1f", v)
        } else {
            return String(Int(v.rounded()))
        }
    }

    private func increment() {
        let next = min(range.upperBound, doubleValue + step)
        doubleValue = next
        // 确保 text 同步 — 如果用户当前在输入框里点 +/-, focused=true, onChange 不 sync.
        text = format(next)
    }
    private func decrement() {
        let next = max(range.lowerBound, doubleValue - step)
        doubleValue = next
        text = format(next)
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
