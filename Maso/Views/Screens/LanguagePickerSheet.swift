import SwiftUI

// App 内语言选择器 — 不需要重启 app, 选完即时生效
//
// 列表风格参考 iOS 系统 Settings 的 "Preferred Language" 列表:
//   - 当前生效语言行高亮 + 右侧 ✓
//   - "System Default" 在最上面 (跟随系统)
//   - 其余支持的语言按 SupportedLanguage.allCases 顺序排
struct LanguagePickerSheet: View {
    let manager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // 跟随系统
                    LanguageRow(
                        flag: "🌐",
                        title: "System Default",
                        subtitle: "Follow iPhone language (\(LanguageManager.systemLanguage.nativeName))",
                        selected: manager.selectedLanguage == nil
                    ) {
                        pick(nil)
                    }
                    Divider().background(MasoColor.borderSoft)

                    // 全部支持语言
                    ForEach(SupportedLanguage.allCases) { lang in
                        LanguageRow(
                            flag: lang.flag,
                            title: lang.nativeName,
                            subtitle: lang.englishName,
                            selected: manager.selectedLanguage == lang
                        ) {
                            pick(lang)
                        }
                        if lang != SupportedLanguage.allCases.last {
                            Divider().background(MasoColor.borderSoft)
                        }
                    }
                }
                .background(MasoColor.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, MasoMetrics.pagePaddingHorizontal)
                .padding(.vertical, 16)
            }
            .background(MasoColor.background.ignoresSafeArea())
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(MasoColor.text)
                            .frame(width: 30, height: 30)
                            .background(MasoColor.surfaceHi)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// 选语言 → didSet 触发 Bundle swizzle, MasoApp 顶层 .id(effectiveLanguage.rawValue)
    /// 让整树 rebuild → 所有 Text 重读 string table. 直接 dismiss 让用户回主界面看到新语言.
    private func pick(_ lang: SupportedLanguage?) {
        manager.selectedLanguage = lang
        dismiss()
    }
}

private struct LanguageRow: View {
    let flag: String
    let title: String
    let subtitle: String
    let selected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 14) {
                Text(flag)
                    .font(.system(size: 22))
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    // title 是 "System Default" / "English" 等 — 走 LocalizedStringKey 查表.
                    // subtitle 是各语言原生名 ("简体中文", "한국어"), 不翻译, 直接显示原文.
                    Text(LocalizedStringKey(title))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(MasoColor.text)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(MasoColor.textDim)
                        .lineLimit(1)
                }
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(MasoColor.accent)
                }
            }
            .padding(.horizontal, MasoMetrics.cardPadding)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
