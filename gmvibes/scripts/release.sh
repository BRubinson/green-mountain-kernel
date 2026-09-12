#!/usr/bin/env bash
#
# release.sh — Build the GMVibes DMG and publish it as a GitHub release asset.
#
# Builds via scripts/build-dmg.sh (which auto-detects signing) and uploads the
# resulting DMG to a GitHub release on the `origin` repo (the gmcc-marketplace
# monorepo) using `gh`. Tags are namespaced `gmvibes-v<version>` so app releases
# never collide with marketplace/plugin tags.
#
# Signing / notarization is automatic:
#   • Developer ID Application cert present → signs + notarizes + staples
#     (set NOTARIZE=0 to skip notarization and ship a signed-but-not-notarized DMG).
#   • No Developer ID → ad-hoc DMG (recipients clear quarantine; see README).
#
# Usage:
#   scripts/release.sh                 # tag from MARKETING_VERSION (e.g. gmvibes-v1.0)
#   scripts/release.sh 1.2.0           # explicit version → tag gmvibes-v1.2.0
#   scripts/release.sh v1.2.0          # explicit version → tag gmvibes-v1.2.0
#   NOTARIZE=0 scripts/release.sh      # skip notarization even if Dev ID exists
#
# Prereqs: gh authenticated (`gh auth status`), an `origin` GitHub remote.
# For notarization: a `notarytool` keychain profile (default name "gmcc-ui").
#   xcrun notarytool store-credentials gmcc-ui \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
set -euo pipefail

APP_NAME="GMVibes"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DMG_PATH="$ROOT/build/$APP_NAME.dmg"

# --- Resolve version / tag --------------------------------------------------
ARG="${1:-}"
if [ -n "$ARG" ]; then
  VERSION="${ARG#v}"
else
  VERSION="$(grep -m1 'MARKETING_VERSION' "$APP_NAME.xcodeproj/project.pbxproj" \
    | sed -E 's/.*= ([^;]+);.*/\1/' | tr -d ' ')"
  [ -n "$VERSION" ] || { echo "error: could not read MARKETING_VERSION; pass a version arg" >&2; exit 1; }
fi
TAG="gmvibes-v$VERSION"

# --- Preflight --------------------------------------------------------------
command -v gh >/dev/null || { echo "error: gh not installed" >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "error: gh not authenticated — run: gh auth login" >&2; exit 1; }
# Releases ship to the gmcc-marketplace monorepo — refuse any other origin so
# a stray checkout can never publish somewhere surprising.
ORIGIN="$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)"
case "$ORIGIN" in
  *gmcc-marketplace*) ;;
  *) echo "error: origin is '$ORIGIN' — releases must publish to gmcc-marketplace" >&2; exit 1 ;;
esac

# --- Decide notarization ----------------------------------------------------
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep -c "Developer ID Application" || true)"
if [ "${DEV_ID:-0}" -gt 0 ]; then
  export NOTARIZE="${NOTARIZE:-1}"
  echo "==> Developer ID found — NOTARIZE=$NOTARIZE"
else
  export NOTARIZE=0
  echo "==> No Developer ID — building ad-hoc (unnotarized) DMG"
fi

# --- Build ------------------------------------------------------------------
"$ROOT/scripts/build-dmg.sh"
[ -f "$DMG_PATH" ] || { echo "error: DMG not produced at $DMG_PATH" >&2; exit 1; }

# --- Publish ----------------------------------------------------------------
if [ "$NOTARIZE" = "1" ]; then
  NOTE="Notarized build."
elif [ "${DEV_ID:-0}" -gt 0 ]; then
  NOTE="Signed (Developer ID), not notarized."
else
  NOTE="Ad-hoc build (unsigned). Clear quarantine: \`xattr -dr com.apple.quarantine /Applications/$APP_NAME.app\`"
fi

if gh release view "$TAG" >/dev/null 2>&1; then
  echo "==> Release $TAG exists — uploading asset (clobber)…"
  gh release upload "$TAG" "$DMG_PATH" --clobber
else
  echo "==> Creating release ${TAG}…"
  gh release create "$TAG" "$DMG_PATH" \
    --title "$APP_NAME $TAG" \
    --notes "$NOTE"
fi

echo ""
echo "✅ Published $TAG"
gh release view "$TAG" --json url -q .url
