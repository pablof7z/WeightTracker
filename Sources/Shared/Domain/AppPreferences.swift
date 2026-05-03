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

    // AI
    public static let openRouterModel = "ai.openRouterModel"
    public static let elevenLabsSTTModel = "ai.elevenLabsSTTModel"
    public static let elevenLabsVoiceID = "ai.elevenLabsVoiceID"
    public static let coachVisionModel = "ai.coachVisionModel"

    // Agent
    public static let agentNostrEnabled = "agent.nostr.enabled"
    public static let agentNostrRelayURL = "agent.nostr.relayURL"
    public static let agentNostrSince = "agent.nostr.since"
    public static let agentNostrProfileName = "agent.nostr.profileName"
    public static let agentNostrProfileAbout = "agent.nostr.profileAbout"
    public static let agentSystemPrompt = "agent.systemPrompt"
    public static let agentNostrState = "agent.nostr.state.v1"

    // Macro priors (silent defaults; no Settings UI in M1)
    public static let userSex = "macros.userSex"
    public static let userAgeYears = "macros.userAgeYears"
    public static let userHeightCm = "macros.userHeightCm"
    public static let userActivityFactor = "macros.userActivityFactor"
}

public enum MacroDefaultsPrefs {
    public static let sex: String = Sex.male.rawValue
    public static let ageYears: Int = 35
    public static let heightCm: Double = 175
    public static let activityFactor: Double = 1.5
}

public enum AppGroup {
    public static let identifier = "group.app.pfer.weighttracker"
}

public enum AppConstants {
    public static let cloudKitContainerID = "iCloud.app.pfer.weighttracker"
    public static let bgRefreshIdentifier = "app.pfer.weighttracker.refresh"
    public static let defaultGoalLb: Double = 158.0
    public static let defaultCutDurationWeeks: Int = 16
    public static let defaultOpenRouterModel = "openai/gpt-5.2"
    public static let defaultElevenLabsSTTModel = "scribe_v2_realtime"
    public static let defaultElevenLabsVoiceID = "21m00Tcm4TlvDq8ikWAM"  // Rachel
    public static let defaultCoachVisionModel = "anthropic/claude-sonnet-4-5"
}
