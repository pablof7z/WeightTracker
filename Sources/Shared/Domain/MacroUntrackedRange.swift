import Foundation
import SwiftData

@Model
public final class MacroUntrackedRange {
    @Attribute(.unique) public var id: UUID
    public var cutStartDate: Date
    public var startDate: Date
    public var endDate: Date
    public var reasonRaw: String
    public var customReasonLabel: String?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        cutStartDate: Date,
        startDate: Date,
        endDate: Date,
        reason: UntrackedReason = .life,
        customReasonLabel: String? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.cutStartDate = Reading.dayStart(of: cutStartDate)
        self.startDate = Reading.dayStart(of: startDate)
        self.endDate = Reading.dayStart(of: endDate)
        self.reasonRaw = reason.rawValue
        self.customReasonLabel = customReasonLabel
        self.createdAt = createdAt
    }

    public var reason: UntrackedReason {
        get { UntrackedReason(rawValue: reasonRaw) ?? .life }
        set { reasonRaw = newValue.rawValue }
    }

    public func contains(_ day: Date) -> Bool {
        let d = Reading.dayStart(of: day)
        return d >= startDate && d <= endDate
    }
}
