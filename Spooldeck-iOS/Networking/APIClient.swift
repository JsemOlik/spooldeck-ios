import Foundation

/// A request body for the Spooldeck API. Values are sent as JSON strings, which the server
/// coerces exactly like HTML form fields. Empty values are dropped so the server treats them as unset.
typealias FormBody = [String: String]

enum APIError: LocalizedError {
    case unauthorized
    case server(status: Int, message: String, fieldErrors: [String: [String]])
    case network(Error)
    case decoding(Error)
    case invalidServer

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Your session expired. Please sign in again."
        case .server(_, let message, _): message
        case .network(let error): error.localizedDescription
        case .decoding: "The server sent something unexpected. Is it running the latest Spooldeck?"
        case .invalidServer: "That doesn't look like a Spooldeck server."
        }
    }

    var fieldErrors: [String: [String]] {
        if case .server(_, _, let fieldErrors) = self { return fieldErrors }
        return [:]
    }
}

private struct ErrorBody: Decodable {
    let error: String?
    let fieldErrors: [String: [String]]?
}

/// Talks to the `/api/v1` JSON API of a Spooldeck instance using a bearer token.
final class APIClient {
    let baseURL: URL
    var token: String?
    /// Called when the server rejects the token, so the app can return to the login screen.
    var onUnauthorized: (() -> Void)?

    private let session: URLSession

    init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            if let date = DateParsing.parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(string)")
        }
        return decoder
    }()

    func url(_ path: String) -> URL {
        baseURL.appending(path: path)
    }

    // MARK: - Requests

    func get<T: Decodable>(_ path: String, query: [String: String?] = [:]) async throws -> T {
        var components = URLComponents(url: apiURL(path), resolvingAgainstBaseURL: false)!
        let items = query.compactMap { key, value in
            value.flatMap { $0.isEmpty ? nil : URLQueryItem(name: key, value: $0) }
        }
        if !items.isEmpty { components.queryItems = items.sorted { $0.name < $1.name } }
        return try await perform(URLRequest(url: components.url!))
    }

    @discardableResult
    func send<T: Decodable>(_ method: String, _ path: String, body: FormBody = [:]) async throws -> T {
        var request = URLRequest(url: apiURL(path))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let cleaned = body.compactMapValues { value -> String? in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        request.httpBody = try JSONEncoder().encode(cleaned)
        return try await perform(request)
    }

    func post<T: Decodable>(_ path: String, body: FormBody = [:]) async throws -> T {
        try await send("POST", path, body: body)
    }

    func put<T: Decodable>(_ path: String, body: FormBody = [:]) async throws -> T {
        try await send("PUT", path, body: body)
    }

    @discardableResult
    func delete(_ path: String) async throws -> MutationResult {
        try await send("DELETE", path)
    }

    /// Checks that `baseURL` is a reachable Spooldeck server.
    func checkHealth() async throws {
        var request = URLRequest(url: url("api/health"))
        request.timeoutInterval = 10
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        struct Health: Decodable { let ok: Bool }
        guard let http = response as? HTTPURLResponse,
              let health = try? JSONDecoder().decode(Health.self, from: data)
        else { throw APIError.invalidServer }
        if !health.ok || http.statusCode != 200 {
            throw APIError.server(status: http.statusCode, message: "The server is up but can't reach its database.", fieldErrors: [:])
        }
    }

    // MARK: - Internals

    private func apiURL(_ path: String) -> URL {
        url("api/v1/" + path)
    }

    private func perform<T: Decodable>(_ request: URLRequest) async throws -> T {
        var request = request
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIError.network(error)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidServer }

        if http.statusCode == 401 {
            if token != nil { onUnauthorized?() }
            let body = try? Self.decoder.decode(ErrorBody.self, from: data)
            if token == nil, let message = body?.error {
                throw APIError.server(status: 401, message: message, fieldErrors: [:])
            }
            throw APIError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = try? Self.decoder.decode(ErrorBody.self, from: data)
            let message = body?.error ?? (http.statusCode == 404
                ? "Not found. Does this server have the Spooldeck API (/api/v1)?"
                : "The server answered \(http.statusCode).")
            throw APIError.server(status: http.statusCode, message: message, fieldErrors: body?.fieldErrors ?? [:])
        }
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            #if DEBUG
            print("Decoding \(T.self) from \(request.url?.path() ?? "") failed:", error)
            #endif
            throw APIError.decoding(error)
        }
    }
}

enum DateParsing {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parse(_ string: String) -> Date? {
        fractional.date(from: string) ?? plain.date(from: string) ?? day.date(from: String(string.prefix(10)))
    }

    /// Formats a date as the `YYYY-MM-DD` string the server stores for purchase dates.
    static func dayString(_ date: Date) -> String {
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd"
        return local.string(from: date)
    }

    static func localDay(_ string: String?) -> Date? {
        guard let string, string.count >= 10 else { return nil }
        let local = DateFormatter()
        local.locale = Locale(identifier: "en_US_POSIX")
        local.dateFormat = "yyyy-MM-dd"
        return local.date(from: String(string.prefix(10)))
    }
}
