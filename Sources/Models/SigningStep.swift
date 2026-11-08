import Foundation

enum SigningStep: Int, CaseIterable, Identifiable {
    case unpacking, patching, signing, packaging

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .unpacking: return "Unpacking"
        case .patching: return "Patching"
        case .signing: return "Signing"
        case .packaging: return "Packaging"
        }
    }

    var systemImage: String {
        switch self {
        case .unpacking: return "shippingbox"
        case .patching: return "slider.horizontal.3"
        case .signing: return "signature"
        case .packaging: return "archivebox"
        }
    }
}

struct LogLine: Identifiable, Equatable {
    let id = UUID()
    let date = Date()
    let text: String
    var isError: Bool = false
}
