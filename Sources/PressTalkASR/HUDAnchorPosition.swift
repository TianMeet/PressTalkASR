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
            return "Bottom Right"
        case .bottomLeft:
            return "Bottom Left"
        case .topRight:
            return "Top Right"
        case .topLeft:
            return "Top Left"
        }
    }
}
