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

    func testDisabledAccountsAreOptionalWithoutLosingCachedQuotas() throws {
        let providers = data(#"[{"id":"1","provider":"openai-codex","name":"Enabled","isActive":true},{"id":"2","provider":"kimi","name":"Disabled","isActive":false}]"#)
        let limits = data(#"{"caches":{"1":{"quotas":{"session":{"remainingPercentage":87}}},"2":{"quotas":{"weekly":{"remainingPercentage":31}}}}}"#)
        let accounts = try QuotaParser.parse(providers: providers, limits: limits, now: now)
        XCTAssertEqual(QuotaVisibility.visible(accounts, includeDisabled: false).map(\.name), ["Enabled"])
        let shown = QuotaVisibility.visible(accounts, includeDisabled: true)
        XCTAssertEqual(shown.count, 2)
        XCTAssertEqual(shown.first(where: { !$0.active })?.windows.first?.roundedRemaining, 31)
    }

    func testGroupsAccountsByProviderEvenWhenInterleaved() {
        let cached = QuotaWindow(id: "weekly", label: "wk", remainingPercent: 31, resetAt: nil)
        let accounts = [
            QuotaAccount(id: "1", name: "Work", provider: "openai-codex", active: true, windows: [], isStale: false),
            QuotaAccount(id: "2", name: "Main", provider: "kimi", active: true, windows: [], isStale: false),
            QuotaAccount(id: "3", name: "Personal", provider: "openai", active: false, windows: [cached], isStale: true)
        ]

        let groups = QuotaProviderGroup.grouped(accounts)
        XCTAssertEqual(groups.map(\.providerName), ["Kimi", "OpenAI"])
        XCTAssertEqual(groups.first(where: { $0.id == "OpenAI" })?.accounts.map(\.id), ["1", "3"])
        XCTAssertEqual(groups.first(where: { $0.id == "OpenAI" })?.accounts.last?.windows.first?.roundedRemaining, 31)
        XCTAssertEqual(
            QuotaProviderGroup.grouped(QuotaVisibility.visible(accounts, includeDisabled: false))
                .first(where: { $0.id == "OpenAI" })?.accounts.map(\.id), ["1"])
        XCTAssertTrue(QuotaProviderGroup.grouped([]).isEmpty)
    }

    func testReadsManagementKeyFromDotEnvWithoutLosingHashInsideQuotes() {
        XCTAssertEqual(OmniRouteEnvironment.apiKey(from: "OTHER=hello\nOMNIROUTE_API_KEY=sk-valid # comment"), "sk-valid")
        XCTAssertEqual(OmniRouteEnvironment.apiKey(from: "OMNIROUTE_API_KEY='sk-abc#def' # note"), "sk-abc#def")
        XCTAssertEqual(OmniRouteEnvironment.apiKey(from: "OMNIROUTE_API_KEY=sk-abc#def"), "sk-abc#def")
        XCTAssertEqual(OmniRouteEnvironment.apiKey(from: #"OMNIROUTE_API_KEY="sk-quoted""#), "sk-quoted")
        XCTAssertNil(OmniRouteEnvironment.apiKey(from: "OMNIROUTE_API_KEY_BACKUP=bad\n#OMNIROUTE_API_KEY=bad"))
        XCTAssertNil(OmniRouteEnvironment.apiKey(from: "OMNIROUTE_API_KEY= "))
        XCTAssertNil(OmniRouteEnvironment.apiKey(from: "OMNIROUTE_API_KEY='unterminated"))
    }

    func testMenuBarStatusUsesWorstActiveAccountNotDisabledOrUnlimited() {
        let accounts = [
            QuotaAccount(id: "a", name: "Work", provider: "openai", active: true, windows: [
                QuotaWindow(id: "week", label: "wk", remainingPercent: 81, resetAt: nil),
                QuotaWindow(id: "session", label: "sess", remainingPercent: 35, resetAt: nil)
            ], isStale: false),
            QuotaAccount(id: "b", name: "Personal", provider: "kimi", active: true, windows: [
                QuotaWindow(id: "session", label: "sess", remainingPercent: 8.9, resetAt: nil),
                QuotaWindow(id: "unlimited", label: "other", remainingPercent: 0, resetAt: nil, unlimited: true)
            ], isStale: false),
            QuotaAccount(id: "c", name: "Disabled", provider: "anthropic", active: false, windows: [
                QuotaWindow(id: "week", label: "wk", remainingPercent: 0, resetAt: nil)
            ], isStale: false)
        ]

        let status = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true, connectionUnavailable: false)
        XCTAssertEqual(status.severity, .critical)
        XCTAssertEqual(status.lowestPercent, 8)
        XCTAssertEqual(status.lowestAccount, "Personal")
        XCTAssertEqual(status.lowestProvider, "Kimi")
        XCTAssertEqual(status.lowAccountCount, 2) // Accounts, not quota windows.
        XCTAssertEqual(status.activeAccountCount, 2)
        XCTAssertEqual(status.measuredAccountCount, 2)
        XCTAssertTrue(status.description.contains("Critical quota: 8%"))
    }

    func testMenuBarStatusThresholds() {
        func status(_ remaining: Double) -> QuotaMenuStatus {
            let account = QuotaAccount(id: "1", name: "Main", provider: "kimi", active: true, windows: [
                QuotaWindow(id: "w", label: "wk", remainingPercent: remaining, resetAt: nil)
            ], isStale: false)
            return QuotaMenuStatus.evaluate(accounts: [account], hasLoaded: true, connectionUnavailable: false)
        }

        XCTAssertEqual(status(100).severity, .healthy)
        XCTAssertEqual(status(50).severity, .healthy)
        XCTAssertEqual(status(49.9).severity, .low)
        XCTAssertEqual(status(49.9).lowestPercent, 49)
        XCTAssertEqual(status(20).severity, .low)
        XCTAssertEqual(status(19.9).severity, .critical)
        XCTAssertEqual(status(0).lowestPercent, 0)
    }

    func testMenuBarStatusHandlesLoadingUnknownAndConnectionLoss() {
        let empty = [QuotaAccount]()
        XCTAssertEqual(QuotaMenuStatus.evaluate(accounts: empty, hasLoaded: false, connectionUnavailable: false).severity, .checking)
        XCTAssertEqual(QuotaMenuStatus.evaluate(accounts: empty, hasLoaded: true, connectionUnavailable: false).severity, .unknown)

        let withoutNumbers = QuotaAccount(id: "1", name: "Local", provider: "lm-studio", active: true, windows: [
            QuotaWindow(id: "unlimited", label: "mo", remainingPercent: 0, resetAt: nil, unlimited: true)
        ], isStale: false)
        let unknown = QuotaMenuStatus.evaluate(accounts: [withoutNumbers], hasLoaded: true, connectionUnavailable: false)
        XCTAssertEqual(unknown.severity, .unknown)
        XCTAssertNil(unknown.lowestPercent)

        let offline = QuotaMenuStatus.evaluate(accounts: empty, hasLoaded: false, connectionUnavailable: true)
        XCTAssertEqual(offline.severity, .unknown)
        XCTAssertTrue(offline.connectionUnavailable)
        XCTAssertTrue(offline.description.contains("connection unavailable"))
    }

    func testMenuBarStatusPreservesLastLowQuotaDuringRefreshError() {
        let account = QuotaAccount(id: "1", name: "Work", provider: "openai", active: true, windows: [
            QuotaWindow(id: "w", label: "wk", remainingPercent: 12, resetAt: nil)
        ], isStale: true)
        let status = QuotaMenuStatus.evaluate(accounts: [account], hasLoaded: true, connectionUnavailable: true)
        XCTAssertEqual(status.severity, .critical)
        XCTAssertEqual(status.lowestPercent, 12)
        XCTAssertTrue(status.connectionUnavailable)
        XCTAssertTrue(status.lowestIsStale)
        XCTAssertTrue(status.description.contains("Last known quotas"))
        XCTAssertTrue(status.description.contains("cached"))
    }

    func testQuotaDisplayToggleMatchesOriginalTray() {
        let window = QuotaWindow(id: "wk", label: "wk", remainingPercent: 64.0, resetAt: nil)
        XCTAssertEqual(window.displayedPercent(showUsed: false), 64.0)
        XCTAssertEqual(window.displayedPercent(showUsed: true), 36.0)
        XCTAssertEqual(window.displayedRoundedPercent(showUsed: false), 64)
        XCTAssertEqual(window.displayedRoundedPercent(showUsed: true), 36)

        let empty = QuotaWindow(id: "sess", label: "sess", remainingPercent: 0, resetAt: nil)
        XCTAssertEqual(empty.displayedRoundedPercent(showUsed: true), 100)
        let full = QuotaWindow(id: "sess", label: "sess", remainingPercent: 100, resetAt: nil)
        XCTAssertEqual(full.displayedRoundedPercent(showUsed: true), 0)
    }

    func testHideWithoutQuotaFiltersAccountsAndEmptyProviders() {
        let noQuota = QuotaAccount(id: "1", name: "No quota", provider: "anthropic", active: true, windows: [], isStale: false)
        let unlimited = QuotaAccount(id: "2", name: "Unlimited only", provider: "lm-studio", active: true, windows: [
            QuotaWindow(id: "unlimited", label: "mo", remainingPercent: 0, resetAt: nil, unlimited: true)
        ], isStale: false)
        let zeroQuota = QuotaAccount(id: "3", name: "Exhausted", provider: "kimi", active: true, windows: [
            QuotaWindow(id: "week", label: "wk", remainingPercent: 0, resetAt: nil)
        ], isStale: false)
        let inactive = QuotaAccount(id: "4", name: "Disabled", provider: "kimi", active: false, windows: [
            QuotaWindow(id: "week", label: "wk", remainingPercent: 70, resetAt: nil)
        ], isStale: true)
        let all = [noQuota, unlimited, zeroQuota, inactive]
        var prefs = QuotaDisplayPreferences()

        XCTAssertTrue(prefs.hideWithoutQuota)
        XCTAssertEqual(prefs.visibleGroups(from: all, includeDisabled: false).flatMap(\.accounts).map(\.id), ["3"])
        XCTAssertEqual(prefs.visibleGroups(from: all, includeDisabled: true).flatMap(\.accounts).map(\.id), ["3", "4"])

        prefs.hideWithoutQuota = false
        XCTAssertEqual(prefs.visibleGroups(from: all, includeDisabled: false).flatMap(\.accounts).count, 3)
        XCTAssertEqual(prefs.orderedGroups(from: all).flatMap(\.accounts).count, 4)
    }

    func testManualProviderAndAccountVisibilityDoesNotLoseSettingsEntries() {
        let accounts = [
            QuotaAccount(id: "1", name: "Work", provider: "openai", active: true, windows: [
                QuotaWindow(id: "wk", label: "wk", remainingPercent: 40, resetAt: nil)
            ], isStale: false),
            QuotaAccount(id: "2", name: "Personal", provider: "openai", active: true, windows: [
                QuotaWindow(id: "wk", label: "wk", remainingPercent: 77, resetAt: nil)
            ], isStale: false),
            QuotaAccount(id: "3", name: "Main", provider: "kimi", active: true, windows: [
                QuotaWindow(id: "wk", label: "wk", remainingPercent: 15, resetAt: nil)
            ], isStale: false)
        ]
        var prefs = QuotaDisplayPreferences()
        prefs.hiddenAccounts.insert(QuotaDisplayPreferences.accountKey(accounts[0]))
        XCTAssertEqual(prefs.visibleGroups(from: accounts, includeDisabled: true).flatMap(\.accounts).map(\.id), ["3", "2"])
        prefs.hiddenProviders.insert("OpenAI")
        XCTAssertEqual(prefs.visibleGroups(from: accounts, includeDisabled: true).map(\.id), ["Kimi"])
        XCTAssertEqual(prefs.orderedGroups(from: accounts).flatMap(\.accounts).count, 3)
        prefs.hiddenProviders.remove("OpenAI")
        prefs.hiddenAccounts.remove(QuotaDisplayPreferences.accountKey(accounts[0]))
        XCTAssertEqual(prefs.visibleGroups(from: accounts, includeDisabled: true).flatMap(\.accounts).count, 3)
    }

    func testCustomProviderAndAccountOrderSurvivesUpdatesAndSerialization() throws {
        let a = QuotaAccount(id: "1", name: "First", provider: "openai", active: true, windows: [], isStale: false)
        let b = QuotaAccount(id: "2", name: "Second", provider: "openai", active: true, windows: [], isStale: false)
        let c = QuotaAccount(id: "3", name: "Third", provider: "kimi", active: true, windows: [], isStale: false)
        let all = [a, b, c]
        var prefs = QuotaDisplayPreferences()
        XCTAssertFalse(prefs.moveProvider("Kimi", by: -2, among: all))
        XCTAssertTrue(prefs.moveProvider("OpenAI", by: -1, among: all))
        XCTAssertTrue(prefs.moveAccount(b, by: -1, among: all))
        XCTAssertFalse(prefs.moveAccount(b, by: -1, among: all))
        XCTAssertEqual(prefs.orderedGroups(from: all).map(\.id), ["OpenAI", "Kimi"])
        XCTAssertEqual(prefs.orderedGroups(from: all)[0].accounts.map(\.id), ["2", "1"])

        let encoded = try JSONEncoder().encode(prefs)
        let restored = try JSONDecoder().decode(QuotaDisplayPreferences.self, from: encoded)
        XCTAssertEqual(restored, prefs)

        let new = QuotaAccount(id: "4", name: "New", provider: "openai", active: true, windows: [], isStale: false)
        XCTAssertEqual(restored.orderedGroups(from: [new, a, c, b])[0].accounts.map(\.id), ["2", "1", "4"])

        var reset = restored
        reset.resetOrder()
        XCTAssertTrue(reset.providerOrder.isEmpty)
        XCTAssertTrue(reset.accountOrder.isEmpty)
        XCTAssertEqual(reset.orderedGroups(from: all).map(\.id), ["Kimi", "OpenAI"])
    }

    func testProviderAndConnectionKeysAvoidAmbiguity() {
        let a = QuotaAccount(id: "bc", name: "A", provider: "a", active: true, windows: [], isStale: false)
        let b = QuotaAccount(id: "c", name: "B", provider: "ab", active: true, windows: [], isStale: false)
        XCTAssertNotEqual(QuotaDisplayPreferences.accountKey(a), QuotaDisplayPreferences.accountKey(b))
    }

    func testStaleEntryAndClamp() throws {
        let accounts = try QuotaParser.parse(providers: data(#"[{"id":"a","provider":"kimi"}]"#),
            limits: data(#"{"caches":{"a":{"fetchedAt":"2026-10-26T06:00:00Z","quotas":{"window_5h":{"remainingPercentage":120}}}}}"#), now: now)
        XCTAssertTrue(accounts[0].isStale)
        XCTAssertEqual(accounts[0].windows[0].roundedRemaining, 100)
    }
}
