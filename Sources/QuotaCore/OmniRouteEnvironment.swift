import Foundation

/// Extracts only the management key; provider credentials and unrelated env values are ignored.
public enum OmniRouteEnvironment {
    public static func apiKey(from contents: String) -> String? {
        let assignment = "OMNIROUTE_API_KEY="
        for line in contents.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(assignment) else { continue }
            let raw = String(trimmed.dropFirst(assignment.count))
                .trimmingCharacters(in: .whitespaces)
            guard !raw.isEmpty else { return nil }

            if let quote = raw.first, quote == "\"" || quote == "'" {
                guard let closing = raw.dropFirst().firstIndex(of: quote) else { return nil }
                let after = raw[raw.index(after: closing)...]
                    .trimmingCharacters(in: .whitespaces)
                guard after.isEmpty || after.hasPrefix("#") else { return nil }
                let value = String(raw[raw.index(after: raw.startIndex)..<closing])
                return value.isEmpty ? nil : value
            }

            let value: String
            if let hash = raw.firstIndex(of: "#"),
               (hash == raw.startIndex || raw[raw.index(before: hash)].isWhitespace) {
                value = String(raw[..<hash]).trimmingCharacters(in: .whitespaces)
            } else {
                value = raw
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
