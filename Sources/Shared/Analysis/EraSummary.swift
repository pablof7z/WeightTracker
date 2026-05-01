import Foundation

public struct EraStats: Identifiable, Sendable {
    public let id: UUID
    public let label: String
    public let startYear: Int
    public let endYear: Int
    public let readingCount: Int
    public let gapCount: Int
    public let meanDriftLb: Double
    public let meanRateLbPerMonth: Double
    public let gainRatio: Double

    public init(
        id: UUID = UUID(),
        label: String,
        startYear: Int,
        endYear: Int,
        readingCount: Int,
        gapCount: Int,
        meanDriftLb: Double,
        meanRateLbPerMonth: Double,
        gainRatio: Double
    ) {
        self.id = id
        self.label = label
        self.startYear = startYear
        self.endYear = endYear
        self.readingCount = readingCount
        self.gapCount = gapCount
        self.meanDriftLb = meanDriftLb
        self.meanRateLbPerMonth = meanRateLbPerMonth
        self.gainRatio = gainRatio
    }
}

public enum EraSummary {

    public static let eras: [(label: String, start: Int, end: Int)] = [
        ("2014\u{2013}17", 2014, 2017),
        ("2018\u{2013}20", 2018, 2020),
        ("2021\u{2013}23", 2021, 2023),
        ("2024+", 2024, 9999)
    ]

    public static func compute(readings: [Reading], gaps: [Gap]) -> [EraStats] {
        let cal = Calendar.current
        return eras.map { era in
            let eraReadings = readings.filter {
                let y = cal.component(.year, from: $0.date)
                return y >= era.start && y <= era.end
            }
            let eraGaps = gaps.filter {
                let y = cal.component(.year, from: $0.startDate)
                return y >= era.start && y <= era.end
            }
            let meanDrift: Double
            let meanRate: Double
            let gainRatio: Double
            if eraGaps.isEmpty {
                meanDrift = 0
                meanRate = 0
                gainRatio = 0
            } else {
                meanDrift = eraGaps.map { $0.driftLb }.reduce(0, +) / Double(eraGaps.count)
                meanRate = eraGaps.map { $0.driftLbPerMonth }.reduce(0, +) / Double(eraGaps.count)
                let gains = eraGaps.filter { $0.didGain }.count
                gainRatio = Double(gains) / Double(eraGaps.count)
            }
            return EraStats(
                label: era.label,
                startYear: era.start,
                endYear: era.end,
                readingCount: eraReadings.count,
                gapCount: eraGaps.count,
                meanDriftLb: meanDrift,
                meanRateLbPerMonth: meanRate,
                gainRatio: gainRatio
            )
        }
    }
}
