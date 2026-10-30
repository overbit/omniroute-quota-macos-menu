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
        XCTAssertEqual(req.cachePolicy, .reloadIgnoringLocalCacheData)
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

    func testFiveThemeNamesAndPersistence() throws {
        let themes = QuotaTheme.allCases
        XCTAssertEqual(themes, [.oled, .midnight, .forest, .dusk, .paper])
        XCTAssertEqual(Set(themes.map(\.displayName)).count, 5)
        XCTAssertEqual(Set(themes.map(\.tokens.background)).count, 5)
        XCTAssertTrue(QuotaTheme.paper.isLight)
        XCTAssertTrue(themes.filter(\.isLight).count == 1)
        // Legacy Graphite selections automatically resolve to OLED.
        XCTAssertEqual(QuotaTheme(rawValue: "graphite"), .oled)
        XCTAssertEqual(QuotaTheme.oled.rawValue, "graphite")
        XCTAssertEqual(QuotaTheme.oled.displayName, "OLED")
        XCTAssertFalse(themes.map(\.displayName).contains("Graphite"))
        XCTAssertEqual(QuotaTheme.oled.tokens.background, 0x000000)
        XCTAssertNotEqual(QuotaTheme.oled.tokens.background, QuotaTheme.oled.tokens.raised)
        XCTAssertEqual(QuotaTheme.paper.tokens.background, 0xF5F7FA)
        XCTAssertEqual(QuotaTheme.paper.tokens.raised, 0xFFFFFF)
        let priorChoice = try JSONDecoder().decode(QuotaTheme.self, from: Data(#""graphite""#.utf8))
        XCTAssertEqual(priorChoice, .oled)
        XCTAssertNil(QuotaTheme(rawValue: "unknown"))

        for theme in themes {
            let restored = try JSONDecoder().decode(QuotaTheme.self, from: JSONEncoder().encode(theme))
            XCTAssertEqual(restored, theme)
        }
    }

    func testThemeColorsRemainReadableAcrossBackgroundsAndControls() {
        func luminance(_ rgb: UInt32) -> Double {
            func linear(_ byte: UInt32) -> Double {
                let value = Double(byte) / 255
                return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear((rgb >> 16) & 0xFF)
                + 0.7152 * linear((rgb >> 8) & 0xFF)
                + 0.0722 * linear(rgb & 0xFF)
        }
        func contrast(_ first: UInt32, _ second: UInt32) -> Double {
            let bright = max(luminance(first), luminance(second))
            let dark = min(luminance(first), luminance(second))
            return (bright + 0.05) / (dark + 0.05)
        }

        for theme in QuotaTheme.allCases {
            let colors = theme.tokens
            for background in [colors.background, colors.raised] {
                for foreground in [colors.text, colors.muted, colors.faint,
                                   colors.good, colors.warning, colors.bad, colors.accent] {
                    XCTAssertGreaterThanOrEqual(contrast(foreground, background), 4.5,
                                                "\(theme.displayName): \(String(foreground, radix: 16)) lacks readable contrast")
                }
            }
            XCTAssertGreaterThanOrEqual(contrast(colors.text, colors.background), 7.0,
                                        "\(theme.displayName): primary text should have strong contrast")
        }
    }

    func testMenuBarPreferencesKeepExistingAllActiveBehavior() {
        let accounts = [
            QuotaAccount(id: "work", name: "Work", provider: "openai-codex", active: true,
                         windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 52, resetAt: nil)], isStale: false),
            QuotaAccount(id: "paused", name: "Paused", provider: "kimi", active: false,
                         windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 0, resetAt: nil)], isStale: false),
        ]
        let prefs = QuotaMenuPreferences()
        XCTAssertEqual(prefs.mode, .dynamic)
        XCTAssertEqual(prefs.scope, .allActive)
        XCTAssertEqual(prefs.monitoredAccounts(from: accounts).map(\.id), ["work"])
        let status = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true,
                                              connectionUnavailable: false, preferences: prefs)
        XCTAssertEqual(status.severity, .healthy)
        XCTAssertEqual(status.lowestPercent, 52)
    }

    func testStaticMenuBarSuppressesLowQuotaAndConnectionWarnings() {
        var prefs = QuotaMenuPreferences()
        prefs.mode = .staticIcon
        let empty = QuotaMenuStatus.evaluate(accounts: [], hasLoaded: false,
                                             connectionUnavailable: true, preferences: prefs)
        XCTAssertEqual(empty.severity, .staticIcon)
        XCTAssertFalse(empty.isLow)
        XCTAssertFalse(empty.connectionUnavailable)
        XCTAssertNil(empty.lowestPercent)
        XCTAssertTrue(empty.description.contains("Quota warnings are disabled"))

        let exhausted = QuotaAccount(id: "a", name: "Exhausted", provider: "kimi", active: true,
                                     windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 0, resetAt: nil)], isStale: false)
        let staticWithZero = QuotaMenuStatus.evaluate(accounts: [exhausted], hasLoaded: true,
                                                      connectionUnavailable: false, preferences: prefs)
        XCTAssertEqual(staticWithZero.severity, .staticIcon)
        XCTAssertFalse(staticWithZero.isLow)
    }

    func testDynamicMenuBarSelectsProvidersAndAccountsIndependentlyOfDisplayFilters() {
        let openAI = QuotaAccount(id: "a", name: "main", provider: "openai-codex", active: true,
                                  windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 75, resetAt: nil)], isStale: false)
        let disabled = QuotaAccount(id: "b", name: "disabled", provider: "openai", active: false,
                                    windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 0, resetAt: nil)], isStale: false)
        let kimi = QuotaAccount(id: "c", name: "main", provider: "kimi", active: true,
                                windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 5, resetAt: nil)], isStale: false)
        let accounts = [openAI, disabled, kimi]
        var prefs = QuotaMenuPreferences()
        prefs.scope = .selected

        // With no selected accounts, 0% elsewhere must not trigger a warning.
        XCTAssertEqual(QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true,
                                                  connectionUnavailable: false,
                                                  preferences: prefs).severity, .unknown)

        prefs.selectProvider("OpenAI", selected: true)
        XCTAssertEqual(prefs.monitoredAccounts(from: accounts).map(\.id), ["a", "b"])
        var status = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true,
                                              connectionUnavailable: false, preferences: prefs)
        XCTAssertEqual(status.severity, .critical)
        XCTAssertEqual(status.lowestPercent, 0)
        XCTAssertEqual(status.lowestAccount, "disabled")

        prefs.selectProvider("OpenAI", selected: false)
        prefs.selectAccount(openAI, selected: true)
        XCTAssertEqual(prefs.monitoredAccounts(from: accounts).map(\.id), ["a"])
        status = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true,
                                          connectionUnavailable: false, preferences: prefs)
        XCTAssertEqual(status.severity, .healthy)
        XCTAssertEqual(status.lowestPercent, 75)

        // A hidden account still counts for alerts; display settings never filter alerts.
        var display = QuotaDisplayPreferences()
        display.hiddenAccounts.insert(QuotaDisplayPreferences.accountKey(kimi))
        prefs.selectAccount(kimi, selected: true)
        XCTAssertFalse(display.visibleGroups(from: accounts, includeDisabled: false)
                        .flatMap(\.accounts).contains(where: { $0.id == kimi.id }))
        status = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true,
                                          connectionUnavailable: false, preferences: prefs)
        XCTAssertEqual(status.lowestAccount, kimi.name)
        XCTAssertEqual(status.lowestPercent, 5)
    }

    func testMenuBarProviderSelectionIncludesFutureConnectionsAndHandlesMissingQuota() {
        var prefs = QuotaMenuPreferences()
        prefs.scope = .selected
        prefs.selectProvider("Kimi", selected: true)
        let unknown = QuotaAccount(id: "without", name: "missing", provider: "kimi", active: false,
                                   windows: [], isStale: false)
        let unlimited = QuotaAccount(id: "unlimited", name: "unlimited", provider: "kimi", active: true,
                                     windows: [QuotaWindow(id: "mo", label: "mo", remainingPercent: 100,
                                                           resetAt: nil, unlimited: true)], isStale: false)
        let full = QuotaAccount(id: "new", name: "new", provider: "kimi", active: true,
                                windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 23, resetAt: nil)], isStale: false)
        let others = QuotaAccount(id: "other", name: "other", provider: "openai", active: true,
                                  windows: [QuotaWindow(id: "wk", label: "wk", remainingPercent: 1, resetAt: nil)], isStale: false)
        let accounts = [unknown, unlimited, full, others]
        let status = QuotaMenuStatus.evaluate(accounts: accounts, hasLoaded: true,
                                              connectionUnavailable: false, preferences: prefs)
        XCTAssertEqual(prefs.monitoredAccounts(from: accounts).map(\.id), ["without", "unlimited", "new"])
        XCTAssertEqual(status.severity, .low)
        XCTAssertEqual(status.lowestPercent, 23)
        XCTAssertEqual(status.measuredAccountCount, 1)
        XCTAssertTrue(status.description.contains("2 monitored accounts have no reported quota"))
    }

    func testMenuBarPreferencesPersistModeScopeAndSelectionAcrossRenames() throws {
        let account = QuotaAccount(id: "unique", name: "main", provider: "openai-codex",
                                   active: true, windows: [], isStale: false)
        var prefs = QuotaMenuPreferences()
        prefs.mode = .staticIcon
        prefs.scope = .selected
        prefs.selectProvider("Kimi", selected: true)
        prefs.selectAccount(account, selected: true)

        let persisted = try JSONDecoder().decode(QuotaMenuPreferences.self,
                                                 from: JSONEncoder().encode(prefs))
        XCTAssertEqual(persisted, prefs)
        let renamed = QuotaAccount(id: "unique", name: "renamed", provider: "openai-codex",
                                   active: false, windows: [], isStale: true)
        XCTAssertTrue(persisted.monitors(renamed))
        XCTAssertFalse(persisted.monitors(QuotaAccount(id: "other", name: "renamed", provider: "openai-codex",
                                                       active: true, windows: [], isStale: false)))
        prefs.selectAccount(account, selected: false)
        XCTAssertFalse(prefs.monitors(renamed))
        prefs.mode = .dynamic
        XCTAssertTrue(prefs.monitors(QuotaAccount(id: "new", name: "new", provider: "kimi",
                                                  active: true, windows: [], isStale: false)))
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

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Mock only the local OmniRoute HTTP boundary, not the client's parsing.
private final class StubOmniRouteURLProtocol: URLProtocol {
    static var responder: ((URLRequest) -> (Int, Data))?
    static var requests: [(String, String)] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let requestURL = request.url, let responder = Self.responder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        Self.requests.append((request.httpMethod ?? "GET", requestURL.path))
        let (status, data) = responder(request)
        let response = HTTPURLResponse(url: requestURL, statusCode: status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class QuotaRefreshTests: XCTestCase {
    private func data(_ json: String) -> Data { Data(json.utf8) }

    override func tearDown() {
        StubOmniRouteURLProtocol.responder = nil
        StubOmniRouteURLProtocol.requests = []
        super.tearDown()
    }

    func testManualRefreshUpdatesDisabledAccountWithoutEnablingIt() async throws {
        let providers = data(#"[{"id":"enabled","name":"Active","provider":"kimi","isActive":true},{"id":"disabled","name":"Paused","provider":"openai-codex","isActive":false}]"#)
        let before = data(#"{"caches":{"enabled":{"quotas":{"session":{"remainingPercentage":45}}}}}"#)
        let after = data(#"{"caches":{"enabled":{"quotas":{"session":{"remainingPercentage":91}}},"disabled":{"quotas":{"session":{"remainingPercentage":74}}}}}"#)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubOmniRouteURLProtocol.self]
        let client = OmniRouteClient(session: URLSession(configuration: config))
        var updated = false
        StubOmniRouteURLProtocol.responder = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "x-omniroute-cli-token"), "token")
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/providers"):
                return (200, providers)
            case ("POST", "/api/usage/provider-limits"):
                return (200, self.data(#"{"errors":{}}"#))
            case ("GET", "/api/usage/disabled"):
                updated = true
                return (200, self.data(#"{"quotas":{"session":{"remainingPercentage":74}}}"#))
            case ("GET", "/api/usage/provider-limits"):
                return (200, updated ? after : before)
            default:
                XCTFail("Unexpected endpoint: \(request.httpMethod ?? "") \(request.url?.path ?? "")")
                return (404, self.data("{}"))
            }
        }

        let credentials = OmniRouteCredentials(apiKey: "sk-test", cliToken: "token")
        let result = try await client.refreshAll(from: OmniRouteEndpoint("127.0.0.1:20128"), credentials: credentials)
        XCTAssertTrue(updated)
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.accounts.first(where: { $0.id == "disabled" })?.windows.first?.roundedRemaining, 74)
        XCTAssertEqual(result.accounts.first(where: { $0.id == "enabled" })?.windows.first?.roundedRemaining, 91)
        XCTAssertEqual(result.accounts.first(where: { $0.id == "disabled" })?.active, false)
        XCTAssertEqual(StubOmniRouteURLProtocol.requests.map { "\($0.0) \($0.1)" }, [
            "GET /api/providers", "POST /api/usage/provider-limits",
            "GET /api/usage/disabled", "GET /api/usage/provider-limits"
        ])
    }

    func testUnsupportedDisabledAccountDoesNotBlockOtherCacheUpdates() async throws {
        let providers = data(#"[{"id":"disabled","provider":"lm-studio","isActive":false},{"id":"enabled","provider":"kimi","isActive":true}]"#)
        let limits = data(#"{"caches":{"enabled":{"quotas":{"weekly":{"remainingPercentage":50}}}}}"#)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubOmniRouteURLProtocol.self]
        let client = OmniRouteClient(session: URLSession(configuration: config))
        StubOmniRouteURLProtocol.responder = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/providers"): return (200, providers)
            case ("POST", "/api/usage/provider-limits"): return (200, self.data(#"{"errors":{}}"#))
            case ("GET", "/api/usage/disabled"): return (400, self.data(#"{"error":"Unsupported"}"#))
            case ("GET", "/api/usage/provider-limits"): return (200, limits)
            default: return (404, self.data("{}"))
            }
        }
        let result = try await client.refreshAll(from: OmniRouteEndpoint("localhost"), credentials: .init())
        XCTAssertNil(result.warning)
        XCTAssertEqual(result.accounts.count, 2)
        XCTAssertEqual(result.accounts.first(where: { $0.id == "enabled" })?.windows.first?.roundedRemaining, 50)
        XCTAssertTrue(result.accounts.first(where: { $0.id == "disabled" })?.windows.isEmpty ?? false)
    }

    func testDisabledStillRefreshesWhenBulkSyncFails() async throws {
        let providers = data(#"[{"id":"enabled","provider":"kimi","isActive":true},{"id":"disabled","provider":"openai-codex","isActive":false}]"#)
        let cache = data(#"{"caches":{"disabled":{"quotas":{"session":{"remainingPercentage":63}}}}}"#)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubOmniRouteURLProtocol.self]
        let client = OmniRouteClient(session: URLSession(configuration: config))
        StubOmniRouteURLProtocol.responder = { request in
            switch (request.httpMethod ?? "", request.url?.path ?? "") {
            case ("GET", "/api/providers"): return (200, providers)
            case ("POST", "/api/usage/provider-limits"): return (500, self.data(#"{"error":"sync failed"}"#))
            case ("GET", "/api/usage/disabled"): return (200, self.data(#"{"quotas":{"session":{"remainingPercentage":63}}}"#))
            case ("GET", "/api/usage/provider-limits"): return (200, cache)
            default:
                XCTFail("Unexpected refresh request")
                return (404, self.data("{}"))
            }
        }
        let result = try await client.refreshAll(from: OmniRouteEndpoint("localhost"), credentials: .init())
        XCTAssertTrue(result.bulkFailed)
        XCTAssertNotNil(result.warning)
        XCTAssertEqual(result.accounts.first(where: { $0.id == "disabled" })?.windows.first?.roundedRemaining, 63)
        XCTAssertEqual(result.accounts.first(where: { $0.id == "disabled" })?.active, false)
        XCTAssertTrue(StubOmniRouteURLProtocol.requests.contains { $0.0 == "GET" && $0.1 == "/api/usage/disabled" })
    }

    func testAutomaticCachedLoadDoesNotTriggerLiveRequests() async throws {
        let providers = data(#"[{"id":"disabled","provider":"kimi","isActive":false}]"#)
        let limits = data(#"{"caches":{"disabled":{"quotas":{"session":{"remainingPercentage":38}}}}}"#)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubOmniRouteURLProtocol.self]
        let client = OmniRouteClient(session: URLSession(configuration: config))
        StubOmniRouteURLProtocol.responder = { request in
            switch request.url?.path ?? "" {
            case "/api/providers": return (200, providers)
            case "/api/usage/provider-limits": return (200, limits)
            default: return (404, self.data("{}"))
            }
        }
        let result = try await client.load(from: OmniRouteEndpoint("localhost"), credentials: .init())
        XCTAssertEqual(result.first?.windows.first?.roundedRemaining, 38)
        XCTAssertEqual(StubOmniRouteURLProtocol.requests.count, 2)
        XCTAssertTrue(StubOmniRouteURLProtocol.requests.allSatisfy { $0.0 == "GET" })
    }
}
