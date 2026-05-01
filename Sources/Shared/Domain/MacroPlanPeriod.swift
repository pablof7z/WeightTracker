import Foundation
import SwiftData

@Model
public final class MacroPlanPeriod {
    @Attribute(.unique) public var id: UUID
    public var cutStartDate: Date
    public var startDate: Date
    public var endDate: Date?
    public var kcal: Int
    public var proteinG: Int?
    public var carbsG: Int?
    public var fatG: Int?
    public var tagRaw: String
    public var customTagLabel: String?
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        cutStartDate: Date,
        startDate: Date,
        endDate: Date? = nil,
        kcal: Int,
        proteinG: Int? = nil,
        carbsG: Int? = nil,
        fatG: Int? = nil,
        tag: MacroPlanTag = .standard,
        customTagLabel: String? = nil,
        note: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.cutStartDate = Reading.dayStart(of: cutStartDate)
        self.startDate = Reading.dayStart(of: startDate)
        self.endDate = endDate.map { Reading.dayStart(of: $0) }
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.tagRaw = tag.rawValue
        self.customTagLabel = customTagLabel
        self.note = note
        self.createdAt = createdAt
    }

    public var tag: MacroPlanTag {
        get { MacroPlanTag(rawValue: tagRaw) ?? .standard }
        set { tagRaw = newValue.rawValue }
    }
}
