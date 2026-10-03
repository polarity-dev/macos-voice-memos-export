import Foundation

private let version = "0.1.1"

private struct ParsedCommand {
    enum Action {
        case list
        case search(query: String, exact: Bool)
        case export(query: String, destination: String, exact: Bool, all: Bool)
        case inspect
    }

    let action: Action
    let json: Bool
}

private func normalized(_ value: String) -> String {
    value.precomposedStringWithCompatibilityMapping
        .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func matches(_ recordings: [Recording], query: String, exact: Bool) -> [Recording] {
    let needle = normalized(query)
    return recordings.filter {
        let title = normalized($0.title)
        return exact ? title == needle : title.contains(needle)
    }
}

private func loadRecordings(client: BrokerClient) throws -> [Recording] {
    try client.withResponse(["operation": "recordings"]) { result, _ in
        guard let rows = result as? [[String: Any]] else {
            throw VoiceMemosError.broker("The broker returned invalid recordings data.")
        }
        return try rows.map(Recording.from(json:))
    }
}

private func durationString(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded()))
    let hours = total / 3600
    let minutes = (total % 3600) / 60
    let remaining = total % 60
    return hours > 0
        ? String(format: "%d:%02d:%02d", hours, minutes, remaining)
        : String(format: "%d:%02d", minutes, remaining)
}

private func printRecordings(_ recordings: [Recording], json: Bool) throws {
    if json {
        try printJSON(recordings.map { $0.jsonObject() })
        return
    }
    guard !recordings.isEmpty else {
        print("No recordings found.")
        return
    }

    print("  #  Recorded             Duration  Local      Title")
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

    for (index, recording) in recordings.enumerated() {
        let date = recording.recordedAt.map(formatter.string(from:)) ?? "?"
        let local = recording.isAvailable ? "yes" : "no"
        print(
            "\(String(format: "%3d", index + 1))  "
                + "\(date.rightPadded(to: 19))  "
                + "\(durationString(recording.duration).leftPadded(to: 8))  "
                + "\(local.rightPadded(to: 9))  \(recording.title)"
        )
    }
}

private func printJSON(_ object: Any) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
    guard let output = String(data: data, encoding: .utf8) else {
        throw VoiceMemosError.filesystem("Unable to encode JSON output.")
    }
    print(output)
}

private func usage() -> String {
    """
    Usage:
      voice-memos list [--json]
      voice-memos search <query> [--exact] [--json]
      voice-memos export <query> --to <directory> [--exact] [--all] [--json]
      voice-memos inspect [--json]
      voice-memos --version

    Search is case- and diacritic-insensitive. Export refuses ambiguous matches
    unless --all is provided.
    """
}

private func parseCommand(_ arguments: [String]) throws -> ParsedCommand {
    if arguments == ["--version"] || arguments == ["-V"] {
        print("voice-memos \(version)")
        exit(0)
    }
    if arguments.isEmpty || arguments.contains("--help") || arguments.contains("-h") {
        print(usage())
        exit(0)
    }

    var args = arguments
    let command = args.removeFirst()
    let json = removeFlag("--json", from: &args)
    let exact = removeFlag("--exact", from: &args)
    let all = removeFlag("--all", from: &args)

    switch command {
    case "list":
        guard args.isEmpty, !exact, !all else { throw VoiceMemosError.invalidUsage(usage()) }
        return ParsedCommand(action: .list, json: json)
    case "search":
        guard args.count == 1, !all else { throw VoiceMemosError.invalidUsage(usage()) }
        return ParsedCommand(action: .search(query: args[0], exact: exact), json: json)
    case "export":
        guard let destinationIndex = args.firstIndex(of: "--to"),
              destinationIndex + 1 < args.count else {
            throw VoiceMemosError.invalidUsage("export requires --to <directory>\n\n\(usage())")
        }
        let destination = args[destinationIndex + 1]
        args.removeSubrange(destinationIndex...(destinationIndex + 1))
        guard args.count == 1 else { throw VoiceMemosError.invalidUsage(usage()) }
        return ParsedCommand(
            action: .export(query: args[0], destination: destination, exact: exact, all: all),
            json: json
        )
    case "inspect":
        guard args.isEmpty, !exact, !all else { throw VoiceMemosError.invalidUsage(usage()) }
        return ParsedCommand(action: .inspect, json: json)
    default:
        throw VoiceMemosError.invalidUsage("Unknown command: \(command)\n\n\(usage())")
    }
}

private func removeFlag(_ flag: String, from arguments: inout [String]) -> Bool {
    guard let index = arguments.firstIndex(of: flag) else { return false }
    arguments.remove(at: index)
    return true
}

private func stageAndExport(
    recording: Recording,
    destination: URL,
    client: BrokerClient
) throws -> [String: Any] {
    try client.withResponse(["operation": "stage", "id": recording.id]) { result, exchangeDirectory in
        guard let response = result as? [String: Any],
              let filename = response["file"] as? String,
              recordingExtensions.map({ "recording.\($0)" }).contains(filename) else {
            throw VoiceMemosError.broker("The broker returned invalid staged-file data.")
        }
        let stagedFile = exchangeDirectory.appendingPathComponent(filename)
        let values = try stagedFile.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw VoiceMemosError.broker("The broker did not produce a regular audio file.")
        }
        let (path, copied) = try ExportDestination().copy(
            stagedFile: stagedFile,
            recording: recording,
            to: destination
        )
        return ["recording": recording.jsonObject(), "path": path.path, "copied": copied]
    }
}

private func run() throws -> Int32 {
    let command = try parseCommand(Array(CommandLine.arguments.dropFirst()))
    let client = BrokerClient()

    switch command.action {
    case .inspect:
        return try client.withResponse(["operation": "inspect"]) { summary, _ in
            guard let summary = summary as? [String: Any] else {
                throw VoiceMemosError.broker("The broker returned invalid schema data.")
            }
            if command.json {
                try printJSON(summary)
            } else {
                print("Database: \(summary["databasePath"] ?? "?")")
                print("Recordings: \(summary["recordingCount"] ?? 0)")
                print("Recognized columns: \((summary["recognizedColumns"] as? [String] ?? []).joined(separator: ", "))")
            }
            return 0
        }

    case .list:
        try printRecordings(loadRecordings(client: client), json: command.json)
        return 0

    case .search(let query, let exact):
        let found = matches(try loadRecordings(client: client), query: query, exact: exact)
        try printRecordings(found, json: command.json)
        return found.isEmpty ? 1 : 0

    case .export(let query, let destination, let exact, let all):
        let found = matches(try loadRecordings(client: client), query: query, exact: exact)
        let available = found.filter(\.isAvailable)
        guard !found.isEmpty else {
            fputs("No recording found for \"\(query)\".\n", stderr)
            return 1
        }
        guard !available.isEmpty else {
            fputs("Matching recordings are not available locally.\n", stderr)
            try printRecordings(found, json: command.json)
            return 1
        }
        guard available.count == 1 || all else {
            fputs("Found \(available.count) local recordings; use --exact or --all.\n", stderr)
            try printRecordings(available, json: command.json)
            return 2
        }

        let destinationURL = URL(
            fileURLWithPath: (destination as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
        let selected = all ? available : [available[0]]
        let results = try selected.map {
            try stageAndExport(recording: $0, destination: destinationURL, client: client)
        }
        if command.json {
            try printJSON(results)
        } else {
            for result in results {
                let copied = result["copied"] as? Bool == true
                print("\(copied ? "Exported" : "Already exported"): \(result["path"] ?? "?")")
            }
        }
        return 0
    }
}

do {
    exit(try run())
} catch let error as VoiceMemosError {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(error.isUsageError ? 64 : 1)
} catch {
    fputs("Error: \(error.localizedDescription)\n", stderr)
    exit(1)
}

private extension String {
    func leftPadded(to width: Int) -> String {
        String(repeating: " ", count: max(0, width - count)) + self
    }

    func rightPadded(to width: Int) -> String {
        self + String(repeating: " ", count: max(0, width - count))
    }
}

private extension VoiceMemosError {
    var isUsageError: Bool {
        if case .invalidUsage = self { return true }
        return false
    }
}
