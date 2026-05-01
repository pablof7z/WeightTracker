import Foundation

public struct Gap: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let durationDays: Int
    public let weightStartKg: Double
    public let weightEndKg: Double

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        durationDays: Int,
        weightStartKg: Double,
        weightEndKg: Double
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.durationDays = durationDays
        self.weightStartKg = weightStartKg
        self.weightEndKg = weightEndKg
    }

    public var driftKg: Double { weightEndKg - weightStartKg }
    public var driftLb: Double { UnitConvert.kgToLb(driftKg) }
    public var driftLbPerMonth: Double {
        guard durationDays > 0 else { return 0 }
        return driftLb * 30.0 / Double(durationDays)
    }
    public var didGain: Bool { driftKg > 0 }
}
