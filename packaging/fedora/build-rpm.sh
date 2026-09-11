#!/usr/bin/env bash
# Builds the Vitrine RPM on Fedora, from whatever is committed in this
# checkout. Run it from anywhere; it finds the repository itself.
#
#   ./packaging/fedora/build-rpm.sh
#
# Output: the finished package under ~/rpmbuild/RPMS/, with its path printed
# at the end. Install it with `sudo dnf install <that file>`.
#
# One-time setup on the build machine:
#   sudo dnf install rpm-build rpmdevtools swift-lang gtk4-devel \
#                    libadwaita-devel desktop-file-utils libappstream-glib
#
# SwiftPM resolves adwaita-swift during the build, so the machine needs to be
# online the first time.

set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
SPEC="$HERE/vitrine.spec"

NAME=vitrine
VERSION="$(awk '/^Version:/ { print $2 }' "$SPEC")"

TOPDIR="$(rpm --eval '%{_topdir}')"
mkdir -p "$TOPDIR"/{SOURCES,SPECS,BUILD,RPMS,SRPMS}

echo "→ Archiving $NAME-$VERSION from HEAD…"
git -C "$ROOT" archive --format=tar.gz \
    --prefix="$NAME-$VERSION/" \
    -o "$TOPDIR/SOURCES/$NAME-$VERSION.tar.gz" HEAD

cp "$SPEC" "$TOPDIR/SPECS/"

echo "→ rpmbuild…"
rpmbuild -ba "$TOPDIR/SPECS/$(basename "$SPEC")"

echo "✓ built:"
find "$TOPDIR/RPMS" -name "$NAME-$VERSION-*.rpm" -newermt '-5 minutes'
