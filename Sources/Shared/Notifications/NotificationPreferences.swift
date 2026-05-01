import Foundation

public struct NotificationPreferences: Sendable {
    public var master: Bool
    public var gapForming: Bool
    public var gapDeepening: Bool
    public var clusterBroken: Bool
    public var cutDay: Bool
    public var cutMilestone: Bool
    public var cutStall: Bool
    public var quietStartHour: Int
    public var quietEndHour: Int

    public static let `default` = NotificationPreferences(
        master: true,
        gapForming: true,
        gapDeepening: true,
        clusterBroken: true,
        cutDay: true,
        cutMilestone: true,
        cutStall: true,
        quietStartHour: 21,
        quietEndHour: 7
    )

    public static func fromDefaults(_ d: UserDefaults = .standard) -> NotificationPreferences {
        NotificationPreferences(
            master: d.object(forKey: AppPrefKey.notifMaster) as? Bool ?? true,
            gapForming: d.object(forKey: AppPrefKey.notifGapForming) as? Bool ?? true,
            gapDeepening: d.object(forKey: AppPrefKey.notifGapDeepening) as? Bool ?? true,
            clusterBroken: d.object(forKey: AppPrefKey.notifClusterBroken) as? Bool ?? true,
            cutDay: d.object(forKey: AppPrefKey.notifCutDay) as? Bool ?? true,
            cutMilestone: d.object(forKey: AppPrefKey.notifCutMilestone) as? Bool ?? true,
            cutStall: d.object(forKey: AppPrefKey.notifCutStall) as? Bool ?? true,
            quietStartHour: d.object(forKey: AppPrefKey.notifQuietStartHour) as? Int ?? 21,
            quietEndHour: d.object(forKey: AppPrefKey.notifQuietEndHour) as? Int ?? 7
        )
    }
}

public struct ScheduledTrigger: Sendable {
    public let id: String
    public let title: String
    public let body: String
    public let fireAfter: TimeInterval

    public init(id: String, title: String, body: String, fireAfter: TimeInterval) {
        self.id = id
        self.title = title
        self.body = body
        self.fireAfter = fireAfter
    }
}
