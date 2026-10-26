# UI design contract

## Source of truth

The quota popover replicates the **visual hierarchy, dimensions, spacing, controls,
and color tokens** of [OmniRouteTray](https://github.com/zoispag/omniroute-tray),
particularly its \`src/styles.css\`, \`src/main.js\` (\`paintRateLimits()\`), and
\`index.html\`. The user's supplied OmniRouteTray screenshot is the visual target.

This remains a standalone, native SwiftUI quota viewer. It does not replicate
OmniRouteTray's Tauri runtime, server supervision, update manager, trends, or costs.

## Dimensions and rhythm

- **320-point** popover width; content height follows its data and caps at
  **510 points**, scrolling between a fixed header and footer.
- Header: green/amber/red 9-point status dot, bold 15-point OmniRoute, 11-point
  running state, on one baseline; 13/16-point padding.
- Status strip: 11-point muted "active/configured providers · accounts"; no
  invented cache rate or server version.
- Usage heading: spaced 10.5-point "USAGE" and a small, outlined, persistent
  **% left / % used** button.
- Each account: inline 16-point brand mark (bundled official/OmniRouteTray SVG),
  12-point bold account name, then compact rows. One account follows the next
  within the provider group, without repeated section headings or cards.
- Each quota row is a four-column grid:
  **22-point window label / flexible 7-point bar / 34-point percentage /
  44-point reset countdown**, 7-point gaps and 5-point row separation.
- Groups preserve provider grouping and get modest 12-point vertical spacing.
- Fixed footer: small app name, click-to-open local port chip, three
  28-point outlined actions (refresh, open router, settings).

## Color and type

- Reproduce OmniRouteTray dark CSS palette: background \`#1c1c1e\`,
  raised \`#2c2c2e\`, border/track \`#38383a\`, foreground \`#f5f5f7\`,
  muted \`#a1a1aa\`.
- Green \`#22c55e\`, amber \`#f59e0b\`, red \`#ef4444\`; quota bar color
  expresses **remaining** quota even when displaying \`% used\`.
- SF system fonts; percentages and reset times use tabular numerals.
- Unavailable values are labeled, not rendered as 100% quota.
- Native status-bar OmniRoute mark is 13pt with a dynamic low-quota warning
  below 50% and a critical warning below 20%.

## Interaction and edge cases

- Clicking the status item opens the popover; the view stays readable with
  many providers and long account names (middle truncation and hover title).
- The quota-mode toggle persists across launches.
- Settings live in the **footer**, unlike the previous oversized header gear.
  It contains local address, optional key overrides, disabled-account display,
  and a Quit action.
- Disabled accounts remain optional, retain any last cached quota, and are
  clearly marked OFF; stale readings get an independent warning.
- Header/footer remain fixed while usage scrolls. VoiceOver labels name each
  quota window and percentage. Offline and empty states have retry/recovery.
- The independent app uses only local OmniRoute API data; features such as
  OmniRouteTray's cache hit-rate and server version are intentionally omitted
  unless those facts can be retrieved reliably.
