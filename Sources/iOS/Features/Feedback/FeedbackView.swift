import SwiftUI
import UIKit

private enum FeedbackScope: String, CaseIterable, Identifiable {
    case mine = "Mine"
    case everyone = "Everyone"

    var id: String { rawValue }
}

struct FeedbackView: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var scope: FeedbackScope = .mine
    @State private var composePresented = false
    @State private var identityPresented = false

    private var visibleThreads: [FeedbackThread] {
        services.feedback.threads
    }

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Feedback")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                    ToolbarItem(placement: .principal) {
                        Button {
                            identityPresented = true
                        } label: {
                            Label(identityLabel, systemImage: identityIcon)
                                .labelStyle(.iconOnly)
                                .symbolRenderingMode(services.feedback.bunkerConnected ? .multicolor : .monochrome)
                        }
                        .accessibilityLabel(identityLabel)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            if services.feedback.publicKeyHex == nil {
                                identityPresented = true
                            } else {
                                composePresented = true
                            }
                        } label: {
                            Label("New feedback", systemImage: "square.and.pencil")
                        }
                    }
                }
                .navigationDestination(for: String.self) { rootID in
                    FeedbackThreadDetailView(rootID: rootID)
                        .environmentObject(services)
                }
                .task(id: scope) {
                    await services.feedback.loadThreads(mineOnly: scope == .mine)
                }
                .refreshable {
                    await services.feedback.loadThreads(mineOnly: scope == .mine)
                }
                .sheet(isPresented: $composePresented) {
                    FeedbackComposeSheet()
                        .environmentObject(services)
                }
                .sheet(isPresented: $identityPresented) {
                    FeedbackIdentitySheet()
                        .environmentObject(services)
                }
        }
    }

    @ViewBuilder
    private var content: some View {
        if services.feedback.isLoading && visibleThreads.isEmpty {
            ProgressView()
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Picker("Show", selection: $scope) {
                        ForEach(FeedbackScope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))

                if visibleThreads.isEmpty {
                    Section {
                        ContentUnavailableView {
                            Label(emptyTitle, systemImage: "bubble.left.and.bubble.right")
                        } description: {
                            Text(emptyDescription)
                        }
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(visibleThreads) { thread in
                            NavigationLink(value: thread.id) {
                                FeedbackThreadRow(
                                    thread: thread,
                                    authorName: authorName(for: thread)
                                )
                            }
                        }
                    }
                }
            }
        }
    }

    private var identityLabel: String {
        switch services.feedback.identityState {
        case .remoteSigner:
            return "Remote signer connected"
        case .importedNsec:
            return "nsec identity"
        case .localGenerated:
            return "Local identity"
        case .loading:
            return "Loading identity"
        case .missing:
            return "Set up identity"
        case .error:
            return "Identity error"
        }
    }

    private var identityIcon: String {
        services.feedback.publicKeyHex == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.fill"
    }

    private var emptyTitle: String {
        scope == .mine ? "No feedback from you" : "No project feedback"
    }

    private var emptyDescription: String {
        scope == .mine ? "Start a thread and it will stay attached to this project." : "Published project feedback will appear here."
    }

    private func authorName(for thread: FeedbackThread) -> String? {
        guard scope == .everyone else { return nil }
        if thread.root.pubkey == services.feedback.publicKeyHex { return "You" }
        return services.feedback.profile(for: thread.root.pubkey).displayName
    }
}

private struct FeedbackThreadRow: View {
    let thread: FeedbackThread
    let authorName: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(thread.title)
                    .font(.body.weight(thread.metadata?.title == nil ? .regular : .semibold))
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(Date(timeIntervalSince1970: TimeInterval(thread.lastActivity)), style: .relative)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Text(thread.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 6) {
                if let status = thread.metadata?.statusLabel?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !status.isEmpty {
                    FeedbackStatusPill(text: status)
                }
                if let activity = thread.metadata?.currentActivity?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !activity.isEmpty {
                    Text(activity)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text("\(thread.messages.count) \(thread.messages.count == 1 ? "message" : "messages")")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if let authorName {
                    Text("by \(authorName)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 3)
    }
}

private struct FeedbackStatusPill: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Color.accentColor)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .glassToastCapsule(tint: Color.accentColor.opacity(0.14))
    }
}

private struct FeedbackComposeSheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                TextEditor(text: $draft)
                    .font(.body)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 12)
                    .padding(.top, 12)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                }
            }
            .navigationTitle("New Feedback")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending..." : "Send") { send() }
                        .disabled(sending || trimmedDraft.isEmpty)
                }
            }
        }
    }

    private var trimmedDraft: String {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func send() {
        sending = true
        errorMessage = nil
        Task {
            do {
                _ = try await services.feedback.sendRootFeedback(trimmedDraft)
                Haptics.success()
                dismiss()
            } catch {
                Haptics.warning()
                errorMessage = error.localizedDescription
            }
            sending = false
        }
    }
}

private struct FeedbackThreadDetailView: View {
    @EnvironmentObject private var services: AppServices

    let rootID: String

    @State private var thread: FeedbackThread?
    @State private var draft = ""
    @State private var sending = false
    @State private var errorMessage: String?

    private var messages: [NostrEvent] {
        thread?.messages ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            messageList
            Divider()
            FeedbackReplyComposer(
                draft: $draft,
                sending: sending,
                errorMessage: errorMessage,
                send: send
            )
        }
        .navigationTitle(thread?.title ?? "Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await reload()
        }
        .task(id: Set(messages.map(\.pubkey)).sorted().joined(separator: ",")) {
            await reloadProfiles()
        }
        .refreshable {
            await reload()
        }
    }

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    threadHeader

                    ForEach(Array(messages.enumerated()), id: \.element.id) { index, event in
                        let previous = index > 0 ? messages[index - 1] : nil
                        FeedbackMessageBubble(
                            event: event,
                            previous: previous,
                            ownPubkey: services.feedback.publicKeyHex,
                            profile: services.feedback.profile(for: event.pubkey)
                        )
                        .id(event.id)
                    }
                }
                .padding(.vertical, 10)
            }
            .onChange(of: messages.count) { _, _ in
                guard let lastID = messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
        }
    }

    @ViewBuilder
    private var threadHeader: some View {
        if let thread {
            let summary = thread.metadata?.summary?.trimmingCharacters(in: .whitespacesAndNewlines)
            let activity = thread.metadata?.currentActivity?.trimmingCharacters(in: .whitespacesAndNewlines)
            if summary?.isEmpty == false || activity?.isEmpty == false || thread.metadata?.statusLabel?.isEmpty == false {
                VStack(alignment: .leading, spacing: 6) {
                    if let status = thread.metadata?.statusLabel, !status.isEmpty {
                        FeedbackStatusPill(text: status)
                    }
                    if let summary, !summary.isEmpty {
                        Text(summary)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    if let activity, !activity.isEmpty {
                        Text(activity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }
        }
    }

    private func reload() async {
        thread = await services.feedback.loadThread(rootID: rootID)
    }

    private func reloadProfiles() async {
        _ = await services.feedback.loadThread(rootID: rootID)
    }

    private func send() {
        guard let thread else { return }
        sending = true
        errorMessage = nil
        Task {
            do {
                let updated = try await services.feedback.sendReply(content: draft, in: thread)
                self.thread = updated
                draft = ""
                Haptics.success()
            } catch {
                Haptics.warning()
                errorMessage = error.localizedDescription
            }
            sending = false
        }
    }
}

private struct FeedbackMessageBubble: View {
    let event: NostrEvent
    let previous: NostrEvent?
    let ownPubkey: String?
    let profile: FeedbackProfile

    private var isOwn: Bool {
        event.pubkey == ownPubkey
    }

    private var startsBurst: Bool {
        guard let previous else { return true }
        return previous.pubkey != event.pubkey || event.created_at - previous.created_at > 300
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isOwn {
                Spacer(minLength: 44)
            } else {
                avatarSlot
            }

            VStack(alignment: isOwn ? .trailing : .leading, spacing: 3) {
                if startsBurst {
                    Text(isOwn ? "You" : profile.displayName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .padding(.horizontal, 4)
                }
                Text(markdownContent)
                    .font(.body)
                    .foregroundStyle(isOwn ? .white : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        isOwn ? Color.accentColor : Color(.secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                Text(Self.timeFormatter.string(from: Date(timeIntervalSince1970: TimeInterval(event.created_at))))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .frame(maxWidth: 310, alignment: isOwn ? .trailing : .leading)

            if isOwn {
                avatarSlot
            } else {
                Spacer(minLength: 44)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, startsBurst ? 8 : 2)
    }

    @ViewBuilder
    private var avatarSlot: some View {
        if startsBurst {
            FeedbackAvatar(profile: profile)
        } else {
            Color.clear.frame(width: 28, height: 1)
        }
    }

    private var markdownContent: AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        var output = AttributedString("")
        let lines = event.content.split(separator: "\n", omittingEmptySubsequences: false)
        for (index, line) in lines.enumerated() {
            let string = String(line)
            let parsed = (try? AttributedString(markdown: string, options: options)) ?? AttributedString(string)
            output.append(parsed)
            if index < lines.count - 1 {
                output.append(AttributedString("\n"))
            }
        }
        return output
    }
}

private struct FeedbackAvatar: View {
    let profile: FeedbackProfile

    var body: some View {
        Group {
            if let url = profile.pictureURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        fallback
                    }
                }
            } else {
                fallback
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 1))
    }

    private var fallback: some View {
        ZStack {
            Color.accentColor.opacity(0.16)
            Text(profile.initials)
                .font(.caption.weight(.bold))
                .foregroundStyle(Color.accentColor)
        }
    }
}

private struct FeedbackReplyComposer: View {
    @Binding var draft: String
    let sending: Bool
    let errorMessage: String?
    let send: () -> Void

    private var canSend: Bool {
        !sending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 12)
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Reply...", text: $draft, axis: .vertical)
                    .lineLimit(1...5)
                    .textFieldStyle(.roundedBorder)

                Button(action: send) {
                    if sending {
                        ProgressView()
                            .frame(width: 18, height: 18)
                    } else {
                        Image(systemName: "paperplane.fill")
                            .font(.title3)
                    }
                }
                .frame(width: 38, height: 38)
                .glassButtonStyle(prominent: true)
                .glassCircle()
                .disabled(!canSend)
                .accessibilityLabel("Send reply")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
            .padding(.top, 8)
        }
        .background(Color(.systemBackground))
    }
}

private struct FeedbackIdentitySheet: View {
    @EnvironmentObject private var services: AppServices
    @Environment(\.dismiss) private var dismiss

    @State private var bunkerField = ""
    @State private var nsecField = ""
    @State private var nsecRevealed = false
    @State private var connecting = false
    @State private var detectedSigner: KnownSigner?
    @State private var flash: String?

    var body: some View {
        NavigationStack {
            Form {
                if let npub = services.feedback.publicKeyNpub {
                    Section {
                        LabeledContent("npub") {
                            Button {
                                UIPasteboard.general.string = npub
                                showFlash("Copied")
                            } label: {
                                Text(npub)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .buttonStyle(.plain)
                        }
                        LabeledContent("State", value: stateText)
                        if services.feedback.bunkerConnected {
                            LabeledContent("Signed via") {
                                Text("Remote signer")
                                    .foregroundStyle(.green)
                            }
                        }
                    } header: {
                        Text("Your Identity")
                    }
                }

                Section {
                    if let detectedSigner {
                        Button {
                            Task { await connectViaSigner(detectedSigner) }
                        } label: {
                            HStack {
                                Text("Connect via \(detectedSigner.name)")
                                Spacer()
                                if connecting || services.feedback.nostrConnectPending {
                                    ProgressView().controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.up.forward")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(connecting || services.feedback.nostrConnectPending)
                    }

                    TextField("bunker://...", text: $bunkerField, axis: .vertical)
                        .lineLimit(1...3)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Button("Connect") {
                            Task { await connectBunker() }
                        }
                        .glassButtonStyle(prominent: true)
                        .disabled(connecting || bunkerField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        if connecting || services.feedback.nostrConnectPending {
                            ProgressView().controlSize(.small)
                        }
                        if let flash {
                            Text(flash)
                                .font(.caption)
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                } header: {
                    Text("Remote Signer")
                } footer: {
                    Text("Use Amber, Primal, or a bunker URI. Your private key stays in the signer.")
                }

                Section {
                    HStack {
                        Group {
                            if nsecRevealed {
                                TextField("nsec1... or hex", text: $nsecField)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            } else {
                                SecureField("nsec1... or hex", text: $nsecField)
                            }
                        }
                        Button {
                            nsecRevealed.toggle()
                        } label: {
                            Image(systemName: nsecRevealed ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.borderless)
                    }

                    Button("Save nsec") {
                        Task { await saveNsec() }
                    }
                    .glassButtonStyle(prominent: true)
                    .disabled(nsecField.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                } header: {
                    Text("Local Key")
                } footer: {
                    Text("Stored in this device's Keychain.")
                }

                Section {
                    Button("Generate new local identity", role: .destructive) {
                        Task {
                            await services.feedback.resetGeneratedIdentity()
                            showFlash("Generated")
                        }
                    }

                    if services.feedback.bunkerConnected {
                        Button("Disconnect remote signer", role: .destructive) {
                            Task {
                                await services.feedback.disconnectRemoteSigner()
                                showFlash("Disconnected")
                            }
                        }
                    }
                }

                if let error = services.feedback.lastError {
                    Section {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Feedback Identity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                detectedSigner = KnownSigner.detect()
            }
        }
    }

    private var stateText: String {
        switch services.feedback.identityState {
        case .loading:
            return "Loading"
        case .localGenerated:
            return "Local generated key"
        case .importedNsec:
            return "nsec"
        case .remoteSigner:
            return "Remote signer"
        case .missing:
            return "Missing"
        case .error(let message):
            return message
        }
    }

    private func connectBunker() async {
        let trimmed = bunkerField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await services.feedback.connectBunker(uri: trimmed)
            bunkerField = ""
            Haptics.success()
            showFlash("Connected")
        } catch {
            Haptics.warning()
            showFlash("Failed: \(error.localizedDescription)")
        }
    }

    private func connectViaSigner(_ signer: KnownSigner) async {
        guard let relayURL = URL(string: "wss://relay.tenex.chat") else { return }
        connecting = true
        defer { connecting = false }
        do {
            let uri = try await services.feedback.beginNostrConnect(relayURL: relayURL)
            guard let url = URL(string: uri) else { return }
            await UIApplication.shared.open(url)
        } catch {
            Haptics.warning()
            showFlash("Failed: \(error.localizedDescription)")
        }
        _ = signer
    }

    private func saveNsec() async {
        let trimmed = nsecField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        await services.feedback.importNsec(trimmed)
        if services.feedback.lastError == nil {
            nsecField = ""
            Haptics.success()
            showFlash("Saved")
        } else {
            Haptics.warning()
            showFlash("Invalid key")
        }
    }

    private func showFlash(_ text: String) {
        flash = text
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            await MainActor.run {
                if flash == text {
                    flash = nil
                }
            }
        }
    }
}
