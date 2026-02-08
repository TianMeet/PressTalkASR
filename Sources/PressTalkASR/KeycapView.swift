import SwiftUI

struct KeycapView: View {
    let keys: [String]

    init(_ keys: [String]) {
        self.keys = keys
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(keys, id: \.self) { key in
                Text(key)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .padding(.horizontal, key.count > 1 ? 7 : 5)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.08))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 0.8)
                    )
            }
        }
    }
}
