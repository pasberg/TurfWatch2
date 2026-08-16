import Foundation
import CoreLocation
import Security
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
    private let keychainKey = "turf_password"

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyHundredMeters

        if let saved = UserDefaults.standard.string(forKey: usernameKey),
           !saved.isEmpty,
           let pwd = loadKeychain() {
            username = saved
            TurfAPIService.shared.setCredentials(username: saved, password: pwd)
            isLoggedIn = true
        }
    }

    // MARK: - Login / Logout

    @MainActor
    func login(username: String, password: String) async throws {
        TurfAPIService.shared.setCredentials(username: username, password: password)
        let user = try await TurfAPIService.shared.fetchUser(name: username)
        saveKeychain(password)
        UserDefaults.standard.set(username, forKey: usernameKey)
        self.username = username
        self.currentUser = user
        self.isLoggedIn = true
    }

    func logout() {
        deleteKeychain()
        UserDefaults.standard.removeObject(forKey: usernameKey)
        TurfAPIService.shared.clearCredentials()
        username = ""
        isLoggedIn = false
        currentUser = nil
        nearbyZones = []
        allZones = []
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

    /// Full zone set from the unstable API (all zones, with polygons), cached for
    /// the session so we filter locally instead of re-downloading on every pan.
    private var allZones: [TurfZone] = []

    /// How far around the user we keep zones, and how many at most — a watch can't
    /// render tens of thousands of polygons, and you only care about what's nearby.
    private let nearbyRadiusMeters: CLLocationDistance = 20_000
    private let maxNearbyZones = 250

    @MainActor
    func refreshNearbyZones(force: Bool = false) async {
        guard let loc = location else {
            requestLocation()
            return
        }
        isLoadingZones = true
        errorMessage = nil
        do {
            if allZones.isEmpty || force {
                allZones = try await TurfAPIService.shared.fetchAllZones()
            }
            // Filter the (potentially huge) set down to nearby zones off the main
            // thread so the watch UI never hitches.
            let zones = allZones
            let radius = nearbyRadiusMeters
            let limit = maxNearbyZones
            nearbyZones = await Task.detached(priority: .userInitiated) { () -> [TurfZone] in
                zones
                    .compactMap { zone -> (TurfZone, CLLocationDistance)? in
                        let d = loc.distance(from: CLLocation(latitude: zone.latitude, longitude: zone.longitude))
                        return d <= radius ? (zone, d) : nil
                    }
                    .sorted { $0.1 < $1.1 }
                    .prefix(limit)
                    .map { $0.0 }
            }.value
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

    // MARK: - Keychain

    private func saveKeychain(_ value: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
    }

    private func loadKeychain() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keychainKey
        ]
        SecItemDelete(query as CFDictionary)
    }
}
