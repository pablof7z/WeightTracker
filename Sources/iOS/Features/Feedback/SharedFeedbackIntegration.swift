import Foundation
import ShakeFeedbackKit

extension ShakeFeedbackConfig {
    static let weightTracker = ShakeFeedbackConfig(
        appName: "WeightTracker",
        clientTag: "weighttracker-ios",
        projectATag: "31933:09d48a1a5dbe13404a729634f1d6ba722d40513468dd713c8ea38ca9b7b6f2c7:weighttracker"
    )
}

struct WeightTrackerShakeFeedbackSigner: ShakeFeedbackSigner, @unchecked Sendable {
    weak var feedback: FeedbackService?

    var publicKeyHex: String? {
        get async {
            await MainActor.run { feedback?.publicKeyHex }
        }
    }

    func signFeedbackEvent(_ draft: ShakeFeedbackEventDraft) async throws -> ShakeFeedbackEvent {
        guard let feedback else { throw ShakeFeedbackError.missingIdentity }
        let event = try await feedback.signSharedFeedbackEvent(
            kind: draft.kind,
            content: draft.content,
            tags: draft.tags
        )
        return ShakeFeedbackEvent(
            id: event.id,
            pubkey: event.pubkey,
            createdAt: event.created_at,
            kind: event.kind,
            tags: event.tags,
            content: event.content,
            sig: event.sig
        )
    }
}
