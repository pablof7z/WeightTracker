import SwiftUI
import SwiftData

@main
struct WeightTrackerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false
    @AppStorage(AppPrefKey.theme) private var theme: String = ThemePreference.system.rawValue
    @StateObject private var appServices = AppServices.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appServices)
                .preferredColorScheme(colorScheme)
                .modelContainer(appServices.modelContainer)
                .task {
                    BackgroundTaskRegistration.register(
                        repository: appServices.repository,
                        notifications: appServices.notifications
                    )
                    await appServices.bootstrap()
                }
        }
    }

    private var colorScheme: ColorScheme? {
        switch ThemePreference(rawValue: theme) ?? .system {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var services: AppServices
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false
    @State private var feedbackPresented = false
    @State private var lastShakeAt: Date = .distantPast

    var body: some View {
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .background(NostrApprovalPresenter())
        .onShake(perform: handleShake)
        .onOpenURL(perform: handleURL)
        .sheet(isPresented: $feedbackPresented) {
            FeedbackView()
                .environmentObject(services)
                .presentationDetents([.large])
        }
    }

    private func handleShake() {
        let now = Date()
        guard now.timeIntervalSince(lastShakeAt) >= 1 else { return }
        lastShakeAt = now
        Haptics.light()
        feedbackPresented = true
    }

    private func handleURL(_ url: URL) {
        guard url.scheme == "weighttracker", url.host == "nip46" else { return }
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        guard let bunkerURI = items.first(where: { $0.name == "bunker" })?.value else { return }
        Task {
            try? await services.feedback.connectBunker(uri: bunkerURI)
        }
    }
}

struct MainTabView: View {
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayPager()
                .tag(0)
                .tabItem { Label("Today", systemImage: "scalemass") }
            ProgressTabView()
                .tag(1)
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            CutsView()
                .tag(2)
                .tabItem { Label("Cuts", systemImage: "scissors") }
            CoachTabView()
                .tag(3)
                .tabItem { Label("Coach", systemImage: "brain.head.profile") }
            SettingsView()
                .tag(4)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCutsTab)) { _ in
            selection = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .openMealPlanEditor)) { _ in
            selection = 2
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCoachForMealSetup)) { _ in
            selection = 3
        }
    }
}
