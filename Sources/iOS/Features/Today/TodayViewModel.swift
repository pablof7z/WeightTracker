import Foundation
import SwiftUI
import SwiftData

@MainActor
final class TodayViewModel: ObservableObject {
    // Display value in current weight unit (lb or kg)
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

    struct SavedConfirmation: Identifiable, Equatable {
        let id = UUID()
        let displayWeight: Double
        let weightUnitSymbol: String
        let deltaDisplay: Double?
        let date: Date
        let clusterNote: String?
    }

    /// Load state for a given date. If a reading exists on that date, populate from it.
    /// Otherwise fall back to the most-recent prior reading (or default) and mark as placeholder.
    func loadForDate(_ date: Date, repository: ReadingRepository, unit: WeightUnit, bodyUnit: BodyUnit) {
        let day = Reading.dayStart(of: date)
        self.date = day

        if let earliest = repository.allReadings().first {
            self.minDate = min(self.minDate, Reading.dayStart(of: earliest.date))
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

    /// Convenience that loads for today.
    func prefill(from repository: ReadingRepository, unit: WeightUnit, bodyUnit: BodyUnit = .inches) {
        loadForDate(Date(), repository: repository, unit: unit, bodyUnit: bodyUnit)
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

        // Build confirmation card
        let deltaDisplay: Double? = {
            guard let priorKg else { return nil }
            let priorDisp = UnitConvert.displayWeight(kg: priorKg, in: weightUnit)
            return displayValue - priorDisp
        }()

        let clusters = ClusterDetector.clusters(from: services.repository.allReadings())
        let active = ClusterDetector.activeCluster(in: clusters)
        let clusterNote: String? = active.map { c in
            switch c.classification {
            case .cut: return "Active cut: \(c.durationDays)d"
            case .bulk: return "Active bulk: \(c.durationDays)d"
            case .maintenance: return "Maintenance: \(c.durationDays)d"
            case .flat: return "Flat: \(c.durationDays)d"
            }
        }

        lastSaved = SavedConfirmation(
            displayWeight: displayValue,
            weightUnitSymbol: weightUnit.symbol,
            deltaDisplay: deltaDisplay,
            date: day,
            clusterNote: clusterNote
        )
    }
}
