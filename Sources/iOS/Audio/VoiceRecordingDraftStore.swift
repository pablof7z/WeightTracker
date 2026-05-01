import Combine
import Foundation

enum VoiceRecordingDraftStatus: String, Codable, Hashable, Sendable {
    case recording
    case needsTranscription
    case transcribed
    case failed
}

struct VoiceRecordingDraft: Codable, Hashable, Identifiable, Sendable {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var fileName: String
    var sampleRate: Int
    var byteCount: Int
    var duration: TimeInterval
    var transcript: String?
    var failureMessage: String?
    var status: VoiceRecordingDraftStatus

    var isRestorable: Bool {
        status != .recording && byteCount > 0
    }
}

@MainActor
final class VoiceRecordingDraftStore: ObservableObject {
    static let shared = VoiceRecordingDraftStore()

    @Published private(set) var recordings: [VoiceRecordingDraft]

    private let directoryURL: URL
    private let metadataURL: URL

    private init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        directoryURL = baseURL.appendingPathComponent("VoiceRecordings", isDirectory: true)
        metadataURL = directoryURL.appendingPathComponent("recordings.json")
        try? FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        recordings = Self.load(from: metadataURL)
        recoverInterruptedRecordings()
        pruneMissingFiles()
    }

    var latestRestorable: VoiceRecordingDraft? {
        recordings
            .filter { $0.isRestorable && fileExists(for: $0) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .first
    }

    func recording(id: UUID) -> VoiceRecordingDraft? {
        recordings.first { $0.id == id && fileExists(for: $0) }
    }

    func url(for draft: VoiceRecordingDraft) -> URL {
        directoryURL.appendingPathComponent(draft.fileName)
    }

    func beginRecording(sampleRate: Int) throws -> ActiveVoiceRecording {
        let id = UUID()
        let fileName = "voice-\(id.uuidString).wav"
        let url = directoryURL.appendingPathComponent(fileName)
        _ = FileManager.default.createFile(
            atPath: url.path,
            contents: wavHeader(sampleRate: sampleRate, dataByteCount: 0)
        )
        let handle = try FileHandle(forWritingTo: url)
        handle.seekToEndOfFile()

        let now = Date()
        let draft = VoiceRecordingDraft(
            id: id,
            createdAt: now,
            updatedAt: now,
            fileName: fileName,
            sampleRate: sampleRate,
            byteCount: 0,
            duration: 0,
            transcript: nil,
            failureMessage: nil,
            status: .recording
        )
        recordings.insert(draft, at: 0)
        save()
        return ActiveVoiceRecording(id: id, url: url, handle: handle, sampleRate: sampleRate)
    }

    func append(_ data: Data, to active: ActiveVoiceRecording) {
        guard !data.isEmpty, !active.isClosed else { return }
        active.handle.seekToEndOfFile()
        active.handle.write(data)
        active.byteCount += data.count
        updateWAVHeader(for: active)
        active.handle.synchronizeFile()

        update(id: active.id) { draft in
            draft.byteCount = active.byteCount
            draft.duration = Self.duration(byteCount: active.byteCount, sampleRate: active.sampleRate)
            draft.updatedAt = Date()
        }
    }

    @discardableResult
    func finish(_ active: ActiveVoiceRecording, transcript: String?, failureMessage: String?) -> VoiceRecordingDraft? {
        guard !active.isClosed else { return recording(id: active.id) }
        updateWAVHeader(for: active)
        active.handle.synchronizeFile()
        active.handle.closeFile()
        active.isClosed = true

        let trimmedTranscript = transcript?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTranscript = trimmedTranscript?.isEmpty == false ? trimmedTranscript : nil
        let trimmedFailure = failureMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalFailure = trimmedFailure?.isEmpty == false ? trimmedFailure : nil

        update(id: active.id) { draft in
            draft.byteCount = active.byteCount
            draft.duration = Self.duration(byteCount: active.byteCount, sampleRate: active.sampleRate)
            draft.transcript = finalTranscript
            draft.failureMessage = finalFailure
            draft.status = finalTranscript == nil ? .failed : .transcribed
            draft.updatedAt = Date()
        }

        if active.byteCount == 0 {
            delete(id: active.id)
            return nil
        }

        return recording(id: active.id)
    }

    func markFailed(id: UUID, message: String) {
        update(id: id) { draft in
            draft.status = .failed
            draft.failureMessage = message
            draft.updatedAt = Date()
        }
    }

    func markTranscribed(id: UUID, transcript: String) {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        update(id: id) { draft in
            draft.status = trimmed.isEmpty ? .needsTranscription : .transcribed
            draft.transcript = trimmed.isEmpty ? nil : trimmed
            draft.failureMessage = trimmed.isEmpty ? "The saved recording did not produce a transcript." : nil
            draft.updatedAt = Date()
        }
    }

    func delete(id: UUID) {
        guard let draft = recordings.first(where: { $0.id == id }) else { return }
        try? FileManager.default.removeItem(at: url(for: draft))
        recordings.removeAll { $0.id == id }
        save()
    }

    private func update(id: UUID, mutate: (inout VoiceRecordingDraft) -> Void) {
        guard let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        mutate(&recordings[index])
        save()
    }

    private func recoverInterruptedRecordings() {
        var changed = false
        for index in recordings.indices where recordings[index].status == .recording {
            recordings[index].status = recordings[index].byteCount > 0 ? .failed : .needsTranscription
            recordings[index].failureMessage = "Recording was interrupted before transcription finished."
            recordings[index].updatedAt = Date()
            changed = true
        }
        if changed { save() }
    }

    private func pruneMissingFiles() {
        let originalCount = recordings.count
        recordings.removeAll { !fileExists(for: $0) }
        if recordings.count != originalCount {
            save()
        }
    }

    private func fileExists(for draft: VoiceRecordingDraft) -> Bool {
        FileManager.default.fileExists(atPath: url(for: draft).path)
    }

    private func updateWAVHeader(for active: ActiveVoiceRecording) {
        active.handle.seek(toFileOffset: 0)
        active.handle.write(wavHeader(sampleRate: active.sampleRate, dataByteCount: active.byteCount))
        active.handle.seekToEndOfFile()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(recordings) else { return }
        try? data.write(to: metadataURL, options: [.atomic])
    }

    private static func load(from url: URL) -> [VoiceRecordingDraft] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([VoiceRecordingDraft].self, from: data)) ?? []
    }

    private static func duration(byteCount: Int, sampleRate: Int) -> TimeInterval {
        guard sampleRate > 0 else { return 0 }
        return TimeInterval(byteCount) / TimeInterval(sampleRate * 2)
    }
}

@MainActor
final class ActiveVoiceRecording {
    let id: UUID
    let url: URL
    let handle: FileHandle
    let sampleRate: Int
    var byteCount = 0
    var isClosed = false

    init(id: UUID, url: URL, handle: FileHandle, sampleRate: Int) {
        self.id = id
        self.url = url
        self.handle = handle
        self.sampleRate = sampleRate
    }
}

private func wavHeader(sampleRate: Int, dataByteCount: Int) -> Data {
    var data = Data()
    let byteRate = sampleRate * 2

    data.appendASCII("RIFF")
    data.appendUInt32LE(UInt32(36 + dataByteCount))
    data.appendASCII("WAVE")
    data.appendASCII("fmt ")
    data.appendUInt32LE(16)
    data.appendUInt16LE(1)
    data.appendUInt16LE(1)
    data.appendUInt32LE(UInt32(sampleRate))
    data.appendUInt32LE(UInt32(byteRate))
    data.appendUInt16LE(2)
    data.appendUInt16LE(16)
    data.appendASCII("data")
    data.appendUInt32LE(UInt32(dataByteCount))
    return data
}

private extension Data {
    mutating func appendASCII(_ value: String) {
        append(value.data(using: .ascii)!)
    }

    mutating func appendUInt16LE(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
