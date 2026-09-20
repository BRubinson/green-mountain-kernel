#!/usr/bin/env bash
#
# build-dmg.sh — archive the gm_kernel app through the workspace, sign it
# inside-out, and package a distributable .dmg. Run from anywhere; the repo is
# resolved from this script's own location.
#
# Signing auto-detects:
#   • With a "Developer ID Application" cert installed, the app is signed with
#     the hardened runtime and the DMG can be notarized (NOTARIZE=1).
#   • Otherwise the app is ad-hoc signed; recipients clear quarantine once.
#
# ── THE VERSION COMES FROM gmk/VERSION, NOT FROM THE PROJECT FILE ────────────
#
# One release, one number. MARKETING_VERSION is STAMPED from gmk/VERSION as a
# build-setting override at archive time, so project.pbxproj is never rewritten
# and the working tree stays clean for publish_release.sh's check.
#
# Usage:
#   scripts/build-dmg.sh                       # Release at gmk/VERSION (auto-detect signing)
#   scripts/build-dmg.sh --config Beta 50.0.2  # explicit configuration and version
#   scripts/build-dmg.sh --universal           # arm64 + x86_64 (arm64 alone by default)
#   NOTARIZE=1 scripts/build-dmg.sh            # also notarize + staple (needs Dev ID
#                                              # + a `notarytool` keychain profile)
#
# Output: build/gm_kernel-<version>[-<config>].dmg. The version is in the name
# because it becomes a release asset; the configuration is in the name because
# two DMGs installing two applications that write two different databases must
# never be called the same thing.
#
# Notarization prerequisites (one-time):
#   xcrun notarytool store-credentials gmcc-ui \
#       --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
#
set -euo pipefail

# shellcheck source=gm_build.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gm_build.sh"
gm_repo_root
cd "$GMK"

die() { echo "error: $*" >&2; exit 1; }

NOTARY_PROFILE="${NOTARY_PROFILE:-gmcc-ui}"

# THE CONFIGURATION IS THE ENVIRONMENT. Each one bakes its own GMFSRoot into
# the Info.plist, and the baked key — not $GM_FS_ROOT, which a LaunchServices-
# started app never sees — is what decides the database an app writes. Release
# (prod) is the only one publish_release.sh may ship; a Beta bundle is a
# DIFFERENT APPLICATION to LaunchServices and its own single writer.
CONFIG="Release"
ARCH_CHOICE="arm64"

VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config)    CONFIG="${2:-}"; shift 2 ;;
        --universal) ARCH_CHOICE="universal"; shift ;;
        -*) die "unknown flag $1" ;;
        *)  VERSION="$1"; shift ;;
    esac
done

WANT_ENV="$(gm_config_env "$CONFIG")" || die "--config must be Release, Beta or Debug (got '$CONFIG')"
CONFIG_SUFFIX=""
[ "$CONFIG" = "Release" ] || CONFIG_SUFFIX="-$(tr '[:upper:]' '[:lower:]' <<<"$CONFIG")"

VERSION="${VERSION:-$(cat "$GMK/VERSION")}"
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || die "no version — gmk/VERSION is empty and none was passed"

BUILD_DIR="$GMK/build"
ARCHIVE="$BUILD_DIR/$GM_APP_NAME.xcarchive"
STAGE="$BUILD_DIR/dmg"
DMG_PATH="$BUILD_DIR/$GM_APP_NAME-$VERSION$CONFIG_SUFFIX.dmg"

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

DEV_ID="$(gm_dev_id)"

# BRACES ARE LOAD-BEARING in the message: `…` is multi-byte and bash absorbs
# its leading byte into an unbraced name, which `set -u` then reports as unset.
echo "==> Archiving $GM_APP_NAME ($CONFIG) at ${VERSION}…"
# Through the WORKSPACE, so gmk.xcworkspace/xcshareddata/swiftpm/Package.resolved
# is the one lockfile (-project resolves from the project's private one).
# Version and architecture ride as command-line overrides, never as project
# edits, so the tree publish_release.sh requires clean stays clean.
# shellcheck disable=SC2046
gm_xcb archive "$CONFIG" -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$VERSION" \
  $(gm_xcb_arch "$ARCH_CHOICE") CODE_SIGN_STYLE=Manual -quiet

APP="$ARCHIVE/Products/Applications/$GM_APP_NAME.app"
[ -d "$APP" ] || die "archive did not produce $APP"

# ── The baked root must BE THERE and BE THE ONE THIS CONFIGURATION ASKED FOR ─
#
# gm_app_baked fails the build on an absent key (the app would fall through to
# ~/gmfs and write PRODUCTION while believing it is isolated). The comparison
# below catches the worse case: a bundle labelled beta that bakes ~/gmfs writes
# production while its own menu bar says otherwise. Both keys are checked,
# because they come from two build settings and disagreeing is itself the bug.
BAKED="$(gm_app_baked "$APP")"
read -r BAKED_ENV BAKED_ROOT <<<"$BAKED"
echo "  baked environment: $BAKED_ENV -> $BAKED_ROOT"
WANT_ROOT_ABS="$(gm_env_root "$WANT_ENV")"
WANT_ROOT="~${WANT_ROOT_ABS#"$HOME"}"
if [ "$BAKED_ENV" != "$WANT_ENV" ] || [ "$BAKED_ROOT" != "$WANT_ROOT" ]; then
    echo "error: $CONFIG baked '$BAKED_ENV' -> '$BAKED_ROOT', expected '$WANT_ENV' -> '$WANT_ROOT'." >&2
    echo "       A bundle whose baked root disagrees with its configuration writes" >&2
    echo "       the wrong database and says nothing about it. Refusing to build." >&2
    exit 1
fi

# ── The CLI must actually be IN the bundle, and be the kernel ───────────────
#
# The bundle is the ONLY shipped artifact: install_gm.sh takes the app from the
# DMG and the CLI out of the app. A bundle with no kernel installs cleanly and
# leaves $GM_FS_ROOT/bin empty — and gm_hook exits 0 SILENTLY when its binary
# is missing, so the machine records nothing rather than reporting a problem.
HELPER="$(gm_app_kernel "$APP")"
APP_ARCHS="$(lipo -archs "$HELPER")"
echo "  slices: $GM_MACHO [$APP_ARCHS]"
case " $APP_ARCHS " in *" arm64 "*) ;; *)
    die "$GM_MACHO carries no arm64 slice ([$APP_ARCHS])" ;;
esac

# ── Signing: INSIDE-OUT, and `--deep` is gone ────────────────────────────────
#
# `--deep` is deprecated and wrong for a bundle carrying embedded executables:
# helpers must be signed INDIVIDUALLY, innermost first, each with the hardened
# runtime and the same Team ID, and the outer bundle LAST — otherwise the outer
# seal is computed over helper signatures that are then replaced. The failure
# is remote and late: `--verify` passes locally and notarization rejects the
# submission minutes later. `--deep` survives on --verify, where it reads.
sign_inside_out() {
  _identity="$1"
  _runtime_flags="$2"

  # Nested executables first, each independently; the bundle carries none
  # today (the kernel IS the main executable), but a helper added later must
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

# Verify DEEPLY — the one place --deep is correct, because it reads.
codesign --verify --strict --deep-verify -vv "$APP" 2>&1 | sed 's/^/    /'

echo "==> Staging DMG contents…"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

echo "==> Building ${DMG_PATH}…"
hdiutil create -volname "$GM_APP_NAME" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG_PATH"

if [ -n "$DEV_ID" ]; then
  codesign --force --sign "$DEV_ID" "$DMG_PATH"
fi

if [ "${NOTARIZE:-0}" = "1" ]; then
  [ -n "$DEV_ID" ] || die "NOTARIZE=1 requires a Developer ID cert"
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
