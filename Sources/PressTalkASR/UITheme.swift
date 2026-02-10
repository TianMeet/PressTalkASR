import SwiftUI

enum UITheme {
    static let panelCornerRadius: CGFloat = 18
    static let cardCornerRadius: CGFloat = 12

    static let electricBlue = Color(red: 0.17, green: 0.53, blue: 0.98)
    static let listeningColor = Color(red: 0.12, green: 0.72, blue: 0.44)
    static let transcribingColor = Color(red: 0.92, green: 0.58, blue: 0.12)
    static let successColor = electricBlue
    static let errorColor = Color(red: 0.86, green: 0.30, blue: 0.27)

    static let panelBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBorder = Color(nsColor: .separatorColor).opacity(0.42)
    static let secondaryText = Color.secondary
    static let tertiaryText = Color.secondary.opacity(0.72)
}
