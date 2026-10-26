import Foundation

/// Worst measurable remaining quota among the configured monitoring selection.
/// Unlimited and unavailable quotas do not count as 0% or 100%.
public struct QuotaMenuStatus: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        case staticIcon, checking, unknown, healthy, low, critical
    }

    public let severity: Severity
    public let lowestPercent: Int?
    public let lowestAccount: String?
    public let lowestProvider: String?
    public let lowAccountCount: Int
    public let activeAccountCount: Int
    public let measuredAccountCount: Int
    public let customSelection: Bool
    public let lowestIsStale: Bool
    public let connectionUnavailable: Bool

    public var isLow: Bool { severity == .low || severity == .critical }

    public static func evaluate(
        accounts: [QuotaAccount],
        hasLoaded: Bool,
        connectionUnavailable: Bool,
        preferences: QuotaMenuPreferences = QuotaMenuPreferences()
    ) -> QuotaMenuStatus {
        if preferences.mode == .staticIcon {
            return QuotaMenuStatus(
                severity: .staticIcon, lowestPercent: nil, lowestAccount: nil,
                lowestProvider: nil, lowAccountCount: 0, activeAccountCount: 0,
                measuredAccountCount: 0, customSelection: false,
                lowestIsStale: false, connectionUnavailable: false
            )
        }

        let monitored = preferences.monitoredAccounts(from: accounts)
        let measured: [(account: QuotaAccount, remaining: Double)] = monitored.compactMap { account in
            guard let remaining = account.lowestRemaining else { return nil }
            return (account: account, remaining: remaining)
        }
        let worst = measured.min { $0.remaining < $1.remaining }
        let severity: Severity
        if let remaining = worst?.remaining {
            if remaining < 20 {
                severity = .critical
            } else if remaining < 50 {
                severity = .low
            } else {
                severity = .healthy
            }
        } else {
            severity = (!hasLoaded && !connectionUnavailable) ? .checking : .unknown
        }

        return QuotaMenuStatus(
            severity: severity,
            lowestPercent: worst.map { Int($0.remaining.rounded(.down)) },
            lowestAccount: worst?.account.name,
            lowestProvider: worst?.account.providerName,
            lowAccountCount: measured.filter { $0.remaining < 50 }.count,
            activeAccountCount: monitored.count,
            measuredAccountCount: measured.count,
            customSelection: preferences.scope == .selected,
            lowestIsStale: worst?.account.isStale ?? false,
            connectionUnavailable: connectionUnavailable
        )
    }

    /// Provides an accessible explanation and a useful hover tooltip.
    public var description: String {
        let summary: String
        switch severity {
        case .staticIcon:
            return "OmniRoute static icon. Quota warnings are disabled in Settings."
        case .checking:
            summary = "Checking OmniRoute quotas."
        case .unknown:
            if customSelection {
                summary = activeAccountCount == 0
                    ? "No accounts matched your menu-bar monitoring selection."
                    : "No measurable quotas for the selected accounts."
            } else {
                summary = activeAccountCount == 0
                    ? "No active OmniRoute accounts."
                    : "No measurable quota data for active OmniRoute accounts."
            }
        case .healthy, .low, .critical:
            let percent = lowestPercent ?? 0
            let account = lowestAccount ?? "unknown account"
            let provider = lowestProvider ?? "unknown provider"
            switch severity {
            case .critical:
                summary = "Critical quota: \(percent)% remaining on \(provider), \(account)."
            case .low:
                summary = "Low quota: \(percent)% remaining on \(provider), \(account)."
            default:
                summary = "Lowest quota: \(percent)% remaining on \(provider), \(account)."
            }
        }

        var detail = summary
        if lowAccountCount > 0 {
            detail += " \(lowAccountCount) monitored \(lowAccountCount == 1 ? "account" : "accounts") below 50%."
        }
        let unavailableCount = activeAccountCount - measuredAccountCount
        if unavailableCount > 0 && measuredAccountCount > 0 {
            detail += " \(unavailableCount) monitored \(unavailableCount == 1 ? "account has" : "accounts have") no reported quota."
        }
        if lowestIsStale {
            detail += " Lowest reading is cached and may be outdated."
        }
        if connectionUnavailable {
            detail = (measuredAccountCount > 0
                ? "OmniRoute refresh failed. Last known quotas: "
                : "OmniRoute connection unavailable. ") + detail
        }
        return detail
    }
}
