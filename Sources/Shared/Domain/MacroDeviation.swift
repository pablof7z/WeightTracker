import Foundation
import SwiftData

@Model
public final class MacroDeviation {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var cutStartDate: Date
    public var planPeriodId: UUID
    public var directionRaw: String
    public var magnitudeRaw: String
    public var note: String?
    public var loggedAt: Date

    public init(
        id: UUID = UUID(),
        date: Date,
        cutStartDate: Date,
        planPeriodId: UUID,
        direction: MacroDirection = .unknown,
        magnitude: MacroMagnitude = .wayOff,
        note: String? = nil,
        loggedAt: Date = .now
    ) {
        self.id = id
        self.date = Reading.dayStart(of: date)
        self.cutStartDate = Reading.dayStart(of: cutStartDate)
        self.planPeriodId = planPeriodId
        self.directionRaw = direction.rawValue
        self.magnitudeRaw = magnitude.rawValue
        self.note = note
        self.loggedAt = loggedAt
    }

    public var direction: MacroDirection {
        get { MacroDirection(rawValue: directionRaw) ?? .unknown }
        set { directionRaw = newValue.rawValue }
    }

    public var magnitude: MacroMagnitude {
        get { MacroMagnitude(rawValue: magnitudeRaw) ?? .wayOff }
        set { magnitudeRaw = newValue.rawValue }
    }
}
