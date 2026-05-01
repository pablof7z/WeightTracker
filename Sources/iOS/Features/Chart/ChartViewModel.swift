import Foundation
import SwiftUI

@MainActor
final class ChartViewModel: ObservableObject {
    @Published var readings: [Reading] = []
    @Published var clusters: [Cluster] = []
    @Published var gaps: [Gap] = []
    @Published var movingAverage: [(date: Date, kg: Double)] = []
    @Published var activeCut: ActiveCut?
    @Published var sleepNights: [SleepNight] = []

    private var sleepNightByDay: [Date: SleepNight] = [:]

    func reload(from repository: ReadingRepository) {
        let all = repository.allReadings()
        self.readings = all
        let cs = ClusterDetector.clusters(from: all)
        self.clusters = cs
        self.gaps = GapAnalyzer.gaps(between: cs, readings: all)
        self.movingAverage = Self.trailingAverage(readings: all, days: 30)
        self.activeCut = ActiveCutStore.load()
        let nights = repository.allSleepNights()
        self.sleepNights = nights
        var byDay: [Date: SleepNight] = [:]
        for n in nights {
            byDay[Reading.dayStart(of: n.nightDate)] = n
        }
        self.sleepNightByDay = byDay
    }

    func sleepBefore(date: Date) -> SleepNight? {
        let key = Reading.dayStart(of: date)
        return sleepNightByDay[key]
    }

    /// When an active cut exists, returns the number of days from cut start to max(targetEndDate, today)
    /// so the chart's visible window covers the full cut. Otherwise nil — caller falls back to user range.
    var cutVisibleDays: Int? {
        guard let cut = activeCut else { return nil }
        let end = max(cut.targetEndDate, Date())
        let days = Calendar.current.dateComponents([.day], from: cut.startDate, to: end).day ?? 0
        return max(7, days + 3) // small right-pad so target-line is visible
    }

    var cutScrollEnd: Date? {
        guard let cut = activeCut else { return nil }
        return max(cut.targetEndDate, Date())
    }

    static func trailingAverage(readings: [Reading], days: Int) -> [(date: Date, kg: Double)] {
        guard !readings.isEmpty else { return [] }
        var result: [(Date, Double)] = []
        result.reserveCapacity(readings.count)
        for (i, r) in readings.enumerated() {
            let lower = r.date.addingTimeInterval(-Double(days) * 86_400)
            var sum = 0.0
            var count = 0
            var j = i
            while j >= 0 && readings[j].date >= lower {
                sum += readings[j].weightKg
                count += 1
                j -= 1
            }
            if count > 0 {
                result.append((r.date, sum / Double(count)))
            }
        }
        return result
    }
}
