import SwiftUI

private struct AIUpgradeReminder: ViewModifier {
    let prompt: UpgradePrompt

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(get: { prompt.isPresented }, set: { prompt.isPresented = $0 }),
                      onDismiss: { prompt.didDismiss() }) {
            PaywallScreen(source: prompt.source, context: .aiReminder)
                .presentationDragIndicator(.visible)
        }
    }
}

extension View {
    func aiUpgradeReminder(_ prompt: UpgradePrompt) -> some View {
        modifier(AIUpgradeReminder(prompt: prompt))
    }
}
