import Foundation

/// Storage for the USDA FoodData Central API key.
///
/// USDA FDC is a free public API. Their `DEMO_KEY` is rate-limited to roughly
/// 30 requests/hour and is good enough for development. Production users
/// should request their own free key from <https://api.data.gov/signup/> and
/// drop it in via Settings.
///
/// We deliberately keep this in `UserDefaults` rather than the Keychain — the
/// key is not sensitive (it has no billing attached and only authorizes
/// nutrition lookups) and we want it readable from background tasks without
/// triggering Keychain unlocks.
enum USDACredentialStore {
    static let userDefaultsKey = "usda_api_key"

    /// USDA's documented public sandbox key. Throttled but functional.
    static let defaultKey = "DEMO_KEY"

    /// The key the app should send with USDA requests. Returns the demo key
    /// when the user hasn't configured anything explicitly.
    static var apiKey: String {
        get {
            let stored = UserDefaults.standard.string(forKey: userDefaultsKey)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if let stored, !stored.isEmpty {
                return stored
            }
            return defaultKey
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                UserDefaults.standard.removeObject(forKey: userDefaultsKey)
            } else {
                UserDefaults.standard.set(trimmed, forKey: userDefaultsKey)
            }
        }
    }

    /// Whether the user has supplied a custom (non-demo) key.
    static var hasUserKey: Bool {
        guard let stored = UserDefaults.standard.string(forKey: userDefaultsKey)?
            .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return !stored.isEmpty
    }

    /// Remove the user's stored key, falling back to `defaultKey`.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: userDefaultsKey)
    }
}
