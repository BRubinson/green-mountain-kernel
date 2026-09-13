#!/usr/bin/env bash
#
# build-dmg.sh — Build the GM kernel app (gmk/gmVibes/ in the green-mountain-kernel
# monorepo) into a distributable .dmg. The bundle is gm_kernel.app; the Xcode
# target and scheme are still named GMVibes.
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
# Output: build/gm_kernel-<version>.dmg — the name carries the version because it
# becomes a release asset, and an asset named gm_kernel.dmg forces every installer
# to guess what is inside it. The BUNDLE was renamed GMVibes.app -> gm_kernel.app
# when the app became the kernel host; gm_releases.sh's GM_APP_NAME and this
# script's APP_NAME are the two spellings that must agree.
#
# Notarization prerequisites (one-time):
#   xcrun notarytool store-credentials gmcc-ui \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
set -euo pipefail

SCHEME="GMVibes"
# The BUNDLE name, which is now gm_kernel — the app hosts the writer, so the
# bundle IS the kernel. The Xcode TARGET and SCHEME stay named GMVibes (this
# script and gmk-ci.yml both drive `-scheme GMVibes`), and the BUNDLE IDENTIFIER
# stays `rube.GMVibes` on purpose: a new id is a new NSUserDefaults domain, so
# every preference and window position would reset once for no functional gain.
# gm_releases.sh's GM_APP_NAME must agree with this or the installer looks for a
# bundle the build never produced.
APP_NAME="gm_kernel"
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

# ── Signing: INSIDE-OUT, and `--deep` is gone ────────────────────────────────
#
# `--deep` is deprecated by Apple and is the wrong tool for a bundle that carries
# embedded executables. It became the wrong tool for THIS bundle the moment the
# kernel CLI moved inside it: helpers must be signed INDIVIDUALLY, innermost
# first, each with the hardened runtime and the same Team ID, and the outer bundle
# LAST — otherwise the outer signature is computed over helper signatures that are
# then replaced, and the seal no longer describes the contents.
#
# THE FAILURE IS REMOTE AND LATE, which is why this is worth the words: `--deep`
# signs without complaint and `codesign --verify` passes locally. Notarization
# rejects the submission minutes later, on a machine you are not looking at, with
# a message about nested code. Nothing on the build host tells you.
#
# `--deep` survives on --verify, where it is the correct flag: verifying deeply is
# reading, not writing.
sign_inside_out() {
  _identity="$1"
  _runtime_flags="$2"

  # Helpers first, deepest last-modified order irrelevant — each is independent.
  # `-perm +111 -type f` rather than a hardcoded list: a helper added later must
  # not silently ship unsigned.
  if [ -d "$APP/Contents/Helpers" ]; then
    find "$APP/Contents/Helpers" -type f -perm +111 -print | while IFS= read -r helper; do
      echo "    helper: $(basename "$helper")"
      # shellcheck disable=SC2086
      codesign --force --timestamp $_runtime_flags --sign "$_identity" "$helper"
    done
  fi

  # Frameworks and dylibs, if any ever appear.
  for _dir in "$APP/Contents/Frameworks" "$APP/Contents/XPCServices"; do
    [ -d "$_dir" ] || continue
    find "$_dir" -depth 1 -print | while IFS= read -r item; do
      echo "    nested: $(basename "$item")"
      # shellcheck disable=SC2086
      codesign --force --timestamp $_runtime_flags --sign "$_identity" "$item"
    done
  done

  # The outer bundle LAST.
  echo "    bundle: $(basename "$APP")"
  # shellcheck disable=SC2086
  codesign --force --timestamp $_runtime_flags --sign "$_identity" "$APP"
}

if [ -n "$DEV_ID" ]; then
  echo "==> Signing with: $DEV_ID (hardened runtime, inside-out)"
  sign_inside_out "$DEV_ID" "--options runtime"
else
  echo "==> No Developer ID found — ad-hoc signing (inside-out)."
  echo "    Recipients must clear quarantine once (see README)."
  sign_inside_out "-" ""
fi

# Verify DEEPLY — this is the one place --deep is correct, because it reads.
codesign --verify --strict --deep-verify -vv "$APP" 2>&1 | sed 's/^/    /'

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
