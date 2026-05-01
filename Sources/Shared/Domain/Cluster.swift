import Foundation

public enum ClusterType: String, Sendable, Codable {
    case cut, bulk, maintenance, flat
}

public struct Cluster: Identifiable, Sendable, Hashable {
    public let id: UUID
    public let startDate: Date
    public let endDate: Date
    public let readingIDs: [UUID]
    public let count: Int
    public let meanWeightKg: Double
    public let minWeightKg: Double
    public let maxWeightKg: Double
    public let slopeKgPerDay: Double
    public let classification: ClusterType

    public init(
        id: UUID = UUID(),
        startDate: Date,
        endDate: Date,
        readingIDs: [UUID],
        count: Int,
        meanWeightKg: Double,
        minWeightKg: Double,
        maxWeightKg: Double,
        slopeKgPerDay: Double,
        classification: ClusterType
    ) {
        self.id = id
        self.startDate = startDate
        self.endDate = endDate
        self.readingIDs = readingIDs
        self.count = count
        self.meanWeightKg = meanWeightKg
        self.minWeightKg = minWeightKg
        self.maxWeightKg = maxWeightKg
        self.slopeKgPerDay = slopeKgPerDay
        self.classification = classification
    }

    public var slopeLbPerDay: Double { UnitConvert.kgToLb(slopeKgPerDay) }
    public var durationDays: Int {
        max(0, Calendar.current.dateComponents([.day], from: startDate, to: endDate).day ?? 0)
    }
    public func contains(date: Date) -> Bool {
        date >= startDate && date <= endDate
    }
}
