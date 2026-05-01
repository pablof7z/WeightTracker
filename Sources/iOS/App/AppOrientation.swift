import UIKit

/// Process-wide orientation lock — read by AppDelegate's
/// `supportedInterfaceOrientationsFor` and updated by views that need to
/// force a specific orientation (e.g. the fullscreen chart in landscape).
final class AppOrientation: @unchecked Sendable {
    static let shared = AppOrientation()
    private init() {}

    var supportedMask: UIInterfaceOrientationMask = .portrait

    /// Update the supported mask AND request a geometry update so the active
    /// scene rotates immediately.
    @MainActor
    func set(_ mask: UIInterfaceOrientationMask) {
        supportedMask = mask
        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first
        else { return }
        if #available(iOS 16.0, *) {
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { _ in }
            scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        AppOrientation.shared.supportedMask
    }
}
