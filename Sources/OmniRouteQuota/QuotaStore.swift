#if os(macOS)
import Foundation
import QuotaCore
import SwiftUI

@MainActor
final class QuotaStore: ObservableObject {
    @Published private(set) var accounts: [QuotaAccount] = []
    @Published private(set) var refreshing = false
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var errorMessage: String?
    @Published var showingSettings = false
    @Published var showDisabledAccounts = UserDefaults.standard.bool(forKey: "showDisabledAccounts") {
        didSet { UserDefaults.standard.set(showDisabledAccounts, forKey: "showDisabledAccounts") }
    }

    private let client = OmniRouteClient(session: URLSession(configuration: .ephemeral))
    private var polling: Task<Void, Never>?

    var address: String = UserDefaults.standard.string(forKey: "omnirouteAddress") ?? "127.0.0.1:20128"
    var apiKey: String = LocalCredentials.read("apiKey")
    var tokenOverride: String = LocalCredentials.read("cliToken")

    var connected: Bool { lastUpdated != nil && errorMessage == nil }
    var providerCount: Int { Set(accounts.map(\.provider)).count }
    var activeCount: Int { accounts.filter(\.active).count }
    var visibleAccounts: [QuotaAccount] { QuotaVisibility.visible(accounts, includeDisabled: showDisabledAccounts) }
    var visibleProviderCount: Int { Set(visibleAccounts.map(\.providerName)).count }
    var lowestRemaining: Double? { accounts.filter(\.active).compactMap(\.lowestRemaining).min() }

    func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    func refresh() async {
        guard !refreshing else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let endpoint = try OmniRouteEndpoint(address)
            let credentials = OmniRouteCredentials(
                apiKey: apiKey.isEmpty ? LocalCredentials.automaticAPIKey() : apiKey,
                cliToken: tokenOverride.isEmpty ? LocalCredentials.automaticToken() : tokenOverride)
            let result = try await client.load(from: endpoint, credentials: credentials)
            accounts = result
            lastUpdated = Date()
            errorMessage = nil
        } catch {
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

    func openDashboard() {
        guard let endpoint = try? OmniRouteEndpoint(address) else { return }
        NSWorkspace.shared.open(endpoint.baseURL)
    }
}
#endif
