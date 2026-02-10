import SwiftUI

struct SettingsCard<Content: View>: View {
    var accent: Color = UITheme.electricBlue
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                        .fill(.ultraThinMaterial)
                    RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent.opacity(0.12),
                                    Color.clear
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                }
            )
            .overlay(
                ZStack {
                    RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                        .stroke(UITheme.panelBorder, lineWidth: 0.8)
                    RoundedRectangle(cornerRadius: UITheme.cardCornerRadius - 1, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 0.6)
                }
            )
            .shadow(color: Color.black.opacity(0.08), radius: 10, y: 4)
    }
}
