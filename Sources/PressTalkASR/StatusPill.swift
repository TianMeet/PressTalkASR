import SwiftUI

struct PopoverStatusPillModel {
    let text: String
    let color: Color
    let showsDot: Bool
    let showsSpinner: Bool
}

struct PopoverStatusPill: View {
    let model: PopoverStatusPillModel

    var body: some View {
        HStack(spacing: 6) {
            if model.showsSpinner {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.65)
                    .tint(model.color)
            } else if model.showsDot {
                Circle()
                    .fill(model.color)
                    .frame(width: 6, height: 6)
            }

            Text(model.text)
                .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(model.color.opacity(0.15))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(model.color.opacity(0.28), lineWidth: 0.8)
        )
        .frame(height: 22)
    }
}
