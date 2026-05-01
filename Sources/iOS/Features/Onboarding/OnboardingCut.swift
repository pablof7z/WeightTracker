import SwiftUI

struct OnboardingCut: View {
    @EnvironmentObject private var services: AppServices
    @AppStorage(AppPrefKey.weightUnit) private var weightUnitRaw: String = WeightUnit.lbs.rawValue
    @AppStorage(AppPrefKey.goalWeightKg) private var goalWeightKg: Double = 0

    @State private var targetLb: Double = AppConstants.defaultGoalLb
    @State private var weeks: Int = AppConstants.defaultCutDurationWeeks
    @State private var startWeightLb: Double = 175

    private var unit: WeightUnit { WeightUnit(rawValue: weightUnitRaw) ?? .lbs }

    private var targetBinding: Binding<Double> {
        Binding(
            get: { unit == .lbs ? targetLb : UnitConvert.lbToKg(targetLb) },
            set: { targetLb = unit == .lbs ? $0 : UnitConvert.kgToLb($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Image(systemName: "scissors")
                    .font(.system(size: 48))
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
                Text("Pick a cut target (optional)")
                    .font(.title.bold())
                Text("Set a target weight and a duration. We'll track your daily pace and project where you'll land — you can adjust either anytime.")
                    .foregroundStyle(.secondary)

                HStack {
                    Text("Target weight")
                    Spacer()
                    TextField("Target", value: targetBinding, format: .number.precision(.fractionLength(1)))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                        .frame(width: 90)
                    Text(unit.symbol).foregroundStyle(.secondary)
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
                    services.cutCoach.refresh(trigger: .activeCutChanged)
                    Task { await services.notifications.scheduleEvaluatedTriggers() }
                } label: {
                    Label("Start a cut", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Text("Skip — just tracking for now")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }
            .padding()
        }
        .onAppear {
            if let recent = services.repository.mostRecent() {
                let recentLb = UnitConvert.kgToLb(recent.weightKg)
                startWeightLb = recentLb
                targetLb = max(recentLb - 10, 100)
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
