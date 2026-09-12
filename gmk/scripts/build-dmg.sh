#!/usr/bin/env bash
#
# build-dmg.sh — Build GMVibes (gmk/gmVibes/ in the green-mountain-kernel monorepo) into a distributable .dmg.
# Run from anywhere; it resolves gmk/ from its own location.
#
# Auto-detects signing capability:
#   • If a "Developer ID Application" cert is installed, the app is signed with
#     the hardened runtime and the DMG can be notarized (see NOTARIZE below).
#   • Otherwise the app is ad-hoc signed and packaged into a DMG that works
#     today — recipients clear Gatekeeper quarantine once (see README).
#
# ── THE VERSION COMES FROM gmk/VERSION, NOT FROM THE PROJECT FILE ────────────
#
# One release, one number. `gmk/VERSION` pins the three binaries and the app
# together, and MARKETING_VERSION is STAMPED from it at archive time rather than
# read out of project.pbxproj. Before this the app carried an independently
# edited MARKETING_VERSION and shipped under its own `gmvibes-v*` tag, so the
# app's About box and the installed runtime could disagree with nothing to
# notice. The stamp is a build setting override, so project.pbxproj is never
# rewritten and the working tree stays clean for publish_release.sh's check.
#
# Usage:
#   scripts/build-dmg.sh                 # build at gmk/VERSION (auto-detect signing)
#   scripts/build-dmg.sh 50.0.2          # build at an explicit version
#   NOTARIZE=1 scripts/build-dmg.sh      # also notarize + staple (needs Dev ID
#                                        # + a `notarytool` keychain profile)
#
# Output: build/GMVibes-<version>.dmg — the name carries the version because it
# becomes a release asset, and an asset named GMVibes.dmg forces every installer
# to guess what is inside it.
#
# Notarization prerequisites (one-time):
#   xcrun notarytool store-credentials gmcc-ui \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
set -euo pipefail

SCHEME="GMVibes"
APP_NAME="GMVibes"
PROJECT="gmk.xcodeproj"
CONFIG="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-gmcc-ui}"

# gmk/ — the directory holding the one Xcode project, one level up from
# gmk/scripts/. This script sits beside build_gm.sh rather than under
# gmk/gmVibes/ because everything in the app's source directory is inside its
# filesystem-synchronized Xcode group, and a shell script is not app sources.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${1:-$(cat "$ROOT/VERSION")}"
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || { echo "error: no version — gmk/VERSION is empty and none was passed" >&2; exit 1; }

BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Detect a Developer ID Application signing identity, if present.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)"

# BRACES ARE LOAD-BEARING HERE. The `…` that follows is multi-byte, and bash
# absorbs its leading byte into an unbraced variable name — `$VERSION…` expands
# a name that does not exist, which under `set -u` kills the script on a line
# that is only printing a message.
echo "==> Archiving $SCHEME ($CONFIG) at ${VERSION}…"
# MARKETING_VERSION/CURRENT_PROJECT_VERSION are overridden on the command line
# rather than written into project.pbxproj: the number lives in gmk/VERSION, and
# a build that edits the project file would dirty the tree that
# publish_release.sh requires to be clean.
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  | grep -E "^(===|\*\*|note:|error:|warning:)" || true

APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: archive did not produce $APP" >&2; exit 1; }

if [ -n "$DEV_ID" ]; then
  echo "==> Signing with: $DEV_ID (hardened runtime)"
  codesign --deep --force --options runtime --timestamp \
    --sign "$DEV_ID" "$APP"
else
  echo "==> No Developer ID found — ad-hoc signing."
  echo "    Recipients must clear quarantine once (see README)."
  codesign --deep --force --sign - "$APP"
fi

echo "==> Staging DMG contents…"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Building ${DMG_PATH}…"
hdiutil create -volname "$APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

if [ -n "$DEV_ID" ]; then
  codesign --force --sign "$DEV_ID" "$DMG_PATH"
fi

if [ "${NOTARIZE:-0}" = "1" ]; then
  [ -n "$DEV_ID" ] || { echo "error: NOTARIZE=1 requires a Developer ID cert" >&2; exit 1; }
  echo "==> Notarizing (profile: $NOTARY_PROFILE)…"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  echo "==> Stapling…"
  xcrun stapler staple "$DMG_PATH"
fi

echo ""
echo "✅ Done: $DMG_PATH"
if [ -z "$DEV_ID" ]; then
  echo "   (ad-hoc — unsigned for external distribution)"
fi
