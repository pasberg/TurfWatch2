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
    /// True while the map is showing bundled seed zones (not live data).
    @Published var usingSeedZones = false

    // MARK: - Loading / error
    @Published var isLoadingUser = false
    @Published var isLoadingZones = false
    /// Error from the profile/user lookup.
    @Published var errorMessage: String?
    /// Error from the zone load, kept separate so a successful user refresh
    /// doesn't wipe the reason we're still on seed data (e.g. rate limiting).
    @Published var zoneErrorMessage: String?

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
        didTryFullIndex = false
        rateLimitedUntil = nil
        consecutiveRateLimits = 0
        AppState.clearCachedZones()
        usingSeedZones = false
        errorMessage = nil
        zoneErrorMessage = nil
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
        // Don't fire profile lookups while rate-limited — they count toward the
        // same limit and only keep us stuck.
        if inCooldown { return }
        isLoadingUser = true
        errorMessage = nil
        do {
            currentUser = try await TurfAPIService.shared.fetchUser(name: username)
        } catch let error as TurfError {
            errorMessage = error.errorDescription
            if case .rateLimited(let retry) = error {
                beginRateLimit(retryAfter: retry)
            }
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
    private let maxNearbyZones = 100
    /// How long an on-disk zone cache is considered fresh.
    private static let zoneCacheMaxAge: TimeInterval = 60 * 60 * 24
    /// Set once we've tried a network load, so auto-triggers don't hammer the
    /// rate-limited all-zones endpoint; manual refresh (force) ignores it.
    private var didAttemptZoneLoad = false
    /// Guards the once-per-session attempt to upgrade from the bundled index to
    /// the full live /zones/all index.
    private var didTryFullIndex = false
    /// While set and in the future, we're in a rate-limit cooldown and skip
    /// network calls — retrying only extends Turf's limit and keeps us on seed.
    /// Published so the UI can show a live countdown.
    @Published private(set) var rateLimitedUntil: Date?
    /// Consecutive 429s, used to back off progressively — Turf often limits for
    /// longer than its Retry-After header suggests.
    private var consecutiveRateLimits = 0

    /// True while inside a rate-limit cooldown.
    @MainActor
    private var inCooldown: Bool {
        if let until = rateLimitedUntil, Date() < until { return true }
        return false
    }

    /// Starts/extends a cooldown after a 429. Backs off 30s → 60s → 120s → 240s,
    /// capped at 5 min, and never shorter than the server's Retry-After.
    @MainActor
    private func beginRateLimit(retryAfter: TimeInterval?) {
        consecutiveRateLimits += 1
        let escalated = min(30.0 * pow(2.0, Double(consecutiveRateLimits - 1)), 300.0)
        let wait = max(retryAfter ?? 0, escalated)
        rateLimitedUntil = Date().addingTimeInterval(wait)
    }

    @MainActor
    func refreshNearbyZones(force: Bool = false) async {
        guard let loc = location else {
            requestLocation()
            return
        }
        // Show bundled seed zones immediately so there's always something nearby —
        // even offline or while the live endpoint is rate-limited.
        if nearbyZones.isEmpty {
            // Only zones we have real shapes for are shown offline; the rest of the
            // bundle is a lightweight index used purely to find nearby ids below.
            let seeded = nearbyFiltered(displayableSeedZones, around: loc)
            if !seeded.isEmpty {
                nearbyZones = seeded
                usingSeedZones = true
            }
        }

        // Honour an active cooldown: show the remaining wait instead of firing
        // another doomed request (which would just extend the rate limit).
        if let until = rateLimitedUntil, Date() < until {
            let secs = Int(until.timeIntervalSinceNow.rounded(.up))
            zoneErrorMessage = "För många anrop – vänta ~\(secs) s"
            return
        }

        // Try the live flow once automatically; manual refresh (force) ignores it.
        if !force && didAttemptZoneLoad { return }
        didAttemptZoneLoad = true
        isLoadingZones = true
        zoneErrorMessage = nil
        defer { isLoadingZones = false }

        do {
            // Decide which zones are "near me" using the lightest index available:
            // a cached full index if we have one, otherwise the bundled seed zones.
            // This lets us refresh live ownership through the LIGHT detail endpoint
            // without hitting the heavy, rate-limited /zones/all on every refresh.
            if allZones.isEmpty {
                if let cached = await Task.detached(priority: .userInitiated, operation: {
                       AppState.loadCachedZones(maxAge: AppState.zoneCacheMaxAge)
                   }).value {
                    allZones = cached
                }
            }
            let indexSource = allZones.isEmpty ? seedZones : allZones
            var nearbyIds = await nearestZoneIds(from: indexSource, around: loc)

            // Only when neither a cached index nor the seed zones cover this area
            // (e.g. the user is far from Frillesås) do we fall back to the heavy
            // all-zones index to discover nearby ids.
            if nearbyIds.isEmpty && allZones.isEmpty {
                let fresh = try await TurfAPIService.shared.fetchAllZones()
                allZones = fresh
                Task.detached(priority: .utility) { AppState.saveCachedZones(fresh) }
                nearbyIds = await nearestZoneIds(from: fresh, around: loc)
            }

            // Fetch fresh details (polygon + current owner) for the nearby zones.
            let detailed = try await TurfAPIService.shared.fetchZoneDetails(ids: nearbyIds)
            if !detailed.isEmpty {
                nearbyZones = detailed.sorted {
                    (distanceTo($0) ?? .infinity) < (distanceTo($1) ?? .infinity)
                }
                usingSeedZones = false
                rateLimitedUntil = nil
                consecutiveRateLimits = 0
            }

            // The light path worked using the bundled index. Try once per session
            // to upgrade to the full live index so areas the bundle covers only
            // sparsely (e.g. central Göteborg) fill in on the next refresh. Its
            // failure must not disturb the data we just loaded, so it's silent.
            if allZones.isEmpty && !detailed.isEmpty && !didTryFullIndex {
                didTryFullIndex = true
                if let fresh = try? await TurfAPIService.shared.fetchAllZones(), !fresh.isEmpty {
                    allZones = fresh
                    Task.detached(priority: .utility) { AppState.saveCachedZones(fresh) }
                }
            }
        } catch let error as TurfError {
            handleZoneError(error)
            // Keep the seed zones we already showed.
        } catch {
            zoneErrorMessage = error.localizedDescription
        }
    }

    /// Records a failed zone load. For rate limits it also starts a cooldown so
    /// we stop firing requests until the server's Retry-After has elapsed.
    @MainActor
    private func handleZoneError(_ error: TurfError) {
        zoneErrorMessage = error.errorDescription
        if case .rateLimited(let retry) = error {
            beginRateLimit(retryAfter: retry)
        }
    }

    /// Nearest zone ids within range of a point, computed off the main thread.
    private func nearestZoneIds(from zones: [TurfZone], around loc: CLLocation) async -> [Int] {
        let radius = nearbyRadiusMeters
        let limit = maxNearbyZones
        return await Task.detached(priority: .userInitiated) { () -> [Int] in
            zones
                .compactMap { zone -> (Int, CLLocationDistance)? in
                    let d = loc.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude))
                    return d <= radius ? (zone.id, d) : nil
                }
                .sorted { $0.1 < $1.1 }
                .prefix(limit)
                .map { $0.0 }
        }.value
    }

    /// Filters a zone set to those within range of a point, nearest first.
    private func nearbyFiltered(_ zones: [TurfZone], around loc: CLLocation) -> [TurfZone] {
        zones
            .compactMap { z -> (TurfZone, CLLocationDistance)? in
                let d = loc.distance(from: CLLocation(latitude: z.latitude, longitude: z.longitude))
                return d <= nearbyRadiusMeters ? (z, d) : nil
            }
            .sorted { $0.1 < $1.1 }
            .prefix(maxNearbyZones)
            .map { $0.0 }
    }

    /// Zones bundled with the app, shown as a fallback when the live API is
    /// unavailable or rate-limited.
    private lazy var seedZones: [TurfZone] = AppState.loadSeedZones()
    /// Seed zones we can actually draw (have a polygon). The full `seedZones` set
    /// also includes lightweight index-only zones used just for nearby-id lookup.
    private lazy var displayableSeedZones: [TurfZone] = seedZones.filter { $0.polygon != nil }

    private static func loadSeedZones() -> [TurfZone] {
        guard let url = Bundle.main.url(forResource: "seed_zones", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return [] }
        let items = (try? JSONDecoder().decode([FailableDecodable<TurfZone>].self, from: data)) ?? []
        return items.compactMap { $0.value }
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
