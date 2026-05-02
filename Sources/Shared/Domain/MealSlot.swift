import Foundation
import SwiftData

@Model
public final class MealSlot {
    @Attribute(.unique) public var id: UUID
    public var scheduleId: UUID
    public var name: String
    public var minutesFromMidnight: Int
    public var kindRaw: String
    public var sortOrder: Int
    public var kcalPercent: Double?
    public var proteinPercent: Double?
    public var fatPercent: Double?
    public var carbsPercent: Double?
    public var note: String?
    public var createdAt: Date

    // Calculated absolute values (set by the calculate_meal coach tool).
    // When present, these take priority over the percent-based fields above
    // because they represent ground-truth nutrition for the foods the user
    // actually plans to eat for this slot.
    public var calculatedKcal: Int?
    public var calculatedProteinG: Int?
    public var calculatedFatG: Int?
    public var calculatedCarbsG: Int?
    public var calculatedAt: Date?
    public var foodDescription: String?  // human-readable summary, e.g. "150g chicken + 200g rice"

    public init(
        id: UUID = UUID(),
        scheduleId: UUID,
        name: String,
        minutesFromMidnight: Int,
        kind: MealKind = .custom,
        sortOrder: Int? = nil,
        kcalPercent: Double? = nil,
        proteinPercent: Double? = nil,
        fatPercent: Double? = nil,
        carbsPercent: Double? = nil,
        note: String? = nil,
        createdAt: Date = Date(),
        calculatedKcal: Int? = nil,
        calculatedProteinG: Int? = nil,
        calculatedFatG: Int? = nil,
        calculatedCarbsG: Int? = nil,
        calculatedAt: Date? = nil,
        foodDescription: String? = nil
    ) {
        self.id = id
        self.scheduleId = scheduleId
        self.name = name
        self.minutesFromMidnight = max(0, min(minutesFromMidnight, 1439))
        self.kindRaw = kind.rawValue
        self.sortOrder = sortOrder ?? minutesFromMidnight
        self.kcalPercent = kcalPercent
        self.proteinPercent = proteinPercent
        self.fatPercent = fatPercent
        self.carbsPercent = carbsPercent
        self.note = note
        self.createdAt = createdAt
        self.calculatedKcal = calculatedKcal
        self.calculatedProteinG = calculatedProteinG
        self.calculatedFatG = calculatedFatG
        self.calculatedCarbsG = calculatedCarbsG
        self.calculatedAt = calculatedAt
        self.foodDescription = foodDescription
    }

    public var kind: MealKind {
        get { MealKind(rawValue: kindRaw) ?? .custom }
        set { kindRaw = newValue.rawValue }
    }
}
