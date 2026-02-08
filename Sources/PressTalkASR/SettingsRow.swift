import SwiftUI

struct SettingsRow: View {
    let icon: String
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool
    var isDisabled: Bool = false
    var badgeText: String? = nil
    var trailingActionTitle: String? = nil
    var trailingAction: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 16, height: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .regular))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(isDisabled)

                if let badgeText {
                    Text(badgeText)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.primary.opacity(0.08))
                        )
                }

                if let trailingActionTitle, let trailingAction {
                    Button(trailingActionTitle, action: trailingAction)
                        .buttonStyle(.borderless)
                        .controlSize(.small)
                        .font(.system(size: 11.5, weight: .medium))
                }
            }
        }
        .opacity(isDisabled ? 0.72 : 1)
    }
}
