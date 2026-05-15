import XCTest
@testable import WeightTracker

@MainActor
final class WhatsNewServiceTests: XCTestCase {

    private let fixtureJSON = #"""
    {
      "schema_version": 1,
      "entries": [
        {
          "shipped_at": "2026-05-10T22:00:00Z",
          "lines": ["Newest line"]
        },
        {
          "shipped_at": "2026-05-09T12:00:00Z",
          "lines": ["Middle line A", "Middle line B"]
        },
        {
          "shipped_at": "2026-05-08T08:00:00Z",
          "lines": ["Oldest line"]
        }
      ]
    }
    """#

    private func fixtureEntries() throws -> [WhatsNewEntry] {
        try WhatsNewService.decode(Data(fixtureJSON.utf8))
    }

    private func date(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    // MARK: - Bundled file

    func testBundledChangelogParses() {
        let entries = WhatsNewService.loadEntries()
        XCTAssertFalse(entries.isEmpty, "whats-new.json must ship with at least one entry.")
        XCTAssertFalse(entries.contains { $0.lines.isEmpty }, "Every entry needs at least one line.")
        let timestamps = entries.map(\.shippedAt)
        XCTAssertEqual(Set(timestamps).count, timestamps.count, "Every entry needs a unique shipped_at timestamp.")
    }

    // MARK: - Decoding

    func testFixtureDecodes() throws {
        let entries = try fixtureEntries()
        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries[0].lines, ["Newest line"])
        XCTAssertEqual(entries[1].lines.count, 2)
    }

    // MARK: - unseenEntries

    func testUnseenEntriesEmptyWhenNoMarker() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: nil, entries: entries)
        XCTAssertTrue(unseen.isEmpty, "nil marker must return empty — seedIfNeeded is responsible for seeding.")
    }

    func testUnseenEntriesEmptyWhenMarkerIsNewest() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: date("2026-05-10T22:00:00Z"), entries: entries)
        XCTAssertTrue(unseen.isEmpty)
    }

    func testUnseenEntriesReturnsNewerSlice() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: date("2026-05-09T12:00:00Z"), entries: entries)
        XCTAssertEqual(unseen.map(\.lines), [["Newest line"]])
    }

    func testUnseenEntriesReturnsAllNewer() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: date("2026-05-08T08:00:00Z"), entries: entries)
        XCTAssertEqual(unseen.map(\.lines), [["Newest line"], ["Middle line A", "Middle line B"]])
    }

    func testUnseenEntriesEmptyWhenMarkerInFuture() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: date("2030-01-01T00:00:00Z"), entries: entries)
        XCTAssertTrue(unseen.isEmpty)
    }

    func testUnseenEntriesAreNewestFirst() throws {
        let entries = try fixtureEntries()
        let unseen = WhatsNewService.unseenEntries(lastSeenAt: date("2026-05-08T08:00:00Z"), entries: entries)
        let dates = unseen.map(\.shippedAt)
        XCTAssertEqual(dates, dates.sorted(by: >))
    }

    // MARK: - seedIfNeeded

    func testSeedIfNeededWritesMarkerToNewest() throws {
        let entries = try fixtureEntries()
        let key = WhatsNewService.lastSeenAtKey
        UserDefaults.standard.removeObject(forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        WhatsNewService.seedIfNeeded(entries: entries)

        let stored = UserDefaults.standard.string(forKey: key)
        XCTAssertNotNil(stored, "seedIfNeeded must write the marker.")
        let storedDate = WhatsNewService.iso8601.date(from: stored!)!
        XCTAssertEqual(storedDate, date("2026-05-10T22:00:00Z"))
    }

    func testSeedIfNeededIsIdempotent() throws {
        let entries = try fixtureEntries()
        let key = WhatsNewService.lastSeenAtKey
        let existing = "2026-01-01T00:00:00Z"
        UserDefaults.standard.set(existing, forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }

        WhatsNewService.seedIfNeeded(entries: entries)

        XCTAssertEqual(UserDefaults.standard.string(forKey: key), existing, "Must not overwrite an existing marker.")
    }
}
