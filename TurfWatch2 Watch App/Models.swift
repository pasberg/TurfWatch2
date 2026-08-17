import Foundation
import CoreLocation

struct TurfUser: Codable, Identifiable {
    let id: Int
    let name: String
    let points: Int?            // points this round
    let totalPoints: Int?       // all-time points
    let rank: Int?              // rank/level in the game
    let place: Int?             // position on the overall leaderboard
    let pointsPerHour: Int?
    let taken: Int?             // total takeovers ("taggar")
    let uniqueZonesTaken: Int?
    let zones: [Int]?           // ids of zones currently held
    let medals: [Int]?          // ids of earned medals
    let region: TurfRegion?
    let country: String?
    let blocktime: Int?
}

/// A single vertex used when polygon boundary data is available.
struct TurfCoordinate: Codable {
    let latitude: Double
    let longitude: Double
}

struct TurfZone: Codable, Identifiable {
    let id: Int
    let name: String
    let latitude: Double
    let longitude: Double
    let pointsPerHour: Int?
    let takeoverPoints: Int?
    let totalTakeovers: Int?
    let currentOwner: TurfUserRef?
    let region: TurfRegion?
    let type: TurfZoneType?
    let dateLastTaken: String?

    /// Polygon boundary of the zone — the real, hand-drawn irregular area.
    ///
    /// The Turf `unstable` API (`api.turfgame.com/unstable/zones`) returns a
    /// `polygon` array of boundary vertices for each zone, matching the shapes drawn
    /// in the rezoning tool. When present the map renders the true polygon; when
    /// absent it falls back to a circle of the zone's real size around the center.
    let polygon: [TurfCoordinate]?

    var isNeutral: Bool { currentOwner == nil }

    /// Center of the zone as a coordinate.
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Real-world radius of the zone in meters, used to draw its area on the map.
    /// Turf zones are roughly 25×25 m, so ~16 m radius approximates the footprint.
    var areaRadius: CLLocationDistance { 16 }

    /// Boundary vertices as map coordinates, when polygon data is available.
    var areaCoordinates: [CLLocationCoordinate2D]? {
        guard let polygon, polygon.count >= 3 else { return nil }
        return polygon.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

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

struct TurfUserRef: Codable, Identifiable {
    let id: Int
    let name: String
}

struct TurfRegion: Codable {
    let id: Int
    let name: String
    let country: String?
    let area: TurfArea?
}

/// Municipality-level subdivision within a region (e.g. "Götene").
struct TurfArea: Codable {
    let id: Int
    let name: String
}

/// Zone category (e.g. Bridge, Holy, Monument, Train Station).
struct TurfZoneType: Codable {
    let id: Int
    let name: String
}

enum TurfError: Error, LocalizedError {
    case userNotFound
    case networkError(String)
    case decodingError(String)

    var errorDescription: String? {
        switch self {
        case .userNotFound: return "Användaren hittades inte"
        case .networkError(let msg): return "Nätverksfel: \(msg)"
        case .decodingError(let msg): return "Datafel: \(msg)"
        }
    }
}
