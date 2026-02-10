import SwiftUI

struct SettingsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UITheme.cardCornerRadius, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 0.8)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 3, y: 2)
    }
}
