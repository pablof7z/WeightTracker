import SwiftUI

struct OnboardingFlow: View {
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false

    var body: some View {
        VStack(spacing: 24) {
            Text("Welcome to WeightTracker").font(.title.bold())
            Text("A weight tracker that knows about gaps. Your data stays on your device.")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Get started") { onboardingComplete = true }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
