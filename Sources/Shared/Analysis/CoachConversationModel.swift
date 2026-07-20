import Foundation

/// Pure, testable grouping of the flat `CoachNote` stream into a Telegram-style
/// list of conversations.
///
/// Design decisions (all non-destructive):
///  - `CoachNote.conversationID == nil` (legacy rows + automated coach output)
///    all collapse into ONE fixed default conversation ("Coach").
///  - Every distinct non-nil `conversationID` is its own conversation.
///  - A note is an *audio* message when it has an `audioDraftID`; if it also has
///    no usable text it is *audio-only* (failed transcription).
public enum CoachConversationGrouping {
    /// Fixed sentinel used for the default "Coach" conversation — the home for
    /// every legacy note and all automated coach output (weigh-in runs,
    /// proposals, nudges, pinned notes).
    public static let defaultConversationID = UUID(uuidString: "00000000-0000-0000-0000-00000C0AC400")!

    public static let defaultTitle = "Coach"

    /// Resolve the effective conversation a note belongs to (nil → default).
    public static func conversationID(for note: CoachNote) -> UUID {
        note.conversationID ?? defaultConversationID
    }

    /// Build the conversation list from a flat note stream, newest activity first.
    /// The default "Coach" conversation is always present (even with zero notes)
    /// so the mic always has somewhere to resume and automated output has a home.
    public static func conversations(from notes: [CoachNote]) -> [CoachConversationSummary] {
        var buckets: [UUID: [CoachNote]] = [:]
        for note in notes {
            buckets[conversationID(for: note), default: []].append(note)
        }
        // Guarantee the default conversation always exists.
        if buckets[defaultConversationID] == nil {
            buckets[defaultConversationID] = []
        }

        let summaries: [CoachConversationSummary] = buckets.map { id, groupNotes in
            let sorted = groupNotes.sorted { $0.createdAt < $1.createdAt }
            let isDefault = (id == defaultConversationID)
            return CoachConversationSummary(
                id: id,
                title: title(for: sorted, isDefault: isDefault),
                lastMessagePreview: preview(for: sorted.last),
                lastActivity: sorted.last?.createdAt,
                messageCount: sorted.count,
                isDefault: isDefault
            )
        }

        // Newest activity first; the default conversation sorts by its own
        // activity but wins ties (distantPast for empty) so it never floats to
        // the top ahead of real chats unless it is genuinely the most recent.
        return summaries.sorted { lhs, rhs in
            let l = lhs.lastActivity ?? .distantPast
            let r = rhs.lastActivity ?? .distantPast
            if l != r { return l > r }
            return lhs.isDefault && !rhs.isDefault
        }
    }

    /// The ordered messages (oldest first) for a single conversation.
    public static func messages(in conversationID: UUID, from notes: [CoachNote]) -> [CoachNote] {
        notes
            .filter { self.conversationID(for: $0) == conversationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    // MARK: - Helpers

    private static func title(for sortedNotes: [CoachNote], isDefault: Bool) -> String {
        if isDefault { return defaultTitle }
        // Derive a title from the first user text message; fall back gracefully.
        if let firstUserText = sortedNotes.first(where: {
            $0.source == .user && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.text ?? sortedNotes.first(where: {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        })?.text {
            return truncated(firstUserText, limit: 40)
        }
        return "New conversation"
    }

    private static func preview(for note: CoachNote?) -> String {
        guard let note else { return "" }
        if note.isAudioOnly { return "Voice message" }
        return truncated(note.text, limit: 80)
    }

    private static func truncated(_ raw: String, limit: Int) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}

/// A single row in the conversations list.
public struct CoachConversationSummary: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let title: String
    public let lastMessagePreview: String
    public let lastActivity: Date?
    public let messageCount: Int
    public let isDefault: Bool

    public init(
        id: UUID,
        title: String,
        lastMessagePreview: String,
        lastActivity: Date?,
        messageCount: Int,
        isDefault: Bool
    ) {
        self.id = id
        self.title = title
        self.lastMessagePreview = lastMessagePreview
        self.lastActivity = lastActivity
        self.messageCount = messageCount
        self.isDefault = isDefault
    }
}
