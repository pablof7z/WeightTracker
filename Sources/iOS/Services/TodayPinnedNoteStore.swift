import Foundation
import Combine

struct TodayPinnedNote: Codable, Equatable {
    var text: String
    var createdAt: Date
}

@MainActor
final class TodayPinnedNoteStore: ObservableObject {
    static let shared = TodayPinnedNoteStore()

    @Published private(set) var pinnedNote: TodayPinnedNote?

    private let key = "coach.todayPinnedNote"
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private init() {
        pinnedNote = load()
    }

    func pin(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let note = TodayPinnedNote(text: trimmed, createdAt: Date())
        pinnedNote = note
        persist(note)
    }

    func dismiss() {
        pinnedNote = nil
        UserDefaults.standard.removeObject(forKey: key)
    }

    private func load() -> TodayPinnedNote? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? decoder.decode(TodayPinnedNote.self, from: data)
    }

    private func persist(_ note: TodayPinnedNote) {
        guard let data = try? encoder.encode(note) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
