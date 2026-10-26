import XCTest
@testable import QuotaCore

final class QuotaCoreTests: XCTestCase {
    private func data(_ text: String) -> Data { Data(text.utf8) }
    private let now = ISO8601DateFormatter().date(from: "2026-10-26T10:00:00Z")!

    func testReadsAllAccountsWithDifferentWindowFormats() throws {
        let providers = data(#"{"connections":[{"id":"c1","name":"work@example.com","provider":"openai-codex","isActive":true},{"id":"c2","name":"Personal","provider":"antigravity","isActive":false}]}"#)
        let limits = data(#"{"caches":{"c1":{"fetchedAt":"2026-10-26T09:59:00Z","quotas":{"session (5h)":{"remainingPercentage":64,"resetAt":"2026-10-26T14:59:00Z"},"weekly (7d)":{"used":10,"total":100,"resetAt":"2026-11-02T10:00:00Z"}}},"c2":{"quotas":{"window_1d":{"remainingPercentage":31}}}}}"#)
        let accounts = try QuotaParser.parse(providers: providers, limits: limits, now: now)
        XCTAssertEqual(accounts.count, 2)
        XCTAssertEqual(accounts[0].providerName, "Antigravity")
        XCTAssertFalse(accounts[0].active)
        XCTAssertEqual(accounts[0].windows[0].label, "1d")
        XCTAssertEqual(accounts[1].windows.map(\.label), ["sess", "wk"])
        XCTAssertEqual(accounts[1].windows.map(\.roundedRemaining), [64, 90])
        XCTAssertFalse(accounts[1].isStale)
        XCTAssertEqual(accounts[1].windows[0].countdown(from: now), "4h59m")
    }

    func testPerModelLimitsUseLowestRemainingByResetTime() throws {
        let providers = data(#"[{"id":"1","provider":"antigravity","name":"Main"}]"#)
        let limits = data(#"{"caches":{"1":{"quotas":{"gemini-pro":{"remainingPercentage":87,"resetAt":"2026-10-26T15:00:00Z"},"claude-sonnet":{"remainingPercentage":43,"resetAt":"2026-10-26T15:00:00Z"},"gemini-flash":{"remainingPercentage":100,"resetAt":"2026-10-28T11:00:00Z"}}}}}"#)
        let windows = try QuotaParser.parse(providers: providers, limits: limits, now: now)[0].windows
        XCTAssertEqual(windows.count, 2)
        XCTAssertEqual(windows.map(\.roundedRemaining), [43, 100])
        XCTAssertEqual(windows.map(\.label), ["5h", "1d"])
    }

    func testMissingQuotaDoesNotInventFullBar() throws {
        let accounts = try QuotaParser.parse(
            providers: data(#"[{"id":"one","provider":"kimi"}]"#),
            limits: data(#"{"caches":{"one":{"quotas":{"session":{"message":"timed out"}}}}}"#),
            now: now)
        XCTAssertTrue(accounts[0].windows.isEmpty)
    }

    func testMalformedResponseIsNotReportedAsEmptyAccounts() {
        XCTAssertThrowsError(try QuotaParser.parse(providers: data(#"{"oops":true}"#), limits: data(#"{"caches":{}}"#))) { error in
            XCTAssertEqual(error as? QuotaError, .invalidProviders)
        }
        XCTAssertThrowsError(try QuotaParser.parse(providers: data("[]"), limits: data("{}"))) { error in
            XCTAssertEqual(error as? QuotaError, .invalidCache)
        }
    }

    func testOnlyLoopbackServerCanReceiveCredentials() throws {
        XCTAssertEqual(try OmniRouteEndpoint("localhost:20128").url(for: "api/providers").absoluteString, "http://localhost:20128/api/providers")
        for invalid in ["https://example.com", "http://192.168.1.1:20128", "http://127.0.0.1@other.com:20128", "file:///tmp/secret", "http://localhost:20128/api"] {
            XCTAssertThrowsError(try OmniRouteEndpoint(invalid), invalid)
        }
        let client = OmniRouteClient()
        let req = client.makeRequest(try OmniRouteEndpoint("127.0.0.1:20128").url(for: "api/providers"), credentials: .init(apiKey: "sk-test", cliToken: "token"))
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
        XCTAssertEqual(req.value(forHTTPHeaderField: "x-omniroute-cli-token"), "token")
    }

    func testStaleEntryAndClamp() throws {
        let accounts = try QuotaParser.parse(providers: data(#"[{"id":"a","provider":"kimi"}]"#),
            limits: data(#"{"caches":{"a":{"fetchedAt":"2026-10-26T06:00:00Z","quotas":{"window_5h":{"remainingPercentage":120}}}}}"#), now: now)
        XCTAssertTrue(accounts[0].isStale)
        XCTAssertEqual(accounts[0].windows[0].roundedRemaining, 100)
    }
}
