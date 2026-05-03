import SwiftUI
import SwiftData

/// Root view for the Coach tab. Hosts the Daily Briefing stack — the coach's
/// async output surface — and shows a badge count of pending proposals on the
/// tab icon.
struct CoachTabView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.modelContext) private var context

    @State private var pendingCount: Int = 0

    var body: some View {
        CoachBriefingView(isTab: true)
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in reload() }
    }

    private func reload() {
        guard let cut = ActiveCutStore.load() else {
            pendingCount = 0
            return
        }
        pendingCount = services.coachProposalStore.pendingProposals(forCutStartDate: cut.startDate).count
    }
}
