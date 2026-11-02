/// The user's preferred quota presentation, independent of filtering and alerts.
public enum QuotaLayoutMode: String, CaseIterable, Codable, Identifiable, Sendable {
    case fullWidthRows = "full-width-rows"
    case quotaLedger = "quota-ledger"

    public static let storageKey = "quotaLayoutMode"
    public static let defaultMode: Self = .fullWidthRows

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fullWidthRows: return "Full-width rows"
        case .quotaLedger: return "Quota ledger"
        }
    }

    public var detail: String {
        switch self {
        case .fullWidthRows: return "An account heading with one full-width meter per quota."
        case .quotaLedger: return "Account, window, percentage and reset on each row, without bars."
        }
    }
}
