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

public struct OmniRouteClient {
    private let session: URLSession

    public init(session: URLSession = .shared) { self.session = session }

    public func load(from endpoint: OmniRouteEndpoint, credentials: OmniRouteCredentials) async throws -> [QuotaAccount] {
        async let providers = request(endpoint.url(for: "api/providers"), credentials: credentials)
        async let limits = request(endpoint.url(for: "api/usage/provider-limits"), credentials: credentials)
        return try QuotaParser.parse(providers: await providers, limits: await limits)
    }

    public func makeRequest(_ url: URL, credentials: OmniRouteCredentials) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !credentials.apiKey.isEmpty { request.setValue("Bearer \(credentials.apiKey)", forHTTPHeaderField: "Authorization") }
        if !credentials.cliToken.isEmpty { request.setValue(credentials.cliToken, forHTTPHeaderField: "x-omniroute-cli-token") }
        return request
    }

    private func request(_ url: URL, credentials: OmniRouteCredentials) async throws -> Data {
        let (data, response) = try await session.data(for: makeRequest(url, credentials: credentials))
        guard let response = response as? HTTPURLResponse else { throw QuotaError.http(0) }
        if response.statusCode == 401 || response.statusCode == 403 { throw QuotaError.unauthorized }
        guard (200..<300).contains(response.statusCode) else { throw QuotaError.http(response.statusCode) }
        return data
    }
}
