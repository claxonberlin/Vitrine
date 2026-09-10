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

# SwiftPM emits each target's declared resources — the SVG icon set, the
# splash paintings — as a side-by-side bundle. Bundle.module looks in the main
# bundle's resource path, so every one of them has to travel into the .app;
# without this the toolbar icons render as blank space and the cards lose
# their artwork.
shopt -s nullglob
RESOURCE_BUNDLES=("$ROOT/.build/$CONFIG/"*.bundle)
shopt -u nullglob
if [[ ${#RESOURCE_BUNDLES[@]} -eq 0 ]]; then
    echo "  ! no resource bundles found in $ROOT/.build/$CONFIG" >&2
fi
for bundle in "${RESOURCE_BUNDLES[@]}"; do
    cp -R "$bundle" "$APP/Contents/Resources/"
done

# Ad-hoc sign so Gatekeeper stops asking on every launch.
codesign --force --sign - "$APP" >/dev/null

# Touching the bundle nudges Finder to refresh the icon cache.
touch "$APP"

echo "✓ $APP"
echo "  open it with:  open '$APP'"
