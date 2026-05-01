import SwiftUI

struct CoachAuditSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var runs: [CoachRun] = []
    @State private var notes: [CoachNote] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Notes") {
                    if notes.isEmpty {
                        Text("No coach notes yet.")
                            .font(.subheadline)
                            .foregroundStyle(Color.secondary)
                    } else {
                        ForEach(notes, id: \.id) { note in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(note.kindLabel)
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(Self.relativeDate(note.createdAt))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text(note.text)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }

                Section("Runs") {
                    if runs.isEmpty {
                        Text("No coach runs recorded yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(runs, id: \.id) { run in
                            CoachRunAuditRow(run: run)
                        }
                    }
                }
            }
            .navigationTitle("Coach Audit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear(perform: reload)
            .refreshable { reload() }
        }
    }

    private func reload() {
        runs = services.cutCoach.recentAuditRuns(limit: 80)
        notes = services.cutCoach.recentNotes(limit: 20, userVisibleOnly: true)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CoachRunAuditRow: View {
    let run: CoachRun

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.triggerLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(run.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(run.statusLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(run.status == .failed ? .red : .secondary)
                    Text(Self.dateFormatter.string(from: run.startedAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let targets = run.targetSummary {
                Text(targets)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ForEach(run.reasonBullets.prefix(4), id: \.self) { reason in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(Color.secondary.opacity(0.55))
                        .frame(width: 4, height: 4)
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.primary)
                }
            }

            if let error = run.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Text(run.contextFingerprint.prefix(12))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}

private extension CoachRun {
    var triggerLabel: String {
        switch trigger {
        case .appBootstrap: return "App bootstrap"
        case .backgroundRefresh: return "Background refresh"
        case .healthWeight: return "Health weight update"
        case .healthSleep: return "Health sleep update"
        case .healthActivity: return "Health activity update"
        case .weightSaved: return "Weight data changed"
        case .activeCutChanged: return "Cut changed"
        case .macroPlanChanged: return "Macro plan changed"
        case .macroDeviationChanged: return "Food adherence changed"
        case .macroUntrackedChanged: return "Untracked range changed"
        case .voiceCheckIn: return "Voice check-in"
        case .nostrConversation: return "Nostr conversation"
        case .toolMutationFollowup: return "Tool mutation follow-up"
        case .manual: return "Manual refresh"
        }
    }

    var kindLabel: String {
        switch kind {
        case .deterministicRefresh: return "Deterministic coach run"
        case .llmAgent: return "AI coach run"
        }
    }

    var statusLabel: String {
        switch status {
        case .started: return "Started"
        case .succeeded: return "Saved"
        case .failed: return "Failed"
        case .skipped: return "Skipped"
        case .cancelled: return "Cancelled"
        }
    }

    var reasonBullets: [String] {
        guard
            let recommendationJSON,
            let object = try? JSONSerialization.jsonObject(with: recommendationJSON) as? [String: Any],
            let reasons = object["reasons"] as? [[String: Any]]
        else { return [] }
        return reasons.compactMap { $0["text"] as? String }
    }

    var targetSummary: String? {
        guard
            let recommendationJSON,
            let object = try? JSONSerialization.jsonObject(with: recommendationJSON) as? [String: Any],
            let targets = object["dailyTargets"] as? [String: Any],
            let kcal = targets["kcal"] as? Int
        else { return nil }

        let protein = targets["proteinG"] as? Int
        let fat = targets["fatG"] as? Int
        let carbs = targets["carbsG"] as? Int
        var parts = ["\(kcal) kcal"]
        if let protein { parts.append("P \(protein)") }
        if let fat { parts.append("F \(fat)") }
        if let carbs { parts.append("C \(carbs)") }
        return parts.joined(separator: "  ")
    }
}

private extension CoachNote {
    var kindLabel: String {
        switch kind {
        case .checkIn: return "Check-in"
        case .observation: return "Observation"
        case .planReason: return "Plan reason"
        case .foodContext: return "Food context"
        case .trainingContext: return "Training"
        case .sleepContext: return "Sleep"
        case .moodContext: return "Mood"
        case .digestionContext: return "Digestion"
        case .internalAudit: return "Audit"
        }
    }
}
