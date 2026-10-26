#if os(macOS)
import CryptoKit
import Foundation
import Security

// User-supplied overrides never leave the Mac. OmniRoute's local CLI token is
// derived from the machine ID and its per-install salt, not stored or uploaded.
enum LocalCredentials {
    private static let service = "com.overbit.OmniRouteQuota"

    static func read(_ account: String) -> String {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    static func save(_ value: String, account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let removal = SecItemDelete(query as CFDictionary)
        guard removal == errSecSuccess || removal == errSecItemNotFound else {
            throw CredentialError.keychain(removal)
        }
        guard !value.isEmpty else { return }
        var addition = query
        addition[kSecValueData as String] = Data(value.utf8)
        addition[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(addition as CFDictionary, nil)
        guard status == errSecSuccess else { throw CredentialError.keychain(status) }
    }

    static func automaticToken() -> String {
        guard let uuid = machineID() else { return "" }
        let saltPath = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".omniroute/cli-token-salt.json")
        let salt: String
        if let data = try? Data(contentsOf: saltPath),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: String],
           let persisted = json["salt"], persisted.count == 64,
           persisted.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) {
            salt = persisted
        } else {
            salt = "omniroute-cli-auth-v1"
        }
        let mac = HMAC<SHA256>.authenticationCode(
            for: Data(salt.utf8), using: SymmetricKey(data: Data(uuid.utf8)))
        return mac.map { String(format: "%02x", $0) }.joined()
    }

    private static func machineID() -> String? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/ioreg")
        task.arguments = ["-rd1", "-c", "IOPlatformExpertDevice"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        guard (try? task.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        task.waitUntilExit()
        guard task.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8),
              let suffix = output.components(separatedBy: "IOPlatformUUID").dropFirst().first,
              let line = suffix.components(separatedBy: .newlines).first else { return nil }
        let uuid = line.replacingOccurrences(of: "=", with: "")
            .replacingOccurrences(of: "\"", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return uuid.count == 36 ? uuid : nil
    }
}

enum CredentialError: LocalizedError {
    case keychain(OSStatus)
    var errorDescription: String? {
        switch self {
        case .keychain(let status): return "Could not save credentials to Keychain (\(status))."
        }
    }
}
#endif
