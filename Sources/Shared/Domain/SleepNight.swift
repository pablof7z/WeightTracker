import Foundation
import SwiftData

@Model
public final class SleepNight {
    @Attribute(.unique) public var nightDate: Date     // Reading.dayStart(of: wakeDate)
    public var inBedStart: Date?
    public var inBedEnd: Date?
    public var asleepMinutes: Int
    public var coreMinutes: Int
    public var deepMinutes: Int
    public var remMinutes: Int
    public var awakeMinutes: Int
    public var sourceProductType: String?
    public var lastUpdated: Date

    public init(
        nightDate: Date,
        inBedStart: Date? = nil,
        inBedEnd: Date? = nil,
        asleepMinutes: Int = 0,
        coreMinutes: Int = 0,
        deepMinutes: Int = 0,
        remMinutes: Int = 0,
        awakeMinutes: Int = 0,
        sourceProductType: String? = nil,
        lastUpdated: Date = Date()
    ) {
        self.nightDate = Reading.dayStart(of: nightDate)
        self.inBedStart = inBedStart
        self.inBedEnd = inBedEnd
        self.asleepMinutes = asleepMinutes
        self.coreMinutes = coreMinutes
        self.deepMinutes = deepMinutes
        self.remMinutes = remMinutes
        self.awakeMinutes = awakeMinutes
        self.sourceProductType = sourceProductType
        self.lastUpdated = lastUpdated
    }

    public var asleepHours: Double { Double(asleepMinutes) / 60.0 }
}
