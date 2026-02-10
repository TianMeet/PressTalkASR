import Foundation

enum HUDAnchorPosition: String, CaseIterable, Identifiable {
    case bottomRight
    case bottomLeft
    case topRight
    case topLeft

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .bottomRight:
            return L10n.tr("hud.anchor.bottom_right")
        case .bottomLeft:
            return L10n.tr("hud.anchor.bottom_left")
        case .topRight:
            return L10n.tr("hud.anchor.top_right")
        case .topLeft:
            return L10n.tr("hud.anchor.top_left")
        }
    }
}
