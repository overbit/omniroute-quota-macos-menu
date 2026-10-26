# OmniRoute Quotas for macOS

A small, native **macOS 14+ menu-bar app** that shows the remaining quotas for every account connected to [OmniRoute](https://github.com/cheaper-inference/OmniRoute). Open the popover, check your session/weekly/daily limits and reset times, close it. No Dock icon, server supervision, analytics, or extra runtime.

The interface follows the compact, dark account list shown in the project reference: one row per account, colored quota bars, and short reset countdowns. The menu-bar icon signals when any active, measurable quota drops below 20%.

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
2. Click the chart icon in the menu bar. Configured accounts and quota windows appear automatically.
3. If your server uses custom auth or a different port, click **Settings**. Enter the local address, an optional management API key, or an optional CLI token override. Custom secrets are stored in macOS Keychain.

For the usual local OmniRoute setup, the app can derive the CLI management token from the Mac's platform UUID and OmniRoute's `~/.omniroute/cli-token-salt.json` (as OmniRoute itself does). It **does not read `~/.omniroute/.env`** or your stored provider credentials. If the server has a custom `OMNIROUTE_CLI_TOKEN` or `OMNIROUTE_CLI_SALT`, paste an authorized token into Settings. The server address is constrained to `localhost`, `127.0.0.1`, or `::1` to prevent accidentally sending management credentials to a remote host.

## Data and refresh

- `GET /api/providers` supplies all configured connections, including paused accounts.
- `GET /api/usage/provider-limits` supplies OmniRoute's **cached** per-connection quota data. The app does not probe provider usage endpoints directly.
- Refreshes every 60 seconds while running, plus manual refresh. If a refresh fails, previously fetched quotas remain visible with a warning.
- Standard session/weekly/daily/monthly windows are displayed. Providers that report quotas per model are consolidated by reset time using the **lowest remaining percentage**, so a quota never appears safer than its most constrained model.
- A blank quota is shown as **Quota not available**, not a fabricated 100%.

No analytics, telemetry, or external network requests are made by this app. No provider credentials are needed or read.

## Development

The project uses Swift Package Manager without third-party dependencies. `QuotaCore` contains the API client, quota parsing, and percentage/countdown logic, with XCTest coverage. `OmniRouteQuota` contains SwiftUI, Keychain integration, local CLI token derivation, and the menu-bar popover. Tests can run on Linux; the actual native app must be compiled on macOS.

This is an independent companion app, not an official OmniRoute product.