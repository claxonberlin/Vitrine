#!/usr/bin/env bash
# Fills Sources/VitrineKit/Resources/Splashes with the artwork Blender ships
# with each X.Y release — the painting on its startup screen — so an install
# has every one of them on hand and the app never has to scrape blender.org
# for a series it already knows.
#
# Run it when a new series is released; it skips what is already there.
#
# Usage:
#   ./splashes.sh              # fetch what's missing
#   ./splashes.sh --force      # re-fetch everything
#   ./splashes.sh 5.3          # fetch just these series
#
# The artwork is the social-preview image on the release's own announcement
# page — there is no API for it, and the file names follow no pattern worth
# guessing at. A series with no page yet (the alpha in development) is
# reported and skipped; the app still scrapes at runtime for anything it
# doesn't find here.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
DEST="$ROOT/Sources/VitrineKit/Resources/Splashes"

ALL_SERIES=(
    2.80 2.81 2.82 2.83 2.90 2.91 2.92 2.93
    3.0 3.1 3.2 3.3 3.4 3.5 3.6
    4.0 4.1 4.2 4.3 4.4 4.5
    5.0 5.1 5.2 5.3
)

FORCE=0
SERIES=()
for arg in "$@"; do
    case "$arg" in
        --force) FORCE=1 ;;
        *) SERIES+=("$arg") ;;
    esac
done
[[ ${#SERIES[@]} -eq 0 ]] && SERIES=("${ALL_SERIES[@]}")

mkdir -p "$DEST"

# Reads the og:image out of a release page. Both attribute orders are
# accepted, since nothing obliges the page to pick one — the same two
# patterns `SplashLibrary.parseArtworkURL` uses.
artwork_url() {
    curl -sL "https://www.blender.org/download/releases/${1//./-}/" | python3 -c '
import re, sys
html = sys.stdin.read()
match = (re.search(r"<meta[^>]+property=[\"\x27]og:image[\"\x27][^>]*?content=[\"\x27]([^\"\x27]+)", html)
         or re.search(r"<meta[^>]+content=[\"\x27]([^\"\x27]+)[\"\x27][^>]*?property=[\"\x27]og:image[\"\x27]", html))
print(match.group(1) if match else "")
'
}

for series in "${SERIES[@]}"; do
    if [[ $FORCE -eq 0 ]] && compgen -G "$DEST/$series.*" > /dev/null; then
        echo "· $series already here"
        continue
    fi

    url="$(artwork_url "$series")"
    if [[ -z "$url" ]]; then
        echo "! $series has no announcement page yet"
        continue
    fi

    ext="${url##*.}"
    ext="${ext%%\?*}"
    [[ -z "$ext" || ${#ext} -gt 4 ]] && ext="img"
    rm -f "$DEST/$series".*
    curl -sL "$url" -o "$DEST/$series.$ext"
    echo "→ $series.$ext  $(basename "$url")"
done

echo "✓ $DEST"
