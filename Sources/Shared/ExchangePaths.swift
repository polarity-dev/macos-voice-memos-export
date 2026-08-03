import Foundation

struct ExchangePaths {
    static let root = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Caches/dev.voicememosexport.cli/Exchange", isDirectory: true)

    let directory: URL
    let request: URL
    let response: URL

    static func create() throws -> ExchangePaths {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        return ExchangePaths(
            directory: directory,
            request: directory.appendingPathComponent("request.json"),
            response: directory.appendingPathComponent("response.json")
        )
    }

    static func validate(request: URL, response: URL) throws -> ExchangePaths {
        let fileManager = FileManager.default
        let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
        let requestDirectory = request.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL
        let responseDirectory = response.deletingLastPathComponent()
            .resolvingSymlinksInPath().standardizedFileURL

        guard request.lastPathComponent == "request.json",
              response.lastPathComponent == "response.json",
              requestDirectory == responseDirectory,
              isDirectChild(requestDirectory, of: canonicalRoot),
              !fileManager.fileExists(atPath: response.path) else {
            throw VoiceMemosError.broker("Invalid broker exchange paths.")
        }

        let requestValues = try request.resourceValues(forKeys: [
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ])
        guard requestValues.isRegularFile == true,
              requestValues.isSymbolicLink != true,
              request.resolvingSymlinksInPath().deletingLastPathComponent() == requestDirectory else {
            throw VoiceMemosError.broker("Invalid broker request file.")
        }

        return ExchangePaths(directory: requestDirectory, request: request, response: response)
    }

    private static func isDirectChild(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count == rootComponents.count + 1
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
