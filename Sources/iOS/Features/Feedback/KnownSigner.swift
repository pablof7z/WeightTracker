import UIKit

enum KnownSigner: CaseIterable {
    case amber
    case primal

    var name: String {
        switch self {
        case .amber: return "Amber"
        case .primal: return "Primal"
        }
    }

    var urlScheme: String {
        switch self {
        case .amber: return "nostrsigner"
        case .primal: return "primal"
        }
    }

    @MainActor
    static func detect() -> KnownSigner? {
        for signer in KnownSigner.allCases {
            if let url = URL(string: "\(signer.urlScheme)://"),
               UIApplication.shared.canOpenURL(url) {
                return signer
            }
        }
        return nil
    }
}
