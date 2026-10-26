# UI design contract

## Purpose and density

A dark, single-surface **Operate** interface: one-click check, no navigation stack or dashboard. The UI is approximately 410 points wide, groups compact account rows by provider, and caps the scroll region at 500 points. Actions live in the header/footer; the primary surface is quota information.

## Visual language

- Native SF system typography, 11–15 pt. Figures use tabular rounded numerals; account names stay truncatable.
- Neutral graphite `#171A1D`-family background, off-white primary text, muted cool gray metadata, hairline separators.
- Quota fill is semantic: green at 50% or more, amber below 50%, red below 20%. The 13-point menu-bar glyph warns with a small dot below 20% without increasing its width.
- Original OmniRoute artwork anchors the macOS app icon, menu-bar status item, and popover header. Provider marks use official SVGs from the local OmniRoute server with monogram fallbacks; no third-party icon CDN. No nested cards, elevation effects, or unnecessary ornament.
- Geometry: each quota line has a 32-pt period label, flexible bar, 40-pt percent and 53-pt countdown. Provider headings own the icon and label; nested account names and disabled/stale markers identify each connection while quota bars keep the full row width.

## Interaction and states

- Click menu-bar icon to open; popover remains native and closes on focus loss.
- Background refresh every 60 seconds; manual refresh via footer.
- Settings replace the quota content in the same popover and allow local URL/auth configuration. A persistent **Show disabled accounts** switch reveals inactive connections without requesting new upstream quota data; the default is off.
- Offline shows actionable retry/settings. Partial failures retain last good figures and add a warning. Inactive connections keep their last cached quota if available, and are labeled Disabled; no missing data is treated as full quota.
- Support VoiceOver through labeled buttons and combined quota rows.