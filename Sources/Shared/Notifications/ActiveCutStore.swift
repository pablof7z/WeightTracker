import Foundation

public enum ActiveCutStore {
    public static func load() -> ActiveCut? {
        guard let data = UserDefaults.standard.data(forKey: AppPrefKey.activeCutJSON) else { return nil }
        return try? JSONDecoder.iso.decode(ActiveCut.self, from: data)
    }

    public static func save(_ cut: ActiveCut?) {
        if let cut, let data = try? JSONEncoder.iso.encode(cut) {
            UserDefaults.standard.set(data, forKey: AppPrefKey.activeCutJSON)
        } else {
            UserDefaults.standard.removeObject(forKey: AppPrefKey.activeCutJSON)
        }
    }
}

public extension JSONEncoder {
    static let iso: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

public extension JSONDecoder {
    static let iso: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
