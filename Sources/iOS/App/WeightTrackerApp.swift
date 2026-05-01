import SwiftUI
import SwiftData

@main
struct WeightTrackerApp: App {
    @AppStorage(AppPrefKey.onboardingComplete) private var onboardingComplete: Bool = false
    @AppStorage(AppPrefKey.theme) private var theme: String = ThemePreference.system.rawValue
    @StateObject private var appServices = AppServices.shared

    init() {
        BackgroundTaskRegistration.register(
            repository: AppServices.shared.repository,
            notifications: AppServices.shared.notifications
        )
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appServices)
                .preferredColorScheme(colorScheme)
                .modelContainer(appServices.modelContainer)
                .task { await appServices.bootstrap() }
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
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("Today", systemImage: "scalemass") }
            ChartView()
                .tabItem { Label("Chart", systemImage: "chart.xyaxis.line") }
            TrendsView()
                .tabItem { Label("Trends", systemImage: "chart.bar.xaxis") }
            CutsView()
                .tabItem { Label("Cuts", systemImage: "scissors") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
