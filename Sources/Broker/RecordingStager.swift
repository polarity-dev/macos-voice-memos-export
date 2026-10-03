import Foundation

struct RecordingStager {
    private let fileManager = FileManager.default

    func stage(_ recording: StoredRecording, in exchangeDirectory: URL) throws -> String {
        guard let source = recording.sourceURL else {
            throw VoiceMemosError.filesystem(
                "The recording is not available locally: \(recording.metadata.title)"
            )
        }
        let filename = "recording.\(source.pathExtension.lowercased())"
        let destination = exchangeDirectory.appendingPathComponent(filename)
        guard !fileManager.fileExists(atPath: destination.path) else {
            throw VoiceMemosError.filesystem("The broker staging file already exists.")
        }
        do {
            try fileManager.copyItem(at: source, to: destination)
        } catch {
            throw VoiceMemosError.filesystem("Unable to stage recording: \(error.localizedDescription)")
        }
        return filename
    }
}
