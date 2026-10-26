# OmniRoute Quotas for macOS

A small, native **macOS 14+ menu-bar app** that shows the remaining quotas for every account connected to [OmniRoute](https://github.com/cheaper-inference/OmniRoute). Open the popover, check your session/weekly/daily limits and reset times, close it. No Dock icon, server supervision, analytics, or extra runtime.

The interface follows the compact, dark quota list shown in the project reference: accounts grouped under each provider icon, colored quota bars, and short reset countdowns. The official OmniRoute menu-bar icon updates automatically **even when its popover is closed**: normal icon for healthy quotas (50% or more), amber warning and lowest remaining percentage under 50%, and red warning and lowest percentage under 20%. Loading, missing quota data, and connection failures have distinct status indicators. Hover over the icon to identify the affected provider/account and the number of low accounts; disabled connections and unlimited quotas do not trigger warnings. The app bundle uses OmniRoute's original macOS icon; provider logos come from your local OmniRoute server when available.

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
2. Click the OmniRoute icon in the menu bar. Accounts and quota windows appear grouped by provider automatically. In **Settings**, switch on **Show disabled accounts** to include inactive connections and their last cached quotas.
3. If your server uses custom auth or a different port, click **Settings**. Enter the local address, an optional management API key override, or an optional CLI token override. Overrides are stored in macOS Keychain.

For the usual local OmniRoute setup, the app can derive the CLI management token from the Mac's platform UUID and OmniRoute's `~/.omniroute/cli-token-salt.json` (as OmniRoute itself does). When the management API-key override is empty, it reads only `OMNIROUTE_API_KEY` from `~/.omniroute/.env` on each refresh. The `.env` value is not displayed, logged, or copied into Keychain. A manual API-key override takes precedence. Other provider credentials in `.env` are not used. If the server has a custom `OMNIROUTE_CLI_TOKEN` or `OMNIROUTE_CLI_SALT`, paste an authorized token into Settings. The server address is constrained to `localhost`, `127.0.0.1`, or `::1` to prevent accidentally sending management credentials to a remote host.

## Data and refresh

- `GET /api/providers` supplies all configured connections. Disabled accounts are hidden by default and can be shown using the persistent **Show disabled accounts** setting.
- `GET /api/usage/provider-limits` supplies OmniRoute's **cached** per-connection quota data. The app does not probe provider usage endpoints directly.
- Refreshes every 60 seconds starting when the menu-bar icon appears, without requiring the popover to be opened, plus manual refresh. If a refresh fails, previously fetched quotas remain visible with a warning; the menu-bar indicator preserves last-known low quotas and shows a connection warning.
- Standard session/weekly/daily/monthly windows are displayed. Providers that report quotas per model are consolidated by reset time using the **lowest remaining percentage**, so a quota never appears safer than its most constrained model.
- A blank quota is shown as **Quota not available**, not a fabricated 100%. Disabled accounts show last cached quotas when present and an explicit **Disabled** label; these figures may be stale.

No analytics, telemetry, or external network requests are made by this app. The optional management API key is read locally; provider credentials are not used.

## Development

The project uses Swift Package Manager without third-party dependencies. `QuotaCore` contains the API client, quota parsing, and percentage/countdown logic, with XCTest coverage. `OmniRouteQuota` contains SwiftUI, Keychain integration, local CLI token derivation, and the menu-bar popover. Tests can run on Linux; the actual native app must be compiled on macOS.

This is an independent companion app, not an official OmniRoute product.
## Artwork

The packaged application reuses the official OmniRoute desktop (`icon.icns`, `icon.png`) and menu-bar (`tray-icon.png`) images from `electron/assets/` in [cheaper-inference/OmniRoute](https://github.com/cheaper-inference/OmniRoute). Their license notice is preserved in `Assets/OmniRoute/LICENSE`. Provider icons are requested only from your running local OmniRoute server at `/providers/{id}.svg`; if no matching image is available, a compact monogram is used. This companion app is not affiliated with or endorsed by OmniRoute.
