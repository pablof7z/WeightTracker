import Foundation

public struct ActiveCut: Codable, Equatable, Sendable {
    public var startDate: Date
    public var startWeightKg: Double
    public var targetWeightKg: Double
    public var targetEndDate: Date
    public var dailyReminderSecondsAfterMidnight: Int

    public init(
        startDate: Date,
        startWeightKg: Double,
        targetWeightKg: Double,
        targetEndDate: Date,
        dailyReminderSecondsAfterMidnight: Int = 7 * 3600 + 30 * 60
    ) {
        self.startDate = startDate
        self.startWeightKg = startWeightKg
        self.targetWeightKg = targetWeightKg
        self.targetEndDate = targetEndDate
        self.dailyReminderSecondsAfterMidnight = dailyReminderSecondsAfterMidnight
    }

    public var totalLossKg: Double { startWeightKg - targetWeightKg }
    public var totalLossLb: Double { UnitConvert.kgToLb(totalLossKg) }
    public var totalDays: Int {
        max(1, Calendar.current.dateComponents([.day], from: startDate, to: targetEndDate).day ?? 1)
    }
    public func daysElapsed(now: Date = Date()) -> Int {
        Calendar.current.dateComponents([.day], from: startDate, to: now).day ?? 0
    }
    public func daysRemaining(now: Date = Date()) -> Int {
        max(0, totalDays - daysElapsed(now: now))
    }
}

public struct HistoricalCut: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let startWeightKg: Double
    public let endWeightKg: Double
    public let totalLossKg: Double
    public let avgRateKgPerWeek: Double
    public let durationDays: Int

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        startWeightKg: Double,
        endWeightKg: Double,
        totalLossKg: Double,
        avgRateKgPerWeek: Double,
        durationDays: Int
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.startWeightKg = startWeightKg
        self.endWeightKg = endWeightKg
        self.totalLossKg = totalLossKg
        self.avgRateKgPerWeek = avgRateKgPerWeek
        self.durationDays = durationDays
    }

    public var totalLossLb: Double { UnitConvert.kgToLb(totalLossKg) }
    public var avgRateLbPerWeek: Double { UnitConvert.kgToLb(avgRateKgPerWeek) }
}
