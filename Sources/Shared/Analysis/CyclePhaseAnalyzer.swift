import Foundation

public enum CyclePhase: Sendable {
    case menstrual
    case follicular
    case luteal
    case uncertain
}

public enum CyclePhaseAnalyzer {

    private static let secondsPerDay: TimeInterval = 86_400
    private static let defaultCycleLength = 28
    private static let follicularStartDay = 6
    private static let follicularEndDay = 12
    private static let menstrualEndDay = 5
    private static let lutealStartDay = 15
    private static let highRetentionMenstrualEndDay = 5
    private static let cycleLengthSpreadThreshold = 7

    public static func phase(for date: Date, cycleStarts: [Date]) -> CyclePhase {
        guard let cycleStart = mostRecentStart(at: date, in: cycleStarts) else {
            return .uncertain
        }
        let day = dayOfCycle(date: date, cycleStart: cycleStart)
        let length = inferredCycleLength(cycleStarts: cycleStarts)

        if day > length + 5 {
            return .uncertain
        }

        switch day {
        case ...menstrualEndDay:
            return .menstrual
        case follicularStartDay...follicularEndDay:
            return .follicular
        case lutealStartDay...:
            return .luteal
        default:
            return .uncertain
        }
    }

    public static func follicularReadings(from readings: [Reading], cycleStarts: [Date]) -> [Reading] {
        guard !cycleStarts.isEmpty else { return [] }
        return readings.filter { phase(for: $0.date, cycleStarts: cycleStarts) == .follicular }
    }

    public static func isHighRetention(date: Date, cycleStarts: [Date]) -> Bool {
        guard let cycleStart = mostRecentStart(at: date, in: cycleStarts) else { return false }
        let day = dayOfCycle(date: date, cycleStart: cycleStart)
        let length = inferredCycleLength(cycleStarts: cycleStarts)
        if day > length + 5 { return false }
        if day <= highRetentionMenstrualEndDay { return true }
        if day >= lutealStartDay && day <= length { return true }
        return false
    }

    public static func highRetentionRanges(in range: ClosedRange<Date>, cycleStarts: [Date]) -> [(Date, Date)] {
        guard !cycleStarts.isEmpty else { return [] }
        let length = inferredCycleLength(cycleStarts: cycleStarts)
        let calendar = Calendar.current
        var windows: [(Date, Date)] = []

        for (index, start) in cycleStarts.enumerated() {
            let nextStart: Date = {
                if index + 1 < cycleStarts.count { return cycleStarts[index + 1] }
                return calendar.date(byAdding: .day, value: length, to: start) ?? start.addingTimeInterval(Double(length) * secondsPerDay)
            }()

            if let menstrualEnd = calendar.date(byAdding: .day, value: highRetentionMenstrualEndDay, to: start) {
                windows.append((start, min(menstrualEnd, nextStart)))
            }

            if let lutealStart = calendar.date(byAdding: .day, value: lutealStartDay - 1, to: start),
               lutealStart < nextStart {
                windows.append((lutealStart, nextStart))
            }
        }

        return windows.compactMap { window -> (Date, Date)? in
            let lower = max(window.0, range.lowerBound)
            let upper = min(window.1, range.upperBound)
            guard lower < upper else { return nil }
            return (lower, upper)
        }
    }

    private static func mostRecentStart(at date: Date, in cycleStarts: [Date]) -> Date? {
        cycleStarts.last(where: { $0 <= date })
    }

    private static func dayOfCycle(date: Date, cycleStart: Date) -> Int {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: cycleStart), to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days + 1
    }

    private static func inferredCycleLength(cycleStarts: [Date]) -> Int {
        guard cycleStarts.count >= 2 else { return defaultCycleLength }
        let sorted = cycleStarts.sorted()
        var lengths: [Int] = []
        for i in 1..<sorted.count {
            let days = Calendar.current.dateComponents([.day], from: sorted[i - 1], to: sorted[i]).day ?? 0
            if days > 0 { lengths.append(days) }
        }
        guard !lengths.isEmpty else { return defaultCycleLength }
        let recent = Array(lengths.suffix(3))
        guard let lo = recent.min(), let hi = recent.max() else { return defaultCycleLength }
        if hi - lo > cycleLengthSpreadThreshold { return defaultCycleLength }
        let mean = recent.reduce(0, +) / recent.count
        return mean
    }
}
