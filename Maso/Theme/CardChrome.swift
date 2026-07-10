import SwiftUI

// 共享卡片外壳 — padding 14 + surface 填充 + corner medium (16).
// 原本私有在 AISummaryCard.swift, 抽成 internal 让 AI Coach Summary 卡 (Progress) 跟
// Training Preferences 卡 (Routines) 共用同一片壳, 保证两张卡颜色/圆角/内边距逐像素一致.
// (跟 InsightsChartsView 其它卡也一致.)
/// iOS 26 系统 Liquid Glass 按钮是否可用 — 给调用处在表达式里切"玻璃态字色/描边/阴影"用
/// (#available 进不了三目表达式, 只能预存成布尔; 值进程内不变, 存一次即可).
let systemGlassAvailable: Bool = {
    if #available(iOS 26.0, *) { return true } else { return false }
}()

extension View {
    func cardChrome() -> some View {
        self
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .glassCardBackground()
            .clipShape(RoundedRectangle(cornerRadius: MasoMetrics.cornerRadiusMedium))
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
