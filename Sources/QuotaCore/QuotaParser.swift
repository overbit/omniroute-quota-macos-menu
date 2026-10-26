import Foundation

public enum QuotaParser {
    public static func parse(providers: Data, limits: Data, now: Date = Date()) throws -> [QuotaAccount] {
        let rawProviders = try JSONSerialization.jsonObject(with: providers)
        let connections: [Any]
        if let array = rawProviders as? [Any] {
            connections = array
        } else if let object = rawProviders as? [String: Any],
                  let array = (object["connections"] ?? object["providers"]) as? [Any] {
            connections = array
        } else {
            throw QuotaError.invalidProviders
        }

        let rawLimits = try JSONSerialization.jsonObject(with: limits)
        guard let limitsObject = rawLimits as? [String: Any],
              let cache = limitsObject["caches"] as? [String: Any] else {
            throw QuotaError.invalidCache
        }

        var accounts: [QuotaAccount] = []
        for connection in connections {
            guard let item = connection as? [String: Any],
                  let id = item["id"] as? String,
                  let provider = item["provider"] as? String else { continue }
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? (item["email"] as? String) ?? provider
            let active = (item["isActive"] ?? item["enabled"]) as? Bool ?? true
            let cached = cache[id] as? [String: Any]
            let quotas = cached?["quotas"] as? [String: Any] ?? [:]
            let windows = parseWindows(quotas, now: now)
            let fetchedAt = (cached?["fetchedAt"] as? String).flatMap(parseDate)
            let hasError = (cached?["message"] as? String).map { !$0.isEmpty } ?? false
            let isStale = hasError || (fetchedAt.map { now.timeIntervalSince($0) > 90 * 60 } ?? false)
            accounts.append(.init(id: id, name: name, provider: provider, active: active,
                                  windows: windows, isStale: isStale))
        }
        if accounts.isEmpty && !connections.isEmpty { throw QuotaError.invalidProviders }
        return accounts.sorted {
            if $0.providerName != $1.providerName { return $0.providerName < $1.providerName }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private static func parseWindows(_ quotas: [String: Any], now: Date) -> [QuotaWindow] {
        var windows: [QuotaWindow] = []
        for key in quotas.keys.sorted() where isTimeWindow(key) {
            guard let entry = quotas[key] as? [String: Any],
                  let remaining = percentage(entry) else { continue }
            let unlimited = entry["unlimited"] as? Bool ?? false
            windows.append(.init(id: key, label: shortLabel(key),
                                 remainingPercent: unlimited ? 100 : remaining,
                                 resetAt: (entry["resetAt"] as? String).flatMap(parseDate),
                                 unlimited: unlimited))
        }
        if windows.isEmpty {
            // Per-model providers: group windows by reset time, using the most constrained model.
            var buckets: [Date: Double] = [:]
            for entry in quotas.values {
                guard let object = entry as? [String: Any],
                      let reset = (object["resetAt"] as? String).flatMap(parseDate),
                      let remaining = percentage(object) else { continue }
                buckets[reset] = min(buckets[reset] ?? 100, remaining)
            }
            windows = buckets.keys.sorted().map { reset in
                let minutes = max(0, reset.timeIntervalSince(now) / 60)
                let label = minutes >= 20 * 1_440 ? "mo" : minutes >= 4 * 1_440 ? "wk" :
                            minutes >= 20 * 60 ? "1d" : minutes >= 3 * 60 ? "5h" : "1h"
                return .init(id: "reset-\(reset.timeIntervalSince1970)", label: label,
                             remainingPercent: buckets[reset] ?? 0, resetAt: reset)
            }
        }
        return windows.sorted { a, b in
            let priority: [String: Int] = ["sess": 0, "5h": 1, "1h": 2, "1d": 3, "wk": 4, "mo": 5]
            let left = priority[a.label] ?? 6
            let right = priority[b.label] ?? 6
            return left == right ? a.id < b.id : left < right
        }
    }

    private static func percentage(_ value: [String: Any]) -> Double? {
        if value["unlimited"] as? Bool == true { return 100 }
        if let remaining = number(value["remainingPercentage"]) { return clamp(remaining) }
        if let used = number(value["used"]), let total = number(value["total"]), total > 0 {
            return clamp(100 - used / total * 100)
        }
        if let remaining = number(value["remaining"]), let total = number(value["total"]), total > 0 {
            return clamp(remaining / total * 100)
        }
        return nil
    }

    private static func number(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber, number.doubleValue.isFinite else { return nil }
        return number.doubleValue
    }

    private static func clamp(_ value: Double) -> Double { min(100, max(0, value)) }

    private static func isTimeWindow(_ key: String) -> Bool {
        let lower = key.lowercased()
        return lower.hasPrefix("session") || lower.hasPrefix("weekly") || lower == "monthly"
            || lower.hasPrefix("window_") || lower == "5h" || lower == "1d"
            || lower.contains("(5h)") || lower.contains("(7d)")
    }

    private static func shortLabel(_ key: String) -> String {
        let lower = key.lowercased()
        if lower.hasPrefix("session") { return "sess" }
        if lower.hasPrefix("weekly") || lower.contains("7d") { return "wk" }
        if lower.contains("monthly") { return "mo" }
        if lower.contains("5h") { return "5h" }
        if lower.contains("1d") || lower.contains("24h") { return "1d" }
        if lower.contains("1h") { return "1h" }
        return String(lower.prefix(4))
    }

    private static func parseDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let result = formatter.date(from: value) { return result }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
