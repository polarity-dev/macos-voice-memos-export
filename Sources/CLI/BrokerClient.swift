import Foundation

struct BrokerClient {
    private let timeout: TimeInterval = 30

    func withResponse<T>(
        _ request: [String: Any],
        body: (Any, URL) throws -> T
    ) throws -> T {
        let appURL = try brokerAppURL()
        let exchange = try ExchangePaths.create()
        defer { try? FileManager.default.removeItem(at: exchange.directory) }

        let data = try JSONSerialization.data(withJSONObject: request, options: [.sortedKeys])
        try data.write(to: exchange.request, options: .atomic)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [
            "-n", "-a", appURL.path,
            "--args", exchange.request.path, exchange.response.path,
        ]
        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw VoiceMemosError.broker("Unable to launch VoiceMemosExport.app: \(detail)")
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: exchange.response.path) {
                let responseData = try Data(contentsOf: exchange.response)
                guard let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any],
                      let ok = response["ok"] as? Bool else {
                    throw VoiceMemosError.broker("The broker returned an invalid response.")
                }
                if ok {
                    return try body(response["result"] ?? NSNull(), exchange.directory)
                }
                throw VoiceMemosError.broker(response["error"] as? String ?? "Unknown broker error.")
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw VoiceMemosError.broker("Timed out waiting for VoiceMemosExport.app.")
    }

    private func brokerAppURL() throws -> URL {
        let defaultPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications/VoiceMemosExport.app").path
        let path = ProcessInfo.processInfo.environment["VOICE_MEMOS_EXPORT_APP"] ?? defaultPath
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VoiceMemosError.broker(
                "VoiceMemosExport.app was not found at \(url.path). Run `make install` first."
            )
        }
        return url
    }
}
