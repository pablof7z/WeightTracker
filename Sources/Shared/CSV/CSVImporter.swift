import Foundation

// MARK: - Public Types

public struct SkippedRow: Sendable {
    public let line: Int
    public let reason: String
    public init(line: Int, reason: String) {
        self.line = line
        self.reason = reason
    }
}

public struct CSVImportPreview {
    public let rowCount: Int
    public let validReadings: [Reading]
    public let firstDate: Date?
    public let lastDate: Date?
    public let detectedWeightUnit: WeightUnit
    public let detectedBodyUnit: BodyUnit
    public let weightUnitConfidence: Double
    public let bodyUnitConfidence: Double
    public let collisionDates: [Date]
    public let duplicatesCollapsed: Int
    public let skippedRows: [SkippedRow]

    public init(
        rowCount: Int,
        validReadings: [Reading],
        firstDate: Date?,
        lastDate: Date?,
        detectedWeightUnit: WeightUnit,
        detectedBodyUnit: BodyUnit,
        weightUnitConfidence: Double,
        bodyUnitConfidence: Double,
        collisionDates: [Date],
        duplicatesCollapsed: Int,
        skippedRows: [SkippedRow]
    ) {
        self.rowCount = rowCount
        self.validReadings = validReadings
        self.firstDate = firstDate
        self.lastDate = lastDate
        self.detectedWeightUnit = detectedWeightUnit
        self.detectedBodyUnit = detectedBodyUnit
        self.weightUnitConfidence = weightUnitConfidence
        self.bodyUnitConfidence = bodyUnitConfidence
        self.collisionDates = collisionDates
        self.duplicatesCollapsed = duplicatesCollapsed
        self.skippedRows = skippedRows
    }
}

public enum CSVImportError: Error, LocalizedError {
    case emptyFile
    case missingHeader
    case headerMissingColumn(String)
    case mixedWeightUnits
    case mixedBodyUnits
    case noValidRows

    public var errorDescription: String? {
        switch self {
        case .emptyFile:
            return "The CSV file is empty."
        case .missingHeader:
            return "The CSV file is missing a header row."
        case .headerMissingColumn(let name):
            return "The CSV header is missing a required column: \(name)."
        case .mixedWeightUnits:
            return "The CSV file appears to mix weight units (kg and lbs). Please use a single unit."
        case .mixedBodyUnits:
            return "The CSV file appears to mix body measurement units (cm and inches). Please use a single unit."
        case .noValidRows:
            return "The CSV file contains no valid rows."
        }
    }
}

// MARK: - Importer

public enum CSVImporter {

    public static func parse(
        url: URL,
        weightUnitOverride: WeightUnit? = nil,
        bodyUnitOverride: BodyUnit? = nil
    ) throws -> CSVImportPreview {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .isoLatin1)
        else {
            throw CSVImportError.emptyFile
        }
        return try parse(text: text, weightUnitOverride: weightUnitOverride, bodyUnitOverride: bodyUnitOverride)
    }

    public static func parse(
        text: String,
        weightUnitOverride: WeightUnit? = nil,
        bodyUnitOverride: BodyUnit? = nil
    ) throws -> CSVImportPreview {

        // Strip BOM if present.
        var working = text
        if working.hasPrefix("\u{FEFF}") {
            working.removeFirst()
        }

        // Split lines, preserving line numbers (1-indexed).
        let rawLines = working.components(separatedBy: .newlines)
        // Identify the first non-empty line as header.
        var headerLineIndex: Int?
        for (idx, line) in rawLines.enumerated() {
            if !line.trimmingCharacters(in: .whitespaces).isEmpty {
                headerLineIndex = idx
                break
            }
        }
        guard let headerIdx = headerLineIndex else {
            throw CSVImportError.emptyFile
        }

        let headerFields = splitCSVLine(rawLines[headerIdx]).map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
        guard !headerFields.isEmpty else {
            throw CSVImportError.missingHeader
        }

        // Required: Date, Weight. Hips & Waist optional but recognized.
        guard let dateCol = headerFields.firstIndex(of: "date") else {
            throw CSVImportError.headerMissingColumn("Date")
        }
        guard let weightCol = headerFields.firstIndex(of: "weight") else {
            throw CSVImportError.headerMissingColumn("Weight")
        }
        let hipsCol = headerFields.firstIndex(of: "hips")
        let waistCol = headerFields.firstIndex(of: "waist")

        let dateFormatter: DateFormatter = {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone(identifier: "UTC")
            f.locale = Locale(identifier: "en_US_POSIX")
            return f
        }()

        // Parsed candidate row before unit conversion.
        struct RawRow {
            let line: Int
            let date: Date
            let weight: Double
            let hips: Double?
            let waist: Double?
        }

        var rawRows: [RawRow] = []
        var skipped: [SkippedRow] = []

        for i in (headerIdx + 1)..<rawLines.count {
            let lineNumber = i + 1
            let line = rawLines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }

            let fields = splitCSVLine(line)

            func field(at idx: Int?) -> String? {
                guard let idx = idx, idx < fields.count else { return nil }
                let v = fields[idx].trimmingCharacters(in: .whitespaces)
                return v
            }

            guard let dateStr = field(at: dateCol), !dateStr.isEmpty else {
                skipped.append(SkippedRow(line: lineNumber, reason: "Missing date"))
                continue
            }
            guard let date = dateFormatter.date(from: dateStr) else {
                skipped.append(SkippedRow(line: lineNumber, reason: "Invalid date format (expected YYYY-MM-DD)"))
                continue
            }

            let weightStr = field(at: weightCol) ?? ""
            if weightStr.isEmpty {
                // Empty weight rows dropped silently per spec.
                skipped.append(SkippedRow(line: lineNumber, reason: "Empty weight"))
                continue
            }
            guard let weight = parseDouble(weightStr), weight > 0 else {
                skipped.append(SkippedRow(line: lineNumber, reason: "Invalid weight value"))
                continue
            }

            var hipsVal: Double? = nil
            if let raw = field(at: hipsCol), !raw.isEmpty {
                if let v = parseDouble(raw), v > 0 {
                    hipsVal = v
                } else {
                    skipped.append(SkippedRow(line: lineNumber, reason: "Invalid hips value"))
                    continue
                }
            }

            var waistVal: Double? = nil
            if let raw = field(at: waistCol), !raw.isEmpty {
                if let v = parseDouble(raw), v > 0 {
                    waistVal = v
                } else {
                    skipped.append(SkippedRow(line: lineNumber, reason: "Invalid waist value"))
                    continue
                }
            }

            rawRows.append(RawRow(line: lineNumber, date: date, weight: weight, hips: hipsVal, waist: waistVal))
        }

        guard !rawRows.isEmpty else {
            throw CSVImportError.noValidRows
        }

        // Detect weight units across the file as a whole.
        let weightValues = rawRows.map { $0.weight }
        let weightDetection = CSVUnitDetector.detectWeight(values: weightValues)
        if weightDetection.mixed && weightUnitOverride == nil {
            throw CSVImportError.mixedWeightUnits
        }
        let weightUnit = weightUnitOverride ?? weightDetection.unit
        let weightConfidence = weightDetection.confidence

        // Detect body units (combine hips+waist).
        let bodyValues = rawRows.flatMap { row -> [Double] in
            var v: [Double] = []
            if let h = row.hips { v.append(h) }
            if let w = row.waist { v.append(w) }
            return v
        }
        let bodyDetection = CSVUnitDetector.detectBody(values: bodyValues)
        if bodyDetection.mixed && bodyUnitOverride == nil {
            throw CSVImportError.mixedBodyUnits
        }
        let bodyUnit = bodyUnitOverride ?? bodyDetection.unit
        let bodyConfidence = bodyDetection.confidence

        // Convert to canonical (kg / cm) and bucket by day-start.
        // We must also track collision dates and duplicates collapsed.
        // §5: keep LAST in file order on duplicate dates.
        struct Candidate {
            let line: Int
            let dayStart: Date
            let weightKg: Double
            let hipsCm: Double?
            let waistCm: Double?
        }

        let candidates: [Candidate] = rawRows.map { row in
            let kg: Double = (weightUnit == .lbs) ? UnitConvert.lbToKg(row.weight) : row.weight
            let hipsCm: Double? = row.hips.map { (bodyUnit == .inches) ? UnitConvert.inchToCm($0) : $0 }
            let waistCm: Double? = row.waist.map { (bodyUnit == .inches) ? UnitConvert.inchToCm($0) : $0 }
            return Candidate(
                line: row.line,
                dayStart: Reading.dayStart(of: row.date),
                weightKg: kg,
                hipsCm: hipsCm,
                waistCm: waistCm
            )
        }

        // Collapse duplicates: keep last per dayStart.
        var lastByDay: [Date: Candidate] = [:]
        var firstSeenOrder: [Date] = []
        var seenSet: Set<Date> = []
        var duplicateDays: Set<Date> = []

        for c in candidates {
            if seenSet.contains(c.dayStart) {
                duplicateDays.insert(c.dayStart)
            } else {
                seenSet.insert(c.dayStart)
                firstSeenOrder.append(c.dayStart)
            }
            lastByDay[c.dayStart] = c
        }

        let duplicatesCollapsed = candidates.count - lastByDay.count

        // Build readings in original first-seen order, but using last value seen.
        let readings: [Reading] = firstSeenOrder.compactMap { day in
            guard let c = lastByDay[day] else { return nil }
            return Reading(
                date: c.dayStart,
                weightKg: c.weightKg,
                hipsCm: c.hipsCm,
                waistCm: c.waistCm,
                source: .importCSV
            )
        }

        let sortedDates = readings.map { $0.date }.sorted()
        let first = sortedDates.first
        let last = sortedDates.last

        return CSVImportPreview(
            rowCount: rawRows.count,
            validReadings: readings,
            firstDate: first,
            lastDate: last,
            detectedWeightUnit: weightUnit,
            detectedBodyUnit: bodyUnit,
            weightUnitConfidence: weightConfidence,
            bodyUnitConfidence: bodyConfidence,
            collisionDates: Array(duplicateDays).sorted(),
            duplicatesCollapsed: duplicatesCollapsed,
            skippedRows: skipped
        )
    }

    // MARK: - CSV line splitter (handles quoted fields and escaped quotes)

    static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        current.append("\"")
                        i = line.index(after: next)
                        continue
                    } else {
                        inQuotes = false
                        i = next
                        continue
                    }
                } else {
                    current.append(ch)
                    i = line.index(after: i)
                }
            } else {
                if ch == "," {
                    fields.append(current)
                    current = ""
                    i = line.index(after: i)
                } else if ch == "\"" {
                    inQuotes = true
                    i = line.index(after: i)
                } else if ch == "\r" {
                    i = line.index(after: i)
                } else {
                    current.append(ch)
                    i = line.index(after: i)
                }
            }
        }
        fields.append(current)
        return fields
    }

    static func parseDouble(_ s: String) -> Double? {
        let cleaned = s.replacingOccurrences(of: ",", with: ".").trimmingCharacters(in: .whitespaces)
        return Double(cleaned)
    }
}
