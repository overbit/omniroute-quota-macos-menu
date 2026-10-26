#if os(macOS)
import AppKit
import Foundation
import QuotaCore

/// Original icon artwork from OmniRoute. Use AppKit's template rendering for
/// the status bar so the white glyph adapts to the macOS menu-bar appearance.
@MainActor
enum OmniRouteArtwork {
    static let statusBar: NSImage? = {
        guard let url = Bundle.main.url(forResource: "tray-icon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = true
        return image
    }()

    static let header: NSImage? = {
        guard let url = Bundle.main.url(forResource: "icon", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()

    private static var cache: [String: NSImage] = [:]

    /// Provider SVGs are served by the running local OmniRoute dashboard. On
    /// macOS 14+ NSImage can render them; unsupported SVGs use a letter badge.
    static func providerIcon(_ providerID: String, server: String) async -> NSImage? {
        guard let endpoint = try? OmniRouteEndpoint(server),
              let asset = assetName(for: providerID) else { return nil }
        let url = endpoint.url(for: "providers/\(asset).svg")
        let cacheKey = url.absoluteString
        if let cached = cache[cacheKey] { return cached }

        var request = URLRequest(url: url)
        request.timeoutInterval = 4
        request.cachePolicy = .returnCacheDataElseLoad
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let response = response as? HTTPURLResponse,
              response.statusCode == 200,
              data.count < 128_000,
              String(decoding: data.prefix(500), as: UTF8.self).contains("<svg"),
              let image = NSImage(data: data), image.isValid else { return nil }
        cache[cacheKey] = image
        return image
    }

    private static func assetName(for provider: String) -> String? {
        let lower = provider.lowercased()
        if lower.hasPrefix("openai-compatible-") || lower.hasPrefix("anthropic-compatible-") {
            return nil // Custom providers should not inherit an unrelated brand.
        }
        let alias: String
        switch lower {
        case "openai-codex": alias = "codex"
        case "kimi-coding", "kimi-web", "moonshot": alias = "kimi-logomark-dark"
        case "claude-code": alias = "claude"
        case "opencode-go", "opencode-zen": return nil // No licensed local SVG in OmniRoute.
        case "qwen-cloud", "qwen-cloud-token-plan": return nil
        default: alias = lower
        }
        guard !alias.isEmpty,
              alias.utf8.allSatisfy({ ($0 >= 97 && $0 <= 122) || ($0 >= 48 && $0 <= 57) || $0 == 45 })
        else { return nil }
        return alias
    }
}
#endif
