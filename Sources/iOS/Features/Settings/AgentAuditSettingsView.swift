import SwiftUI

// MARK: - List

struct AgentAuditListView: View {
    @EnvironmentObject private var services: AppServices
    @State private var runs: [CoachRun] = []

    var body: some View {
        Group {
            if runs.isEmpty {
                ContentUnavailableView(
                    "No Runs",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Agent runs will appear here.")
                )
            } else {
                List {
                    ForEach(runs, id: \.id) { run in
                        NavigationLink {
                            AgentAuditRunDetailView(run: run)
                        } label: {
                            AuditRunRow(run: run)
                        }
                    }
                }
            }
        }
        .navigationTitle("Audit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    private func reload() {
        runs = services.coachAuditStore.recentRuns(limit: 200)
    }
}

private struct AuditRunRow: View {
    let run: CoachRun

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(run.trigger.auditDisplayName)
                    .font(.subheadline.weight(.medium))
                Spacer()
                AuditStatusBadge(status: run.status)
            }
            Text(run.startedAt, style: .date) + Text("  ") + Text(run.startedAt, style: .time)
            if let model = run.modelID {
                Text(model)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct AgentAuditRunDetailView: View {
    let run: CoachRun
    @EnvironmentObject private var services: AppServices
    @State private var toolCalls: [CoachToolCall] = []
    @State private var notes: [CoachNote] = []

    var body: some View {
        List {
            Section("Run") {
                LabeledContent("Trigger", value: run.trigger.auditDisplayName)
                LabeledContent("Status", value: run.status.auditDisplayName)
                LabeledContent("Started", value: run.startedAt.formatted(.dateTime.month().day().hour().minute().second()))
                if let completed = run.completedAt {
                    LabeledContent("Duration", value: durationString(run.startedAt, completed))
                }
                if let model = run.modelID {
                    LabeledContent("Model", value: model)
                }
                if let error = run.errorMessage {
                    LabeledContent("Error") {
                        Text(error).foregroundStyle(.red)
                    }
                }
            }

            if let input = run.userInputText {
                Section("Input") {
                    Text(input)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }

            let steps = buildSteps()
            if !steps.isEmpty {
                Section("Steps (\(steps.count))") {
                    ForEach(steps) { step in
                        AuditStepRow(step: step)
                    }
                }
            }

            if let output = extractContent(from: run.finalResponseJSON) {
                Section("Output") {
                    Text(output)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
            }
        }
        .navigationTitle(run.trigger.auditDisplayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { reload() }
    }

    private func reload() {
        toolCalls = services.coachAuditStore.toolCalls(runID: run.id)
        notes = services.coachAuditStore.notes(runID: run.id)
    }

    private func buildSteps() -> [AuditStep] {
        var steps: [AuditStep] = []
        steps += toolCalls.map { AuditStep.toolCall($0) }
        steps += notes.map { AuditStep.note($0) }
        return steps.sorted { $0.timestamp < $1.timestamp }
    }

    private func extractContent(from data: Data?) -> String? {
        guard let data,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return content
    }

    private func durationString(_ start: Date, _ end: Date) -> String {
        let s = Int(end.timeIntervalSince(start))
        return s < 60 ? "\(s)s" : "\(s / 60)m \(s % 60)s"
    }
}

// MARK: - Steps

enum AuditStep: Identifiable {
    case toolCall(CoachToolCall)
    case note(CoachNote)

    var id: UUID {
        switch self {
        case .toolCall(let c): c.id
        case .note(let n): n.id
        }
    }

    var timestamp: Date {
        switch self {
        case .toolCall(let c): c.requestedAt
        case .note(let n): n.createdAt
        }
    }
}

private struct AuditStepRow: View {
    let step: AuditStep

    var body: some View {
        switch step {
        case .toolCall(let call): ToolCallStepRow(call: call)
        case .note(let note): NoteStepRow(note: note)
        }
    }
}

private struct ToolCallStepRow: View {
    let call: CoachToolCall
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 8) {
                    AuditStepIcon(symbol: "function", color: toolColor(call.toolName))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(call.toolName)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("#\(call.sequence) · \(call.status.auditDisplayName)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                AuditJSONBlock(label: "Args", data: call.argumentsJSON)
                if let result = call.resultJSON {
                    AuditJSONBlock(label: "Result", data: result)
                }
                if let err = call.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                }
            }
        }
    }

    private func toolColor(_ name: String) -> Color {
        if name.hasPrefix("get") || name.hasPrefix("snapshot") { return .blue }
        if name.hasPrefix("replace") || name.hasPrefix("log") { return .orange }
        if name.hasPrefix("append") || name.hasPrefix("record") { return .green }
        if name.hasPrefix("mark") { return .purple }
        if name.hasPrefix("calculate") { return .teal }
        return .gray
    }
}

private struct NoteStepRow: View {
    let note: CoachNote

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            AuditStepIcon(symbol: note.kind.auditSystemImage, color: note.kind.auditColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(note.kind.auditDisplayName)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(note.text)
                    .font(.subheadline)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct AuditStepIcon: View {
    var symbol: String
    var color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.caption2)
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(color, in: RoundedRectangle(cornerRadius: 5))
    }
}

private struct AuditJSONBlock: View {
    var label: String
    var data: Data

    private var prettyText: String {
        guard let obj = try? JSONSerialization.jsonObject(with: data),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: .prettyPrinted),
              let str = String(data: pretty, encoding: .utf8)
        else { return String(data: data, encoding: .utf8) ?? "" }
        return str
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
            Text(prettyText)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - Status badge

private struct AuditStatusBadge: View {
    let status: CoachRunStatus

    var body: some View {
        Text(status.auditDisplayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(status.auditColor.opacity(0.15), in: Capsule())
            .foregroundStyle(status.auditColor)
    }
}

// MARK: - Display name extensions

extension CoachRunTrigger {
    var auditDisplayName: String {
        switch self {
        case .appBootstrap: "App Bootstrap"
        case .backgroundRefresh: "Background Refresh"
        case .healthWeight: "Health: Weight"
        case .healthSleep: "Health: Sleep"
        case .healthActivity: "Health: Activity"
        case .weightSaved: "Weight Saved"
        case .activeCutChanged: "Cut Changed"
        case .macroPlanChanged: "Macro Plan Changed"
        case .macroDeviationChanged: "Macro Deviation"
        case .macroUntrackedChanged: "Untracked Range"
        case .voiceCheckIn: "Voice Check-in"
        case .conversation: "In-App Chat"
        case .nostrConversation: "Conversation"
        case .toolMutationFollowup: "Tool Followup"
        case .manual: "Manual"
        }
    }
}

extension CoachRunStatus {
    var auditDisplayName: String {
        switch self {
        case .started: "Running"
        case .succeeded: "Done"
        case .failed: "Failed"
        case .skipped: "Skipped"
        case .cancelled: "Cancelled"
        }
    }

    var auditColor: Color {
        switch self {
        case .started: .orange
        case .succeeded: .green
        case .failed: .red
        case .skipped, .cancelled: .gray
        }
    }
}

extension CoachToolCallStatus {
    var auditDisplayName: String {
        switch self {
        case .requested: "Pending"
        case .succeeded: "OK"
        case .failed: "Failed"
        case .rejected: "Rejected"
        }
    }
}

extension CoachNoteKind {
    var auditDisplayName: String {
        switch self {
        case .checkIn: "Check-in"
        case .observation: "Observation"
        case .planReason: "Plan Reason"
        case .foodContext: "Food"
        case .trainingContext: "Training"
        case .sleepContext: "Sleep"
        case .moodContext: "Mood"
        case .digestionContext: "Digestion"
        case .internalAudit: "Internal"
        }
    }

    var auditSystemImage: String {
        switch self {
        case .checkIn: "person.fill"
        case .observation: "eye.fill"
        case .planReason: "doc.text.fill"
        case .foodContext: "fork.knife"
        case .trainingContext: "figure.run"
        case .sleepContext: "moon.fill"
        case .moodContext: "face.smiling.fill"
        case .digestionContext: "waveform.path.ecg"
        case .internalAudit: "terminal.fill"
        }
    }

    var auditColor: Color {
        switch self {
        case .checkIn: .blue
        case .observation: .indigo
        case .planReason: .purple
        case .foodContext: .orange
        case .trainingContext: .green
        case .sleepContext: .teal
        case .moodContext: .yellow
        case .digestionContext: .mint
        case .internalAudit: .gray
        }
    }
}
