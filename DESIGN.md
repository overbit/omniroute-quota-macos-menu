# UI design contract

## Source of truth

The quota popover offers the two user-approved single-row directions:
**Full-width rows (Option A)** and **Quota ledger (Option C)**. Full-width rows
is the default; Settings lets each user choose their preferred layout and saves
it across launches. The unselected inline-account concept (Option B) is not a
shipping mode. Both retain restrained surfaces, aligned numbers and every quota.
The native tray baseline comes from
[OmniRouteTray](https://github.com/zoispag/omniroute-tray).

This remains a standalone, native SwiftUI quota viewer. It does not replicate
OmniRouteTray's Tauri runtime, server supervision, update manager, trends, or costs.

## Dimensions and rhythm

- **310-point** popover width; content height follows the visible quota rows
  and caps at **425 points**, scrolling between a fixed header and footer.
  Empty providers and unused rows consume no space.
- Header: green/amber/red 9-point status dot, bold 15-point OmniRoute, 11-point
  running state, on one baseline; 13/16-point padding.
- A single 32-point status toolbar combines 10.5-point muted
  "active/configured providers · accounts" with the persistent **% left / % used**
  control. The Usage tab already names the view, so no redundant USAGE heading
  or extra divider consumes list space. No invented cache rate or server version.
- **Full-width rows:** each account has a 16-point heading with its bundled
  provider mark, 11.5-point semibold name, and OFF / STALE indicators. After a
  2-point gap, **every quota gets one 16-point full-width row**. The row uses a
  36-point window label, flexible 4-point quota bar, 34-point percentage and
  49-point reset countdown, with 7-point gaps. Bars are not indented or boxed.
  Accounts have 4-point separation and provider groups have 5-point separation.
- **Quota ledger:** every **22-point row** repeats provider/account identity,
  OFF / STALE state, window label, percentage and reset time. There are no bars,
  separate account headings, blank continuation-name cells, or account/group
  gaps. A faint horizontal rule separates rows. Identity uses the flexible space;
  the fixed 24-point window / 34-point percentage / 49-point reset columns stay
  aligned. Long names truncate in the middle and retain their full hover title.
- Both layouts preserve quota order, show single and additional windows equally,
  and render unavailable accounts explicitly when the no-quota filter is off.
  Five two-window accounts fit the maximum usage viewport in either layout when
  no warning is present. Sparse Usage content shrinks the actual popover around
  its rows and footer; Timeline and Settings retain the 425-point maximum height.
- Fixed footer: small app name, click-to-open local port chip, three
  24-point outlined actions (refresh, open router, settings).

## Color and type

- **OLED** replaces Graphite as the default, using true-black #000000 canvas
  (unlit OLED pixels), near-black #101014 elevated controls, #626270 outlines,
  and near-white #F6F7FA primary text. Muted gray copy remains legible.
  Quota bars preserve clear green, amber, and red meaning, with distinct
  warning hues against both black and raised surfaces. No background gradients
  or unnecessary illuminated panels are added.
- **macOS Light / macOS Dark** replace Midnight and Dusk. They resolve native
  AppKit window/control backgrounds, labels, separators, and the user's accent
  color under Aqua / Dark Aqua respectively, rather than hard-coded imitations.
  Each choice stays explicitly light or dark regardless of the system appearance;
  its thumbnail resolves under the same appearance as the full popover. Muted,
  faint, and quota/status text blend toward the native label color only when
  necessary to retain 4.5:1 contrast on both native surfaces.
- **Forest** retains its muted evergreen palette and verdant focus accents.
  **Paper** retains neutral light surfaces and deep readable text. All five
  choices share semantic roles without changing layout or quota calculations.
- Quota bar color always expresses remaining quota, even in % used mode.
  Semantic success, warning, and critical colors maintain at least
  4.5:1 contrast against background and elevated surfaces in all five themes.
  Both macOS Light and Paper use readable status hues and light native controls.
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
- **Settings → Quota layout** provides a native segmented choice of
  **Full-width rows / Quota ledger** with a short description of the current
  choice. It updates presentation immediately using `AppStorage("quotaLayoutMode")`,
  defaults to Full-width rows for new/existing installs without a saved choice,
  and requires no Save & connect, refresh or restart. It is independent of theme,
  percentage direction, ordering, visibility, cached data and menu-bar monitoring.
- **Settings → Theme** has five immediately selectable, accessible miniature
  palette previews (OLED, macOS Light, macOS Dark, Forest, Paper). Native theme
  captions wrap to two lines rather than shrinking or truncating their names.
  Selection is persisted using AppStorage("quotaTheme") and propagated via a SwiftUI
  environment palette to every popover/account/quota/settings subview.
  Native toggle/field appearance follows the selected light/dark scheme.
  The status-bar glyph remains a macOS-controlled template image and is
  not recolored by the popover theme. Existing Graphite preferences seamlessly
  resolve to OLED using the original stored identifier. Saved Midnight and Dusk
  values resolve to macOS Dark; new native choices save `macos-light` /
  `macos-dark`. OLED remains the default. No preference reset is required.
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
