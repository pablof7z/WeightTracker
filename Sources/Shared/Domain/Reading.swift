import Foundation
import SwiftData

@Model
public final class Reading {
    @Attribute(.unique) public var id: UUID
    public var date: Date
    /// Stable civil-date identity for the weigh-in. `Date` remains for SwiftData
    /// sorting and compatibility, while this key prevents timezone changes from
    /// turning (for example) an Aug 8 reading into Aug 7 or Aug 9.
    public var civilDayKey: String?
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
        deviceName: String? = nil,
        civilDayKey: String? = nil,
        calendar: Calendar = .current
    ) {
        self.id = id
        let key = civilDayKey ?? Self.civilDayKey(for: date, calendar: calendar)
        self.civilDayKey = key
        self.date = Self.date(fromCivilDayKey: key, calendar: calendar)
            ?? Self.dayStart(of: date, calendar: calendar)
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

    public func dayStart(in calendar: Calendar = .current) -> Date {
        guard let civilDayKey,
              let stable = Self.date(fromCivilDayKey: civilDayKey, calendar: calendar)
        else { return calendar.startOfDay(for: date) }
        return stable
    }

    public static func civilDayKey(for date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    public static func date(fromCivilDayKey key: String, calendar: Calendar = .current) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }
}
