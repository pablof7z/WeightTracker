import Foundation
import SwiftData

@Model
public final class Reading {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    public var weightKg: Double
    public var hipsCm: Double?
    public var waistCm: Double?
    public var sourceRaw: String
    public var note: String?
    public var deviceName: String?

    public init(
        id: UUID = UUID(),
        date: Date,
        weightKg: Double,
        hipsCm: Double? = nil,
        waistCm: Double? = nil,
        source: ReadingSource = .manual,
        note: String? = nil,
        deviceName: String? = nil
    ) {
        self.id = id
        self.date = Self.dayStart(of: date)
        self.weightKg = weightKg
        self.hipsCm = hipsCm
        self.waistCm = waistCm
        self.sourceRaw = source.rawValue
        self.note = note
        self.deviceName = deviceName
    }

    public var source: ReadingSource {
        get { ReadingSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    public static func dayStart(of date: Date, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }
}
