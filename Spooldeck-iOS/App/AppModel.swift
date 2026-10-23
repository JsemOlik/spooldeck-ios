import Foundation
import Observation

/// App-wide state: which server we talk to, whether we're signed in, and a data version that
/// screens watch to reload after any mutation.
@Observable
final class AppModel {
    enum Phase: Equatable {
        case needsServer
        case needsLogin
        case signedIn
    }

    private(set) var phase: Phase = .needsServer
    private(set) var serverURL: URL?
    private(set) var username: String?
    private(set) var api: APIClient
    /// Bumped after every successful mutation so lists and details refetch.
    private(set) var dataVersion = 0
    /// Spool ids to open in the label designer, shown as a sheet from the root.
    var labelSpoolIds: [Int]?

    private let defaults = UserDefaults.standard

    init() {
        let placeholder = URL(string: "https://localhost")!
        api = APIClient(baseURL: placeholder)
        if let saved = defaults.string(forKey: "serverURL"), let url = URL(string: saved) {
            serverURL = url
            api = APIClient(baseURL: url)
            if let token = Self.debugToken ?? Keychain.read(account: url.absoluteString) {
                api.token = token
                username = defaults.string(forKey: "username")
                phase = .signedIn
            } else {
                phase = .needsLogin
            }
        }
        api.onUnauthorized = { [weak self] in self?.handleUnauthorized() }
    }

    var token: String? { api.token }

    /// Debug builds accept `-serverURL <url> -debugToken <token>` launch arguments, so UI tests
    /// and screenshots can start signed in.
    private static var debugToken: String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: "debugToken")
        #else
        nil
        #endif
    }

    // MARK: - Onboarding

    /// Normalises user input into a server URL ("spools.example.com" → "https://spools.example.com").
    static func normalizeServerURL(_ input: String) -> URL? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if !text.contains("://") { text = "https://" + text }
        while text.hasSuffix("/") { text.removeLast() }
        guard let url = URL(string: text), let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil else {
            return nil
        }
        return url
    }

    func connect(to input: String) async throws {
        guard let url = Self.normalizeServerURL(input) else { throw APIError.invalidServer }
        let client = APIClient(baseURL: url)
        try await client.checkHealth()
        client.onUnauthorized = { [weak self] in self?.handleUnauthorized() }
        api = client
        serverURL = url
        defaults.set(url.absoluteString, forKey: "serverURL")
        phase = .needsLogin
    }

    func signIn(username: String, password: String) async throws {
        let response: LoginResponse = try await api.post("auth/login", body: ["username": username, "password": password])
        store(token: response.token)
        self.username = response.user.username
        defaults.set(response.user.username, forKey: "username")
        phase = .signedIn
    }

    /// Replaces the stored token, e.g. after a password change signs every session out.
    func store(token: String) {
        api.token = token
        if let serverURL { Keychain.save(token, account: serverURL.absoluteString) }
    }

    func signOut(everywhere: Bool = false) async {
        if api.token != nil {
            let path = everywhere ? "auth/logout-everywhere" : "auth/logout"
            _ = try? await api.post(path) as MutationResult
        }
        clearSession()
    }

    func changeServer() {
        clearSession()
        serverURL = nil
        defaults.removeObject(forKey: "serverURL")
        phase = .needsServer
    }

    func didMutate() {
        dataVersion += 1
    }

    private func handleUnauthorized() {
        guard phase == .signedIn else { return }
        clearSession()
    }

    private func clearSession() {
        if let serverURL { Keychain.delete(account: serverURL.absoluteString) }
        api.token = nil
        username = nil
        defaults.removeObject(forKey: "username")
        if serverURL != nil { phase = .needsLogin }
    }
}
