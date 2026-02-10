import SwiftUI

struct SessionStatusBadge: View {
    let status: AppViewModel.SessionStatus

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.color)
                .frame(width: 7, height: 7)
            Text(status.title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous)
                .fill(status.color.opacity(0.18))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(status.color.opacity(0.35), lineWidth: 0.8)
        )
    }
}
