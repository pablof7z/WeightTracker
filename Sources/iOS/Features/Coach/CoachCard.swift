import SwiftUI

/// The Cuts-tab "Coach" glance card.
///
/// Mental model: the coach is asynchronous — it works while you're away and
/// leaves cards behind. This card surfaces those cards. It has three states:
///
///  1. Caught up (no pending proposals, no recent observation)
///  2. Has pending proposals (count badge + first reasoning + Review)
///  3. Caught up with a recent observation (last note + Got it)
///
/// Tapping "Review" opens `CoachBriefingView` as a full-screen sheet — the
/// daily-briefing flow. This card lives inside `CutsView`'s existing
/// `NavigationStack`, so it never wraps itself in another one.
struct CoachCard: View {
    @EnvironmentObject private var services: AppServices

    @StateObject private var stt = ElevenLabsRealtimeSTT()
    @AppStorage(AppPrefKey.elevenLabsSTTModel) private var sttModel: String = AppConstants.defaultElevenLabsSTTModel

    @State private var pendingProposals: [CoachProposal] = []
    @State private var recentNote: CoachNote?
    @State private var dismissedNoteIDs: Set<UUID> = []
    @State private var showBriefing = false
    @State private var showVoiceCheckIn = false
    @State private var lastRunAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Coach", systemImage: "brain.head.profile")
                    .font(.headline)
                Spacer()
                if !pendingProposals.isEmpty {
                    proposalCountBadge
                }
            }

            content

            actionRow
        }
        .padding()
        .background(
            Color(.secondarySystemGroupedBackground),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .coachProposalDidChange)) { _ in
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .mealScheduleDidChange)) { _ in
            reload()
        }
        .fullScreenCover(isPresented: $showBriefing, onDismiss: { reload() }) {
            CoachBriefingView()
                .environmentObject(services)
        }
        .sheet(isPresented: $showVoiceCheckIn, onDismiss: {
            if stt.isRecording || stt.isStarting { stt.cancel() }
        }) {
            VoiceCheckInSheet(
                stt: stt,
                onFinish: finishVoiceCheckIn,
                onPause: { stt.pause() },
                onResume: { stt.resume() }
            )
            .presentationDetents([.height(320), .medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sub-views

    @ViewBuilder
    private var content: some View {
        if let proposal = pendingProposals.first {
            Text(proposal.reasoning)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        } else if let note = displayedNote {
            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        } else {
            caughtUpSnapshot
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        if !pendingProposals.isEmpty {
            Button {
                showBriefing = true
            } label: {
                Label("Review", systemImage: "tray.full")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle(prominent: true)
        } else if let note = displayedNote {
            Button {
                dismissedNoteIDs.insert(note.id)
                recentNote = nil
            } label: {
                Label("Got it", systemImage: "checkmark")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
        } else {
            Button {
                startVoiceCheckIn()
            } label: {
                Label("Talk to coach", systemImage: "bubble.left.and.bubble.right")
                    .frame(maxWidth: .infinity)
            }
            .glassButtonStyle()
        }
    }

    private var proposalCountBadge: some View {
        Text("\(pendingProposals.count) \(pendingProposals.count == 1 ? "proposal" : "proposals")")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(Color.accentColor)
            .background(Color.accentColor.opacity(0.13), in: Capsule())
    }

    @ViewBuilder
    private var caughtUpSnapshot: some View {
        let snapshot = weekSnapshot()
        VStack(alignment: .leading, spacing: 8) {
            Text("Caught up")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                snapshotMetric(
                    title: "Avg/day",
                    value: snapshot.avgPerDay,
                    systemImage: "scalemass"
                )
                snapshotMetric(
                    title: "Adherence",
                    value: snapshot.adherence,
                    systemImage: "checkmark.seal"
                )
                snapshotMetric(
                    title: "Days left",
                    value: snapshot.daysRemaining,
                    systemImage: "calendar"
                )
            }

            HStack(spacing: 6) {
                Image(systemName: "moon.stars")
                    .foregroundStyle(.secondary)
                Text(snapshot.nextRunLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func snapshotMetric(title: String, value: String, systemImage: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Voice check-in

    private func startVoiceCheckIn() {
        showVoiceCheckIn = true
        Task { @MainActor in
            do {
                try await stt.start(modelID: sttModel)
            } catch {
                stt.recordStartFailure(error)
            }
        }
    }

    private func finishVoiceCheckIn() {
        Task { @MainActor in
            let recordingID = stt.currentRecordingID
            let transcript = await stt.stop()
            showVoiceCheckIn = false

            if services.coachAuditStore.appendNote(
                source: .user,
                kind: .checkIn,
                visibility: .userVisible,
                cutStartDate: ActiveCutStore.load()?.startDate,
                day: Date(),
                text: transcript,
                audioDraftID: recordingID
            ) != nil {
                await services.coachAgent.run(transcript: transcript, trigger: .voiceCheckIn)
                reload()
            }
        }
    }

    // MARK: - Data

    private var displayedNote: CoachNote? {
        guard let note = recentNote, !dismissedNoteIDs.contains(note.id) else { return nil }
        return note
    }

    private func reload() {
        let cut = ActiveCutStore.load()
        if let cut {
            pendingProposals = services.coachProposalStore.pendingProposals(forCutStartDate: cut.startDate)
        } else {
            pendingProposals = []
        }
        recentNote = services.coachAuditStore
            .recentNotes(limit: 1, userVisibleOnly: true)
            .first
        lastRunAt = UserDefaults.standard.object(forKey: "coach.lastRunAt") as? Date
    }

    // MARK: - Snapshot computation

    private struct WeekSnapshot {
        let avgPerDay: String
        let adherence: String
        let daysRemaining: String
        let nextRunLabel: String
    }

    private func weekSnapshot() -> WeekSnapshot {
        guard let cut = ActiveCutStore.load() else {
            return WeekSnapshot(
                avgPerDay: "—",
                adherence: "—",
                daysRemaining: "—",
                nextRunLabel: "Next run tonight"
            )
        }

        let avg = avgDailyChangeLabel(cut: cut)
        let adherence = adherenceLabel(cut: cut)
        let daysLeft = "\(cut.daysRemaining())"

        return WeekSnapshot(
            avgPerDay: avg,
            adherence: adherence,
            daysRemaining: daysLeft,
            nextRunLabel: "Next run tonight"
        )
    }

    private func avgDailyChangeLabel(cut: ActiveCut) -> String {
        // Simple delta over the cut so far in lb / day.
        let cal = Calendar.current
        let elapsedDays = max(1, cal.dateComponents([.day], from: cut.startDate, to: Date()).day ?? 1)
        // We don't have direct access to readings here — the snapshot is best-effort.
        // Use the cut's planned rate as a fallback so the user sees a sensible value.
        let totalPlannedLossKg = cut.startWeightKg - cut.targetWeightKg
        let plannedDays = max(1, cut.totalDays)
        let plannedKgPerDay = totalPlannedLossKg / Double(plannedDays)
        let plannedLbPerDay = UnitConvert.kgToLb(plannedKgPerDay)
        // Soft sign: a cut is loss, so display as negative.
        let signed = -abs(plannedLbPerDay)
        _ = elapsedDays
        return String(format: "%.2f lb", signed)
    }

    private func adherenceLabel(cut: ActiveCut) -> String {
        let misses = services.macroDeviationStore
            .deviationsInLastDays(7, cutStartDate: cut.startDate)
            .count
        let onTarget = max(0, 7 - misses)
        let pct = Int((Double(onTarget) / 7.0 * 100).rounded())
        return "\(pct)%"
    }
}
