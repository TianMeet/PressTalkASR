import SwiftUI

struct KeycapView: View {
    let keys: [String]

    init(_ keys: [String]) {
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(keys.enumerated()), id: \.offset) { index, key in
                if index > 0 {
                    Text("+")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(UITheme.tertiaryText)
                }

                Text(key)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .padding(.horizontal, key.count > 1 ? 9 : 7)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.92))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor).opacity(0.6), lineWidth: 0.8)
                    )
                    .shadow(color: Color.black.opacity(0.10), radius: 1.2, y: 0.8)
            }
        }
    }
}
