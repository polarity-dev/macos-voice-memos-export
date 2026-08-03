import Foundation
import SQLite3

struct StoredRecording {
    let metadata: Recording
    let sourceURL: URL?
}

final class VoiceMemosStore {
    private static let appleEpoch = Date(timeIntervalSince1970: 978_307_200)
    private static let table = "ZCLOUDRECORDING"
    private static let supportedColumns = [
        "ZUNIQUEID", "ZUUID", "ZCUSTOMLABELFORSORTING", "ZENCRYPTEDTITLE",
        "ZCUSTOMLABEL", "ZDATE", "ZDURATION", "ZLOCALDURATION", "ZPATH",
    ]

    let databaseURL: URL
    let recordingsDirectory: URL

    init(homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser) {
        recordingsDirectory = homeDirectory
            .appendingPathComponent("Library/Group Containers/group.com.apple.VoiceMemos.shared/Recordings", isDirectory: true)
        databaseURL = recordingsDirectory.appendingPathComponent("CloudRecordings.db")
    }

    func recordings() throws -> [StoredRecording] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let columns = try columnNames(database)
        guard columns.contains("ZPATH") else {
            throw VoiceMemosError.unsupportedSchema("The Voice Memos database does not contain ZPATH.")
        }
        let selected = Self.supportedColumns.filter(columns.contains)
        let order = columns.contains("ZDATE") ? " ORDER BY ZDATE DESC" : ""
        return try query(
            database,
            sql: "SELECT \(selected.joined(separator: ", ")) FROM \(Self.table)\(order)"
        ).map(recording(from:))
    }

    func schemaSummary() throws -> [String: Any] {
        let database = try openDatabase()
        defer { sqlite3_close(database) }

        let columns = try columnNames(database).sorted()
        let recognized = Self.supportedColumns.filter(columns.contains)
        let countRows = try query(database, sql: "SELECT COUNT(*) AS count FROM \(Self.table)")
        return [
            "databasePath": databaseURL.path,
            "recordingCount": countRows.first?["count"] as? Int64 ?? 0,
            "recognizedColumns": recognized,
            "allColumns": columns,
        ]
    }

    private func openDatabase() throws -> OpaquePointer {
        var database: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &database,
            SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX,
            nil
        )
        guard result == SQLITE_OK, let database else {
            let detail = database.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            sqlite3_close(database)
            throw VoiceMemosError.database(
                "Cannot open the Voice Memos database: \(detail). Grant Full Disk Access to VoiceMemosExport.app."
            )
        }
        return database
    }

    private func columnNames(_ database: OpaquePointer) throws -> Set<String> {
        let names = try query(database, sql: "PRAGMA table_info(\(Self.table))")
            .compactMap { $0["name"] as? String }
        guard !names.isEmpty else {
            throw VoiceMemosError.unsupportedSchema("The Voice Memos database does not contain \(Self.table).")
        }
        return Set(names)
    }

    private func query(_ database: OpaquePointer, sql: String) throws -> [[String: Any]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
              let statement else {
            throw VoiceMemosError.database("SQL prepare failed: \(String(cString: sqlite3_errmsg(database)))")
        }
        defer { sqlite3_finalize(statement) }

        var rows: [[String: Any]] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return rows }
            guard result == SQLITE_ROW else {
                throw VoiceMemosError.database("SQL query failed: \(String(cString: sqlite3_errmsg(database)))")
            }
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                row[name] = value(statement, column: index)
            }
            rows.append(row)
        }
    }

    private func value(_ statement: OpaquePointer, column: Int32) -> Any {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER: return sqlite3_column_int64(statement, column)
        case SQLITE_FLOAT: return sqlite3_column_double(statement, column)
        case SQLITE_TEXT:
            guard let text = sqlite3_column_text(statement, column) else { return NSNull() }
            return String(cString: text)
        default: return NSNull()
        }
    }

    private func recording(from row: [String: Any]) -> StoredRecording {
        let id = firstString(in: row, keys: ["ZUNIQUEID", "ZUUID"]) ?? "unknown"
        let title = firstString(
            in: row,
            keys: ["ZCUSTOMLABELFORSORTING", "ZENCRYPTEDTITLE", "ZCUSTOMLABEL"]
        ) ?? "Untitled"
        let timestamp = number(in: row, keys: ["ZDATE"])
        let duration = number(in: row, keys: ["ZDURATION", "ZLOCALDURATION"]) ?? 0
        let path = firstString(in: row, keys: ["ZPATH"]) ?? ""
        let sourceURL = resolveRecordingPath(path)
        return StoredRecording(
            metadata: Recording(
                id: id,
                title: title,
                recordedAt: timestamp.map { Self.appleEpoch.addingTimeInterval($0) },
                duration: duration,
                isAvailable: sourceURL != nil
            ),
            sourceURL: sourceURL
        )
    }

    private func firstString(in row: [String: Any], keys: [String]) -> String? {
        for key in keys {
            guard let value = row[key] as? String else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty { return trimmed }
        }
        return nil
    }

    private func number(in row: [String: Any], keys: [String]) -> Double? {
        for key in keys {
            if let value = row[key] as? Double { return value }
            if let value = row[key] as? Int64 { return Double(value) }
        }
        return nil
    }

    private func resolveRecordingPath(_ path: String) -> URL? {
        guard !path.isEmpty else { return nil }
        let candidate = path.hasPrefix("/")
            ? URL(fileURLWithPath: path)
            : recordingsDirectory.appendingPathComponent(path)
        let root = recordingsDirectory.resolvingSymlinksInPath().standardizedFileURL
        let resolved = candidate.resolvingSymlinksInPath().standardizedFileURL
        guard isDescendant(resolved, of: root), resolved.pathExtension.lowercased() == "m4a" else {
            return nil
        }
        guard let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey]),
              values.isRegularFile == true else { return nil }
        return resolved
    }

    private func isDescendant(_ candidate: URL, of root: URL) -> Bool {
        let rootComponents = root.pathComponents
        let candidateComponents = candidate.pathComponents
        return candidateComponents.count > rootComponents.count
            && Array(candidateComponents.prefix(rootComponents.count)) == rootComponents
    }
}
