import Foundation
import CoreLocation
import Security

class AppState: NSObject, ObservableObject, CLLocationManagerDelegate {

    // MARK: - Auth state
    @Published var isLoggedIn = false
    @Published var username = ""

    // MARK: - User data
    @Published var currentUser: TurfUser?
    @Published var nearbyZones: [TurfZone] = []
    @Published var ownedZones: [TurfZone] = []

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
        ownedZones = []
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
            let user = try await TurfAPIService.shared.fetchUser(name: username)
            currentUser = user
            if let refs = user.zones, !refs.isEmpty {
                let ids = refs.prefix(30).map(\.id)
                ownedZones = try await TurfAPIService.shared.fetchZones(ids: Array(ids))
            } else {
                ownedZones = []
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoadingUser = false
    }

    @MainActor
    func refreshNearbyZones() async {
        guard let loc = location else {
            requestLocation()
            return
        }
        isLoadingZones = true
        errorMessage = nil
        do {
            let zones = try await TurfAPIService.shared.fetchNearbyZones(
                latitude: loc.coordinate.latitude,
                longitude: loc.coordinate.longitude
            )
            nearbyZones = zones.sorted { distanceTo($0) ?? .infinity < distanceTo($1) ?? .infinity }
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
