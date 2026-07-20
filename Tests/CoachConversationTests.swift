import XCTest
@testable import WeightTracker

@MainActor
final class CoachConversationTests: XCTestCase {

    private func note(
        source: CoachNoteSource = .user,
        text: String = "hello",
        conversationID: UUID? = nil,
        audioDraftID: UUID? = nil,
        createdAt: Date
    ) -> CoachNote {
        CoachNote(
            source: source,
            kind: .checkIn,
            cutStartDate: nil,
            day: createdAt,
            text: text,
            audioDraftID: audioDraftID,
            conversationID: conversationID,
            createdAt: createdAt
        )
    }

    private func t(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: 1_700_000_000 + offset)
    }

    // MARK: - Legacy nil → default conversation

    func testLegacyNilNotesCollapseIntoDefaultConversation() {
        let notes = [
            note(text: "old one", conversationID: nil, createdAt: t(0)),
            note(source: .agent, text: "old reply", conversationID: nil, createdAt: t(10)),
        ]
        let conversations = CoachConversationGrouping.conversations(from: notes)
        XCTAssertEqual(conversations.count, 1)
        let coach = try! XCTUnwrap(conversations.first)
        XCTAssertTrue(coach.isDefault)
        XCTAssertEqual(coach.id, CoachConversationGrouping.defaultConversationID)
        XCTAssertEqual(coach.title, "Coach")
        XCTAssertEqual(coach.messageCount, 2)
    }

    func testDefaultConversationAlwaysPresentEvenWithNoNotes() {
        let conversations = CoachConversationGrouping.conversations(from: [])
        XCTAssertEqual(conversations.count, 1)
        XCTAssertTrue(conversations.first?.isDefault ?? false)
        XCTAssertEqual(conversations.first?.messageCount, 0)
    }

    // MARK: - New conversation isolation

    func testNewConversationIsIsolatedFromDefault() {
        let convo = UUID()
        let notes = [
            note(text: "legacy", conversationID: nil, createdAt: t(0)),
            note(text: "brand new topic", conversationID: convo, createdAt: t(100)),
            note(source: .agent, text: "reply in new", conversationID: convo, createdAt: t(110)),
        ]
        let conversations = CoachConversationGrouping.conversations(from: notes)
        XCTAssertEqual(conversations.count, 2)

        // Newest activity first → the new conversation leads.
        XCTAssertEqual(conversations.first?.id, convo)
        XCTAssertFalse(conversations.first?.isDefault ?? true)
        XCTAssertEqual(conversations.first?.messageCount, 2)
        XCTAssertEqual(conversations.first?.title, "brand new topic")

        let messages = CoachConversationGrouping.messages(in: convo, from: notes)
        XCTAssertEqual(messages.count, 2)
        XCTAssertTrue(messages.allSatisfy { $0.conversationID == convo })

        let defaultMessages = CoachConversationGrouping.messages(
            in: CoachConversationGrouping.defaultConversationID, from: notes)
        XCTAssertEqual(defaultMessages.count, 1)
        XCTAssertEqual(defaultMessages.first?.text, "legacy")
    }

    // MARK: - Audio + text coexist in one conversation

    func testAudioAndTextCoexistInOneConversation() {
        let convo = UUID()
        let notes = [
            note(text: "typed message", conversationID: convo, createdAt: t(0)),
            note(text: "spoken with transcript", conversationID: convo,
                 audioDraftID: UUID(), createdAt: t(10)),
        ]
        let messages = CoachConversationGrouping.messages(in: convo, from: notes)
        XCTAssertEqual(messages.count, 2)
        XCTAssertFalse(messages[0].isAudioOnly)      // pure text
        XCTAssertNil(messages[0].audioDraftID)
        XCTAssertNotNil(messages[1].audioDraftID)    // audio bubble w/ transcript
        XCTAssertFalse(messages[1].isAudioOnly)      // has transcript text
    }

    // MARK: - Failed transcription = audio-only message

    func testFailedTranscriptionIsAudioOnly() {
        let convo = UUID()
        let notes = [
            note(text: "", conversationID: convo, audioDraftID: UUID(), createdAt: t(0)),
        ]
        let conversations = CoachConversationGrouping.conversations(from: notes)
        // Default + the audio-only conversation.
        let target = try! XCTUnwrap(conversations.first { $0.id == convo })
        XCTAssertEqual(target.messageCount, 1)
        XCTAssertEqual(target.lastMessagePreview, "Voice message")

        let messages = CoachConversationGrouping.messages(in: convo, from: notes)
        XCTAssertTrue(messages[0].isAudioOnly)
        XCTAssertNotNil(messages[0].audioDraftID)
    }
}
