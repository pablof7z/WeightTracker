import SwiftUI

private enum AgentSettingsDestination: Hashable {
    case identity
    case relay
    case profile
    case definition
    case memories
    case whitelist
    case conversations
}

struct AgentSettingsView: View {
    @EnvironmentObject private var services: AppServices

    @State private var enabled = CoachNostrAgentSettings.load().enabled
    @State private var statusText = "Idle"

    var body: some View {
        Form {
            Section {
                Toggle("Enabled", isOn: $enabled)
                    .onChange(of: enabled) { _, _ in saveEnabled() }
            } header: {
                Text("Nostr")
            } footer: {
                Text(statusText)
            }

            Section("Configuration") {
                NavigationLink(value: AgentSettingsDestination.identity) {
                    AgentSettingsRow(
                        title: "Identity",
                        subtitle: services.coachNostrAgent.publicKeyNpub.map(Self.shortValue) ?? "No local agent key",
                        systemImage: "key.fill",
                        tint: .orange
                    )
                }
                NavigationLink(value: AgentSettingsDestination.relay) {
                    AgentSettingsRow(
                        title: "Relay",
                        subtitle: CoachNostrAgentSettings.load().relayURL,
                        systemImage: "antenna.radiowaves.left.and.right",
                        tint: .blue
                    )
                }
                NavigationLink(value: AgentSettingsDestination.profile) {
                    AgentSettingsRow(
                        title: "Profile",
                        subtitle: CoachNostrAgentSettings.load().profileName,
                        systemImage: "person.crop.circle.fill",
                        tint: .green
                    )
                }
                NavigationLink(value: AgentSettingsDestination.definition) {
                    AgentSettingsRow(
                        title: "Definition",
                        subtitle: "Persona for Nostr chat replies",
                        systemImage: "text.quote",
                        tint: .purple
                    )
                }
                NavigationLink(value: AgentSettingsDestination.memories) {
                    AgentSettingsRow(
                        title: "Memories",
                        subtitle: "\(services.coachNostrAgent.state.memories.count) saved",
                        systemImage: "brain.head.profile",
                        tint: .pink
                    )
                }
            }

            Section("Access") {
                NavigationLink(value: AgentSettingsDestination.whitelist) {
                    AgentSettingsRow(
                        title: "Whitelist",
                        subtitle: "\(services.coachNostrAgent.state.allowedPubkeys.count) allowed, \(services.coachNostrAgent.state.blockedPubkeys.count) blocked",
                        systemImage: "checkmark.shield.fill",
                        tint: .teal,
                        badgeCount: services.coachNostrAgent.state.pendingApprovals.count
                    )
                }
                NavigationLink(value: AgentSettingsDestination.conversations) {
                    AgentSettingsRow(
                        title: "Conversations",
                        subtitle: "\(services.coachNostrAgent.state.conversations.count) local threads",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        tint: .indigo
                    )
                }
            }
        }
        .navigationTitle("Agent")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AgentSettingsDestination.self) { destination in
            switch destination {
            case .identity: AgentIdentitySettingsView()
            case .relay: AgentRelaySettingsView()
            case .profile: AgentProfileSettingsView()
            case .definition: AgentDefinitionSettingsView()
            case .memories: AgentMemoriesSettingsView()
            case .whitelist: AgentWhitelistSettingsView()
            case .conversations: AgentConversationsSettingsView()
            }
        }
        .onAppear {
            enabled = CoachNostrAgentSettings.load().enabled
            updateStatusText()
        }
        .onReceive(services.coachNostrAgent.$status) { _ in
            updateStatusText()
        }
    }

    private func saveEnabled() {
        var settings = CoachNostrAgentSettings.load()
        settings.enabled = enabled
        settings.save()
        services.coachNostrAgent.start(settings: settings)
        updateStatusText()
    }

    private func updateStatusText() {
        statusText = Self.statusText(for: services.coachNostrAgent.status)
    }

    static func statusText(for status: CoachNostrAgentService.Status) -> String {
        switch status {
        case .idle:
            return "Off"
        case .missingCredentials:
            return "Missing local agent key"
        case .starting:
            return "Connecting"
        case .running(let relayURL):
            return "Connected to \(relayURL)"
        case .backingOff(let error):
            return "Reconnecting: \(error)"
        case .error(let message):
            return message
        }
    }

    static func shortValue(_ value: String) -> String {
        guard value.count > 18 else { return value }
        return "\(value.prefix(10))...\(value.suffix(6))"
    }
}

private struct AgentSettingsRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var tint: Color
    var badgeCount: Int = 0

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(tint, in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if badgeCount > 0 {
                Text("\(badgeCount)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
        }
    }
}

private struct AgentIdentitySettingsView: View {
    @EnvironmentObject private var services: AppServices

    @State private var keyPair: NostrKeyPair?

    var body: some View {
        Form {
            Section {
                if let keyPair {
                    LabeledContent("Public key", value: keyPair.npub)
                        .font(.caption)
                        .textSelection(.enabled)
                    LabeledContent("Hex", value: keyPair.publicKeyHex)
                        .font(.caption)
                        .textSelection(.enabled)
                } else {
                    Text("No local agent key.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Identity")
            } footer: {
                Text("This read-only local identity signs the agent's Nostr profile and replies.")
            }
        }
        .navigationTitle("Identity")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            services.coachNostrAgent.ensureIdentity()
            reloadKey()
        }
    }

    private func reloadKey() {
        keyPair = try? NostrCredentialStore.loadKeyPair()
    }
}

private struct AgentRelaySettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var relayURL = CoachNostrAgentSettings.load().relayURL
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Relay", text: $relayURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onSubmit(save)

                Button("Save relay") {
                    save()
                }
            } footer: {
                Text("Use one ws:// or wss:// relay for the local agent.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Relay")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        let trimmed = relayURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let nextRelay = trimmed.isEmpty ? CoachNostrAgentSettings.defaultRelayURL : trimmed
        guard let url = URL(string: nextRelay), url.scheme == "ws" || url.scheme == "wss" else {
            message = "Enter a ws:// or wss:// relay URL."
            return
        }

        var settings = CoachNostrAgentSettings.load()
        settings.relayURL = nextRelay
        settings.save()
        relayURL = nextRelay
        services.coachNostrAgent.start(settings: settings)
        message = "Relay saved"
    }
}

private struct AgentProfileSettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var profileName = CoachNostrAgentSettings.load().profileName
    @State private var profileAbout = CoachNostrAgentSettings.load().profileAbout
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Display name", text: $profileName)
                    .textInputAutocapitalization(.words)

                TextField("About", text: $profileAbout, axis: .vertical)
                    .lineLimit(2...4)

                Button("Save profile") {
                    save()
                }
            } footer: {
                Text("Published as kind:0 metadata when the agent connects.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Profile")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        var settings = CoachNostrAgentSettings.load()
        settings.profileName = profileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CoachNostrAgentSettings.defaultProfileName
            : profileName.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.profileAbout = profileAbout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? CoachNostrAgentSettings.defaultProfileAbout
            : profileAbout.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.save()
        profileName = settings.profileName
        profileAbout = settings.profileAbout
        services.coachNostrAgent.start(settings: settings)
        message = "Profile saved"
    }
}

private struct AgentDefinitionSettingsView: View {
    @State private var systemPrompt = CoachNostrAgentSettings.load().systemPrompt
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextEditor(text: $systemPrompt)
                    .font(.body.monospaced())
                    .frame(minHeight: 240)

                Button("Save definition") {
                    save()
                }

                Button("Reset to default") {
                    systemPrompt = CoachNostrAgentSettings.defaultSystemPrompt
                    save()
                }
            } footer: {
                Text("Tool rules, audited context, memories, and date conventions are appended automatically.")
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Definition")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func save() {
        var settings = CoachNostrAgentSettings.load()
        settings.systemPrompt = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        settings.save()
        message = "Definition saved"
    }
}

private struct AgentMemoriesSettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var draft = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                TextField("Memory", text: $draft, axis: .vertical)
                    .lineLimit(2...5)
                Button("Add memory") {
                    addMemory()
                }
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            Section("Saved") {
                if services.coachNostrAgent.state.memories.isEmpty {
                    Text("No saved memories.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(services.coachNostrAgent.state.memories) { memory in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(memory.text)
                            Text(memory.createdAt, style: .date)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                services.coachNostrAgent.deleteMemory(memory.id)
                            }
                        }
                    }
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Memories")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addMemory() {
        do {
            _ = try services.coachNostrAgent.recordMemory(text: draft, source: "manual")
            draft = ""
            message = "Memory saved"
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct AgentWhitelistSettingsView: View {
    @EnvironmentObject private var services: AppServices
    @State private var manualPubkey = ""
    @State private var message: String?

    var body: some View {
        Form {
            Section("Pending") {
                if services.coachNostrAgent.state.pendingApprovals.isEmpty {
                    Text("No pending approvals.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(services.coachNostrAgent.state.pendingApprovals) { approval in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(CoachNostrAgentService.shortNpub(approval.senderPubkey))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                            Text(approval.content)
                                .lineLimit(4)
                            HStack {
                                Button("Allow") {
                                    Task { await services.coachNostrAgent.allow(pubkey: approval.senderPubkey) }
                                }
                                Button("Block", role: .destructive) {
                                    services.coachNostrAgent.block(pubkey: approval.senderPubkey)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                TextField("npub, nostr:npub, or hex", text: $manualPubkey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                HStack {
                    Button("Allow") {
                        allowManual()
                    }
                    Button("Block", role: .destructive) {
                        blockManual()
                    }
                }
            } header: {
                Text("Manual")
            }

            Section("Allowed") {
                if services.coachNostrAgent.state.allowedPubkeys.isEmpty {
                    Text("No allowed pubkeys.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sorted(services.coachNostrAgent.state.allowedPubkeys), id: \.self) { pubkey in
                        PubkeyPolicyRow(pubkey: pubkey, actionTitle: "Revoke") {
                            services.coachNostrAgent.revoke(pubkey: pubkey)
                        }
                    }
                }
            }

            Section("Blocked") {
                if services.coachNostrAgent.state.blockedPubkeys.isEmpty {
                    Text("No blocked pubkeys.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sorted(services.coachNostrAgent.state.blockedPubkeys), id: \.self) { pubkey in
                        PubkeyPolicyRow(pubkey: pubkey, actionTitle: "Unblock") {
                            services.coachNostrAgent.unblock(pubkey: pubkey)
                        }
                    }
                }
            }

            if let message {
                Section {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Whitelist")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func allowManual() {
        do {
            let normalized = try CoachNostrAgentService.normalizedPubkey(manualPubkey)
            manualPubkey = ""
            Task { await services.coachNostrAgent.allow(pubkey: normalized) }
            message = "Pubkey allowed"
        } catch {
            message = error.localizedDescription
        }
    }

    private func blockManual() {
        do {
            let normalized = try CoachNostrAgentService.normalizedPubkey(manualPubkey)
            manualPubkey = ""
            services.coachNostrAgent.block(pubkey: normalized)
            message = "Pubkey blocked"
        } catch {
            message = error.localizedDescription
        }
    }

    private func sorted(_ pubkeys: Set<String>) -> [String] {
        pubkeys.sorted()
    }
}

private struct PubkeyPolicyRow: View {
    var pubkey: String
    var actionTitle: String
    var action: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(CoachNostrAgentService.shortNpub(pubkey))
                Text(pubkey)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer()
            Button(actionTitle, action: action)
        }
    }
}

private struct AgentConversationsSettingsView: View {
    @EnvironmentObject private var services: AppServices

    var body: some View {
        List {
            if services.coachNostrAgent.state.conversations.isEmpty {
                Text("No local conversations.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(services.coachNostrAgent.state.conversations) { conversation in
                    NavigationLink {
                        AgentConversationDetailView(conversation: conversation)
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(CoachNostrAgentService.shortNpub(conversation.counterpartyPubkey))
                            Text(conversation.turns.last?.content ?? "")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(conversation.lastTouched, style: .relative)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Conversations")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct AgentConversationDetailView: View {
    var conversation: NostrConversation

    var body: some View {
        List {
            ForEach(conversation.turns) { turn in
                VStack(alignment: turn.direction == .outgoing ? .trailing : .leading, spacing: 4) {
                    Text(turn.direction == .outgoing ? "Agent" : CoachNostrAgentService.shortNpub(turn.pubkey))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(turn.content)
                        .frame(maxWidth: .infinity, alignment: turn.direction == .outgoing ? .trailing : .leading)
                    Text(Date(timeIntervalSince1970: TimeInterval(turn.createdAt)), style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .navigationTitle(CoachNostrAgentService.shortNpub(conversation.counterpartyPubkey))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NostrApprovalPresenter: View {
    @EnvironmentObject private var services: AppServices

    private var pendingApproval: NostrPendingApproval? {
        services.coachNostrAgent.state.pendingApprovals.first
    }

    var body: some View {
        Color.clear
            .sheet(isPresented: Binding(
                get: { pendingApproval != nil },
                set: { _ in }
            )) {
                if let approval = pendingApproval {
                    NavigationStack {
                        Form {
                            Section {
                                Text(CoachNostrAgentService.shortNpub(approval.senderPubkey))
                                    .textSelection(.enabled)
                                Text(approval.content)
                            } footer: {
                                Text("Unknown senders must be allowed before their messages can run the local agent.")
                            }
                        }
                        .navigationTitle("Agent Request")
                        .navigationBarTitleDisplayMode(.inline)
                        .interactiveDismissDisabled()
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Block", role: .destructive) {
                                    services.coachNostrAgent.block(pubkey: approval.senderPubkey)
                                }
                            }
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Allow") {
                                    Task { await services.coachNostrAgent.allow(pubkey: approval.senderPubkey) }
                                }
                            }
                        }
                    }
                }
            }
    }
}
