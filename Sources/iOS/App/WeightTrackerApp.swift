import SwiftUI
import SwiftData

@main
struct WeightTrackerApp: App {
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
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false

    var body: some View {
        Group {
            if onboardingComplete {
                MainTabView()
            } else {
                OnboardingFlow()
            }
        }
    }
}

struct MainTabView: View {
    @State private var selection: Int = 0

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tag(0)
                .tabItem { Label("Today", systemImage: "scalemass") }
            ChartView()
                .tag(1)
                .tabItem { Label("Chart", systemImage: "chart.xyaxis.line") }
            TrendsView()
                .tag(2)
                .tabItem { Label("Trends", systemImage: "chart.bar.xaxis") }
            CutsView()
                .tag(3)
                .tabItem { Label("Cuts", systemImage: "scissors") }
            SettingsView()
                .tag(4)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openCutsTab)) { _ in
            selection = 3
        }
    }
}
