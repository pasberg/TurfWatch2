import Foundation
import CoreLocation
import SwiftUI

class AppState: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Auth state
    @Published var isLoggedIn = false
    @Published var username = ""

    // MARK: - User data
    @Published var currentUser: TurfUser?
    @Published var nearbyZones: [TurfZone] = []

    // MARK: - Loading / error
    @Published var isLoadingUser = false
    @Published var isLoadingZones = false
    @Published var errorMessage: String?

    // MARK: - Location
    @Published var location: CLLocation?
    @Published var locationDenied = false

    private let clManager = CLLocationManager()
    private let usernameKey = "turf_username"

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        // The Turf API is public and read-only, so we only need to remember the
        // username — there's no password to authenticate.
        if let saved = UserDefaults.standard.string(forKey: usernameKey), !saved.isEmpty {
            username = saved
            isLoggedIn = true
        }
    }

    // MARK: - Login / Logout

    @MainActor
    func login(username: String) async throws {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Verify the username exists by looking it up before saving it.
        let user = try await TurfAPIService.shared.fetchUser(name: trimmed)
        UserDefaults.standard.set(user.name, forKey: usernameKey)
        self.username = user.name
        self.currentUser = user
        self.isLoggedIn = true
    }

    func logout() {
        UserDefaults.standard.removeObject(forKey: usernameKey)
        username = ""
        isLoggedIn = false
        currentUser = nil
        nearbyZones = []
        allZones = []
        didAttemptZoneLoad = false
        AppState.clearCachedZones()
        errorMessage = nil
    }

    // MARK: - Location

    func requestLocation() {
        switch clManager.authorizationStatus {
        case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            clManager.requestLocation()
        case .denied, .restricted:
            locationDenied = true
        @unknown default:
            break
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            locationDenied = false
            manager.requestLocation()
        case .denied, .restricted:
            locationDenied = true
        default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        location = locations.last
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if (error as NSError).code != CLError.locationUnknown.rawValue {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Data refresh

    @MainActor
    func refreshUser() async {
        guard isLoggedIn else { return }
        isLoadingUser = true
        errorMessage = nil
        do {
            currentUser = try await TurfAPIService.shared.fetchUser(name: username)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingUser = false
    }

    /// Full zone set from the unstable API (all zones, with polygons). Cached in
    /// memory for the session and on disk between launches so we don't re-download
    /// the large payload every time.
    private var allZones: [TurfZone] = []

    /// How far around the user we keep zones, and how many at most — a watch can't
    /// render tens of thousands of polygons, and you only care about what's nearby.
    private let nearbyRadiusMeters: CLLocationDistance = 20_000
    private let maxNearbyZones = 150
    /// How long an on-disk zone cache is considered fresh.
    private static let zoneCacheMaxAge: TimeInterval = 60 * 60 * 24
    /// Set once we've tried a network load, so auto-triggers don't hammer the
    /// rate-limited all-zones endpoint; manual refresh (force) ignores it.
    private var didAttemptZoneLoad = false

    @MainActor
    func refreshNearbyZones(force: Bool = false) async {
        guard let loc = location else {
            requestLocation()
            return
        }
        // Don't auto-retry after a failed attempt; manual refresh (force) ignores it.
        if !force && didAttemptZoneLoad && nearbyZones.isEmpty { return }
        didAttemptZoneLoad = true
        isLoadingZones = true
        errorMessage = nil
        do {
            // 1. Load the lightweight zone index once (cache-first). The index
            //    rarely changes, so even a manual refresh keeps the cached copy and
            //    only re-POSTs details below — this avoids re-hitting the heavy,
            //    rate-limited /zones/all endpoint on every retry.
            if allZones.isEmpty {
                if let cached = await Task.detached(priority: .userInitiated, operation: {
                       AppState.loadCachedZones(maxAge: AppState.zoneCacheMaxAge)
                   }).value {
                    allZones = cached
                } else {
                    let fresh = try await TurfAPIService.shared.fetchAllZones()
                    allZones = fresh
                    Task.detached(priority: .utility) { AppState.saveCachedZones(fresh) }
                }
            }

            // 2. Pick the nearest zone ids (off the main thread).
            let zones = allZones
            let radius = nearbyRadiusMeters
            let limit = maxNearbyZones
            let nearbyIds: [Int] = await Task.detached(priority: .userInitiated) { () -> [Int] in
                zones
                    .compactMap { zone -> (Int, CLLocationDistance)? in
                        let d = loc.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude))
                        return d <= radius ? (zone.id, d) : nil
                    }
                    .sorted { $0.1 < $1.1 }
                    .prefix(limit)
                    .map { $0.0 }
            }.value

            // 3. Fetch full details (polygon + owner) for just those, and sort by distance.
            let detailed = try await TurfAPIService.shared.fetchZoneDetails(ids: nearbyIds)
            nearbyZones = detailed.sorted {
                (distanceTo($0) ?? .infinity) < (distanceTo($1) ?? .infinity)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingZones = false
    }

    // MARK: - Helpers

    func distanceTo(_ zone: TurfZone) -> Double? {
        guard let loc = location else { return nil }
        return loc.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude))
    }

    func formatDistance(_ meters: Double) -> String {
        meters < 1000 ? "\(Int(meters)) m" : String(format: "%.1f km", meters / 1000)
    }

    func isMyZone(_ zone: TurfZone) -> Bool {
        zone.currentOwner?.name.lowercased() == username.lowercased()
    }

    /// How long a zone stays blocked (locked from takeover) after it's taken.
    /// Turf's block time is a per-round setting; this is an approximation and
    /// may need tuning if the API later exposes the real value.
    private let blockDurationMinutes: Double = 25

    /// A zone is blocked if it was taken within the last `blockDurationMinutes`.
    func isBlocked(_ zone: TurfZone) -> Bool {
        guard zone.currentOwner != nil, let taken = zone.lastTakenDate else { return false }
        return Date().timeIntervalSince(taken) < blockDurationMinutes * 60
    }

    /// Shared colour legend used across map, list and detail views.
    /// - black: blocked (in cooldown after a takeover)
    /// - green: your own zone
    /// - red: taken (owned by someone else, available to take)
    /// - yellow: neutral (no owner)
    func zoneColor(_ zone: TurfZone) -> Color {
        if isBlocked(zone) { return .black }
        if zone.currentOwner == nil { return .yellow }
        if isMyZone(zone) { return .green }
        return .red
    }

    /// Shared status label matching the colour legend.
    func zoneStatusText(_ zone: TurfZone) -> String {
        if isBlocked(zone) { return "Blockerad" }
        guard let owner = zone.currentOwner else { return "Neutral" }
        return isMyZone(zone) ? "Din zon" : owner.name
    }

    // MARK: - Zone disk cache

    private struct ZoneCache: Codable {
        let savedAt: Date
        let zones: [TurfZone]
    }

    private static func cacheURL() -> URL? {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("turf_zones_cache.json")
    }

    /// Writes the full zone set to the caches directory. Safe to call off the main thread.
    static func saveCachedZones(_ zones: [TurfZone]) {
        guard let url = cacheURL() else { return }
        let payload = ZoneCache(savedAt: Date(), zones: zones)
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns the cached zones if the cache exists and is younger than `maxAge`.
    static func loadCachedZones(maxAge: TimeInterval) -> [TurfZone]? {
        guard let url = cacheURL(),
              let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(ZoneCache.self, from: data),
              Date().timeIntervalSince(payload.savedAt) < maxAge else { return nil }
        return payload.zones
    }

    static func clearCachedZones() {
        guard let url = cacheURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
