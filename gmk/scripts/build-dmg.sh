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
NOTARY_PROFILE="${NOTARY_PROFILE:-gmcc-ui}"

# ── Which environment's bundle is this? ──────────────────────────────────────
#
# THE CONFIGURATION IS THE ENVIRONMENT. Each one bakes its own GMFSRoot into the
# Info.plist, and the baked key — not $GM_FS_ROOT, which a LaunchServices-started
# app never sees — is what decides the database an app writes:
#
#   Release → ~/gmfs        (prod)    the ONLY thing publish_release.sh may ship
#   Beta    → ~/beta_gmfs   (beta)    hand-built, hand-delivered, never published
#   Debug   → ~/test_gmfs   (test)    what Xcode Run produces
#
# A Beta bundle is a DIFFERENT APPLICATION to LaunchServices (its bundle id
# carries `.beta`), so it is its own single writer over its own root rather than
# a second writer over prod's.
CONFIG="Release"
CONFIG_SUFFIX=""

# gmk/ — the directory holding the one Xcode project, one level up from
# gmk/scripts/. This script sits beside build_gm.sh rather than under
# gmk/gmVibes/ because everything in the app's source directory is inside its
# filesystem-synchronized Xcode group, and a shell script is not app sources.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION=""
while [ $# -gt 0 ]; do
    case "$1" in
        --config)
            CONFIG="${2:-}"; shift 2
            case "$CONFIG" in
                Release) CONFIG_SUFFIX="" ;;
                Beta)    CONFIG_SUFFIX="-beta" ;;
                Debug)   CONFIG_SUFFIX="-debug" ;;
                *) echo "error: --config must be Release, Beta or Debug (got '$CONFIG')" >&2; exit 1 ;;
            esac
            ;;
        -*) echo "error: unknown flag $1" >&2; exit 1 ;;
        *)  VERSION="$1"; shift ;;
    esac
done

VERSION="${VERSION:-$(cat "$ROOT/VERSION")}"
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || { echo "error: no version — gmk/VERSION is empty and none was passed" >&2; exit 1; }

BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
STAGE="$BUILD_DIR/dmg"
# THE ENVIRONMENT IS IN THE FILENAME. Two DMGs named identically that install
# two different applications writing two different databases is exactly the
# ambiguity the per-bundle baked root exists to remove; reintroducing it in the
# filename would be a joke at our own expense.
DMG_PATH="$BUILD_DIR/$APP_NAME-$VERSION$CONFIG_SUFFIX.dmg"

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
# ── The CLI comes FIRST, and it is built here rather than by Xcode ──────────
#
# `gm_kernel` is a SwiftPM executable. Building it from inside an xcodebuild
# script phase would put two build systems on one build directory, so the phase
# only COPIES — this is where the bytes come from, and the path is handed over
# as GM_KERNEL_MACHO.
#
# ARCHS must match the archive's. A universal app around an arm64-only helper is
# a bundle that half-works on an Intel machine, which is worse than one that
# plainly does not.
echo "==> Building the gm_kernel CLI…"
swift build -c release --package-path "$ROOT/gmKernel" --arch arm64 >/dev/null
GM_KERNEL_MACHO="$(swift build -c release --package-path "$ROOT/gmKernel" --arch arm64 --show-bin-path)/gm_kernel"
[ -x "$GM_KERNEL_MACHO" ] || {
    echo "error: the CLI build produced no executable at $GM_KERNEL_MACHO" >&2; exit 1; }
echo "  CLI: $GM_KERNEL_MACHO ($(lipo -archs "$GM_KERNEL_MACHO"))"

echo "==> Archiving $SCHEME ($CONFIG) at ${VERSION}…"
# MARKETING_VERSION/CURRENT_PROJECT_VERSION are overridden on the command line
# rather than written into project.pbxproj: the number lives in gmk/VERSION, and
# a build that edits the project file would dirty the tree that
# publish_release.sh requires to be clean.
# ARCHS=arm64 for the same reason rebuild_local.sh dropped the Intel slice: the
# archive was compiling every dependency in the app's graph — GRDB included —
# a second time for x86_64, and the machines this ships to are Apple Silicon.
# This is the app-side half of that saving.
#
# ONLY_ACTIVE_ARCH=NO is set alongside it DELIBERATELY. Left at YES the output
# would depend on the architecture of whatever machine happened to run the
# archive, which means the same command producing different bits on different
# builders — exactly the ambiguity a release build must not have.
#
# Passed on the COMMAND LINE, like MARKETING_VERSION above and for the same
# reason: a build that edits project.pbxproj dirties the tree publish_release.sh
# requires to be clean.
xcodebuild archive \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration "$CONFIG" \
  -archivePath "$ARCHIVE" \
  MARKETING_VERSION="$VERSION" \
  CURRENT_PROJECT_VERSION="$VERSION" \
  GM_KERNEL_MACHO="$GM_KERNEL_MACHO" \
  ARCHS=arm64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGNING_ALLOWED=NO \
  | grep -E "^(===|\*\*|note:|error:|warning:)" || true

APP="$ARCHIVE/Products/Applications/$APP_NAME.app"
[ -d "$APP" ] || { echo "error: archive did not produce $APP" >&2; exit 1; }

# ── The baked root must BE THERE, and a missing one is FATAL ─────────────────
#
# The app resolves its filesystem root from this Info.plist key first, precisely
# so that no launch context can redirect it. The failure mode when the key is
# absent is the dangerous direction: resolution falls through to ~/gmfs and the
# bundle writes PRODUCTION while believing it is isolated.
#
# That is not hypothetical. `INFOPLIST_KEY_GMFSRoot` — the obvious way to set
# this — is silently DROPPED, because that build-setting prefix is a declared
# allow-list Xcode filters against. It builds clean and produces a bundle with
# no key. Verified empirically; hence a real Info.plist, and hence this gate.
#
# Fail the BUILD rather than ship a bundle whose root is a guess.
BAKED_ROOT="$(plutil -extract GMFSRoot raw "$APP/Contents/Info.plist" 2>/dev/null || true)"
case "$BAKED_ROOT" in
    ""|*'$('*)
        echo "error: $APP has no usable GMFSRoot in Info.plist (got '${BAKED_ROOT:-<absent>}')." >&2
        echo "       Without it the app falls through to ~/gmfs and writes PRODUCTION." >&2
        exit 1
        ;;
esac
BAKED_ENV="$(plutil -extract GMEnvironment raw "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
echo "  baked environment: $BAKED_ENV -> $BAKED_ROOT"

# ── …AND IT MUST BE THE ROOT THIS CONFIGURATION ASKED FOR ───────────────────
#
# The check above catches an ABSENT key. This one catches a WRONG one, which is
# the worse failure by a distance: a bundle labelled beta that bakes ~/gmfs
# writes production while its own menu bar says otherwise, and every safeguard
# downstream reads the label rather than the root.
#
# Cross-check both keys against the configuration, because they come from two
# separate build settings and disagreeing is itself the bug.
case "$CONFIG" in
    Release) WANT_ENV="prod"; WANT_ROOT="~/gmfs" ;;
    Beta)    WANT_ENV="beta"; WANT_ROOT="~/beta_gmfs" ;;
    Debug)   WANT_ENV="test"; WANT_ROOT="~/test_gmfs" ;;
esac
if [ "$BAKED_ENV" != "$WANT_ENV" ] || [ "$BAKED_ROOT" != "$WANT_ROOT" ]; then
    echo "error: $CONFIG baked '$BAKED_ENV' -> '$BAKED_ROOT', expected '$WANT_ENV' -> '$WANT_ROOT'." >&2
    echo "       A bundle whose baked root disagrees with its configuration writes" >&2
    echo "       the wrong database and says nothing about it. Refusing to build." >&2
    exit 1
fi

# ── The CLI must actually be IN the bundle ──────────────────────────────────
#
# The bundle is the ONLY shipped artifact now: `install_gm.sh` takes the app from
# the DMG and the CLI out of the app. A bundle with no helper installs cleanly
# and leaves $GM_FS_ROOT/bin empty — and because `gm_hook` exits 0 SILENTLY when
# its binary is missing, the result is a machine that records nothing rather than
# one that reports a problem.
#
# The embed phase is sandboxed and declares this exact path as its output, so it
# either landed or the build already failed. Check anyway: this assertion is
# cheap and the failure it guards is silent.
HELPER="$APP/Contents/Helpers/gm_kernel"
[ -x "$HELPER" ] || {
    echo "error: $APP carries no Contents/Helpers/gm_kernel." >&2
    echo "       The 'Embed gm_kernel CLI' phase did not run or did not land." >&2
    exit 1; }

# ── Slice verification, which used to live in publish ───────────────────────
#
# publish_release.sh read slices off the TARBALL with lipo. The tarball is gone,
# so the check has to happen where the bits are made or it does not happen at
# all. Verify the helper and the app's own Mach-O carry the same architectures —
# a universal app around an arm64-only helper half-works, which is worse than a
# clean refusal.
HELPER_ARCHS="$(lipo -archs "$HELPER")"
APP_ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME")"
echo "  slices: app [$APP_ARCHS], helper [$HELPER_ARCHS]"
if [ "$HELPER_ARCHS" != "$APP_ARCHS" ]; then
    echo "error: app is [$APP_ARCHS] but its helper is [$HELPER_ARCHS]." >&2
    echo "       A bundle whose halves disagree on architecture fails on one machine" >&2
    echo "       and not another. Refusing to build." >&2
    exit 1
fi

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
