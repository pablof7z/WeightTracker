import SwiftUI

struct DisplaySettingsSection: View {
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.bodyUnit) private var bodyUnitRaw: String = BodyUnit.inches.rawValue
    @AppStorage(AppPrefKey.theme) private var themeRaw: String = ThemePreference.system.rawValue

    var body: some View {
        Section("Display") {
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
        }
    }
}
