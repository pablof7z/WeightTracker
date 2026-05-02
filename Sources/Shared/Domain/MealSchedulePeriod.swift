import Foundation
import SwiftData

@Model
public final class MealSchedulePeriod {
    @Attribute(.unique) public var id: UUID
    public var cutStartDate: Date
    public var startDate: Date
    public var endDate: Date?
    public var note: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        cutStartDate: Date,
        startDate: Date,
        endDate: Date? = nil,
        note: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.cutStartDate = Reading.dayStart(of: cutStartDate)
        self.startDate = Reading.dayStart(of: startDate)
        self.endDate = endDate.map { Reading.dayStart(of: $0) }
        self.note = note
        self.createdAt = createdAt
    }
}
