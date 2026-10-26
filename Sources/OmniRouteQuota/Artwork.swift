#if os(macOS)
import AppKit
import Foundation
import QuotaCore

/// Desktop artwork comes from OmniRoute; the native-sized template status-bar
/// glyph comes from OmniRouteTray for legibility in light and dark menu bars.
@MainActor
enum OmniRouteArtwork {
    static let statusBar: NSImage? = {
        // OmniRouteTray's dedicated 22 px status glyph is purpose-built for the
        // menu bar. Display it at exactly 11 pt on Retina (no fuzzy resampling).
        guard let url = Bundle.main.url(forResource: "tray-icon-22", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 11, height: 11)
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
        guard let asset = assetName(for: providerID) else { return nil }
        // Bundle the same essential marks as OmniRouteTray. Offline and custom
        // installations should still show real provider icons, not monograms.
        let localKey = "bundled:\(asset)"
        if let cached = cache[localKey] { return cached }
        if let file = Bundle.main.url(forResource: asset, withExtension: "svg", subdirectory: "providers"),
           let image = NSImage(contentsOf: file), image.isValid {
            cache[localKey] = image
            return image
        }

        guard let endpoint = try? OmniRouteEndpoint(server) else { return nil }
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
        case "openai", "openai-codex", "codex": alias = "codex"
        case "anthropic", "claude", "claude-code": alias = "claude"
        case "kimi", "kimi-coding", "kimi-web", "moonshot": alias = "kimi"
        case "opencode", "opencode-go", "opencode-zen": alias = "opencode"
        case "github", "github-copilot", "copilot": alias = "github-copilot"
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
