# Product

<!-- impeccable:product-schema 1 -->

## Platform

macOS 14+ (native menu-bar application).

## Users

People who have multiple OmniRoute provider connections and want to check their quota without opening the main router dashboard.

## Product Purpose

Show each configured provider/account's remaining usage windows and reset timers in one click, without managing or duplicating the OmniRoute service.

## Operating Context

OmniRoute runs locally at port 20128 unless configured otherwise. The app is launched from the macOS menu bar and uses local cached quota/connection APIs.

## Constraints

Compact themeable popover modeled on the supplied screenshot, with five persistent presets and a true-black OLED palette as default; minimal vertical and horizontal overhead; multiple accounts per provider; persistent custom provider/account order and manual visibility; hide entries lacking measurable quota by default while retaining them in Settings; optional visibility of disabled connections and cached quotas; safe read-only local API access using the local management API key when available; official OmniRoute app and menu-bar artwork; a dynamic at-a-glance menu-bar warning based on the worst measurable active-account quota, excluding disabled accounts and unlimited windows; clear loading, empty, stale, and offline states.

## Evidence on Hand

The user's OmniRouteTray screenshot, and upstream OmniRoute / OmniRouteTray endpoint contracts. There is no existing code in the target repository at project start.