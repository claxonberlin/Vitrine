#!/usr/bin/env bash
# Wraps the swift-built executable into a real Vitrine.app bundle, with
# Info.plist + custom icon + ad-hoc signature. Idempotent: re-run any time.
#
# Usage:
#   ./bundle.sh            # debug build (fast iteration)
#   ./bundle.sh release    # optimized build for shipping
#
# Output: ./Vitrine.app  (drag to /Applications when ready)

set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="Vitrine"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/$APP_NAME.app"
ICON="$ROOT/Resources/AppIcon.icns"
INFO_PLIST="$ROOT/Resources/Info.plist"

echo "→ Building ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$ROOT/.build/$CONFIG/$APP_NAME"
if [[ ! -f "$BIN" ]]; then
    echo "Binary not found at $BIN" >&2
    exit 1
fi

echo "→ Assembling $APP…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$APP_NAME"
cp "$ICON" "$APP/Contents/Resources/AppIcon.icns"
cp "$INFO_PLIST" "$APP/Contents/Info.plist"

# SwiftPM emits declared resources — the SVG icon set — as a side-by-side
# bundle. Bundle.module looks in the main bundle's resource path, so it has to
# travel into the .app; without this the toolbar icons render as blank space.
RESOURCE_BUNDLE="$ROOT/.build/$CONFIG/${APP_NAME}_${APP_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"
else
    echo "  ! resource bundle not found at $RESOURCE_BUNDLE" >&2
fi

# Ad-hoc sign so Gatekeeper stops asking on every launch.
codesign --force --sign - "$APP" >/dev/null

# Touching the bundle nudges Finder to refresh the icon cache.
touch "$APP"

echo "✓ $APP"
echo "  open it with:  open '$APP'"
