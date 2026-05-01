import SwiftUI

struct OnboardingFlow: View {
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false
    @State private var page: Int = 0

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingWhatItIs().tag(0)
                OnboardingImport().tag(1)
                OnboardingHealth().tag(2)
                OnboardingReminders().tag(3)
                OnboardingCut().tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .accessibilityLabel("Onboarding, page \(page + 1) of \(pageCount)")

            footer
                .padding(.horizontal)
                .padding(.bottom, 12)
        }
    }

    private var footer: some View {
        HStack {
            if page < pageCount - 1 {
                Button("Skip") { complete() }
                    .buttonStyle(.bordered)
                Spacer()
                Button("Next") {
                    withAnimation { page = min(pageCount - 1, page + 1) }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Spacer()
                Button("Done") { complete() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private func complete() {
        onboardingComplete = true
    }
}
