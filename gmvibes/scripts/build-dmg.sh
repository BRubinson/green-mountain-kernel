#!/usr/bin/env bash
#
# build-dmg.sh — Build GMVibes (gmvibes/ in the gmcc-marketplace monorepo) into a distributable .dmg.
#
# Auto-detects signing capability:
#   • If a "Developer ID Application" cert is installed, the app is signed with
#     the hardened runtime and the DMG can be notarized (see NOTARIZE below).
#   • Otherwise the app is ad-hoc signed and packaged into a DMG that works
#     today — recipients clear Gatekeeper quarantine once (see README).
#
# Usage:
#   scripts/build-dmg.sh                 # build (auto-detect signing)
#   NOTARIZE=1 scripts/build-dmg.sh      # also notarize + staple (needs Dev ID
#                                        # + a `notarytool` keychain profile)
#
# Notarization prerequisites (one-time):
#   xcrun notarytool store-credentials gmcc-ui \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
set -euo pipefail

SCHEME="GMVibes"
APP_NAME="GMVibes"
PROJECT="GMVibes.xcodeproj"
CONFIG="Release"
NOTARY_PROFILE="${NOTARY_PROFILE:-gmcc-ui}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Detect a Developer ID Application signing identity, if present.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)"

echo "==> Archiving $SCHEME ($CONFIG)…"
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
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
