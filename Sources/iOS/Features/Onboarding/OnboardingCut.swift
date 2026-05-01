import SwiftUI

struct OnboardingCut: View {
    @EnvironmentObject private var services: AppServices
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.goalWeightKg) private var goalWeightKg: Double = 0

    @State private var targetLb: Double = AppConstants.defaultGoalLb
    @State private var weeks: Int = AppConstants.defaultCutDurationWeeks
    @State private var startWeightLb: Double = 175

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "scissors")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                Text("Pick a cut target (optional)")
                    .font(.title.bold())
                Text("Your historical cuts have averaged ~0.95 lb/wk for ~10 weeks. We've set 158 lbs in 16 weeks as a starting suggestion — adjust freely.")
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Target weight")
                    Spacer()
                    TextField("Target", value: $targetLb, format: .number.precision(.fractionLength(1)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 90)
                    Text("lb").foregroundStyle(.secondary)
                }
                Stepper("Duration: \(weeks) weeks", value: $weeks, in: 4...52)

                Button {
                    let cut = ActiveCut(
                        startDate: Date(),
                        startWeightKg: latestStartKg(),
                        targetWeightKg: UnitConvert.lbToKg(targetLb),
                        targetEndDate: Calendar.current.date(byAdding: .day, value: weeks * 7, to: Date()) ?? Date()
                    )
                    ActiveCutStore.save(cut)
                    goalWeightKg = cut.targetWeightKg
                    Task { await services.notifications.scheduleEvaluatedTriggers() }
                } label: {
                    Label("Start a cut", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Skip — just tracking for now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding()
        }
        .onAppear {
            if let recent = services.repository.mostRecent() {
                startWeightLb = UnitConvert.kgToLb(recent.weightKg)
            }
        }
    }

    private func latestStartKg() -> Double {
        if let recent = services.repository.mostRecent() {
            return recent.weightKg
        }
        return UnitConvert.lbToKg(startWeightLb)
    }
}
