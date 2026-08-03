import Foundation

struct Recording {
    let id: String
    let title: String
    let recordedAt: Date?
    let duration: TimeInterval
    let isAvailable: Bool

    func jsonObject() -> [String: Any] {
        [
            "id": id,
            "title": title,
            "recordedAt": recordedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "durationSeconds": duration,
            "available": isAvailable,
        ]
    }

    static func from(json: [String: Any]) throws -> Recording {
        guard let id = json["id"] as? String,
              let title = json["title"] as? String,
              let duration = json["durationSeconds"] as? Double,
              let available = json["available"] as? Bool else {
            throw VoiceMemosError.broker("The broker returned invalid recording metadata.")
        }
        let recordedAt = (json["recordedAt"] as? String).flatMap {
            ISO8601DateFormatter().date(from: $0)
        }
        return Recording(
            id: id,
            title: title,
            recordedAt: recordedAt,
            duration: duration,
            isAvailable: available
        )
    }
}

enum VoiceMemosError: Error, LocalizedError {
    case broker(String)
    case database(String)
    case filesystem(String)
    case invalidUsage(String)
    case unsupportedSchema(String)

    var errorDescription: String? {
        switch self {
        case .broker(let message), .database(let message), .filesystem(let message),
             .invalidUsage(let message), .unsupportedSchema(let message):
            return message
        }
    }
}
