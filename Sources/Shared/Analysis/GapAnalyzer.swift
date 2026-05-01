import Foundation

public enum GapAnalyzer {

    private static let activeGapThresholdDays: Int = 14

    public static func gaps(between clusters: [Cluster], readings: [Reading]) -> [Gap] {
        guard clusters.count >= 2 else { return [] }
        let byID: [UUID: Reading] = Dictionary(uniqueKeysWithValues: readings.map { ($0.id, $0) })
        let cal = Calendar.current
        var result: [Gap] = []
        for i in 0..<(clusters.count - 1) {
            let prev = clusters[i]
            let next = clusters[i + 1]
            guard let prevLastID = prev.readingIDs.last,
                  let nextFirstID = next.readingIDs.first,
                  let prevReading = byID[prevLastID],
                  let nextReading = byID[nextFirstID]
            else { continue }
            let days = cal.dateComponents([.day], from: prevReading.date, to: nextReading.date).day ?? 0
            result.append(Gap(
                startDate: prevReading.date,
                endDate: nextReading.date,
                durationDays: max(0, days),
                weightStartKg: prevReading.weightKg,
                weightEndKg: nextReading.weightKg
            ))
        }
        return result
    }

    public static func activeGap(clusters: [Cluster], lastReading: Reading?, now: Date = Date()) -> Gap? {
        guard let last = lastReading else { return nil }
        let cal = Calendar.current
        let daysSinceLast = cal.dateComponents([.day], from: last.date, to: now).day ?? 0

        let needsActiveGap: Bool
        if let lastCluster = clusters.last {
            let daysSinceCluster = cal.dateComponents([.day], from: lastCluster.endDate, to: now).day ?? 0
            needsActiveGap = daysSinceLast > activeGapThresholdDays || daysSinceCluster > activeGapThresholdDays
        } else {
            needsActiveGap = daysSinceLast > activeGapThresholdDays
        }
        guard needsActiveGap else { return nil }

        let start = clusters.last?.endDate ?? last.date
        return Gap(
            startDate: start,
            endDate: now,
            durationDays: max(0, cal.dateComponents([.day], from: start, to: now).day ?? 0),
            weightStartKg: last.weightKg,
            weightEndKg: last.weightKg
        )
    }
}
