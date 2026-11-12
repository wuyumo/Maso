import SwiftUI

// Shared content cards use the Diet glass surface, standard padding and radius.
/// iOS 26 系统 Liquid Glass 按钮是否可用 — 给调用处在表达式里切"玻璃态字色/描边/阴影"用
/// (#available 进不了三目表达式, 只能预存成布尔; 值进程内不变, 存一次即可).
let systemGlassAvailable: Bool = {
    if #available(iOS 26.0, *) { return true } else { return false }
}()

extension View {
    /// Shared explanatory values beside target-card progress bars.
    func targetProgressTextStyle() -> some View {
        self.font(.subheadline.weight(.medium))
            .foregroundStyle(MasoColor.textSoft)
            .monospacedDigit()
    }

    @ViewBuilder
    func nativeGlassProminentButtonStyle() -> some View {
        if #available(iOS 26.0, *) { self.buttonStyle(.glassProminent) }
        else { self.buttonStyle(.borderedProminent) }
    }

    /// “iOS default button” means native Liquid Glass on supported systems.
    @ViewBuilder
    func nativeGlassButtonStyle() -> some View {
        if #available(iOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered)
        }
    }

    func cardChrome() -> some View { contentCardChrome() }

    func contentCardChrome(padding: CGFloat = MasoMetrics.cardPadding,
                           cornerRadius: CGFloat = MasoMetrics.cornerRadiusMedium) -> some View {
        self.frame(maxWidth: .infinity, alignment: .leading)
            .padding(padding).glassCardBackground(cornerRadius: cornerRadius)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// 扁平卡底 — 纯 surface 填充, 无玻璃折光/无描边 (owner: routine 等内容卡去边框, 只留底色).
    /// Coach composer 仍走 glassCardBackground (保留玻璃 + 描边), 不受此影响.
    func flatCardBackground(cornerRadius: CGFloat = MasoMetrics.cornerRadiusMedium) -> some View {
        self.background(MasoColor.surface, in: RoundedRectangle(cornerRadius: cornerRadius))
    }

    /// 液态玻璃卡底 (试验性, 回退点 tag pre-liquid-glass; owner 拍板: 全部卡片用 iOS 原生
    /// Liquid Glass, 跟按钮/导航胶囊同一套系统材质 — 带边缘折光, 不是普通磨砂).
    /// 只换"底", 布局/描边由调用处照旧; cornerRadius 需与调用处 clipShape 一致 (玻璃按形状折光).
    /// ⚠️ 材质跟随系统 colorScheme — app 根已挂 .preferredColorScheme(.dark) (MasoApp.swift).
    @ViewBuilder
    func glassCardBackground(cornerRadius: CGFloat = MasoMetrics.cornerRadiusMedium) -> some View {
        if #available(iOS 26.0, *) {
            // 纯净玻璃, 无色 tint (owner 反馈卡片发绿 — 之前掺的 accent 4% 已去掉;
            // 卡内仍会隐约透进底层光斑的绿, 那是背景动效透过玻璃的正常表现).
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius))
        } else {
            // iOS <26 回退: ultraThinMaterial + 压暗 (无色 tint).
            self.background {
                ZStack {
                    Rectangle().fill(.ultraThinMaterial)
                    Color.black.opacity(0.30)
                }
            }
        }
    }

    // MARK: - 按钮玻璃底 (owner 拍板: 全 app 自绘按钮统一 iOS 系统 Liquid Glass 样式)
    //
    // 配方跟先例保持一致 (CoachScreen composer [+|#] 药丸/发送键, WorkoutCard 播放键):
    //   tint = nil          → 素玻璃 .regular.interactive()          (小 chips / 工具钮 / 已存态 / 禁用态)
    //   tint = accent 0.85  → 主 CTA 玻璃 (配黑字)
    //   tint = accent 0.25  → 次级钮玻璃 (配 accent 字)
    // iOS <26 一律回退 fallback 纯色底 + clipShape (= 改动前样式);
    // fallback = nil → 旧系统不加底 (调用处自管回退, 比如描边式按钮).
    // 描边/阴影这类"只在旧系统保留"的装饰, 调用处用 systemGlassAvailable 布尔切.

    /// 任意形状版 — Unlock 钮这类多行文本用 RoundedRectangle 的场景.
    @ViewBuilder
    func glassButtonBackground<S: Shape>(tint: Color? = nil, fallback: Color? = nil, in shape: S) -> some View {
        if #available(iOS 26.0, *) {
            if let tint {
                self.glassEffect(.regular.tint(tint).interactive(), in: shape)
            } else {
                self.glassEffect(.regular.interactive(), in: shape)
            }
        } else if let fallback {
            self.background(fallback).clipShape(shape)
        } else {
            self
        }
    }

    /// 胶囊钮 (最常见) 便捷入口.
    func glassCapsuleButtonBackground(tint: Color? = nil, fallback: Color? = nil) -> some View {
        glassButtonBackground(tint: tint, fallback: fallback, in: Capsule())
    }

    /// 圆形图标钮便捷入口.
    func glassCircleButtonBackground(tint: Color? = nil, fallback: Color? = nil) -> some View {
        glassButtonBackground(tint: tint, fallback: fallback, in: Circle())
    }
}

// Shared typography for the Routines and History section headings on Today.
extension Text {
    func trainingSectionTitle() -> some View {
        self
            .font(.system(size: MasoMetrics.sectionTitleSize, weight: .heavy))
            .tracking(MasoMetrics.sectionTitleTracking)
            .textCase(.uppercase)
            .foregroundStyle(MasoColor.textDim)
    }
}

/// Ghost actions beside page and section headings, with a full touch target.
struct SectionActionButton: View {
    let title: LocalizedStringKey
    var leadingIcon: String? = nil
    var showsChevron = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leadingIcon { Image(systemName: leadingIcon) }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                }
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(MasoColor.text)
            .padding(.horizontal, 4)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Reusable, brief confirmation toast for completed actions.
/// The presenting screen controls visibility and dismissal timing.
struct MasoToast: View {
    let message: LocalizedStringKey
    var systemImage: String = "checkmark"

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(MasoColor.accent)
            Text(message)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MasoColor.text)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().stroke(MasoColor.borderSoft.opacity(0.7), lineWidth: 0.7))
        .shadow(color: .black.opacity(0.16), radius: 12, y: 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.updatesFrequently)
    }
}


/// Canonical primary-action label for the app: accent-tinted capsule, dark text/icon,
/// 44pt minimum height. Use inside a plain Button; pass the feature accent when needed.
struct TrainingCardActionLabel: View {
    enum Size { case regular, large }
    let title: LocalizedStringKey
    let icon: String
    let accent: Color
    var prominent = true
    var fillsWidth = false
    var loading = false
    var size: Size = .regular
    var body: some View {
        Group {
            if prominent {
                actionLabel
                    .glassCapsuleButtonBackground(tint: accent.opacity(0.85), fallback: accent)
            } else {
                actionLabel
            }
        }
        .contentShape(Capsule())
    }

    private var actionLabel: some View {
        HStack(spacing: 8) {
            if !icon.isEmpty || loading {
                ZStack {
                    if !icon.isEmpty { Image(systemName: icon).font((size == .large ? Font.subheadline : .caption).weight(.bold)).opacity(loading ? 0 : 1) }
                    if loading { ProgressView().controlSize(.mini).tint(.black) }
                }
            }
            Text(title).font((size == .large ? Font.body : .subheadline).weight(.semibold)).multilineTextAlignment(.center)
        }
        .foregroundStyle(prominent ? Color.black : MasoColor.text)
        .padding(.horizontal, 16).padding(.vertical, size == .large ? 14 : 10)
        .frame(maxWidth: fillsWidth ? .infinity : nil, minHeight: size == .large ? 56 : 44)
    }
}
