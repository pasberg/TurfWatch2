import Foundation

class TurfAPIService {
    static let shared = TurfAPIService()

    /// Stable API — used for the public user lookup.
    private let baseURL = "https://api.turfgame.com/v4"
    /// Unstable API — zone geometry/details live here.
    private let unstableURL = "https://api.turfgame.com/unstable"

    private func request(url: URL, method: String = "GET", body: Data? = nil, timeout: TimeInterval = 15) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = method
        // Only send Content-Type when there's actually a body — a GET that carries
        // Content-Type but no body is rejected by some servers/firewalls.
        if body != nil {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("sv-SE,sv;q=0.9,en;q=0.8", forHTTPHeaderField: "Accept-Language")
        // Mimic a normal mobile browser. Turf serves 200 to the website but has
        // been rate-limiting our custom client UA harder, so present a Safari UA.
        req.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent")
        req.httpBody = body
        return req
    }

    /// Throws a readable error for non-200 responses, with a friendly 429 message.
    private func validate(_ response: URLResponse) throws {
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status == 200 { return }
        if status == 429 {
            // Retry-After may be seconds or an HTTP date; we only parse seconds.
            let retry = http?.value(forHTTPHeaderField: "Retry-After").flatMap { TimeInterval($0) }
            throw TurfError.rateLimited(retryAfter: retry)
        }
        throw TurfError.networkError("HTTP \(status)")
    }

    /// Looks up a user by name. The Turf API v4 has no GET path for a single user
    /// (that returns 404) — you POST a JSON array of names to `/v4/users`.
    func fetchUser(name: String) async throws -> TurfUser {
        guard let url = URL(string: "\(baseURL)/users") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        struct NameQuery: Encodable { let name: String }
        let body = try JSONEncoder().encode([NameQuery(name: name)])
        let (data, response) = try await URLSession.shared.data(for: request(url: url, method: "POST", body: body))
        try validate(response)
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

    /// The lightweight index of *all* zones (GET `unstable/zones/all`): positions
    /// and ids, but no polygon or owner. Large but server-cached, so we cache it on
    /// disk and only re-fetch rarely.
    func fetchAllZones() async throws -> [TurfZone] {
        guard let url = URL(string: "\(unstableURL)/zones/all") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        let (data, response) = try await URLSession.shared.data(for: request(url: url, timeout: 60))
        try validate(response)
        do {
            // Lenient: skip any individual zone that fails to decode.
            let items = try JSONDecoder().decode([FailableDecodable<TurfZone>].self, from: data)
            return items.compactMap { $0.value }
        } catch {
            throw TurfError.decodingError(error.localizedDescription)
        }
    }

    /// Full details (polygon, owner, points) for specific zones, via
    /// POST `unstable/zones` with a body like `[{"id":"1262"}]`. Batched so a big
    /// nearby set doesn't make one oversized request.
    func fetchZoneDetails(ids: [Int]) async throws -> [TurfZone] {
        guard !ids.isEmpty else { return [] }
        guard let url = URL(string: "\(unstableURL)/zones") else {
            throw TurfError.networkError("Ogiltig URL")
        }
        struct IdQuery: Encodable { let id: String }

        var result: [TurfZone] = []
        let batchSize = 100
        var start = 0
        while start < ids.count {
            let chunk = Array(ids[start..<min(start + batchSize, ids.count)])
            let body = try JSONEncoder().encode(chunk.map { IdQuery(id: String($0)) })
            let (data, response) = try await URLSession.shared.data(for: request(url: url, method: "POST", body: body, timeout: 30))
            try validate(response)
            do {
                let items = try JSONDecoder().decode([FailableDecodable<TurfZone>].self, from: data)
                result += items.compactMap { $0.value }
            } catch {
                throw TurfError.decodingError(error.localizedDescription)
            }
            start += batchSize
        }
        return result
    }
}
