import Foundation

/// This preference controls the status-bar indicator only. It never changes
/// the account list, the popover's hidden rows, or how quotas are refreshed.
public enum QuotaMenuMode: String, Codable, Sendable, CaseIterable {
    case staticIcon
    case dynamic
}

public enum QuotaMonitorScope: String, Codable, Sendable, CaseIterable {
    case allActive
    case selected
}

public struct QuotaMenuPreferences: Codable, Equatable, Sendable {
    /// Preserve the original behavior for users upgrading from earlier builds.
    public var mode: QuotaMenuMode = .dynamic
    public var scope: QuotaMonitorScope = .allActive
    public var selectedProviders: Set<String> = []
    public var selectedAccounts: Set<String> = []

    public init() {}

    /// A provider selection covers all current and future accounts in that
    /// provider (including explicitly disabled connections). Account selection
    /// is by stable provider+connection ID, never by display name.
    public func monitoredAccounts(from accounts: [QuotaAccount]) -> [QuotaAccount] {
        switch scope {
        case .allActive:
            return accounts.filter(\.active)
        case .selected:
            return accounts.filter {
                selectedProviders.contains($0.providerName)
                    || selectedAccounts.contains(QuotaDisplayPreferences.accountKey($0))
            }
        }
    }

    public func monitors(_ account: QuotaAccount) -> Bool {
        scope == .allActive
            ? account.active
            : selectedProviders.contains(account.providerName)
                || selectedAccounts.contains(QuotaDisplayPreferences.accountKey(account))
    }

    public mutating func selectProvider(_ name: String, selected: Bool) {
        if selected { selectedProviders.insert(name) }
        else { selectedProviders.remove(name) }
    }

    public mutating func selectAccount(_ account: QuotaAccount, selected: Bool) {
        let key = QuotaDisplayPreferences.accountKey(account)
        if selected { selectedAccounts.insert(key) }
        else { selectedAccounts.remove(key) }
    }
}
