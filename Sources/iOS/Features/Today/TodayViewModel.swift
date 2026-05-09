import Foundation
import SwiftUI
import SwiftData

@MainActor
final class TodayViewModel: ObservableObject {
    @Published var displayValue: Double = 150.0
    @Published var date: Date = Date()
    @Published var hipsValue: String = ""
    @Published var waistValue: String = ""
    @Published var note: String = ""
    @Published var lastSaved: SavedConfirmation?
    @Published var minDate: Date = Calendar.current.date(from: DateComponents(year: 2014, month: 1, day: 1)) ?? Date()
    /// True when the displayed value reflects a saved reading on the selected date.
    /// False when the value is a placeholder carried over from a prior day.
    @Published var hasEntry: Bool = false
    /// Loaded snapshot of active cut (if any) — used by Today screen for header + minichart.
    @Published var activeCut: ActiveCut?
    @Published var inCutReadings: [Reading] = []
    @Published var projection: CutProjectionResult?
    /// 7-day EMA of weight in kg, computed over the most recent ≤7 readings on or before
    /// the currently-selected date. `nil` when fewer than 2 readings are available.
    @Published var ema7Kg: Double?

    struct SavedConfirmation: Identifiable, Equatable {
        let id = UUID()
        let displayWeight: Double
        let weightUnitSymbol: String
        let deltaDisplay: Double?
        let date: Date
        let clusterNote: String?
        let clusterType: ClusterType?
    }

    /// Load state for a given date. If a reading exists on that date, populate from it.
    /// Otherwise fall back to the most-recent prior reading (or default) and mark as placeholder.
    func loadForDate(_ date: Date, repository: ReadingRepository, unit: WeightUnit, bodyUnit: BodyUnit, cycleStarts: [Date] = []) {
        let day = Reading.dayStart(of: date)
        self.date = day

        let allReadings = repository.allReadings()
        if let earliest = allReadings.first {
            self.minDate = min(self.minDate, Reading.dayStart(of: earliest.date))
        }

        self.ema7Kg = Self.computeEMA7Kg(readings: allReadings, asOf: day)

        let cut = ActiveCutStore.load()
        self.activeCut = cut
        if let cut {
            self.inCutReadings = allReadings.filter { $0.date >= cut.startDate }
            // Exclude current cut's readings from historical analysis — only past completed
            // cuts should inform the rate estimates.
            let preCurrentCut = allReadings.filter { $0.date < cut.startDate }
            let clusters = ClusterDetector.clusters(from: preCurrentCut)
            let historicals = HistoricalCutDetector.detect(in: clusters, readings: preCurrentCut)
            self.projection = CutProjection.project(
                active: cut,
                readings: allReadings,
                historicalCuts: historicals,
                cycleStarts: cycleStarts
            )
        } else {
            self.inCutReadings = []
            self.projection = nil
        }

        if let existing = repository.reading(on: day) {
            let display = UnitConvert.displayWeight(kg: existing.weightKg, in: unit)
            self.displayValue = (display * 10.0).rounded() / 10.0
            self.hipsValue = existing.hipsCm.map { String(format: "%.1f", UnitConvert.displayBody(cm: $0, in: bodyUnit)) } ?? ""
            self.waistValue = existing.waistCm.map { String(format: "%.1f", UnitConvert.displayBody(cm: $0, in: bodyUnit)) } ?? ""
            self.note = existing.note ?? ""
            self.hasEntry = true
        } else {
            // Use the most-recent reading at-or-before this date as a placeholder hint
            let prior = repository.allReadings().last(where: { $0.date <= day }) ?? repository.mostRecent()
            if let prior {
                let display = UnitConvert.displayWeight(kg: prior.weightKg, in: unit)
                self.displayValue = (display * 10.0).rounded() / 10.0
            } else {
                self.displayValue = unit == .lbs ? 150.0 : 70.0
            }
            self.hipsValue = ""
            self.waistValue = ""
            self.note = ""
            self.hasEntry = false
        }
    }

    func prefill(from repository: ReadingRepository, unit: WeightUnit, bodyUnit: BodyUnit = .inches, cycleStarts: [Date] = []) {
        loadForDate(Date(), repository: repository, unit: unit, bodyUnit: bodyUnit, cycleStarts: cycleStarts)
    }

    func adjust(by amount: Double) {
        // amount is in display units; round to one decimal place to avoid FP drift
        displayValue = ((displayValue + amount) * 10.0).rounded() / 10.0
    }

    func save(services: AppServices, weightUnit: WeightUnit, bodyUnit: BodyUnit) async {
        let weightKg = UnitConvert.storeWeight(displayValue, from: weightUnit)
        let day = Reading.dayStart(of: date)

        let prior = services.repository.mostRecent()
        let priorKg = prior?.weightKg

        if let existing = services.repository.reading(on: day) {
            services.repository.delete(existing)
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let hipsCm: Double? = {
            guard let v = Double(hipsValue.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
            return UnitConvert.storeBody(v, from: bodyUnit)
        }()
        let waistCm: Double? = {
            guard let v = Double(waistValue.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
            return UnitConvert.storeBody(v, from: bodyUnit)
        }()

        let new = Reading(
            date: day,
            weightKg: weightKg,
            hipsCm: hipsCm,
            waistCm: waistCm,
            source: .manual,
            note: trimmedNote.isEmpty ? nil : trimmedNote
        )
        services.repository.insert(new)
        hasEntry = true

        await services.healthKit.writeReading(new)
        await services.notifications.scheduleEvaluatedTriggers()

        let deltaDisplay: Double? = {
            guard let priorKg else { return nil }
            let priorDisp = UnitConvert.displayWeight(kg: priorKg, in: weightUnit)
            return displayValue - priorDisp
        }()

        let clusters = ClusterDetector.clusters(from: services.repository.allReadings())
        let active = ClusterDetector.activeCluster(in: clusters)
        let clusterNote: String? = active.map { c in
            let day = max(c.durationDays, 1)
            switch c.classification {
            case .cut: return "Cutting · day \(day)"
            case .bulk: return "Bulking · day \(day)"
            case .maintenance: return "Maintaining · day \(day)"
            case .flat: return "Steady · day \(day)"
            }
        }

        lastSaved = SavedConfirmation(
            displayWeight: displayValue,
            weightUnitSymbol: weightUnit.symbol,
            deltaDisplay: deltaDisplay,
            date: day,
            clusterNote: clusterNote,
            clusterType: active?.classification
        )

        // Refresh the EMA to reflect the just-saved reading.
        self.ema7Kg = Self.computeEMA7Kg(readings: services.repository.allReadings(), asOf: day)
    }

    /// 7-day EMA over the most recent ≤7 readings whose date is ≤ `asOf`.
    /// Smoothing factor α = 2/(N+1) with N=7 → α = 0.25. Uses kg (storage unit);
    /// the view converts to display units. Returns nil when fewer than 2 readings exist.
    static func computeEMA7Kg(readings: [Reading], asOf day: Date) -> Double? {
        let eligible = readings
            .filter { $0.date <= day }
            .sorted { $0.date < $1.date }
        let window = eligible.suffix(7)
        guard window.count >= 2 else { return nil }
        let alpha = 0.25 // 2 / (7 + 1)
        var ema = window.first!.weightKg
        for r in window.dropFirst() {
            ema = alpha * r.weightKg + (1.0 - alpha) * ema
        }
        return ema
    }
}
