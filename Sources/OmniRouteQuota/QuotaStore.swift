#if os(macOS)
import Foundation
import QuotaCore
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var accounts: [QuotaAccount] = []
    @Published private(set) var refreshing = false
    @Published private(set) var forcingRefresh = false
    @Published private(set) var refreshWarning: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var showingSettings = false
    @Published var showDisabledAccounts = UserDefaults.standard.bool(forKey: "showDisabledAccounts") {
        didSet { UserDefaults.standard.set(showDisabledAccounts, forKey: "showDisabledAccounts") }
    }

    @Published var displayPreferences: QuotaDisplayPreferences = {
        guard let data = UserDefaults.standard.data(forKey: "quotaDisplayPreferences"),
              let saved = try? JSONDecoder().decode(QuotaDisplayPreferences.self, from: data) else {
            return QuotaDisplayPreferences()
        }
        return saved
    }() {
        didSet {
            if let data = try? JSONEncoder().encode(displayPreferences) {
                UserDefaults.standard.set(data, forKey: "quotaDisplayPreferences")
            }
        }
    }

    private let client = OmniRouteClient(session: URLSession(configuration: .ephemeral))
    private var polling: Task<Void, Never>?

    var address: String = UserDefaults.standard.string(forKey: "omnirouteAddress") ?? "127.0.0.1:20128"
    var apiKey: String = LocalCredentials.read("apiKey")
    var tokenOverride: String = LocalCredentials.read("cliToken")

    init() {
        // Keep the status item live from launch, even if its popover is never opened.
        Task { [weak self] in self?.start() }
    }

    var connected: Bool { lastUpdated != nil && errorMessage == nil }
    var providerCount: Int { Set(accounts.map(\.provider)).count }
    var activeProviderCount: Int { Set(accounts.filter(\.active).map(\.provider)).count }
    var activeCount: Int { accounts.filter(\.active).count }
    var settingsGroups: [QuotaProviderGroup] { displayPreferences.orderedGroups(from: accounts) }
    var visibleGroups: [QuotaProviderGroup] {
        displayPreferences.visibleGroups(from: accounts, includeDisabled: showDisabledAccounts)
    }
    var visibleAccounts: [QuotaAccount] { visibleGroups.flatMap(\.accounts) }
    var visibleProviderCount: Int { visibleGroups.count }
    var lowestRemaining: Double? { accounts.filter(\.active).compactMap(\.lowestRemaining).min() }

    var menuBarStatus: QuotaMenuStatus {
        QuotaMenuStatus.evaluate(
            accounts: accounts,
            hasLoaded: lastUpdated != nil,
            connectionUnavailable: errorMessage != nil
        )
    }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refresh(force: Bool = false) async {
        guard !refreshing else { return }
        refreshing = true
        forcingRefresh = force
        defer {
            refreshing = false
            forcingRefresh = false
        }
        do {
            let endpoint = try OmniRouteEndpoint(address)
            let credentials = OmniRouteCredentials(
                apiKey: apiKey.isEmpty ? LocalCredentials.automaticAPIKey() : apiKey,
                cliToken: tokenOverride.isEmpty ? LocalCredentials.automaticToken() : tokenOverride)

            if force {
                // Only the explicit Refresh button triggers upstream quota probes.
                // The server's bulk refresh skips disabled accounts, so refresh
                // those via the individual endpoint before reading the new cache.
                let result = try await client.refreshAll(from: endpoint, credentials: credentials)
                accounts = result.accounts
                refreshWarning = result.warning
            } else {
                // Cheap polling always reads cached quotas, including disabled
                // accounts previously refreshed by an explicit user action.
                accounts = try await client.load(from: endpoint, credentials: credentials)
            }
            lastUpdated = Date()
            errorMessage = nil
        } catch {
            if force { refreshWarning = nil }
            errorMessage = error.localizedDescription
        }
    }

    func save(address: String, apiKey: String, tokenOverride: String) throws {
        _ = try OmniRouteEndpoint(address)
        let cleanKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanToken = tokenOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        try LocalCredentials.save(cleanKey, account: "apiKey")
        try LocalCredentials.save(cleanToken, account: "cliToken")
        self.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = cleanKey
        self.tokenOverride = cleanToken
        UserDefaults.standard.set(self.address, forKey: "omnirouteAddress")
        showingSettings = false
        Task { await refresh() }
    }

    func setProviderVisible(_ providerID: String, visible: Bool) {
        var updated = displayPreferences
        if visible { updated.hiddenProviders.remove(providerID) }
        else { updated.hiddenProviders.insert(providerID) }
        displayPreferences = updated
    }

    func setAccountVisible(_ account: QuotaAccount, visible: Bool) {
        var updated = displayPreferences
        let key = QuotaDisplayPreferences.accountKey(account)
        if visible { updated.hiddenAccounts.remove(key) }
        else { updated.hiddenAccounts.insert(key) }
        displayPreferences = updated
    }

    func moveProvider(_ providerID: String, by offset: Int) {
        var updated = displayPreferences
        guard updated.moveProvider(providerID, by: offset, among: accounts) else { return }
        displayPreferences = updated
    }

    func moveAccount(_ account: QuotaAccount, by offset: Int) {
        var updated = displayPreferences
        guard updated.moveAccount(account, by: offset, among: accounts) else { return }
        displayPreferences = updated
    }

    func resetDisplayOrder() {
        var updated = displayPreferences
        updated.resetOrder()
        displayPreferences = updated
    }

    func openDashboard() {
        guard let endpoint = try? OmniRouteEndpoint(address) else { return }
        NSWorkspace.shared.open(endpoint.baseURL)
    }
}
#endif
