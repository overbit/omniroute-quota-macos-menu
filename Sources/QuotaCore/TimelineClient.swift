import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A per-request delegate refuses every redirect before credentials can be sent
/// elsewhere. The ephemeral default session never persists timeline payloads.
final class TimelineRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest,
                    completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public struct TimelineClient: @unchecked Sendable {
    private let session: URLSession
    public init(session: URLSession = URLSession(configuration: .ephemeral)) { self.session = session }

    public func load(from endpoint: OmniRouteEndpoint, credentials: OmniRouteCredentials) async throws -> [TimelineRequest] {
        var parts = URLComponents(url: endpoint.url(for: "api/usage/call-logs"), resolvingAgainstBaseURL: false)!
        parts.queryItems = [URLQueryItem(name: "limit", value: "200")]
        let request = OmniRouteClient(session: session).makeRequest(parts.url!, credentials: credentials)
        do {
            let (data, response) = try await session.data(for: request, delegate: TimelineRedirectPolicy())
            guard let http = response as? HTTPURLResponse else { throw TimelineFailure.unavailable }
            switch http.statusCode {
            case 300..<400, 401, 403: throw TimelineFailure.authenticationRequired
            case 404: throw TimelineFailure.unsupported
            case 200..<300: break
            default: throw TimelineFailure.unavailable
            }
            let type = http.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
            if type.contains("text/html") || String(data: data.prefix(256), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("<") == true {
                throw TimelineFailure.authenticationRequired
            }
            return try TimelineParser.parse(data)
        } catch is CancellationError { throw CancellationError() }
        catch let error as URLError where error.code == .cancelled { throw CancellationError() }
        catch let error as TimelineFailure { throw error }
        catch { throw TimelineFailure.unavailable }
    }
}
