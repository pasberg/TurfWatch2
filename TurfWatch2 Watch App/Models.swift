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
