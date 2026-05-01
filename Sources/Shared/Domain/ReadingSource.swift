import Foundation

public enum ReadingSource: String, Codable, CaseIterable, Sendable {
    case manual
    case watch
    case healthKit
    case importCSV = "import"

    public var displayName: String {
        switch self {
        case .manual: return "Manual"
        case .watch: return "Apple Watch"
        case .healthKit: return "Apple Health"
        case .importCSV: return "Imported"
        }
    }
}
