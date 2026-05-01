import Foundation

public enum CSVExporter {

    /// Builds the CSV text for the given readings, displayed in the user's preferred units.
    /// Header is always exactly: `Date,Hips,Waist,Weight`.
    /// Empty cells use empty string. Values formatted with 1 decimal place.
    public static func makeCSVText(readings: [Reading], weightUnit: WeightUnit, bodyUnit: BodyUnit) -> String {
        let sorted = readings.sorted { $0.date < $1.date }

        var out = "Date,Hips,Waist,Weight\n"
        for r in sorted {
            let dateStr = isoDate(r.date)

            let hipsStr: String
            if let hips = r.hipsCm {
                let v = (bodyUnit == .inches) ? UnitConvert.cmToInch(hips) : hips
                hipsStr = formatOneDecimal(v)
            } else {
                hipsStr = ""
            }

            let waistStr: String
            if let waist = r.waistCm {
                let v = (bodyUnit == .inches) ? UnitConvert.cmToInch(waist) : waist
                waistStr = formatOneDecimal(v)
            } else {
                waistStr = ""
            }

            let weightDisplay = (weightUnit == .lbs)
                ? UnitConvert.kgToLb(r.weightKg)
                : r.weightKg
            let weightStr = formatOneDecimal(weightDisplay)

            out.append("\(dateStr),\(hipsStr),\(waistStr),\(weightStr)\n")
        }
        return out
    }

    /// Filename `Measurement-Summary-{firstISO}-to-{lastISO}.csv`.
    /// If readings are empty, falls back to today's date for both ends.
    public static func suggestedFilename(for readings: [Reading]) -> String {
        let dates = readings.map { $0.date }.sorted()
        let first = dates.first ?? Date()
        let last = dates.last ?? Date()
        return "Measurement-Summary-\(isoDate(first))-to-\(isoDate(last)).csv"
    }

    // MARK: - Helpers

    private static let isoFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "UTC")
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private static func isoDate(_ date: Date) -> String {
        isoFormatter.string(from: date)
    }

    private static let oneDecimalFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.numberStyle = .decimal
        f.minimumFractionDigits = 1
        f.maximumFractionDigits = 1
        f.usesGroupingSeparator = false
        f.decimalSeparator = "."
        return f
    }()

    private static func formatOneDecimal(_ value: Double) -> String {
        oneDecimalFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}
