import SwiftUI

/// The Cuts-tab macro card. Reads the current plan period for the active cut,
/// renders kcal + macro grid + 7-day rollup (suppressed for the first 7 days),
/// and exposes Edit / View History entry points.
struct MacroCard: View {
    @EnvironmentObject private var services: AppServices

    let cutStartDate: Date

    @State private var period: MacroPlanPeriod?
    @State private var missCount7d: Int = 0
    @State private var showEdit = false
    @State private var showHistory = false

    @AppStorage(AppPrefKey.userSex) private var userSex: String = MacroDefaultsPrefs.sex
    @AppStorage(AppPrefKey.userAgeYears) private var userAgeYears: Int = MacroDefaultsPrefs.ageYears
    @AppStorage(AppPrefKey.userHeightCm) private var userHeightCm: Double = MacroDefaultsPrefs.heightCm
    @AppStorage(AppPrefKey.userActivityFactor) private var userActivityFactor: Double = MacroDefaultsPrefs.activityFactor

    private var daysSinceCutStart: Int {
        let cal = Calendar.current
        return cal.dateComponents([.day], from: cal.startOfDay(for: cutStartDate), to: cal.startOfDay(for: Date())).day ?? 0
    }

    private var showsRollup: Bool { daysSinceCutStart >= 7 }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(MacroCopy.cardTitle, systemImage: "fork.knife")
                    .font(.headline)
                Spacer()
            }

            if let p = period {
                kcalRow(p)
                macroGrid(p)
            } else {
                Text("No macro plan yet — start a cut to set one.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if showsRollup, period != nil {
                Text(MacroCopy.cardSevenDayRollup(missCount: missCount7d))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                showEdit = true
            } label: {
                Label(MacroCopy.cardEdit, systemImage: "pencil")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            HStack {
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Text(MacroCopy.cardViewHistory)
                        .font(.footnote)
                }
            }
        }
        .padding()
        .glass(in: RoundedRectangle(cornerRadius: 12))
        .onAppear { reload() }
        .sheet(isPresented: $showEdit) {
            let d = defaultsTuple()
            let initial: (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int) = period.map {
                ($0.kcal, $0.proteinG ?? 0, $0.fatG ?? 0, $0.carbsG ?? 0)
            } ?? d
            EditMacrosSheet(
                cutStartDate: cutStartDate,
                initial: initial,
                defaults: d
            ) { kcal, pr, f, c in
                services.macroPlanStore.replaceCurrentPeriod(
                    cutStartDate: cutStartDate,
                    kcal: kcal,
                    proteinG: pr,
                    fatG: f,
                    carbsG: c
                )
                services.cutCoach.refresh(trigger: .macroPlanChanged)
                reload()
            }
        }
        .sheet(isPresented: $showHistory) {
            MacroHistorySheet(cutStartDate: cutStartDate)
                .environmentObject(services)
        }
    }

    @ViewBuilder
    private func kcalRow(_ p: MacroPlanPeriod) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(p.kcal.formatted(.number.grouping(.automatic)))
                .font(.system(size: 36, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text("kcal")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
    }

    @ViewBuilder
    private func macroGrid(_ p: MacroPlanPeriod) -> some View {
        HStack(spacing: 24) {
            macroCell(letter: "P", grams: p.proteinG)
            macroCell(letter: "F", grams: p.fatG)
            macroCell(letter: "C", grams: p.carbsG)
            Spacer()
        }
    }

    @ViewBuilder
    private func macroCell(letter: String, grams: Int?) -> some View {
        let fullName: String = {
            switch letter {
            case "P": return "Protein"
            case "F": return "Fat"
            case "C": return "Carbs"
            default: return letter
            }
        }()
        HStack(spacing: 4) {
            Text(letter)
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
            Text(grams.map { "\($0)" } ?? "—")
                .font(.body.monospacedDigit().weight(.medium))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(grams.map { "\(fullName) \($0) grams" } ?? "\(fullName) not set")
    }

    // MARK: - Helpers

    private func reload() {
        period = services.macroPlanStore.currentPeriod(forCutStartDate: cutStartDate)
        missCount7d = services.macroDeviationStore
            .deviationsInLastDays(7, cutStartDate: cutStartDate)
            .count
    }

    private func defaultsTuple() -> (kcal: Int, proteinG: Int, fatG: Int, carbsG: Int) {
        // Recompute defaults from the active cut's parameters.
        guard let cut = ActiveCutStore.load() else {
            return (2000, 150, 60, 200)
        }
        let sex = Sex(rawValue: userSex) ?? .male
        let d = MacroDefaults.compute(
            startWeightKg: cut.startWeightKg,
            targetWeightKg: cut.targetWeightKg,
            startDate: cut.startDate,
            targetEndDate: cut.targetEndDate,
            sex: sex,
            ageYears: userAgeYears,
            heightCm: userHeightCm,
            activityFactor: userActivityFactor
        )
        return d
    }
}
