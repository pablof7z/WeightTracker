import SwiftUI

struct AboutSection: View {
    @EnvironmentObject private var appServices: AppServices

    var body: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text(versionString).foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(buildString).foregroundStyle(.secondary)
            }
            HStack {
                Text("Readings")
                Spacer()
                Text("\(stats.count)").foregroundStyle(.secondary)
            }
            if let first = stats.earliest, let last = stats.latest {
                HStack {
                    Text("Date range")
                    Spacer()
                    Text("\(first.formatted(date: .abbreviated, time: .omitted)) – \(last.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.secondary)
                }
            }
        }

        Section {
            // TODO: replace with real URL
            Link(destination: URL(string: "https://example.com/privacy")!) {
                Label("Privacy Policy", systemImage: "lock.shield.fill")
            }

            Link(destination: URL(string: "mailto:pfer@me.com?subject=WeightTracker%20Support")!) {
                Label("Contact Support", systemImage: "envelope.fill")
            }

            // TODO: replace with real URL
            Link(destination: URL(string: "https://apps.apple.com/app/idXXXXXXXX")!) {
                Label("Rate WeightTracker", systemImage: "star.fill")
            }
        }
    }

    private var versionString: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "—"
    }

    private var buildString: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "—"
    }

    private var stats: (count: Int, earliest: Date?, latest: Date?) {
        let readings = appServices.repository.allReadings()
        let dates = readings.map { $0.date }.sorted()
        return (readings.count, dates.first, dates.last)
    }
}
