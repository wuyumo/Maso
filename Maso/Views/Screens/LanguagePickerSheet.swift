import SwiftUI

/// Native grouped language picker. Choosing a row applies the language immediately
/// and closes the sheet so the newly localized screen is visible at once.
struct LanguagePickerSheet: View {
    let manager: LanguageManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AppNavigationStack {
            Form {
                Section {
                    Button {
                        pick(nil)
                    } label: {
                        languageRow(
                            title: Text("System Default"),
                            subtitle: Text(String(format: NSLocalizedString("Follow iPhone language (%@)", comment: "system language picker row"), LanguageManager.systemLanguage.nativeName)),
                            selected: manager.selectedLanguage == nil
                        )
                    }

                    ForEach(SupportedLanguage.shipped) { language in
                        Button {
                            pick(language)
                        } label: {
                            languageRow(
                                title: Text(language.nativeName),
                                subtitle: Text(language.englishName),
                                selected: manager.selectedLanguage == language
                            )
                        }
                    }
                } header: {
                    Text("Language")
                }
            }
            .navigationTitle("Language")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func languageRow(title: Text, subtitle: Text, selected: Bool) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                title.font(.body).foregroundStyle(.primary)
                subtitle.font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
    }

    /// didSet updates the localized bundle and rebuilds the app tree without a restart.
    private func pick(_ language: SupportedLanguage?) {
        manager.selectedLanguage = language
        dismiss()
    }
}
