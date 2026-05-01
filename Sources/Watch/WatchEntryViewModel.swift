import Foundation
import SwiftUI

@MainActor
final class WatchEntryViewModel: ObservableObject {
    @Published var displayValue: Double
    @Published var saved: Bool = false
    @Published var lastReading: Reading?

    private let services: WatchServices

    init(services: WatchServices = .shared) {
        self.services = services
        // Determine user unit from prefs (default lbs)
        let unitRaw = UserDefaults.standard.string(forKey: AppPrefKey.weightUnit) ?? WeightUnit.lbs.rawValue
        let unit = WeightUnit(rawValue: unitRaw) ?? .lbs

        let last = services.repository.mostRecent()
        self.lastReading = last

        let initial: Double
        if let last {
            let display = UnitConvert.displayWeight(kg: last.weightKg, in: unit)
            initial = (display * 2.0).rounded() / 2.0
        } else {
            // Default 175 lb in user unit
            let kg = UnitConvert.storeWeight(175.0, from: .lbs)
            let display = UnitConvert.displayWeight(kg: kg, in: unit)
            initial = (display * 2.0).rounded() / 2.0
        }
        self.displayValue = initial
    }

    func loadLast() {
        self.lastReading = services.repository.mostRecent()
    }

    func save() async {
        let unitRaw = UserDefaults.standard.string(forKey: AppPrefKey.weightUnit) ?? WeightUnit.lbs.rawValue
        let unit = WeightUnit(rawValue: unitRaw) ?? .lbs

        let kg = UnitConvert.storeWeight(displayValue, from: unit)
        let reading = Reading(date: Date(), weightKg: kg, source: .watch)
        services.repository.insert(reading)
        await services.healthKit.writeReading(reading)

        saved = true
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        saved = false
        loadLast()
    }
}
