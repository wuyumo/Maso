import SwiftUI

// Onboarding — 单页渐进展开式 (跟 web 端 Onboarding 流程一致)
//   1. 基础信息 (性别 / 年龄 / 体重)
//   2. 每周训练次数
//   3. 想加强的肌群
struct OnboardingScreen: View {
    @Environment(DataStore.self) private var data
    let onDone: () -> Void

    @State private var step: Int = 1
    @State private var gender: Gender = .male
    @State private var age: Int = 25
    @State private var weight: Double = 70
    @State private var daysPerWeek: Int = 3
    // 默认勾上 chest + back — picker 暴露的 major, 之前 .lats 是 sub 但 picker 不显示,
    // 用户改不掉它, 是脏数据. 改成 chest+back 都是 major chip 可见可点的"礼貌默认".
    @State private var strengthen: Set<MuscleGroup> = [.chest, .back]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(format: NSLocalizedString("STEP %lld / 3", comment: ""), step))
                        .font(.system(size: 10, weight: .bold)).tracking(2)
                        .foregroundStyle(MasoColor.accent)
                    Text("Tell us about your training")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(MasoColor.text)
                    Text("Three quick questions — we'll use them to recommend a plan that fits.")
                        .font(.system(size: 13))
                        .foregroundStyle(MasoColor.textDim)
                }
                .padding(.top, MasoMetrics.pagePaddingTop)

                // Step 1: 基础信息
                Group {
                    SectionLabel("About you")
                    HStack(spacing: 16) {
                        ForEach([Gender.male, .female, .other], id: \.self) { g in
                            Button {
                                gender = g
                                if step == 1 { withAnimation { step = 2 } }
                            } label: {
                                // P2-14: Text(LocalizedStringKey) — genderLabel 返回 key,
                                // 否则 Text(String) 走非本地化重载, 中文环境也显英文 "Male".
                                Text(LocalizedStringKey(genderLabel(g)))
                                    .font(.system(size: 14, weight: .bold))
                                    .padding(.horizontal, 16).padding(.vertical, 8)
                                    .background(gender == g ? MasoColor.accent : MasoColor.surface)
                                    .foregroundStyle(gender == g ? .black : MasoColor.text)
                                    .clipShape(Capsule())
                            }.buttonStyle(.plain)
                        }
                    }
                    HStack {
                        Text("Age")
                        Spacer()
                        // 全 app 统一步进控件 — 跟 Settings / 训练中动作详情页同款.
                        NumStepperField(intValue: $age, range: 12...90, suffix: "yrs")
                    }
                    .font(.system(size: 14))
                    HStack {
                        Text("Weight")
                        Spacer()
                        NumStepperField(doubleValue: $weight, range: 30...200, step: 1, suffix: "kg", decimal: false)
                    }
                    .font(.system(size: 14))
                }

                if step >= 2 {
                    Group {
                        SectionLabel("How many days a week do you train?")
                        HStack(spacing: 8) {
                            ForEach(1...6, id: \.self) { n in
                                Button {
                                    daysPerWeek = n
                                    if step == 2 { withAnimation { step = 3 } }
                                } label: {
                                    Text("\(n)")
                                        .font(.system(size: 16, weight: .bold))
                                        .frame(width: 44, height: 44)
                                        .background(daysPerWeek == n ? MasoColor.accent : MasoColor.surface)
                                        .foregroundStyle(daysPerWeek == n ? .black : MasoColor.text)
                                        .clipShape(Circle())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if step >= 3 {
                    Group {
                        SectionLabel("Which muscles do you want to focus on?")
                        // 只显示 6 个大肌群 section — 跟 Settings "Muscles to focus" picker /
                        // "选动作"页 Muscle 筛选完全一致 (不展开细分肌群).
                        MuscleSelector(
                            selected: $strengthen,
                            sectionsOnly: true
                        )
                        Button(action: confirm) {
                            Text("Confirm & build my plan")
                                .font(.system(size: 14, weight: .bold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(MasoColor.accent)
                                .foregroundStyle(.black)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.top, 8)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Spacer(minLength: MasoMetrics.pageBottomInset)
            }
            .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
        }
        .background(MasoColor.background.ignoresSafeArea())
    }

    private func genderLabel(_ g: Gender) -> String {
        switch g { case .male: return "Male"; case .female: return "Female"; case .other: return "Other" }
    }

    private func confirm() {
        data.settings.gender = gender
        data.settings.age = age
        data.settings.weight = weight
        data.settings.weeklyTrainingDays = daysPerWeek
        data.settings.wantStrengthen = Array(strengthen)
        data.settings.onboardingCompleted = true
        // 按 onboarding 偏好自动种几条 AI routine 进 My Routines —— 用户首次进 Today 就有内容,
        // 不会高概率撞空状态; 之后还能去 Routines tab 浏览 AI/Classics 再加.
        data.seedStarterRoutines()
        data.flushSave()
        onDone()
    }
}

// MARK: - SectionLabel + flow layout

private struct SectionLabel: View {
    let text: String
    init(_ t: String) { self.text = t }
    var body: some View {
        // 包 LocalizedStringKey — Text(stringVar) 默认 String overload 不查表, 显式 LSK 才走 i18n.
        Text(LocalizedStringKey(text))
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(MasoColor.textDim)
            .padding(.top, 8)
    }
}

// 极简 flow layout — chips 自动换行 (SwiftUI 在 iOS 16+ 有 Layout 协议, 这里用一个最小实现)
/// Tag-cloud 风格 wrap layout — chips 横向排满一行就换行.
/// 支持 leading / center / trailing 横向对齐 (per-row 居中是 QuickMuscleStep 的需求,
/// 让"选择肌群"区每一行 chip 都视觉居中, 不是默认靠左).
enum FlowAlignment { case leading, center, trailing }

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    /// 每一行内 chip 的横向对齐. 默认 leading (兼容老调用方).
    var alignment: FlowAlignment = .leading

    /// 内部计算: 把所有 subview 按 maxWidth 切成 rows. 每个 row 记录子 size 列表 + content 宽 + 行高.
    private struct LayoutResult {
        var rows: [Row]
        var totalSize: CGSize
        struct Row {
            var sizes: [CGSize]
            var contentWidth: CGFloat   // 包含 chip 间 spacing 的实际总宽
            var height: CGFloat
        }
    }

    private func compute(subviews: Subviews, maxWidth: CGFloat) -> LayoutResult {
        var rows: [LayoutResult.Row] = []
        var curSizes: [CGSize] = []
        var curWidth: CGFloat = 0
        var curHeight: CGFloat = 0
        for v in subviews {
            let size = v.sizeThatFits(.unspecified)
            let projected = curSizes.isEmpty ? size.width : curWidth + spacing + size.width
            if !curSizes.isEmpty && projected > maxWidth {
                rows.append(.init(sizes: curSizes, contentWidth: curWidth, height: curHeight))
                curSizes = [size]
                curWidth = size.width
                curHeight = size.height
            } else {
                if !curSizes.isEmpty { curWidth += spacing }
                curSizes.append(size)
                curWidth += size.width
                curHeight = max(curHeight, size.height)
            }
        }
        if !curSizes.isEmpty {
            rows.append(.init(sizes: curSizes, contentWidth: curWidth, height: curHeight))
        }
        let totalH = rows.reduce(0) { $0 + $1.height } + CGFloat(max(0, rows.count - 1)) * spacing
        let maxRowW = rows.map(\.contentWidth).max() ?? 0
        return LayoutResult(rows: rows, totalSize: CGSize(width: maxRowW, height: totalH))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        return compute(subviews: subviews, maxWidth: maxWidth).totalSize
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = compute(subviews: subviews, maxWidth: bounds.width)
        var y = bounds.minY
        var idx = 0
        for row in result.rows {
            // 每行起点 X 跟 alignment 走 — center 用 (bounds.w - rowContent) / 2 把行视觉拉到中线
            let startX: CGFloat
            switch alignment {
            case .center:   startX = bounds.minX + (bounds.width - row.contentWidth) / 2
            case .trailing: startX = bounds.maxX - row.contentWidth
            case .leading:  startX = bounds.minX
            }
            var x = startX
            for size in row.sizes {
                // 垂直方向: 把每个 subview 在 row.height 范围内居中.
                // 解决场景: major chip 14pt 字号 比 sub chip 11pt 字号高, top-align 会让小 chip
                // 浮在大 chip 上沿, 视觉错位. 改成中线对齐, 不管 chip 高矮都视觉平.
                let yCentered = y + (row.height - size.height) / 2
                subviews[idx].place(at: CGPoint(x: x, y: yCentered), proposal: ProposedViewSize(size))
                x += size.width + spacing
                idx += 1
            }
            y += row.height + spacing
        }
    }
}
