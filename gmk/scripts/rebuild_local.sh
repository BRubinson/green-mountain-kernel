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
# ── WHY arm64 BY DEFAULT ─────────────────────────────────────────────────────
#
# publish_release.sh uploads THIS artifact rather than rebuilding one, so what
# you tested is what ships — which is only true if the thing you tested is
# already shaped like a release: stripped, signed, and carrying the slices that
# will actually be executed.
#
# THAT SET IS NOW arm64 ALONE. It used to be universal, and `--fast` existed to
# opt DOWN to arm64 for the edit-compile loop while publish REFUSED the result.
# The default inverted because the x86_64 slice buys nothing: it compiles and
# links every module a second time, the toolchain itself emits "the x86_64
# architecture is deprecated for your deployment target", and the machines this
# ships to are Apple Silicon. `--universal` opts back UP for the day that stops
# being true.
#
# `--fast` IS KEPT as an accepted flag and is now a no-op synonym for the
# default. Deleting it would break muscle memory and any scripted caller for no
# gain; saying so here is cheaper than a stack of confused re-runs.
#
# Usage:
#   rebuild_local.sh              # arm64 only — releasable
#   rebuild_local.sh --universal  # arm64 + x86_64 — slower, rarely needed now
#   rebuild_local.sh --fast       # accepted, no-op synonym for the default
#   rebuild_local.sh --no-activate
#
#   rebuild_local.sh --env beta   # build into the beta environment's store
#
# Env:
#   GM_ENV                        # prod | beta | test (default: prod)
#   GM_FS_ROOT                    # explicit root; WINS over GM_ENV when set

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

# ONLY WHAT THE STAGED ARTIFACT IS MADE OF. gmKernel links GmKernelHost,
# GmMcpServer and GmHookCli — all of which live in gmDaemon and gmDaemonSdk — and
# its Mach-O is the one file this script stages.
#
# gmUxComponentLibrary and gmAgententicsSdk USED TO BE IN THIS LIST and are
# deliberately not any more. Neither is linked into gm_kernel: the first is UI
# consumed only by gmVibesCore, the second is the generator/tool surface. They
# were being built universal-release on every publish purely as a compile check,
# at roughly 50s each.
#
# THE CHECK MOVED, IT DID NOT VANISH: .github/workflows/gmk-ci.yml runs a
# `packages` matrix with one job per package, so both still compile on every
# push and a break still names the module that broke. Do not "restore" them here.
PACKAGES="gmDaemonSdk gmDaemon gmKernel"

ARCH_FLAGS=""
ARCHES="arm64"
ACTIVATE=1
while [ $# -gt 0 ]; do
    case "$1" in
        # Accepted and intentionally inert — arm64 IS the default now. Kept so an
        # existing caller or habit does not break. See the header.
        --fast)        ;;
        --universal)   ARCH_FLAGS="--arch arm64 --arch x86_64"; ARCHES="arm64,x86_64" ;;
        --no-activate) ACTIVATE=0 ;;
        # Which environment's store to build into. Default prod — unchanged for
        # every existing caller. GM_FS_ROOT still wins if it is set explicitly,
        # so a harness minting a scratch root needs no flag at all.
        --env)         shift; GM_ENV="${1:?--env needs prod|beta|test}" ;;
        --env=*)       GM_ENV="${1#--env=}" ;;
        "") ;;
        *) echo "[GMB] rebuild_local.sh: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done

[ -f "$GMK/gmDaemonSdk/Package.swift" ] || {
    echo "[GMB] ERROR: gmk packages not found under $GMK" >&2; exit 1; }
command -v swift >/dev/null 2>&1 || {
    echo "[GMB] ERROR: swift toolchain not found — xcode-select --install" >&2; exit 1; }

VERSION="$(cat "$GMK/VERSION")"
STAGE_VERSION="$VERSION-BETA"
BUILD_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"

gm_resolve_fs_root

# PRINT THE ROOT BEFORE DOING ANYTHING. This script shuts down a daemon and
# rewrites a release store; an inherited GM_FS_ROOT silently retargeting both
# was previously invisible, which is the kind of quiet that costs an afternoon.
echo "[GMB] environment: $GM_ENV   root: $GM_FS_ROOT"
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
# gmDaemonSdk / gmDaemon (the pen server now lives in gmDaemonSdk), and
# gmKernel links all three personalities into a single
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

# --- generate the plugin -----------------------------------------------------
# THE PLUGIN IS PART OF THE BUILD. It is not a separate manual chore:
# plugins/gmcc is emitted from the bridge in gmAgententicsSdk, so a build of this
# working tree that did not regenerate it could report success while the plugin
# on disk still reflected an older bridge — with nothing saying so.
#
# Placed AFTER the build and staging: the kernel build is the expensive and most
# likely to fail step, and there is no reason to rewrite repo content to
# accompany bits that never built. Placed BEFORE activation because it is
# working-tree content, not part of the release store.
#
# RUNS EVEN WITH --no-activate, deliberately. The plugin is produced regardless
# of whether these binaries are promoted into the store.
#
# Delegated to generate_plugin.sh rather than reimplemented here. That script
# owns two things this one must not duplicate: the repo-root resolution guard,
# and the two-owner split that keeps gm_bridge_writer inside plugins/gmcc while
# the repo-ROOT marketplace manifest is bumped separately. It is idempotent — an
# unchanged bridge at an unchanged version produces no diff.
#
# YES, THIS BUILDS gmAgententicsSdk, which was deliberately removed from
# $PACKAGES above. That is not a contradiction and is not an oversight to
# "optimise" away: it is excluded from PACKAGES because it is not linked into the
# staged Mach-O, and it is built here because it IS the generator.
echo "[GMB] generating the plugin from the bridge..."
bash "$SCRIPT_DIR/generate_plugin.sh"

# --- activate ----------------------------------------------------------------
if [ "$ACTIVATE" -eq 1 ]; then
    gm_activate local "$STAGE_VERSION"
    gm_retire_daemon
else
    echo "[GMB] not activated (--no-activate). Activate with:"
    echo "      bash $SCRIPT_DIR/rebuild_local.sh   # or re-run without the flag"
fi

# NO WARNING FOR arm64 ANY MORE. This block used to fire on every arm64 build to
# say publish would refuse the artifact. That was true when universal was the
# default and `--fast` was the opt-out; it is now exactly backwards, and a stale
# warning telling an operator their correct release build is unpublishable is
# worse than no warning at all.
#
# publish_release.sh still verifies with lipo rather than trusting the manifest,
# and still REFUSES an artifact with no arm64 slice. That is the check that
# matters and it is unchanged.
