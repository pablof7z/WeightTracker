import SwiftUI

struct OnboardingWhatItIs: View {
    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "scalemass")
                .font(.system(size: 72))
                .foregroundStyle(.tint)
            Text("Welcome to WeightTracker")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 12) {
                bullet("See real progress, even when you skip days.")
                bullet("Plan a cut and stay honest about your rate.")
                bullet("Your data stays on your device — synced privately via iCloud.")
            }
            .padding(.horizontal)
            Spacer()
        }
        .padding()
    }

    private func bullet(_ s: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .padding(.top, 2)
            Text(s).font(.body)
        }
    }
}
