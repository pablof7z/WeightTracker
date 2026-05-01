import Foundation

/// Single source of truth for every user-facing string in the macro feature.
/// Keep all copy in one place so we can change tone in one edit and so the
/// design rules ("never X") are enforced by absence rather than convention.
///
/// Critical rules:
/// * Chip text NEVER includes a kcal number.
/// * 7-day rollup NEVER says "X hit" — only "no logged misses" / "1 logged
///   miss" / "N logged misses".
/// * The 3-state legend strings appear verbatim in the history sheet footer.
public enum MacroCopy {
    // MARK: - MacroCard
    public static let cardTitle = "Macros"
    public static let cardEdit = "Edit"
    public static let cardViewHistory = "View history →"

    /// "Last 7d  no logged misses" / "1 logged miss" / "N logged misses".
    public static func cardSevenDayRollup(missCount: Int) -> String {
        switch missCount {
        case 0:  return "Last 7d — no logged misses"
        case 1:  return "Last 7d — 1 logged miss"
        default: return "Last 7d — \(missCount) logged misses"
        }
    }

    public static func logMissError(_ error: MacroDeviationError) -> String {
        switch error {
        case .futureDate:               return "Can't log a miss in the future."
        case .beyondBackfillWindow:     return "Misses can only be logged within the last 30 days."
        case .insideUntrackedRange:     return "That day is inside an untracked range."
        case .frozenOutsideEditWindow:  return "Misses older than 7 days can't be edited — but you can still delete them."
        case .noActivePlan:             return "No macro plan is active for that day."
        }
    }

    // MARK: - Edit macros sheet
    public static let editTitle = "Edit macros"
    public static let editCalories = "Calories"
    public static let editKcal = "kcal"
    public static let editProtein = "Protein"
    public static let editCarbs = "Carbs"
    public static let editFat = "Fat"
    public static let editGramSuffix = "g"
    public static let editReset = "Reset to defaults"
    public static let editSave = "Save"

    // MARK: - Start cut disclosure
    public static let startCutDisclosureLabel = "Macros (optional)"
    public static let startCutDisclosureHint =
        "We'll start with a sensible default. You can change it any time."

    // MARK: - Edit cut banner
    public static let editCutTargetChangedBanner = "Target changed — review macros?"
    public static let editCutOpen = "Open"

    // MARK: - History sheet
    public static let historyTitle = "Macro history"
    public static let historySectionPlan = "PLAN HISTORY"
    public static let historySectionMisses = "LOGGED MISSES"
    public static let historySectionUntracked = "UNTRACKED RANGES"
    public static let historyMarkUntracked = "Mark range as untracked"

    // 3-state legend — appears verbatim in the history sheet footer.
    public static let legendImplicit =
        "Days with no logged miss are assumed fine — we don't track adherence we weren't told about."
    public static let legendMiss =
        "A logged miss marks a day you ate over, under, or way off plan."
    public static let legendUntracked =
        "Untracked ranges are days you opted out of tracking entirely."

    // MARK: - Mark untracked sheet
    public static let untrackedTitle = "Mark range as untracked"
    public static let untrackedFrom = "From"
    public static let untrackedTo = "To"
    public static let untrackedReasonTravel = "Travel"
    public static let untrackedReasonIllness = "Illness"
    public static let untrackedReasonLife = "Life"
    public static let untrackedReasonCustom = "Custom"
    public static let untrackedCustomLabelPlaceholder = "Custom label"
    public static let untrackedSave = "Save"

    public static func untrackedError(_ error: MacroUntrackedRangeError) -> String {
        switch error {
        case .invalidRange: return "End date must be on or after the start date."
        case .futureEnd:    return "Untracked ranges can't end in the future."
        }
    }
}
