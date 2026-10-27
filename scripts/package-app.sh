#!/bin/bash
set -euo pipefail

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "A Mac with Xcode Command Line Tools is required to build the app." >&2
  exit 1
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-0.1.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
DEST="${DEST:-$ROOT/dist}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[0-9]+$ ]]; then
  echo "VERSION must be numeric major.minor.patch and BUILD_NUMBER must be an integer." >&2
  exit 1
fi
swift build -c release
BIN="$(swift build -c release --show-bin-path)/OmniRouteQuota"
APP="$DEST/OmniRouteQuota.app"
mkdir -p "$DEST"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/OmniRouteQuota"
chmod +x "$APP/Contents/MacOS/OmniRouteQuota"
mkdir -p "$APP/Contents/Resources"
# OmniRoute's original desktop and tray artwork (see Assets/OmniRoute/LICENSE).
cp "$ROOT/Assets/OmniRoute/icon.icns" "$APP/Contents/Resources/icon.icns"
cp "$ROOT/Assets/OmniRoute/icon.png" "$APP/Contents/Resources/icon.png"
cp "$ROOT/Assets/OmniRoute/tray-icon.png" "$APP/Contents/Resources/tray-icon.png"
mkdir -p "$APP/Contents/Resources/providers"
cp "$ROOT/Assets/ProviderIcons/"*.svg "$APP/Contents/Resources/providers/"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>OmniRoute Quotas</string>
  <key>CFBundleDisplayName</key><string>OmniRoute Quotas</string>
  <key>CFBundleIdentifier</key><string>com.overbit.OmniRouteQuota</string>
  <key>CFBundleExecutable</key><string>OmniRouteQuota</string>
  <key>CFBundleIconFile</key><string>icon.icns</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$BUILD_NUMBER</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"

# Development / PR builds are deliberately ad-hoc signed (no secrets).
# Release builds MUST use the Apple Developer ID Application certificate.
if [[ -n "${SIGNING_IDENTITY:-}" ]]; then
  echo "Signing release with Developer ID and hardened runtime."
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP"
  codesign --verify --deep --strict --verbose=2 "$APP"
elif [[ "${REQUIRE_SIGNING:-0}" == "1" ]]; then
  echo "Refusing to package a release without SIGNING_IDENTITY." >&2
  exit 1
else
  echo "Ad-hoc development signature; this build is NOT notarized." >&2
  codesign --force --sign - "$APP"
fi

echo "Packaged: $APP"
if [[ "${ZIP:-0}" == "1" ]]; then
  ditto -c -k --keepParent "$APP" "$DEST/OmniRouteQuota-macos.zip"
  echo "Archived: $DEST/OmniRouteQuota-macos.zip"
fi
