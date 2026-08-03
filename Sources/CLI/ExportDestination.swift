import Foundation

struct ExportDestination {
    private let fileManager = FileManager.default

    func copy(stagedFile: URL, recording: Recording, to directory: URL) throws -> (URL, Bool) {
        defer { try? fileManager.removeItem(at: stagedFile) }
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = "\(safeFilename(recording.title)) - \(timestamp(recording.recordedAt))"
        let preferred = directory.appendingPathComponent(stem).appendingPathExtension("m4a")
        let destination = try availableDestination(
            preferred: preferred,
            stagedFile: stagedFile,
            recordingID: recording.id
        )
        if fileManager.fileExists(atPath: destination.path),
           fileManager.contentsEqual(atPath: stagedFile.path, andPath: destination.path) {
            return (destination, false)
        }
        do {
            try fileManager.copyItem(at: stagedFile, to: destination)
        } catch {
            throw VoiceMemosError.filesystem("Copy failed: \(error.localizedDescription)")
        }
        return (destination, true)
    }

    private func availableDestination(preferred: URL, stagedFile: URL, recordingID: String) throws -> URL {
        guard fileManager.fileExists(atPath: preferred.path) else { return preferred }
        if fileManager.contentsEqual(atPath: stagedFile.path, andPath: preferred.path) { return preferred }
        let directory = preferred.deletingLastPathComponent()
        let stem = preferred.deletingPathExtension().lastPathComponent
        let suffix = shortIdentifier(recordingID)
        let identified = directory.appendingPathComponent("\(stem) - \(suffix)").appendingPathExtension("m4a")
        guard fileManager.fileExists(atPath: identified.path) else { return identified }
        if fileManager.contentsEqual(atPath: stagedFile.path, andPath: identified.path) { return identified }
        for counter in 2...999 {
            let candidate = directory
                .appendingPathComponent("\(stem) - \(suffix)-\(counter)")
                .appendingPathExtension("m4a")
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
            if fileManager.contentsEqual(atPath: stagedFile.path, andPath: candidate.path) { return candidate }
        }
        throw VoiceMemosError.filesystem("Unable to create a unique destination filename.")
    }

    private func timestamp(_ date: Date?) -> String {
        guard let date else { return "unknown-date" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter.string(from: date)
    }

    private func safeFilename(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/:\\?%*|\"<>\0").union(.controlCharacters)
        let replaced = value.unicodeScalars.map { forbidden.contains($0) ? "_" : String($0) }.joined()
        let collapsed = replaced.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ."))
        let fallback = collapsed.isEmpty ? "Voice Memo" : collapsed
        var result = ""
        for character in fallback {
            let candidate = result + String(character)
            if candidate.utf8.count > 160 { break }
            result = candidate
        }
        return result.isEmpty ? "Voice Memo" : result
    }

    private func shortIdentifier(_ value: String) -> String {
        let sanitized = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return sanitized.isEmpty ? "unknown" : String(sanitized.suffix(8))
    }
}
