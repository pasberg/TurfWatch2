import Foundation

class TurfAPIService {
    static let shared = TurfAPIService()

    /// Stable API — used for the public user lookup.
    private let baseURL = "https://api.turfgame.com/v4"
    /// Unstable API — the only branch that returns zone `polygon` geometry.
    private let unstableURL = "https://api.turfgame.com/unstable"

    private func request(url: URL, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 15) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        return req
    }

    /// Looks up a user by name. The Turf API v4 has no GET path for a single user
    /// (that returns 404) — you POST a JSON array of names to `/v4/users` and get
    /// back an array of matching user objects. The endpoint is public (read-only),
    /// so no authentication is required.
    func fetchUser(name: String) async throws -> TurfUser {
        guard let url = URL(string: "\(baseURL)/users") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        struct NameQuery: Encodable { let name: String }
        let body = try JSONEncoder().encode([NameQuery(name: name)])
        let (data, response) = try await URLSession.shared.data(for: request(url: url, method: "POST", body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { throw TurfError.networkError("HTTP \(status)") }
        do {
            let users = try JSONDecoder().decode([TurfUser].self, from: data)
            guard let user = users.first else { throw TurfError.userNotFound }
            return user
        } catch let error as TurfError {
            throw error
        } catch {
            throw TurfError.decodingError(error.localizedDescription)
        }
    }

    /// Fetches every zone from the unstable API, each including its `polygon`
    /// boundary. This is a large response, so callers should cache the result and
    /// filter it down to the zones near the user rather than re-fetching often.
    func fetchAllZones() async throws -> [TurfZone] {
        guard let url = URL(string: "\(unstableURL)/zones") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        let (data, response) = try await URLSession.shared.data(for: request(url: url, timeout: 60))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { throw TurfError.networkError("HTTP \(status)") }
        do {
            return try JSONDecoder().decode([TurfZone].self, from: data)
        } catch {
            throw TurfError.decodingError(error.localizedDescription)
        }
    }
}
