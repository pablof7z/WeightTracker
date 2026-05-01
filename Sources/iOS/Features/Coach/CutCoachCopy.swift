import Foundation

enum CutCoachCopy {
    static let today = "Today"
    static let thisWeek = "This week"
    static let calories = "Calories"
    static let protein = "Protein"
    static let fat = "Fat"
    static let carbs = "Carbs"
    static let steps = "Steps"
    static let training = "Training"
    static let reasons = "Reasons"
    static let needOneDetail = "One more detail"
    static let apply = "Apply"
    static let hold = "Hold"
    static let adjust = "Adjust"
    static let extendTimeline = "Extend timeline"
    static let gatherData = "Gather data"

    // Product voice guardrails:
    // - Use factual fragments: target, reason, decision.
    // - Avoid encouragement, pep talk, praise, moral judgment, or chat filler.
    // - Prohibited examples: "great job", "you got this", "keep going",
    //   "proud", "good/bad", "should", "deserve", "don't worry".
    static func reasonBullets(_ reasons: [String]) -> [String] {
        reasons
            .map(Self.reasonBullet)
            .filter { !$0.isEmpty }
    }

    static func reasonBullet(_ reason: String) -> String {
        let trimmed = reason
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".!"))

        guard !trimmed.isEmpty else { return "" }

        let deSentenceCased = trimmed.prefix(1).lowercased() + trimmed.dropFirst()
        return deSentenceCased.replacingOccurrences(of: "You ", with: "you ")
    }
}
