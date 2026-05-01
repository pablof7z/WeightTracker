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
                    ) {
                        appServices.cutCoach.refresh(trigger: .backgroundRefresh)
                    }
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
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false

    var body: some View {
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
        .background(NostrApprovalPresenter())
    }
}

struct MainTabView: View {
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(0)
                .tabItem { Label("Today", systemImage: "scalemass") }
            ProgressTabView()
                .tag(1)
                .tabItem { Label("Progress", systemImage: "chart.xyaxis.line") }
            CutsView()
                .tag(2)
                .tabItem { Label("Cuts", systemImage: "scissors") }
            SettingsView()
                .tag(3)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCutsTab)) { _ in
            selection = 2
        }
    }
}
