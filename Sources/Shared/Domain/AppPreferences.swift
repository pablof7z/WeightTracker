import Foundation
import SwiftUI

public enum AppPrefKey {
    public static let weightUnit = "weightUnit"
    public static let bodyUnit = "bodyUnit"
    public static let theme = "theme"
    public static let onboardingComplete = "onboardingComplete"
    public static let lastChartRangeDays = "lastChartRangeDays"
    public static let icloudSyncEnabled = "icloudSyncEnabled"
    public static let autoExportEnabled = "autoExportEnabled"
    public static let activeCutJSON = "activeCutJSON"
    public static let goalWeightKg = "goalWeightKg"

    // Notification preferences
    public static let notifMaster = "notif.master"
    public static let notifGapForming = "notif.gapForming"
    public static let notifGapDeepening = "notif.gapDeepening"
    public static let notifClusterBroken = "notif.clusterBroken"
    public static let notifCutDay = "notif.cutDay"
    public static let notifCutMilestone = "notif.cutMilestone"
    public static let notifCutStall = "notif.cutStall"
    public static let notifQuietStartHour = "notif.quietStartHour"
    public static let notifQuietEndHour = "notif.quietEndHour"
    public static let notifPausedUntil = "notif.pausedUntil"

    // HealthKit
    public static let healthKitReadEnabled = "hk.readEnabled"
    public static let healthKitWriteEnabled = "hk.writeEnabled"
}

public enum AppGroup {
    public static let identifier = "group.app.pfer.weighttracker"
}

public enum AppConstants {
    public static let cloudKitContainerID = "iCloud.app.pfer.weighttracker"
    public static let bgRefreshIdentifier = "app.pfer.weighttracker.refresh"
    public static let defaultGoalLb: Double = 158.0
    public static let defaultCutDurationWeeks: Int = 16
}
