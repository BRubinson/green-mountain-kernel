#!/bin/bash
#
# install_swiftlint.sh — install the pinned SwiftLint into $GM_FS_ROOT.
#
# Usage:
#   install_swiftlint.sh            # install or upgrade to the pin
#   install_swiftlint.sh --check    # report only, change nothing
#
# Layout (release-store shape): $GM_FS_ROOT/tools/swiftlint/<version>/swiftlint,
# selected by the symlink $GM_FS_ROOT/bin/swiftlint. Writes only under $GM_FS_ROOT.

set -euo pipefail

SWIFTLINT_VERSION="0.65.1"
SWIFTLINT_SHA256="c1e429b0599cf1b516f369a2d9ec04eaf0e436f3c12b637df8851fa52ff694d0"
SWIFTLINT_URL="https://github.com/realm/SwiftLint/releases/download/${SWIFTLINT_VERSION}/portable_swiftlint.zip"

GM_FS_ROOT="${GM_FS_ROOT:-$HOME/gmfs}"
TOOL_DIR="$GM_FS_ROOT/tools/swiftlint/$SWIFTLINT_VERSION"
LINK="$GM_FS_ROOT/bin/swiftlint"

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

installed_version() {
    [ -x "$LINK" ] || return 1
    "$LINK" version 2>/dev/null
}

if [ "$(installed_version || true)" = "$SWIFTLINT_VERSION" ]; then
    echo "[GMB] swiftlint $SWIFTLINT_VERSION already installed at $LINK"
    exit 0
fi

if [ "$CHECK" = 1 ]; then
    echo "[GMB] swiftlint $SWIFTLINT_VERSION not installed (found: $(installed_version || echo none)); run without --check to install"
    exit 1
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "[GMB] downloading SwiftLint $SWIFTLINT_VERSION"
if ! curl -fsSL -o "$TMP/portable_swiftlint.zip" "$SWIFTLINT_URL"; then
    echo "[GMB] ERROR: download failed: $SWIFTLINT_URL" >&2
    echo "[GMB] alternative: brew install swiftlint (unpinned)" >&2
    exit 1
fi

ACTUAL="$(shasum -a 256 "$TMP/portable_swiftlint.zip" | cut -d' ' -f1)"
if [ "$ACTUAL" != "$SWIFTLINT_SHA256" ]; then
    echo "[GMB] ERROR: sha256 mismatch for portable_swiftlint.zip" >&2
    echo "        expected $SWIFTLINT_SHA256" >&2
    echo "        actual   $ACTUAL" >&2
    exit 1
fi

mkdir -p "$TOOL_DIR" "$GM_FS_ROOT/bin"
unzip -qo "$TMP/portable_swiftlint.zip" -d "$TOOL_DIR"
chmod +x "$TOOL_DIR/swiftlint"
ln -sfn "../tools/swiftlint/$SWIFTLINT_VERSION/swiftlint" "$LINK"

echo "[GMB] swiftlint $("$LINK" version) installed: $LINK -> tools/swiftlint/$SWIFTLINT_VERSION/swiftlint"
