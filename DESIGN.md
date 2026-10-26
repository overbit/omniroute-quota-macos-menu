# UI design contract

## Purpose and density

A dark, single-surface **Operate** interface: one-click check, no navigation stack or dashboard. The UI is approximately 410 points wide, shows compact individual account rows, and caps the scroll region at 500 points. Actions live in the header/footer; the primary surface is quota information.

## Visual language

- Native SF system typography, 11–15 pt. Figures use tabular rounded numerals; account names stay truncatable.
- Neutral graphite `#171A1D`-family background, off-white primary text, muted cool gray metadata, hairline separators.
- Quota fill is semantic: green at 50% or more, amber below 50%, red below 20%. The menubar icon warns at below 20%.
- Provider-specific restrained icon tints distinguish brands without external assets. No nested cards, elevation effects, or unnecessary ornament.
- Geometry: each quota line has a 32-pt period label, flexible bar, 40-pt percent and 53-pt countdown; each account displays one title line and its quota lines.

## Interaction and states

- Click menu-bar icon to open; popover remains native and closes on focus loss.
- Background refresh every 60 seconds; manual refresh via footer.
- Settings replace the quota content in the same popover and allow local URL/auth configuration.
- Offline shows actionable retry/settings. Partial failures retain last good figures and add a warning. Empty and inactive accounts are explicit; no missing data is treated as full quota.
- Support VoiceOver through labeled buttons and combined quota rows.