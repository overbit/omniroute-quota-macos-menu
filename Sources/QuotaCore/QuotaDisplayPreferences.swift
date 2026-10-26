import Foundation

/// Presentation preferences only. These never affect the quota cache or menu-bar alerts.
public struct QuotaDisplayPreferences: Codable, Equatable, Sendable {
    public var providerOrder: [String] = []
    public var accountOrder: [String: [String]] = [:]
    public var hiddenProviders: Set<String> = []
    public var hiddenAccounts: Set<String> = []
    public var hideWithoutQuota = true

    public init() {}

    /// The ID is stable across name changes, and unambiguous across providers.
    public static func accountKey(_ account: QuotaAccount) -> String {
        "\(account.provider.utf8.count):\(account.provider)\(account.id)"
    }

    /// An unlimited window alone does not report a finite remaining quota.
    /// Zero remaining is a real quota and must not be hidden.
    public static func hasMeasurableQuota(_ account: QuotaAccount) -> Bool {
        account.windows.contains { !$0.unlimited }
    }

    /// Settings always use the complete list, even if filters hide every row.
    public func orderedGroups(from accounts: [QuotaAccount]) -> [QuotaProviderGroup] {
        let ranks = Dictionary(uniqueKeysWithValues: providerOrder.enumerated().map { ($0.element, $0.offset) })
        let groups = QuotaProviderGroup.grouped(accounts).map { group in
            let order = accountOrder[group.id] ?? []
            let accountRanks = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($0.element, $0.offset) })
            let sorted = group.accounts.enumerated().sorted { lhs, rhs in
                let leftRank = accountRanks[Self.accountKey(lhs.element)] ?? Int.max
                let rightRank = accountRanks[Self.accountKey(rhs.element)] ?? Int.max
                return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
            }.map(\.element)
            return QuotaProviderGroup(id: group.id, providerID: group.providerID, accounts: sorted)
        }
        return groups.enumerated().sorted { lhs, rhs in
            let leftRank = ranks[lhs.element.id] ?? Int.max
            let rightRank = ranks[rhs.element.id] ?? Int.max
            return leftRank == rightRank ? lhs.offset < rhs.offset : leftRank < rightRank
        }.map(\.element)
    }

    public func visibleGroups(from accounts: [QuotaAccount], includeDisabled: Bool) -> [QuotaProviderGroup] {
        orderedGroups(from: accounts).compactMap { group in
            guard !hiddenProviders.contains(group.id) else { return nil }
            let visible = group.accounts.filter { account in
                (includeDisabled || account.active)
                    && !hiddenAccounts.contains(Self.accountKey(account))
                    && (!hideWithoutQuota || Self.hasMeasurableQuota(account))
            }
            guard !visible.isEmpty else { return nil }
            return QuotaProviderGroup(id: group.id, providerID: group.providerID, accounts: visible)
        }
    }

    /// Reordering uses the complete list to prevent hidden entries from becoming unreachable.
    @discardableResult
    public mutating func moveProvider(_ id: String, by offset: Int, among accounts: [QuotaAccount]) -> Bool {
        var identifiers = orderedGroups(from: accounts).map(\.id)
        guard let index = identifiers.firstIndex(of: id),
              identifiers.indices.contains(index + offset), offset != 0 else { return false }
        identifiers.swapAt(index, index + offset)
        providerOrder = identifiers
        return true
    }

    @discardableResult
    public mutating func moveAccount(_ account: QuotaAccount, by offset: Int, among accounts: [QuotaAccount]) -> Bool {
        guard let group = orderedGroups(from: accounts).first(where: {
            $0.accounts.contains(where: { Self.accountKey($0) == Self.accountKey(account) })
        }) else { return false }
        var identifiers = group.accounts.map(Self.accountKey)
        guard let index = identifiers.firstIndex(of: Self.accountKey(account)),
              identifiers.indices.contains(index + offset), offset != 0 else { return false }
        identifiers.swapAt(index, index + offset)
        accountOrder[group.id] = identifiers
        return true
    }

    public mutating func resetOrder() {
        providerOrder = []
        accountOrder = [:]
    }
}
