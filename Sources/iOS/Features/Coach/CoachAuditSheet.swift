import SwiftUI

struct CoachAuditSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var runs: [CoachRun] = []
    @State private var notes: [CoachNote] = []

    var body: some View {
        NavigationStack {
            List {
                Section {
                    CoachAuditSummaryStrip(
                        runCount: runs.count,
                        aiRunCount: runs.filter { $0.kind == .llmAgent }.count,
                        noteCount: notes.count
                    )
                }

                Section("Runs") {
                    if runs.isEmpty {
                        CoachEmptyAuditRow(
                            title: "No coach runs recorded",
                            systemImage: "list.bullet.clipboard"
                        )
                    } else {
                        ForEach(runs, id: \.id) { run in
                            NavigationLink {
                                CoachRunAuditDetailView(run: run)
                                    .environmentObject(services)
                            } label: {
                                CoachRunAuditRow(
                                    run: run,
                                    toolCallCount: services.coachAuditStore.toolCalls(runID: run.id).count,
                                    noteCount: notes.filter { $0.runID == run.id }.count
                                )
                            }
                        }
                    }
                }

                Section("Notes") {
                    if notes.isEmpty {
                        CoachEmptyAuditRow(
                            title: "No coach notes recorded",
                            systemImage: "note.text"
                        )
                    } else {
                        ForEach(notes.prefix(12), id: \.id) { note in
                            CoachNoteAuditRow(note: note, compact: true)
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
        runs = services.coachAuditStore.recentRuns(limit: 100)
        notes = services.coachAuditStore.recentNotes(limit: 100, userVisibleOnly: false)
    }
}

private struct CoachRunAuditDetailView: View {
    @EnvironmentObject private var services: AppServices

    let run: CoachRun

    @State private var toolCalls: [CoachToolCall] = []
    @State private var notes: [CoachNote] = []

    var body: some View {
        List {
            Section("Run") {
                LabeledContent("Type", value: run.kindLabel)
                LabeledContent("Trigger", value: run.triggerLabel)
                LabeledContent("Status") {
                    CoachStatusPill(text: run.statusLabel, status: run.status)
                }
                LabeledContent("Started", value: Self.dateFormatter.string(from: run.startedAt))
                LabeledContent("Completed", value: run.completedAt.map(Self.dateFormatter.string) ?? "-")
                LabeledContent("Duration", value: run.durationLabel)
                LabeledContent("Model", value: run.modelID ?? "-")
                LabeledContent("Prompt", value: run.promptVersion ?? "-")
                LabeledContent("Tools", value: run.toolSchemaVersion ?? "-")
                LabeledContent("Fingerprint", value: String(run.contextFingerprint.prefix(16)))
                    .font(.caption.monospaced())
            }

            if let error = run.errorMessage, !error.isEmpty {
                Section("Error") {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            if run.targetSummary != nil || !run.reasonBullets.isEmpty || run.finalAssistantText != nil {
                Section("Outcome") {
                    if let targets = run.targetSummary {
                        Label(targets, systemImage: "target")
                            .font(.subheadline.monospacedDigit())
                    }

                    ForEach(run.reasonBullets, id: \.self) { reason in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Color.secondary.opacity(0.65))
                                .frame(width: 4, height: 4)
                            Text(reason)
                        }
                        .font(.subheadline)
                    }

                    if let finalText = run.finalAssistantText {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Final LLM response")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(finalText)
                                .font(.subheadline)
                                .textSelection(.enabled)
                        }
                    }
                }
            }

            Section("Tool Calls") {
                if toolCalls.isEmpty {
                    Text(run.kind == .llmAgent ? "No tool calls recorded for this run." : "Deterministic runs do not use agent tools.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(toolCalls, id: \.id) { call in
                        NavigationLink {
                            CoachToolCallAuditDetailView(call: call)
                        } label: {
                            CoachToolCallAuditRow(call: call)
                        }
                    }
                }
            }

            if !notes.isEmpty {
                Section("Notes From This Run") {
                    ForEach(notes, id: \.id) { note in
                        CoachNoteAuditRow(note: note, compact: false)
                    }
                }
            }

            Section("Stored Payloads") {
                CoachJSONDisclosureRow(title: "Context snapshot", data: run.contextSnapshotJSON)
                CoachJSONDisclosureRow(title: "Recommendation", data: run.recommendationJSON)
                CoachJSONDisclosureRow(title: "Final response", data: run.finalResponseJSON)
            }
        }
        .navigationTitle(run.kind == .llmAgent ? "AI Coach Run" : "Coach Run")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear(perform: reload)
        .refreshable { reload() }
    }

    private func reload() {
        toolCalls = services.coachAuditStore.toolCalls(runID: run.id)
        notes = services.coachAuditStore
            .recentNotes(limit: 200, userVisibleOnly: false)
            .filter { $0.runID == run.id }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct CoachToolCallAuditDetailView: View {
    let call: CoachToolCall

    var body: some View {
        List {
            Section("Tool Call") {
                LabeledContent("Tool", value: call.toolName)
                    .font(.subheadline.monospaced())
                LabeledContent("Sequence", value: "#\(call.sequence)")
                LabeledContent("Status") {
                    CoachToolStatusPill(status: call.status)
                }
                LabeledContent("Requested", value: Self.dateFormatter.string(from: call.requestedAt))
                LabeledContent("Completed", value: call.completedAt.map(Self.dateFormatter.string) ?? "-")
                LabeledContent("Provider call", value: call.providerCallID ?? "-")
                LabeledContent("Idempotency", value: call.idempotencyKey)
                    .font(.caption.monospaced())
            }

            if let target = call.targetSummary {
                Section("Mutation") {
                    Text(target)
                        .font(.subheadline.monospaced())
                        .textSelection(.enabled)
                }
            }

            if let error = call.errorMessage, !error.isEmpty {
                Section("Error") {
                    Text(error)
                        .font(.subheadline)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                }
            }

            Section("Payloads") {
                CoachJSONDisclosureRow(title: "Arguments", data: call.argumentsJSON)
                CoachJSONDisclosureRow(title: "Result", data: call.resultJSON)
                CoachJSONDisclosureRow(title: "Before", data: call.beforeJSON)
                CoachJSONDisclosureRow(title: "After", data: call.afterJSON)
            }
        }
        .navigationTitle(call.toolName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

private struct CoachAuditSummaryStrip: View {
    let runCount: Int
    let aiRunCount: Int
    let noteCount: Int

    var body: some View {
        HStack(spacing: 10) {
            CoachAuditMetricTile(title: "Runs", value: "\(runCount)", systemImage: "clock.arrow.circlepath")
            CoachAuditMetricTile(title: "AI", value: "\(aiRunCount)", systemImage: "sparkles")
            CoachAuditMetricTile(title: "Notes", value: "\(noteCount)", systemImage: "note.text")
        }
        .padding(.vertical, 2)
    }
}

private struct CoachAuditMetricTile: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct CoachRunAuditRow: View {
    let run: CoachRun
    let toolCallCount: Int
    let noteCount: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(run.triggerLabel)
                        .font(.subheadline.weight(.semibold))
                    Text(run.kindLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                CoachStatusPill(text: run.statusLabel, status: run.status)
            }

            HStack(spacing: 10) {
                Label(Self.relativeDate(run.startedAt), systemImage: "calendar")
                Label("\(toolCallCount)", systemImage: "wrench.and.screwdriver")
                Label("\(noteCount)", systemImage: "note.text")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .labelStyle(.titleAndIcon)

            if let targets = run.targetSummary {
                Text(targets)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            } else if let finalText = run.finalAssistantText {
                Text(finalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let error = run.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }

            Text(run.contextFingerprint.prefix(12))
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CoachToolCallAuditRow: View {
    let call: CoachToolCall

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("#\(call.sequence) \(call.toolName)")
                        .font(.subheadline.weight(.semibold).monospaced())
                    if let target = call.targetSummary {
                        Text(target)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                CoachToolStatusPill(status: call.status)
            }

            if let error = call.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct CoachNoteAuditRow: View {
    let note: CoachNote
    let compact: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(note.kindLabel)
                    .font(.subheadline.weight(.semibold))
                CoachNoteVisibilityPill(visibility: note.visibility)
                Spacer()
                Text(Self.relativeDate(note.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Text(note.text)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(compact ? 3 : nil)
                .textSelection(.enabled)
        }
        .padding(.vertical, 4)
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter
    }()

    private static func relativeDate(_ date: Date) -> String {
        relativeFormatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct CoachJSONDisclosureRow: View {
    let title: String
    let data: Data?

    var body: some View {
        if let data {
            DisclosureGroup {
                ScrollView(.horizontal) {
                    Text(data.coachPrettyJSONString)
                        .font(.caption2.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                }
            } label: {
                HStack {
                    Text(title)
                    Spacer()
                    Text(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            LabeledContent(title, value: "-")
                .foregroundStyle(.secondary)
        }
    }
}

private struct CoachStatusPill: View {
    let text: String
    let status: CoachRunStatus

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var foreground: Color {
        switch status {
        case .failed: return .red
        case .succeeded: return .green
        case .started: return .orange
        case .skipped, .cancelled: return .secondary
        }
    }

    private var background: Color {
        foreground.opacity(0.13)
    }
}

private struct CoachToolStatusPill: View {
    let status: CoachToolCallStatus

    var body: some View {
        Text(statusLabel)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foreground)
            .background(background, in: Capsule())
    }

    private var statusLabel: String {
        switch status {
        case .requested: return "Requested"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .rejected: return "Rejected"
        }
    }

    private var foreground: Color {
        switch status {
        case .succeeded: return .green
        case .failed, .rejected: return .red
        case .requested: return .orange
        }
    }

    private var background: Color {
        foreground.opacity(0.13)
    }
}

private struct CoachNoteVisibilityPill: View {
    let visibility: CoachNoteVisibility

    var body: some View {
        Text(visibility == .auditOnly ? "Audit" : "Visible")
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .foregroundStyle(visibility == .auditOnly ? Color.secondary : Color.accentColor)
            .background(Color.secondary.opacity(0.10), in: Capsule())
    }
}

private struct CoachEmptyAuditRow: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 4)
    }
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
        case .conversation: return "In-app chat"
        case .nostrConversation: return "Nostr conversation"
        case .toolMutationFollowup: return "Tool mutation follow-up"
        case .manual: return "Manual refresh"
        }
    }

    var kindLabel: String {
        switch kind {
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

    var durationLabel: String {
        guard let completedAt else { return "-" }
        let seconds = max(0, completedAt.timeIntervalSince(startedAt))
        if seconds < 1 {
            return "<1s"
        }
        return String(format: "%.1fs", seconds)
    }

    var reasonBullets: [String] {
        guard
            let recommendationJSON,
            let object = try? JSONSerialization.jsonObject(with: recommendationJSON) as? [String: Any],
            let reasons = object["reasons"] as? [[String: Any]]
        else { return [] }
        return reasons.compactMap { $0["text"] as? String }
    }

    var finalAssistantText: String? {
        guard
            let finalResponseJSON,
            let object = try? JSONSerialization.jsonObject(with: finalResponseJSON) as? [String: Any],
            let text = object["content"] as? String
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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

private extension CoachToolCall {
    var targetSummary: String? {
        guard let targetEntityRaw else { return nil }
        var parts = [targetEntityRaw]
        if let targetID {
            parts.append(String(targetID.uuidString.prefix(8)))
        }
        return parts.joined(separator: " ")
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

private extension Data {
    var coachPrettyJSONString: String {
        if
            let object = try? JSONSerialization.jsonObject(with: self),
            let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: pretty, encoding: .utf8)
        {
            return string
        }

        return String(data: self, encoding: .utf8) ?? "\(count) bytes"
    }
}
