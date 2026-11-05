# OmniRoute Quotas for macOS

**Your AI provider quotas, one click away.**

A lightweight, native macOS menu-bar companion for [OmniRoute](https://github.com/cheaper-inference/OmniRoute). See how much quota remains across connected accounts, when limits reset, and which account needs your attention—without opening a dashboard.

[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-000000?logo=apple&logoColor=white)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-native-F05138?logo=swift&logoColor=white)](Package.swift)
[![macOS build](https://github.com/overbit/omniroute-quota-macos-menu/actions/workflows/build.yml/badge.svg)](https://github.com/overbit/omniroute-quota-macos-menu/actions/workflows/build.yml)
[![No dependencies](https://img.shields.io/badge/dependencies-zero-success)](Package.swift)

**[Get started](#quick-start)** · **[Explore features](#features)** · **[Settings](#make-it-yours)** · **[How it works](#how-it-works)**

> [!NOTE]
> This is an independent companion app. **OmniRoute must already be running on your Mac.** The app reads its local APIs; it does not install, launch, or manage the server.

## Why use it?

- **All your quotas in one glance.** Browse provider connections, session/daily/weekly/monthly windows, remaining percentages, and reset countdowns.
- **Warnings where you look.** A dynamic menu-bar indicator highlights your lowest remaining monitored quotas, even with the popover closed.
- **One click to check live usage.** Cached data refreshes quietly; a manual refresh asks OmniRoute for fresh supported provider limits.
- **See recent routing activity.** A five-minute Timeline displays request status and duration without exposing prompts or request bodies.
- **Made for macOS.** Native SwiftUI, compact layouts, five themes, no Dock icon, and no third-party runtime.
- **Local and private.** No app analytics or telemetry; optional secrets are stored in Keychain.

## Quick start

### Requirements

- macOS **14 (Sonoma) or newer**
- A running [OmniRoute](https://github.com/cheaper-inference/OmniRoute) instance on the **same Mac** (default: `http://127.0.0.1:20128`)
- Xcode Command Line Tools if building from source

### Install

**Signed release (when available):** Download the versioned `OmniRouteQuota-vX.Y.Z-macos.zip` from **[GitHub Releases](https://github.com/overbit/omniroute-quota-macos-menu/releases)**, extract `OmniRouteQuota.app`, and move it to `/Applications`.

> [!IMPORTANT]
> There is **no published release yet**. For now, use the source-build instructions below. GitHub Actions build artifacts are ad-hoc signed, **not notarized**, and intended for testing rather than distribution. Do not disable Gatekeeper to install a production build.

**Build locally** on your Mac:

```sh
git clone https://github.com/overbit/omniroute-quota-macos-menu.git
cd omniroute-quota-macos-menu
swift test
ZIP=1 bash scripts/package-app.sh
open dist/OmniRouteQuota.app
```

The script creates `dist/OmniRouteQuota.app` and a ZIP archive. Local builds use an ad-hoc development signature. See [RELEASING.md](RELEASING.md) for the Developer ID signing and notarization process.

### Connect in seconds

1. Start OmniRoute locally, then launch **OmniRoute Quotas**.
2. Click the OmniRoute icon in your Mac menu bar to view connected accounts and remaining quota.
3. If your OmniRoute server uses a custom local port or credentials, open **Settings** and enter the local address and optional token/key overrides.
4. Choose your layout, theme, and which accounts should influence menu-bar warnings. Preferences are saved automatically.

**Default connection:** `http://127.0.0.1:20128`. Only loopback addresses (`localhost`, `127.0.0.1`, `::1`) are accepted to prevent sending management credentials to remote hosts.

## Features

### Keep quotas visible—not another dashboard open

View each configured provider and account in a compact popover. Quota windows display their **remaining percentage** and **time until reset**, with a toggle to switch between **% left** and **% used**.

Two persistent display modes suit different needs:

| Full-width rows (default) | Quota ledger |
| --- | --- |
| Account headings with one clear meter per quota | Dense, aligned account/window/percentage/reset rows |
| Best for scanning colored quota bars | Best for comparing many limits at once |

The popover stays **310 points wide**, grows with its content up to **425 points tall**, and scrolls longer lists while keeping the header and footer in place. Unlimited or missing quotas are labeled as unavailable, not mistaken for full or empty allowance.

### Get a heads-up before a quota runs out

The native menu-bar icon has two modes:

| Mode | Behavior |
| --- | --- |
| **Static** | Always shows the plain OmniRoute icon |
| **Dynamic** (default) | Displays up to three lowest monitored account percentages when the lowest drops below 50% |

Dynamic warnings turn **amber below 50%** and **red below 20%**. Hover to inspect the accounts behind the warning. Monitor **all active** connections or customize provider/account selections—including disabled connections—without changing which accounts appear in the popover.

### See what OmniRoute has been routing

The **Timeline** view shows recent proxy-request metadata from the last **five minutes**, up to 100 rows. Inspect provider/model, status, local time, elapsed/reported duration, and intervals on a shared timeline. It polls only while the view is open; it is **not** a token stream.

Timeline data is held **in memory only**. Prompts, bodies, paths, headers, account identity, and API-key metadata are not displayed or retained. Availability depends on the local OmniRoute version and its authentication configuration.

### Make it yours

- **Five themes:** OLED (true black, default), macOS Light, macOS Dark, Forest, and Paper.
- **Reorder and hide:** Arrange provider groups and accounts, and choose what appears in Usage.
- **No-quota filter:** Hide accounts with no measurable quota by default; turn it off to inspect unavailable and unlimited-only entries. A real **0% remaining** quota stays visible.
- **Disabled accounts:** Optionally show them with an **OFF** label; cached values may be stale.
- **Independent alerts:** Hiding an account does not automatically exclude it from menu-bar monitoring.
- **Persistent preferences:** Layout, themes, order, visibility, and warning selections survive relaunches.

## How it works

OmniRoute Quotas is a **read-only companion for routing configuration**, not an OmniRoute replacement. It reads local server data and only asks the server to refresh quotas when you explicitly request it.

| Action | OmniRoute endpoint | Frequency |
| --- | --- | --- |
| Load configured connections | `GET /api/providers` | On connection/data reload |
| Read cached quotas | `GET /api/usage/provider-limits` | Every 60 seconds, starting at launch |
| Manually refresh active-account quotas | `POST /api/usage/provider-limits` | On Refresh click |
| Manually refresh disabled-account quotas | `GET /api/usage/{connectionId}` | On Refresh click, sequentially |
| Read recent request activity | `GET /api/usage/call-logs?limit=200` | While Timeline is open, 2 seconds after each response |

**Automatic polling never triggers live provider probes.** Manual refresh may contact upstream providers through OmniRoute; unsupported disabled connections are skipped and partial failures preserve existing cached figures. Quota windows reported per model are conservatively consolidated using the lowest remaining percentage for matching reset times.

### Privacy and security

- **No telemetry or analytics** in this app, and no outbound connections except to the local OmniRoute server. OmniRoute itself may communicate with providers when you request a manual refresh.
- **Local-only server addresses** reduce the risk of management credentials reaching an unintended host; redirects are refused for Timeline.
- **Keychain** stores optional manually entered management API-key and CLI-token overrides.
- Without a manual management key, the app reads only `OMNIROUTE_API_KEY` from `~/.omniroute/.env` on refresh; it does not display, log, or store that value in Keychain.
- For standard local OmniRoute setups, the CLI management token can be derived using the Mac platform UUID and `~/.omniroute/cli-token-salt.json`. Custom token/salt setups can use a manual token override.
- **Disabled accounts are never enabled** by the app, including during manual refresh.

## Development

Built with **SwiftUI + AppKit** and **Swift Package Manager**, with **no third-party package dependencies**.

| Component | Responsibility |
| --- | --- |
| `QuotaCore` | Local API client, quota parsing, remaining percentages, countdowns |
| `OmniRouteQuota` | Native menu bar, popover, Settings, Keychain, local token derivation |
| `Tests/QuotaCoreTests` | Quota and Timeline behavior |
| `Tests/QuotaUITests` | Layouts, themes, percentages, and native menu-bar indicator |

Run the test suite with `swift test`. QuotaCore can be tested on Linux, but building and testing the native app requires macOS.

To export native UI snapshots for inspection on a Mac:

```sh
QUOTA_UI_SNAPSHOT_DIR=/tmp/omniroute-quota-ui swift test --filter QuotaMeterLayoutTests
```

For design decisions, see [DESIGN.md](DESIGN.md). For signed distribution and GitHub release automation, see [RELEASING.md](RELEASING.md).

## Credits and attribution

This project is **independent and not affiliated with or endorsed by OmniRoute**.

- [OmniRoute](https://github.com/cheaper-inference/OmniRoute): local server integration and original desktop/menu-bar artwork, with notices preserved in [Assets/OmniRoute/LICENSE](Assets/OmniRoute/LICENSE).
- [OmniRouteTray](https://github.com/zoispag/omniroute-tray): inspiration for the compact tray layout, adapted into native SwiftUI. Provider artwork and associated notices live in `Assets/ProviderIcons/`.

OmniRoute Quotas deliberately focuses on viewing limits and recent request activity. It does **not** supervise the server or reproduce OmniRouteTray's cost reporting or update management.
