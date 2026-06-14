import Foundation

class TurfAPIService {
    static let shared = TurfAPIService()

    private let baseURL = "https://api.turfgame.com/v4"
    private var authHeader: String?

    func setCredentials(username: String, password: String) {
        let token = "\(username):\(password)".data(using: .utf8)!.base64EncodedString()
        authHeader = "Basic \(token)"
    }

    func clearCredentials() {
        authHeader = nil
    }

    private func request(url: URL, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: 15)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let auth = authHeader {
            req.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        req.httpBody = body
        return req
    }

    func fetchUser(name: String) async throws -> TurfUser {
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? name
        guard let url = URL(string: "\(baseURL)/users/\(encoded)") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        let (data, response) = try await URLSession.shared.data(for: request(url: url))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { throw TurfError.invalidCredentials }
        if status == 404 { throw TurfError.userNotFound }
        if status != 200 { throw TurfError.networkError("HTTP \(status)") }
        do {
            return try JSONDecoder().decode(TurfUser.self, from: data)
        } catch {
            throw TurfError.decodingError(error.localizedDescription)
        }
    }

    func fetchNearbyZones(latitude: Double, longitude: Double) async throws -> [TurfZone] {
        guard let url = URL(string: "\(baseURL)/zones/nearby") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        struct Body: Encodable { let latitude: Double; let longitude: Double }
        let body = try JSONEncoder().encode(Body(latitude: latitude, longitude: longitude))
        let (data, response) = try await URLSession.shared.data(for: request(url: url, method: "POST", body: body))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { throw TurfError.networkError("HTTP \(status)") }
        do {
            return try JSONDecoder().decode([TurfZone].self, from: data)
        } catch {
            throw TurfError.decodingError(error.localizedDescription)
        }
    }

    func fetchZones(ids: [Int]) async throws -> [TurfZone] {
        guard !ids.isEmpty else { return [] }
        let idStr = ids.map(String.init).joined(separator: ",")
        guard let url = URL(string: "\(baseURL)/zones?ids=\(idStr)") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        let (data, response) = try await URLSession.shared.data(for: request(url: url))
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status != 200 { throw TurfError.networkError("HTTP \(status)") }
        do {
            return try JSONDecoder().decode([TurfZone].self, from: data)
        } catch {
            throw TurfError.decodingError(error.localizedDescription)
        }
    }
}
