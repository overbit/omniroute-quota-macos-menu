import Foundation

/// The worst measurable quota across active accounts, for an at-a-glance menu-bar warning.
/// Disabled accounts, unlimited windows, and missing quota data never count as zero or 100%.
public struct QuotaMenuStatus: Equatable, Sendable {
    public enum Severity: Equatable, Sendable {
        case checking, unknown, healthy, low, critical
    }

    public let severity: Severity
    public let lowestPercent: Int?
    public let lowestAccount: String?
    public let lowestProvider: String?
    public let lowAccountCount: Int
    public let activeAccountCount: Int
    public let measuredAccountCount: Int
    public let lowestIsStale: Bool
    public let connectionUnavailable: Bool

    public var isLow: Bool { severity == .low || severity == .critical }

    public static func evaluate(
        accounts: [QuotaAccount],
        hasLoaded: Bool,
        connectionUnavailable: Bool
    ) -> QuotaMenuStatus {
        let active = accounts.filter(\.active)
        let measured: [(account: QuotaAccount, remaining: Double)] = active.compactMap { account in
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
            activeAccountCount: active.count,
            measuredAccountCount: measured.count,
            lowestIsStale: worst?.account.isStale ?? false,
            connectionUnavailable: connectionUnavailable
        )
    }

    /// Provides an accessible explanation and a useful hover tooltip.
    public var description: String {
        let summary: String
        switch severity {
        case .checking:
            summary = "Checking OmniRoute quotas."
        case .unknown:
            summary = activeAccountCount == 0
                ? "No active OmniRoute accounts."
                : "No measurable quota data for active OmniRoute accounts."
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
            detail += " \(lowAccountCount) active \(lowAccountCount == 1 ? "account" : "accounts") below 50%."
        }
        let unavailableCount = activeAccountCount - measuredAccountCount
        if unavailableCount > 0 && measuredAccountCount > 0 {
            detail += " \(unavailableCount) active \(unavailableCount == 1 ? "account has" : "accounts have") no reported quota."
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
