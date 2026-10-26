# OmniRoute Quotas for macOS

A small, native **macOS 14+ menu-bar app** that shows the remaining quotas for every account connected to [OmniRoute](https://github.com/cheaper-inference/OmniRoute). Open the popover, check your session/weekly/daily limits and reset times, close it. No Dock icon, server supervision, analytics, or extra runtime.

The popover follows [OmniRouteTray](https://github.com/zoispag/omniroute-tray)'s actual source UI: a **310-point dark popover**, one-line status header, provider/account status strip, **USAGE** heading with persistent **% left / % used** control, tightly packed provider-grouped account rows, four-column quota bars, and a fixed compact footer. Provider branding is bundled for offline use. This utility does not supervise OmniRoute or reproduce OmniRouteTray's cost and update features. The official OmniRoute menu-bar icon updates automatically **even when its popover is closed**: normal icon for healthy quotas (50% or more), amber warning and lowest remaining percentage under 50%, and red warning and lowest percentage under 20%. Loading, missing quota data, and connection failures have distinct status indicators. Hover over the icon to identify the affected provider/account and the number of low accounts; disabled connections and unlimited quotas do not trigger warnings. The app bundle uses OmniRoute's original macOS icon; provider logos come from your local OmniRoute server when available.

## Install

Download the `OmniRouteQuota-macos.zip` artifact from the latest successful [macOS build](https://github.com/overbit/omniroute-quota-macos-menu/actions/workflows/build.yml), extract `OmniRouteQuota.app`, and copy it to `/Applications`. Builds are ad-hoc signed, **not notarized**. If macOS blocks a self-built or downloaded copy, open it via Finder's right-click **Open** or remove quarantine only after you have verified the source and build.

Alternatively, build locally with the Xcode Command Line Tools:

```sh
swift test
ZIP=1 bash scripts/package-app.sh
open dist/OmniRouteQuota.app
```

## Connect

1. Run OmniRoute on the same Mac (default `http://127.0.0.1:20128`). The app **does not start or stop** the OmniRoute server.
2. Click the OmniRoute icon in the menu bar. Available quota rows are compactly grouped by provider. Open **Settings** to rearrange providers and accounts with the arrow controls; uncheck any provider or account to hide it. Ordering and visibility persist across launches. Use **Reset order** to restore default ordering without changing hidden entries.
3. **Hide accounts without quota** is on by default. It hides connections with no measurable quota and providers with no visible accounts. Turn it off in Settings to inspect them, including unlimited-only connections. A genuine 0%-remaining quota is never hidden. **Show disabled accounts** is a separate setting.
4. If your server uses custom authentication or a different port, use **Settings** to enter the local address, an optional management API key override, or an optional CLI token override. Overrides are stored in macOS Keychain.

For the usual local OmniRoute setup, the app can derive the CLI management token from the Mac's platform UUID and OmniRoute's `~/.omniroute/cli-token-salt.json` (as OmniRoute itself does). When the management API-key override is empty, it reads only `OMNIROUTE_API_KEY` from `~/.omniroute/.env` on each refresh. The `.env` value is not displayed, logged, or copied into Keychain. A manual API-key override takes precedence. Other provider credentials in `.env` are not used. If the server has a custom `OMNIROUTE_CLI_TOKEN` or `OMNIROUTE_CLI_SALT`, paste an authorized token into Settings. The server address is constrained to `localhost`, `127.0.0.1`, or `::1` to prevent accidentally sending management credentials to a remote host.

## Data and refresh

- `GET /api/providers` supplies all configured connections. Disabled accounts are hidden by default and can be shown using the persistent **Show disabled accounts** setting.
- `GET /api/usage/provider-limits` supplies OmniRoute's **cached** per-connection quota data. The app does not probe provider usage endpoints directly.
- Refreshes every 60 seconds from app launch, without requiring the popover to be opened, plus manual refresh. If a refresh fails, previously fetched quotas remain visible with a warning; the menu-bar indicator preserves last-known low quotas and shows a connection warning.
- Standard session/weekly/daily/monthly windows are displayed. Providers that report quotas per model are consolidated by reset time using the **lowest remaining percentage**, so a quota never appears safer than its most constrained model.
- The default no-quota filter hides accounts with no finite quota data and providers left with no visible accounts. Filtering is only visual: it does not remove stored accounts or suppress menu-bar low-quota alerts. Turning off the filter shows **Quota not available**, never a fabricated 100%. Disabled accounts can be included separately and are marked **OFF**; cached figures may be stale.

No analytics, telemetry, or external network requests are made by this app. The optional management API key is read locally; provider credentials are not used.

## Development

The project uses Swift Package Manager without third-party dependencies. `QuotaCore` contains the API client, quota parsing, and percentage/countdown logic, with XCTest coverage. `OmniRouteQuota` contains SwiftUI, Keychain integration, local CLI token derivation, and the menu-bar popover. Tests can run on Linux; the actual native app must be compiled on macOS.

This is an independent companion app, not an official OmniRoute product.
## Artwork

The packaged application reuses the official OmniRoute desktop (`icon.icns`, `icon.png`) and menu-bar (`tray-icon.png`) images from `electron/assets/` in [cheaper-inference/OmniRoute](https://github.com/cheaper-inference/OmniRoute). Their license notice is preserved in `Assets/OmniRoute/LICENSE`. Provider icons are requested only from your running local OmniRoute server at `/providers/{id}.svg`; if no matching image is available, a compact monogram is used. This companion app is not affiliated with or endorsed by OmniRoute.

### UI reference

The popover was adapted from OmniRouteTray's MIT-licensed [CSS](https://github.com/zoispag/omniroute-tray/blob/master/src/styles.css) and [usage renderer](https://github.com/zoispag/omniroute-tray/blob/master/src/main.js) using native SwiftUI rather than the upstream Tauri webview. The visual tokens, 310-point compact width, account/bars hierarchy, percentage toggle and compact footer follow the upstream code, with additional native reorder and visibility controls. Bundled provider marks and license notes are in `Assets/ProviderIcons/`.
