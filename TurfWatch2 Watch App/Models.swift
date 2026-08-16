import Foundation
import CoreLocation

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
    let pointsPerHour: Int
    let takeoverPoints: Int
    let totalTakeovers: Int
    let currentOwner: TurfUserRef?
    let region: TurfRegion?
    let dateLastTaken: String?

    /// Optional polygon boundary of the zone.
    ///
    /// A Turf zone is an irregular real-world *area* (~25×25 m), but the public
    /// Turf API v4 `/zones` endpoint only returns the center point above — it does
    /// not include the polygon vertices that turfgame.com draws on its web map.
    /// This field decodes boundary vertices *if* a data source ever provides them
    /// (e.g. a GeoJSON export); when absent it stays nil and the map falls back to
    /// a circular area of the zone's real size around the center point.
    let points: [TurfCoordinate]?

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
        guard let points, points.count >= 3 else { return nil }
        return points.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
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
