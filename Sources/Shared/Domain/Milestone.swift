import Foundation
import SwiftData

/// A named, dated event the user wants to surface during the active cut —
/// e.g. "Trip" on May 25. Milestones appear as flag markers on the cut
/// progress strip and rotate through the weight forecast widget's horizon
/// rotation. Stored at day granularity (calendar start-of-day).
@Model
public final class Milestone {
    @Attribute(.unique) public var id: UUID
    public var name: String          // e.g. "Trip"
    public var date: Date            // calendar day of the event (startOfDay normalized)
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        name: String,
        date: Date,
        createdAt: Date = Date(),
        calendar: Calendar = .current
    ) {
        self.id = id
        self.name = name
        self.date = calendar.startOfDay(for: date)
        self.createdAt = createdAt
    }
}
