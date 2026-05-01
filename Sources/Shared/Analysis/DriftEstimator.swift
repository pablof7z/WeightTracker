import Foundation

public enum DriftEstimator {

    private static let defaultLbPerMonth: Double = 1.2
    private static let minGapDays: Int = 30

    public static func estimateCurrentWeightLb(
        lastReadingKg: Double,
        daysSinceLast: Int,
        historicalGaps: [Gap]
    ) -> Double {
        let lastLb = UnitConvert.kgToLb(lastReadingKg)
        let qualifying = historicalGaps.filter { $0.durationDays >= minGapDays }
        let median: Double
        if qualifying.isEmpty {
            median = defaultLbPerMonth
        } else {
            median = medianValue(qualifying.map { $0.driftLbPerMonth })
        }
        let months = Double(daysSinceLast) / 30.0
        return lastLb + median * months
    }

    private static func medianValue(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let n = sorted.count
        if n.isMultiple(of: 2) {
            return (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0
        } else {
            return sorted[n / 2]
        }
    }
}
