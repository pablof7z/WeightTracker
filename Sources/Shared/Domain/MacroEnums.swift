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

public enum MealKind: String, Codable, CaseIterable, Sendable {
    case breakfast, lunch, dinner, snack, preWorkout, postWorkout, custom
}

public enum MealEventStatus: String, Codable, CaseIterable, Sendable {
    case eaten, skipped, partial
}

public enum HungerLevel: String, Codable, CaseIterable, Sendable {
    case low, moderate, high
}

/// How a meal event's macro contribution should be attributed.
///
/// - `planned`: user tapped "ate as planned" — macros come from the matched
///   slot's calculated/percentage values.
/// - `calculated`: a `calculate_meal` result was attached to the event and
///   overrides the slot's macros.
/// - `skipped`: meal was skipped, contributes zero macros.
/// - `untracked`: meal was logged but the macro contribution is unknown.
public enum MealAttributionSource: String, Codable, CaseIterable, Sendable {
    case planned
    case calculated
    case skipped
    case untracked
}
