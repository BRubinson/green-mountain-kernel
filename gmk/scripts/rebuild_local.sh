#!/bin/bash
#
# rebuild_local.sh — build the gmk stack from YOUR WORKING TREE and make it live.
#
# This is the developer command. It builds, stages into the local channel as
# `<version>-BETA`, and activates it. The companion is publish_release.sh, which
# takes a staged BETA and ships it:
#
#     bash gmk/scripts/rebuild_local.sh        # build + stage + activate
#     bash gmk/scripts/publish_release.sh      # tag, upload, activate as release
#
# ── WHY -BETA, ALWAYS ────────────────────────────────────────────────────────
#
# A locally built binary is NEVER stamped with a bare release version. There is
# no flag to suppress the suffix. Without it, `gm_hook ping` on a machine running
# uncommitted work is indistinguishable from one running the published build, and
# the first time that matters is the one time it matters: diagnosing a bug that
# only reproduces against bits nobody else has.
#
# ── WHY UNIVERSAL BY DEFAULT ─────────────────────────────────────────────────
#
# Because publish_release.sh uploads THIS artifact rather than rebuilding one.
# What you tested is what ships, which is only true if the thing you tested is
# already shaped like a release: both slices, stripped, signed. `--fast` exists
# for the edit-compile loop and produces a binary that publish will REFUSE, by
# design — it checks slices with lipo rather than trusting the manifest.
#
# Usage:
#   rebuild_local.sh              # universal (arm64 + x86_64) — releasable
#   rebuild_local.sh --fast       # arm64 only — quicker, NOT releasable
#   rebuild_local.sh --no-activate
#
# Env:
#   GM_FS_ROOT                    # the one filesystem root (default: $HOME/gmfs)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_releases.sh
. "$SCRIPT_DIR/gm_releases.sh"

# --- locate the repo ---------------------------------------------------------
# git first; the script-dir walk is the fallback for a checkout with no git
# metadata (a tarball, a vendored copy). The `-d $REPO_ROOT/gmk` test is not
# decoration: `git rev-parse` run from an unexpected directory can resolve to a
# DIFFERENT enclosing repository — a $HOME that happens to be version-controlled
# is the case that actually bites — and the test is what rejects that answer.
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
fi
GMK="$REPO_ROOT/gmk"

PACKAGES="gmDaemonSdk gmDaemon gmUxComponentLibrary gmAgententicsSdk gmMcp gmKernel"

ARCH_FLAGS="--arch arm64 --arch x86_64"
ARCHES="arm64,x86_64"
ACTIVATE=1
for arg in "$@"; do
    case "$arg" in
        --fast)        ARCH_FLAGS=""; ARCHES="arm64" ;;
        --no-activate) ACTIVATE=0 ;;
        "") ;;
        *) echo "[GMB] rebuild_local.sh: unknown flag $arg" >&2; exit 2 ;;
    esac
done

[ -f "$GMK/gmDaemonSdk/Package.swift" ] || {
    echo "[GMB] ERROR: gmk packages not found under $GMK" >&2; exit 1; }
command -v swift >/dev/null 2>&1 || {
    echo "[GMB] ERROR: swift toolchain not found — xcode-select --install" >&2; exit 1; }

VERSION="$(cat "$GMK/VERSION")"
STAGE_VERSION="$VERSION-BETA"
BUILD_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

gm_resolve_fs_root

echo "[GMB] building v$STAGE_VERSION ($ARCHES) from $REPO_ROOT @ $BUILD_SHA"

# --- build -------------------------------------------------------------------
# Each package on its own so a failure names the module that broke rather than
# producing one opaque graph error — the property the CI matrix buys, kept here.
#
# No BuildInfo stamp step: the SwiftPM prebuild plugin in gmDaemon stamps build
# identity inside the build graph, so there is no shell step left to forget.
for p in $PACKAGES; do
    echo "[GMB]   $p"
    # shellcheck disable=SC2086
    swift build -c release --package-path "$GMK/$p" $ARCH_FLAGS
done

bin_path() {
    # shellcheck disable=SC2086
    swift build -c release --package-path "$GMK/$1" $ARCH_FLAGS --show-bin-path
}
# ONE bin path now. The three personalities are library targets inside
# gmDaemonSdk / gmDaemon / gmMcp, and gmKernel links all three into a single
# Mach-O — so there is exactly one artifact to stage and nothing to keep in sync.
KERNEL_BIN="$(bin_path gmKernel)"

# --- stage -------------------------------------------------------------------
# Staged fresh every time: the directory is removed and rebuilt rather than
# copied over, so a binary that stopped being produced cannot linger and get
# shipped alongside the ones that were.
STAGE="$(gm_stage_dir local "$STAGE_VERSION")"
rm -rf "$STAGE"
STAGE="$(gm_stage_dir local "$STAGE_VERSION")"

# ONE MACH-O. This block used to stage three binaries from three different bin
# paths, with a comment warning that staging them from one directory would ship a
# stale copy. That risk is gone with the artifact: there is one file, and the
# entry-point names become SYMLINKS at activation rather than staged files.
cp "$KERNEL_BIN/$GM_MACHO" "$STAGE/$GM_MACHO"

for b in $GM_MACHO; do
    # -S drops debug symbols only; exported symbols and functionality are kept.
    strip -S "$STAGE/$b"
    # Stripping INVALIDATES the signature, and arm64 refuses to exec an unsigned
    # Mach-O at all — so the re-sign is mandatory and must come after the strip,
    # not before. Ad-hoc is sufficient: these are CLIs installed by curl or built
    # here, never delivered through Gatekeeper's quarantine path.
    codesign --force --sign - --timestamp=none "$STAGE/$b" 2>/dev/null
    codesign --verify --strict "$STAGE/$b" || {
        echo "[GMB] ERROR: $b failed signature verification after strip" >&2; exit 1; }
done

gm_write_manifest "$STAGE" "$STAGE_VERSION" local "$BUILD_SHA" "$ARCHES"

echo "[GMB] staged $STAGE"
for b in $GM_MACHO; do
    echo "         $b  $(lipo -archs "$STAGE/$b" 2>/dev/null || echo '?')"
done
echo "         entry points (symlinked at activation): $GM_ENTRYPOINTS"

# --- activate ----------------------------------------------------------------
if [ "$ACTIVATE" -eq 1 ]; then
    gm_activate local "$STAGE_VERSION"
    gm_retire_daemon
else
    echo "[GMB] not activated (--no-activate). Activate with:"
    echo "      bash $SCRIPT_DIR/rebuild_local.sh   # or re-run without the flag"
fi

if [ "$ARCHES" = "arm64" ]; then
    echo ""
    echo "[GMB] NOTE: --fast built arm64 only. publish_release.sh will refuse this"
    echo "      artifact; re-run without --fast before publishing."
fi
