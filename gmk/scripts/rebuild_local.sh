#!/bin/bash
#
# rebuild_local.sh — build the kernel from YOUR WORKING TREE and make it live.
#
# Builds the gm_kernel app through the workspace, stages the bundle's own
# executable into the local channel as `<version>-BETA`, regenerates the plugin
# from it, and activates. publish_release.sh promotes what this staged:
#
#     bash gmk/scripts/rebuild_local.sh            # build + stage + activate
#     bash gmk/scripts/rebuild_local.sh --app      # archive + SIGN the bundle, stage its CLI
#     bash gmk/scripts/publish_release.sh          # notarize, tag, upload
#
# A local build is ALWAYS stamped -BETA, with no flag to suppress it: the suffix
# is the only thing distinguishing bits that were merely built from bits that
# were published, and it is what keeps `gm_hook ping` on uncommitted work from
# looking like the release.
#
# arm64 by default: publish uploads THIS artifact rather than rebuilding, and
# the machines it ships to are Apple Silicon. `--universal` opts back up.
#
# Usage:
#   rebuild_local.sh              # arm64 only — releasable
#   rebuild_local.sh --universal  # arm64 + x86_64 — slower, rarely needed
#   rebuild_local.sh --fast       # accepted, inert synonym for the default
#   rebuild_local.sh --app        # archive + sign the bundle; its executable is the staged CLI
#   rebuild_local.sh --no-activate
#   rebuild_local.sh --no-lint    # skip the swift-format gate (swift_lint_format.sh)
#   rebuild_local.sh --env beta   # build into the beta environment's store
#
# Env:
#   GM_ENV                        # prod | beta | test (default: prod)
#   GM_FS_ROOT                    # explicit root; REFUSED alongside --env

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_build.sh
. "$SCRIPT_DIR/gm_build.sh"
gm_repo_root

die() { echo "[GMB] ERROR: $*" >&2; exit 1; }

ARCH_CHOICE="arm64"
ACTIVATE=1
# --app is OPT-IN: archiving and signing a bundle on every rebuild is a loop
# nobody would run. It is how release bits come into existence — publish
# promotes the signed bundle this produces and never builds one itself.
BUILD_APP=0
ENV_EXPLICIT=0
LINT=1
while [ $# -gt 0 ]; do
    case "$1" in
        --fast)        ;;
        --universal)   ARCH_CHOICE="universal" ;;
        --app)         BUILD_APP=1 ;;
        --no-activate) ACTIVATE=0 ;;
        --no-lint)     LINT=0 ;;
        --env)         shift; GM_ENV="${1:?--env needs prod|beta|test}"; ENV_EXPLICIT=1 ;;
        --env=*)       GM_ENV="${1#--env=}"; ENV_EXPLICIT=1 ;;
        "") ;;
        *) echo "[GMB] rebuild_local.sh: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done

xcode-select -p >/dev/null 2>&1 || die "no active developer directory — install Xcode and run xcode-select -s"

VERSION="$(cat "$GMK/VERSION")"
STAGE_VERSION="$VERSION-BETA"
BUILD_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

gm_resolve_fs_root

# THE ENVIRONMENT SELECTS THE BUILD CONFIGURATION, one to one. Each
# configuration bakes its root into the bundle's Info.plist, and the baked key
# — never $GM_FS_ROOT, which a LaunchServices-started app cannot see — is what
# decides which database that app writes.
BUILD_CONFIG="$(gm_env_config "$GM_ENV")" || die "no build configuration for environment '$GM_ENV'"
IS_PROD=0
[ "$GM_FS_ROOT" = "$HOME/gmfs" ] && IS_PROD=1
ARCH="$(gm_xcb_arch "$ARCH_CHOICE")"

# An explicit --env and an inherited GM_FS_ROOT that disagree would print one
# environment name and write another store. Refuse rather than pick.
if [ "$ENV_EXPLICIT" = 1 ] && [ "$GM_FS_ROOT" != "$(gm_env_root "$GM_ENV")" ]; then
    echo "[GMB] ERROR: --env $GM_ENV means $(gm_env_root "$GM_ENV")," >&2
    echo "             but GM_FS_ROOT is set to $GM_FS_ROOT." >&2
    echo "       Drop one of them. Unset GM_FS_ROOT to use --env, or drop --env" >&2
    echo "       to use the root you exported." >&2
    exit 2
fi

# Print the root before doing anything: this script shuts down a kernel and
# rewrites a release store.
echo "[GMB] environment: $GM_ENV   root: $GM_FS_ROOT"
echo "[GMB] building v$STAGE_VERSION ($BUILD_CONFIG, $ARCH_CHOICE) from $REPO_ROOT @ $BUILD_SHA"

# --- lint --------------------------------------------------------------------
# Lint-only gate; it never rewrites the tree. The committed git hooks are
# activated here once per clone.
if [ "$LINT" -eq 1 ]; then
    HOOKS_PATH="$(git -C "$REPO_ROOT" config core.hooksPath || true)"
    if [ -z "$HOOKS_PATH" ]; then
        git -C "$REPO_ROOT" config core.hooksPath gmk/scripts/githooks
        echo "[GMB] git hooks: core.hooksPath -> gmk/scripts/githooks"
    elif [ "$HOOKS_PATH" != "gmk/scripts/githooks" ]; then
        echo "[GMB] git hooks: core.hooksPath is $HOOKS_PATH (left alone; repo hooks live in gmk/scripts/githooks)"
    fi
    bash "$SCRIPT_DIR/swift_lint_format.sh"
else
    echo "[GMB] lint skipped (--no-lint)"
fi

# --- build and stage ---------------------------------------------------------
# One target, one bundle. Build identity is stamped by the VERSION build rule
# inside the build graph, so there is no shell step left to forget.
#
# ONE STAGING PATH. Both routes yield an app bundle whose executable at
# Contents/MacOS/gm_kernel IS the CLI: the plain build's product, or the
# signed archive `--app` produces — the SAME bytes the DMG ships and publish
# promotes. A function because the roster-moved path below runs it twice.
build_and_stage() {
    echo "[GMB]   gm_xcb build $BUILD_CONFIG ($ARCH)"
    # shellcheck disable=SC2086
    gm_xcb build "$BUILD_CONFIG" $ARCH MARKETING_VERSION="$VERSION" -quiet

    if [ "$BUILD_APP" = 1 ]; then
        echo "[GMB] archiving the app ($BUILD_CONFIG) — its executable becomes the staged CLI"
        UNIVERSAL_FLAG=""
        [ "$ARCH_CHOICE" = "universal" ] && UNIVERSAL_FLAG="--universal"
        # shellcheck disable=SC2086
        bash "$SCRIPT_DIR/build-dmg.sh" --config "$BUILD_CONFIG" $UNIVERSAL_FLAG "$VERSION"
        APP="$GMK/build/$GM_APP_NAME.xcarchive/Products/Applications/$GM_APP_NAME.app"
    else
        APP="$(gm_xcb_app "$BUILD_CONFIG")"
    fi
    [ -d "$APP" ] || die "no app bundle at $APP"

    # The bundle's baked root must match the store being staged into. Compared
    # against $GM_FS_ROOT, never against the env name: the root being WRITTEN is
    # the only thing worth comparing to.
    BAKED="$(gm_app_baked "$APP")" || exit 1
    read -r BAKED_ENV BAKED_ROOT <<<"$BAKED"
    if [ "${BAKED_ROOT/#\~/$HOME}" != "$GM_FS_ROOT" ]; then
        echo "[GMB] ERROR: the app bakes '$BAKED_ENV' -> '$BAKED_ROOT'" >&2
        echo "             but this run stages into $GM_FS_ROOT." >&2
        echo "       That app would write one database while sitting beside another's" >&2
        echo "       binaries. Refusing." >&2
        exit 1
    fi

    # Staged fresh every time: the directory is removed and rebuilt, so a binary
    # that stopped being produced cannot linger and get shipped. A running app
    # from this store holds the old bundle open, so it is stopped first.
    #
    # Production stages the Mach-O and installs the bundle into /Applications
    # after activation; a beta or test root stages the whole bundle, because
    # clients on it launch the kernel from the store.
    [ "$IS_PROD" = 1 ] || gm_stop_kernel_and_wait
    rm -rf "$(gm_stage_dir local "$STAGE_VERSION")"
    if [ "$IS_PROD" = 1 ]; then
        STAGE="$(gm_stage_from_bundle "$APP" local "$STAGE_VERSION" "$BUILD_SHA" | tail -1)"
    else
        STAGE="$(gm_stage_bundle "$APP" local "$STAGE_VERSION" "$BUILD_SHA" | tail -1)"
    fi
    STAGED_MACHO="$(gm_staged_binaries "$STAGE")"
    [ -n "$STAGED_MACHO" ] || die "staging from $APP produced nothing"
    STAGED_MACHO="$STAGE/$STAGED_MACHO"

    # NEVER STRIPPED, NEVER RE-SIGNED HERE. The plain build carries the linker's
    # ad-hoc signature and the --app build the Developer ID's; either verifies
    # standalone and is staged as-is. Stripping would invalidate the first and
    # re-signing would destroy the second. Only what does not verify is
    # re-signed ad-hoc, and the staging function does that before the manifest
    # is written.
    codesign --verify --strict "$STAGED_MACHO" || die "$GM_MACHO in $STAGE has no valid signature"
    echo "[GMB] staged $STAGE  ($GM_MACHO [$(lipo -archs "$STAGED_MACHO" 2>/dev/null || echo '?')], signature verified)"
}

build_and_stage

# --- generate the plugin -----------------------------------------------------
# THE PLUGIN IS PART OF THE BUILD: `gm_kernel bridge` on the exact binary just
# staged emits plugins/gmcc, so the plugin on disk always reflects these bits.
# generate_plugin.sh owns the marketplace bump; it runs even with --no-activate
# because the plugin is working-tree content.
#
# EXIT 3 MEANS THE ROSTER MOVED. The kernel just staged was compiled against the
# previous roster, so it cannot serve the one the bridge has written: build over
# the new source, restage, and generate once more. ONCE — a roster that moves on
# the second pass is a generator that is not converging, and the exit propagates.
echo "[GMB] generating the plugin from the staged kernel..."
GEN_RC=0
GM_KERNEL_BIN="$STAGED_MACHO" bash "$SCRIPT_DIR/generate_plugin.sh" || GEN_RC=$?
if [ "$GEN_RC" -eq 3 ]; then
    echo "[GMB] roster moved — rebuilding so the staged kernel serves it"
    build_and_stage
    GM_KERNEL_BIN="$STAGED_MACHO" bash "$SCRIPT_DIR/generate_plugin.sh"
elif [ "$GEN_RC" -ne 0 ]; then
    exit "$GEN_RC"
fi

# --- activate ----------------------------------------------------------------
if [ "$ACTIVATE" -eq 1 ]; then
    gm_activate local "$STAGE_VERSION"
    gm_stop_kernel_and_wait
    # Production launches /Applications/gm_kernel.app by bundle identifier, so
    # the build just activated must be the bundle installed there, or newer
    # hooks keep quitting and relaunching the older app.
    [ "$IS_PROD" = 1 ] && { gm_install_app_bundle "$APP" || die "could not install $APP into $GM_APP_DEST"; }
else
    echo "[GMB] not activated (--no-activate). Activate with:"
    echo "      bash $SCRIPT_DIR/rebuild_local.sh   # or re-run without the flag"
fi
