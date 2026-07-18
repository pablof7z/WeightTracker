import SwiftUI

struct DisplaySettingsSection: View {
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.theme) private var themeRaw: String = ThemePreference.system.rawValue
    @AppStorage(AppPrefKey.todayChartVariation) private var todayChartVariationRaw: String = CutChartVariation.recentFocus.rawValue

    var body: some View {
        Section {
            Picker("Weight unit", selection: $weightUnitRaw) {
                ForEach(WeightUnit.allCases, id: \.rawValue) { u in
                    Text(u.label).tag(u.rawValue)
                }
            }
            Picker("Body unit", selection: $bodyUnitRaw) {
                ForEach(BodyUnit.allCases, id: \.rawValue) { u in
                    Text(u.label).tag(u.rawValue)
                }
            }
            Picker("Theme", selection: $themeRaw) {
                ForEach(ThemePreference.allCases, id: \.rawValue) { t in
                    Text(t.label).tag(t.rawValue)
                }
            }
            Picker("Today chart", selection: $todayChartVariationRaw) {
                ForEach(CutChartVariation.allCases) { variation in
                    Text(variation.label).tag(variation.rawValue)
                }
            }
        } header: {
            Text("Display")
        } footer: {
            Text("Weight and body units apply throughout the app. The Today chart keeps a stable scale for the selected view. Theme overrides the system appearance for this app only.")
        }
    }
}
