import Foundation

public enum CSVUnitDetector {
    /// Detects whether a list of weight values is in lbs or kg.
    /// - Rule §5.3: any value > 100 → lbs (treat all as lbs); else kg.
    /// - Mixed: if values include both <50 AND >150 → mixed = true.
    /// - Confidence: fraction of values that match the chosen unit's typical range.
    public static func detectWeight(values: [Double]) -> (unit: WeightUnit, confidence: Double, mixed: Bool) {
        guard !values.isEmpty else {
            return (.kg, 0.0, false)
        }

        let hasLow = values.contains { $0 < 50 }
        let hasHigh = values.contains { $0 > 150 }
        let mixed = hasLow && hasHigh

        let anyAbove100 = values.contains { $0 > 100 }
        let unit: WeightUnit = anyAbove100 ? .lbs : .kg

        // Confidence: fraction of values consistent with chosen unit.
        // For lbs: typical range 60..600. For kg: typical range 25..275.
        let consistent = values.filter { v in
            switch unit {
            case .lbs: return v >= 50 && v <= 700
            case .kg:  return v >= 20 && v <= 300
            }
        }.count
        let confidence = Double(consistent) / Double(values.count)

        return (unit, confidence, mixed)
    }

    /// Detects whether body measurement values (hips/waist) are in cm or inches.
    /// - Rule §5.3: any value > 80 → cm; else inches.
    /// - Mixed: values span both <40 (likely inches) AND >120 (definitely cm).
    public static func detectBody(values: [Double]) -> (unit: BodyUnit, confidence: Double, mixed: Bool) {
        guard !values.isEmpty else {
            return (.cm, 0.0, false)
        }

        let hasLow = values.contains { $0 < 40 }
        let hasHigh = values.contains { $0 > 120 }
        let mixed = hasLow && hasHigh

        let anyAbove80 = values.contains { $0 > 80 }
        let unit: BodyUnit = anyAbove80 ? .cm : .inches

        let consistent = values.filter { v in
            switch unit {
            case .cm:     return v >= 40 && v <= 250
            case .inches: return v >= 15 && v <= 100
            }
        }.count
        let confidence = Double(consistent) / Double(values.count)

        return (unit, confidence, mixed)
    }
}
