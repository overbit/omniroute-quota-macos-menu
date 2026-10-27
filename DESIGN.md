# UI design contract

## Source of truth

The quota popover replicates the **visual hierarchy, dimensions, spacing, controls,
and color tokens** of [OmniRouteTray](https://github.com/zoispag/omniroute-tray),
particularly its \`src/styles.css\`, \`src/main.js\` (\`paintRateLimits()\`), and
\`index.html\`. The user's supplied OmniRouteTray screenshot is the visual target.

This remains a standalone, native SwiftUI quota viewer. It does not replicate
OmniRouteTray's Tauri runtime, server supervision, update manager, trends, or costs.

## Dimensions and rhythm

- **310-point** popover width; content height follows the visible quota rows
  and caps at **425 points**, scrolling between a fixed header and footer.
  Empty providers and unused rows consume no space.
- Header: green/amber/red 9-point status dot, bold 15-point OmniRoute, 11-point
  running state, on one baseline; 13/16-point padding.
- Status strip: 11-point muted "active/configured providers · accounts"; no
  invented cache rate or server version.
- Usage heading: spaced 10.5-point "USAGE" and a small, outlined, persistent
  **% left / % used** button.
- Each account: inline 16-point brand mark (bundled official/OmniRouteTray SVG),
  11.5-point semibold account name, then compact rows. One account follows
  the next within the provider group, without repeated headings or cards.
- Each quota row is a four-column grid:
  **22-point window label / flexible 6-point bar / 34-point percentage /
  44-point reset countdown**, 7-point gaps and 3-point row separation.
- Groups preserve provider grouping with 8-point spacing; accounts within
  a provider use 6-point separation.
- Fixed footer: small app name, click-to-open local port chip, three
  24-point outlined actions (refresh, open router, settings).

## Color and type

- **Graphite** is the default and preserves OmniRouteTray's dark CSS palette:
  background #1c1c1e, raised #2c2c2e, border/track #38383a,
  foreground #f5f5f7, muted #a1a1aa. Critical red is slightly brighter to
  keep small labels readable on raised surfaces.
- **Midnight**: cool navy dark, blue focus accents. **Forest**: muted
  evergreen, verdant focus accents. **Dusk**: deep violet with lavender
  focus accents. **Paper**: warm light surfaces with deep readable text.
  Each remaps the same semantic surface, text, border, focus, good, warning,
  and critical roles, without changing layout or quota calculations.
- Quota bar color always expresses remaining quota, even in % used mode.
  Semantic success, warning, and critical colors maintain at least
  4.5:1 contrast against background and elevated surfaces in all five themes.
  Paper explicitly uses darkened status hues and light native controls.
- SF system fonts; percentages and reset times use tabular numerals.
- Unavailable values are labeled, not rendered as 100% quota.
- Native menu-bar mark is a **14-point AppKit template image** with 1× and
  2× pixel representations of OmniRoute's eight-dot ring. This is a native
  `NSImage` rather than a SwiftUI `Shape`: some MenuBarExtra labels fail to
  paint arbitrary shapes. The dots are thick enough to remain visible at
  system menu-bar scale, with no blurry center or redundant warning triangle.
  The template image automatically contrasts with light/dark menu bars.
  In **Static** mode, show only the neutral icon regardless of quota or
  network status. **Dynamic** mode shows a compact number and amber mark below
  50%, red below 20% (including 0%). In Dynamic mode, missing data uses a
  question mark and connection failures use an exclamation if no low number
  exists. CI validates opaque pixels for all eight dots at 1× and 2×.


## Interaction and edge cases

- Clicking the status item opens the popover; the view stays readable with
  many providers and long account names (middle truncation and hover title).
- The quota-mode toggle persists across launches.
- **Settings → Theme** has five immediately selectable, accessible miniature
  palette previews (Graphite, Midnight, Forest, Dusk, Paper). Selection is
  persisted using AppStorage("quotaTheme") and propagated via a SwiftUI
  environment palette to every popover/account/quota/settings subview.
  Native toggle/field appearance follows the selected light/dark scheme.
  The status-bar glyph remains a macOS-controlled template image and is
  not recolored by the popover theme. Existing installations remain Graphite.
- **Menu Bar Icon** settings independently choose **Static / Dynamic**.
  Dynamic supports **All active** (the backward-compatible default) or
  **Custom** selection of provider groups and individual connections.
  Checking a provider includes all accounts with that provider display group,
  including disabled/new accounts. Individual selections use stable
  provider+connection IDs and survive account renames. Disabled accounts
  count when explicitly selected; they are never enabled for routing.
- The monitor selection is independent of every popover display filter:
  a hidden or filtered account may still drive a low-quota warning.
  Static mode suppresses all quota/connection adornments, but cached polling
  continues so switching back to Dynamic is immediate. A selected account
  without measurable quota never counts as 0% or 100%; an actual 0% quota
  remains critical.
- Settings live in the **footer**, unlike the previous oversized header gear.
  They include local address, optional key overrides, disabled-account display,
  the **Hide accounts without quota** switch, ordered provider/account list,
  and Quit action. Settings scroll independently.
- **Hide accounts without quota** is enabled by default; it removes accounts
  with no finite quota windows (including unlimited-only) and automatically
  removes providers that have no remaining visible accounts. A valid 0%-left
  window stays visible. The setting only affects presentation, never API data
  or menu-bar low-quota monitoring.
- The Settings ordering list is always built from every configured account,
  unaffected by the disabled and no-quota filters. Users can move providers
  and accounts up/down, uncheck an entire provider or individual account,
  and reset ordering without resetting visibility. IDs, not labels, identify
  stored preferences across quota refreshes and app launches.
- Disabled accounts remain optional, retain any last cached quota, and are
  clearly marked OFF; stale readings get an independent warning.
- Header/footer remain fixed while usage scrolls. VoiceOver labels name each
  quota window and percentage. Offline and empty states have retry/recovery.
- The footer's **manual** Refresh button performs a live quota sync: OmniRoute's
  bulk POST covers enabled accounts and its individual usage GET covers each
  disabled connection. Disabled accounts retain their disabled routing state.
  The per-connection probes are serialized, with an inter-request delay to
  avoid upstream bursts. Once complete, the UI reloads the entire server cache.
  Partial failures show a warning without treating the server as offline.
  Unsupported/no-quota accounts remain unavailable rather than invented at 100%.
- Automatic 60-second refreshes remain GET-only cache reads; merely opening
  the popover never starts upstream quota probes. Refresh uses a progress indicator
  and a last-check timestamp or failure status. HTTP cache is bypassed locally.
- The independent app uses only local OmniRoute API data; features such as
  OmniRouteTray's cache hit-rate and server version are intentionally omitted
  unless those facts can be retrieved reliably.
