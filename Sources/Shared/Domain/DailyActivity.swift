import Foundation
import SwiftData

@Model
public final class DailyActivity {
    @Attribute(.unique) public var day: Date
    public var steps: Int
    public var activeEnergyKcal: Double?
    public var exerciseMinutes: Int?
    public var source: String?
    public var lastUpdated: Date

    public init(
        day: Date,
        steps: Int = 0,
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Int? = nil,
        source: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.day = Reading.dayStart(of: day)
        self.steps = max(0, steps)
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.source = source
        self.lastUpdated = lastUpdated
    }
}
