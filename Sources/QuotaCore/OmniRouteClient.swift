import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct OmniRouteEndpoint: Sendable {
    public let baseURL: URL

    public init(_ address: String) throws {
        var raw = address.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.contains("://") { raw = "http://" + raw }
        guard let parts = URLComponents(string: raw), parts.scheme == "http",
              let host = parts.host?.lowercased(),
              ["localhost", "127.0.0.1", "::1"].contains(host),
              parts.user == nil, parts.password == nil,
              parts.query == nil, parts.fragment == nil,
              parts.path == "" || parts.path == "/",
              (1...65535).contains(parts.port ?? 20128),
              let base = URL(string: "http://\(host == "::1" ? "[::1]" : host):\(parts.port ?? 20128)") else {
            throw QuotaError.invalidEndpoint
        }
        baseURL = base
    }

    public func url(for path: String) -> URL { baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) }
}

public struct OmniRouteCredentials: Sendable {
    public let apiKey: String
    public let cliToken: String

    public init(apiKey: String = "", cliToken: String = "") {
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.cliToken = cliToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Result of an explicit live refresh. An unsupported disabled connection (HTTP
/// 400/404) is skipped; other per-account failures are surfaced without losing
/// successfully refreshed cached quotas.
public struct OmniRouteManualRefreshResult: Sendable {
    public let accounts: [QuotaAccount]
    public let failedConnectionIDs: [String]
    public let bulkFailed: Bool

    public var warning: String? {
        guard bulkFailed || !failedConnectionIDs.isEmpty else { return nil }
        if bulkFailed && failedConnectionIDs.isEmpty {
            return "Enabled accounts could not be refreshed. Showing available cached quotas."
        }
        if !bulkFailed {
            return "\(failedConnectionIDs.count) account quota refresh\(failedConnectionIDs.count == 1 ? "" : "es") failed. Showing available cached quotas."
        }
        return "Some enabled and disabled account quotas could not be refreshed."
    }
}

public struct OmniRouteClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func load(from endpoint: OmniRouteEndpoint, credentials: OmniRouteCredentials) async throws -> [QuotaAccount] {
        async let providers = request(endpoint.url(for: "api/providers"), credentials: credentials)
        async let limits = request(endpoint.url(for: "api/usage/provider-limits"), credentials: credentials)
        return try QuotaParser.parse(providers: await providers, limits: await limits)
    }

    /// Explicit user action: bulk-refresh supported enabled connections through
    /// OmniRoute's rate-limit-aware scheduler, then individually refresh *all*
    /// disabled connections. The bulk API selects isActive=true and skips them.
    /// No account activation endpoint is called and automatic polling stays cached.
    public func refreshAll(
        from endpoint: OmniRouteEndpoint,
        credentials: OmniRouteCredentials
    ) async throws -> OmniRouteManualRefreshResult {
        let providerData = try await request(endpoint.url(for: "api/providers"), credentials: credentials)
        // Parse the same enabled/disabled flags as the normal cached load.
        let connections = try QuotaParser.parse(
            providers: providerData,
            limits: Data(#"{"caches":{}}"#.utf8)
        )
        let disabled = connections.filter { !$0.active }

        var failedConnectionIDs: [String] = []
        var bulkFailed = false
        var bulk = makeRequest(endpoint.url(for: "api/usage/provider-limits"), credentials: credentials)
        bulk.httpMethod = "POST"
        // OmniRoute's bulk sync spaces OAuth fetches to avoid provider rate limits.
        bulk.timeoutInterval = 180
        do {
            let data = try await request(bulk)
            if let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let errors = result["errors"] as? [String: String] {
                failedConnectionIDs += errors.keys.sorted()
            }
        } catch QuotaError.unauthorized {
            // A server-wide management auth error cannot be fixed by more calls.
            throw QuotaError.unauthorized
        } catch {
            bulkFailed = true
        }

        // These GETs trigger live, connection-scoped refreshes and persist quota
        // caches. Do not depend on showDisabledAccounts or UI hiding preferences.
        // Serialize calls to avoid bursts of upstream OAuth/token requests.
        for (index, account) in disabled.enumerated() {
            if index > 0 { try await Task.sleep(for: .milliseconds(1_500)) }
            let url = endpoint.url(for: "api/usage").appendingPathComponent(account.id)
            var perAccount = makeRequest(url, credentials: credentials)
            perAccount.timeoutInterval = 45
            do {
                _ = try await request(perAccount)
            } catch QuotaError.http(400), QuotaError.http(404) {
                // Unsupported/no-longer-present accounts have no quota endpoint.
            } catch {
                failedConnectionIDs.append(account.id)
            }
        }

        // Parse the final persisted cache; disabled quota values now appear even
        // if they were missing in the snapshot before the button was clicked.
        let cacheData = try await request(endpoint.url(for: "api/usage/provider-limits"), credentials: credentials)
        let accounts = try QuotaParser.parse(providers: providerData, limits: cacheData)
        return OmniRouteManualRefreshResult(
            accounts: accounts,
            failedConnectionIDs: Array(Set(failedConnectionIDs)).sorted(),
            bulkFailed: bulkFailed
        )
    }

    public func makeRequest(_ url: URL, credentials: OmniRouteCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        // Re-read OmniRoute's server-side quota cache on each click/poll. An
        // ephemeral URLSession can still keep its own HTTP cache in memory.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !credentials.apiKey.isEmpty { request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization") }
        if !credentials.cliToken.isEmpty { request.setValue(credentials.cliToken, forHTTPHeaderField: "x-omniroute-cli-token") }
        return request
    }

    private func request(_ url: URL, credentials: OmniRouteCredentials) async throws -> Data {
        try await request(makeRequest(url, credentials: credentials))
    }

    private func request(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else { throw QuotaError.http(0) }
        if response.statusCode == 401 || response.statusCode == 403 { throw QuotaError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw QuotaError.http(response.statusCode) }
        return data
    }
}
