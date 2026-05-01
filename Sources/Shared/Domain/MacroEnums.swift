import Foundation

public enum Sex: String, Codable, CaseIterable, Sendable {
    case male, female, unspecified
}

public enum MacroDirection: String, Codable, CaseIterable, Sendable {
    case over, under, unknown
}

public enum MacroMagnitude: String, Codable, CaseIterable, Sendable {
    case slight     // ~150 kcal
    case moderate   // ~300 kcal
    case large      // ~600 kcal
    case wayOff     // unknown / very far
}

public enum MacroPlanTag: String, Codable, CaseIterable, Sendable {
    case standard, refeed, dietBreak, custom
}

public enum UntrackedReason: String, Codable, CaseIterable, Sendable {
    case travel, illness, life, custom
}
