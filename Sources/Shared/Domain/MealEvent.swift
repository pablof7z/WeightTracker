import Foundation
import SwiftData

@Model
public final class MealEvent {
    @Attribute(.unique) public var id: UUID
    public var date: Date             // dayStart-normalized, for fast day queries
    public var loggedAt: Date         // when the log was recorded
    public var ateAt: Date            // when the meal was actually eaten
    public var minutesFromMidnight: Int  // denormalized from ateAt for pattern queries
    public var scheduleId: UUID?
    public var slotId: UUID?
    public var slotNameSnapshot: String?  // survives slot deletion
    public var statusRaw: String
    public var hungerBeforeRaw: String?
    public var hungerAfterRaw: String?
    public var note: String?
    /// How this event's macros should be attributed. Stored as a raw string so
    /// SwiftData lightweight migration handles the additive column. Defaults to
    /// "planned" so existing rows continue to behave as before.
    public var attributionSourceRaw: String = "planned"

    public init(
        id: UUID = UUID(),
        ateAt: Date,
        loggedAt: Date = Date(),
        scheduleId: UUID? = nil,
        slotId: UUID? = nil,
        slotNameSnapshot: String? = nil,
        status: MealEventStatus,
        hungerBefore: HungerLevel? = nil,
        hungerAfter: HungerLevel? = nil,
        note: String? = nil,
        attributionSource: MealAttributionSource = .planned,
        calendar: Calendar = .current
    ) {
        self.id = id
        self.date = Reading.dayStart(of: ateAt, calendar: calendar)
        self.loggedAt = loggedAt
        self.ateAt = ateAt
        let comps = calendar.dateComponents([.hour, .minute], from: ateAt)
        self.minutesFromMidnight = (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
        self.scheduleId = scheduleId
        self.slotId = slotId
        self.slotNameSnapshot = slotNameSnapshot
        self.statusRaw = status.rawValue
        self.hungerBeforeRaw = hungerBefore?.rawValue
        self.hungerAfterRaw = hungerAfter?.rawValue
        self.note = note
        self.attributionSourceRaw = attributionSource.rawValue
    }

    public var status: MealEventStatus {
        get { MealEventStatus(rawValue: statusRaw) ?? .eaten }
        set { statusRaw = newValue.rawValue }
    }

    public var hungerBefore: HungerLevel? {
        get { hungerBeforeRaw.flatMap { HungerLevel(rawValue: $0) } }
        set { hungerBeforeRaw = newValue?.rawValue }
    }

    public var hungerAfter: HungerLevel? {
        get { hungerAfterRaw.flatMap { HungerLevel(rawValue: $0) } }
        set { hungerAfterRaw = newValue?.rawValue }
    }

    public var attributionSource: MealAttributionSource {
        get { MealAttributionSource(rawValue: attributionSourceRaw) ?? .planned }
        set { attributionSourceRaw = newValue.rawValue }
    }
}
