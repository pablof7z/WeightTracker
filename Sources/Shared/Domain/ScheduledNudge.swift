import Foundation
import SwiftData

public enum NudgeTriggerType: String, Codable, CaseIterable, Sendable {
    case timeOfDay
    case mealMissed
    case custom
}

@Model
public final class ScheduledNudge {
    @Attribute(.unique) public var id: UUID
    public var triggerTypeRaw: String = "custom"
    public var triggerParams: String = "{}"
    public var message: String = "pending"
    public var scheduledAt: Date?
    public var expiresAt: Date?
    public var delivered: Bool = false
    public var cancelledAt: Date?
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        triggerType: NudgeTriggerType = .custom,
        triggerParams: String = "{}",
        message: String,
        scheduledAt: Date? = nil,
        expiresAt: Date? = nil,
        delivered: Bool = false,
        cancelledAt: Date? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.triggerTypeRaw = triggerType.rawValue
        self.triggerParams = triggerParams
        self.message = message
        self.scheduledAt = scheduledAt
        self.expiresAt = expiresAt
        self.delivered = delivered
        self.cancelledAt = cancelledAt
        self.createdAt = createdAt
    }

    public var triggerType: NudgeTriggerType {
        get { NudgeTriggerType(rawValue: triggerTypeRaw) ?? .custom }
        set { triggerTypeRaw = newValue.rawValue }
    }
}
