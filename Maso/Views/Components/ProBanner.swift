import SwiftUI

/// Compact version of the approved brand-poster direction. Shared by Home and
/// Settings; callers own entitlement checks and paywall presentation.
struct ProBanner: View {
    var squareBottom = false
    let onTap: () -> Void
    @Environment(\.layoutDirection) private var layoutDirection

    private var outline: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: MasoMetrics.cornerRadiusMedium,
                               bottomLeadingRadius: squareBottom ? 0 : MasoMetrics.cornerRadiusMedium,
                               bottomTrailingRadius: squareBottom ? 0 : MasoMetrics.cornerRadiusMedium,
                               topTrailingRadius: MasoMetrics.cornerRadiusMedium)
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    MasoMarkIcon(color: MasoColor.textSoft)
                        .frame(width: 12, height: 12)
                    Text("MASSO PRO")
                        .font(.caption2.weight(.bold)).tracking(1.5)
                }
                .foregroundStyle(MasoColor.textSoft)
                .environment(\.layoutDirection, .leftToRight)

                Text("More plans, fewer interruptions")
                    .font(.headline).foregroundStyle(MasoColor.text)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Explore Pro")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(MasoColor.text)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.white.opacity(0.08), in: Capsule())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .frame(minHeight: 112, alignment: .leading)
            .background {
                ZStack(alignment: .trailing) {
                    Color(red: 0.10, green: 0.17, blue: 0.12)
                    LinearGradient(colors: [MasoColor.accent.opacity(0.06), .clear],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    MasoMarkIcon(color: MasoColor.accent)
                        .frame(width: 160, height: 160).opacity(0.28)
                        .environment(\.layoutDirection, .leftToRight)
                        .offset(x: layoutDirection == .rightToLeft ? -42 : 42, y: 12)
                        .accessibilityHidden(true)
                }.allowsHitTesting(false)
            }
            .clipShape(outline)
            .overlay(outline
                .stroke(MasoColor.accent.opacity(0.10), lineWidth: 0.5))
            .contentShape(outline)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("pro.banner")
    }
}
