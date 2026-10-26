import Foundation

public struct QuotaWindow: Identifiable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let remainingPercent: Double
    public let resetAt: Date?
    public let unlimited: Bool

    public init(id: String, label: String, remainingPercent: Double, resetAt: Date?, unlimited: Bool = false) {
        self.id = id
        self.label = label
        self.remainingPercent = max(0, min(100, remainingPercent))
        self.resetAt = resetAt
        self.unlimited = unlimited
    }

    public var roundedRemaining: Int { Int(remainingPercent.rounded()) }

    /// Mirrors OmniRouteTray's usage control: color thresholds always use quota left,
    /// while the bar width and numeric label show the requested direction.
    public func displayedPercent(showUsed: Bool) -> Double {
        showUsed ? 100 - remainingPercent : remainingPercent
    }

    public func displayedRoundedPercent(showUsed: Bool) -> Int {
        Int(displayedPercent(showUsed: showUsed).rounded())
    }

    public func countdown(from now: Date = Date()) -> String {
        guard let resetAt else { return "—" }
        let minutes = Int(resetAt.timeIntervalSince(now) / 60)
        guard minutes > 0 else { return "now" }
        if minutes >= 1_440 { return "\(minutes / 1_440)d\((minutes % 1_440) / 60)h" }
        if minutes >= 60 { return "\(minutes / 60)h\(minutes % 60)m" }
        return "\(minutes)m"
    }
}

public struct QuotaAccount: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let provider: String
    public let active: Bool
    public let windows: [QuotaWindow]
    public let isStale: Bool

    public var providerName: String {
        let raw = provider.lowercased()
        if raw.contains("openai") || raw.contains("codex") { return "OpenAI" }
        if raw.contains("anthropic") || raw.contains("claude") { return "Anthropic" }
        if raw.contains("antigravity") { return "Antigravity" }
        if raw.contains("kimi") { return "Kimi" }
        if raw.contains("opencode") { return "OpenCode" }
        return provider.replacingOccurrences(of: "-", with: " ").capitalized
    }

    public var lowestRemaining: Double? {
        windows.filter { !$0.unlimited }.map(\.remainingPercent).min()
    }
}

public enum QuotaVisibility {
    public static func visible(_ accounts: [QuotaAccount], includeDisabled: Bool) -> [QuotaAccount] {
        includeDisabled ? accounts : accounts.filter(\.active)
    }
}

/// A provider section containing all matching connections and their quota windows.
public struct QuotaProviderGroup: Identifiable, Equatable, Sendable {
    public let id: String
    public let providerID: String
    public let accounts: [QuotaAccount]

    public var providerName: String { id }

    public static func grouped(_ accounts: [QuotaAccount]) -> [QuotaProviderGroup] {
        let byProvider = Dictionary(grouping: accounts, by: \.providerName)
        return byProvider.keys.sorted().compactMap { name in
            guard let members = byProvider[name], let first = members.first else { return nil }
            return QuotaProviderGroup(id: name, providerID: first.provider, accounts: members)
        }
    }
}

public enum QuotaError: LocalizedError, Equatable {
    case invalidEndpoint
    case invalidProviders
    case invalidCache
    case unauthorized
    case http(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidEndpoint: return "Use a local OmniRoute address, such as 127.0.0.1:20128."
        case .invalidProviders: return "OmniRoute returned an unrecognized account list."
        case .invalidCache: return "OmniRoute returned an unrecognized quota cache."
        case .unauthorized: return "OmniRoute denied access. Check your management credentials in Settings."
        case .http(let status): return "OmniRoute returned HTTP \(status)."
        }
    }
}
