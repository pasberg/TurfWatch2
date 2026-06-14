import Foundation

struct TurfUser: Codable, Identifiable {
    let id: Int
    let name: String
    let points: Int
    let rank: Int
    let pointsPerHour: Int
    let taken: Int
    let totalTakenZones: Int
    let zones: [TurfZoneRef]?
    let region: TurfRegion?
    let country: String?
    let blockTime: Int?
}

struct TurfZone: Codable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let pointsPerHour: Int
    let takeoverPoints: Int
    let totalTakeovers: Int
    let currentOwner: TurfUserRef?
    let region: TurfRegion?
    let dateLastTaken: String?

    var isNeutral: Bool { currentOwner == nil }

    /// Parsed timestamp of the last takeover, if available.
    var lastTakenDate: Date? {
        guard let s = dateLastTaken else { return nil }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        if let d = iso.date(from: s) { return d }
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        return df.date(from: s)
    }
}

struct TurfZoneRef: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TurfUserRef: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TurfRegion: Codable {
    let id: Int
    let name: String
    let country: String?
}

enum TurfError: Error, LocalizedError {
    case invalidCredentials
    case userNotFound
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Fel användarnamn eller lösenord"
        case .userNotFound: return "Användaren hittades inte"
        case .networkError(let msg): return "Nätverksfel: \(msg)"
        case .decodingError(let msg): return "Datafel: \(msg)"
        }
    }
}
