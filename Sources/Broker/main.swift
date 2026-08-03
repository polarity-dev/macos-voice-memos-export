import Foundation

private func writeResponse(_ response: [String: Any], to url: URL) {
    do {
        let data = try JSONSerialization.data(withJSONObject: response, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url, options: .atomic)
    } catch {
        fputs("Unable to write broker response: \(error.localizedDescription)\n", stderr)
    }
}

private func handle(_ request: [String: Any], exchangeDirectory: URL) throws -> Any {
    guard let operation = request["operation"] as? String else {
        throw VoiceMemosError.broker("Missing broker operation.")
    }
    let store = VoiceMemosStore()
    switch operation {
    case "inspect":
        return try store.schemaSummary()
    case "recordings":
        return try store.recordings().map { $0.metadata.jsonObject() }
    case "stage":
        guard let id = request["id"] as? String else {
            throw VoiceMemosError.broker("The stage operation requires a recording ID.")
        }
        let recordings = try store.recordings()
        guard let recording = recordings.first(where: { $0.metadata.id == id }) else {
            throw VoiceMemosError.broker("Recording not found for the supplied ID.")
        }
        return ["file": try RecordingStager().stage(recording, in: exchangeDirectory)]
    default:
        throw VoiceMemosError.broker("Unknown broker operation: \(operation)")
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count == 2 else {
    fputs("VoiceMemosExport.app is a broker. Use the voice-memos CLI.\n", stderr)
    exit(64)
}

let requestURL = URL(fileURLWithPath: arguments[0]).standardizedFileURL
let responseURL = URL(fileURLWithPath: arguments[1]).standardizedFileURL

do {
    let exchange = try ExchangePaths.validate(request: requestURL, response: responseURL)
    let data = try Data(contentsOf: exchange.request)
    guard let request = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw VoiceMemosError.broker("Broker request must be a JSON object.")
    }
    writeResponse(
        ["ok": true, "result": try handle(request, exchangeDirectory: exchange.directory)],
        to: exchange.response
    )
} catch {
    if let exchange = try? ExchangePaths.validate(request: requestURL, response: responseURL) {
        writeResponse(["ok": false, "error": error.localizedDescription], to: exchange.response)
    } else {
        fputs("Broker error: \(error.localizedDescription)\n", stderr)
    }
    exit(1)
}
