#!/bin/bash
#
# install_gm.sh — THE FRONT DOOR for everyone who is not editing the sources.
#
# Fetches the `gm_kernel-v*` release whose version matches this plugin's own
# (.claude-plugin/plugin.json), verifies every checksum, stages it under the
# release store, activates the binaries and installs the app.
#
# ── IT UPGRADES THE WHOLE SYSTEM, NOT HALF OF IT ─────────────────────────────
#
# One release carries the three binaries AND the GMVibes DMG at one version, so
# one command moves a machine forward. This used to be impossible: the app was
# published on its own `gmvibes-v*` tag with its own version number by a script
# that shared no code with the publisher, and nothing here fetched it — a user
# who ran this got a new daemon and kept whatever app they had.
#
# The DMG is staged under $GM_FS_ROOT like everything else and installed from
# there. /Applications is the one write outside the root; it is what makes a
# macOS app launchable, it is confined to gm_install_app in the shared library,
# and --no-app turns it off.
#
# ── WHY THIS LIVES IN THE PLUGIN AND NOT IN gmk/scripts ──────────────────────
#
# Because of who runs it. Somebody with a CHECKOUT builds: they have the sources
# and `rebuild_local.sh` is strictly better for them. Somebody with only the
# PLUGIN downloads — and the plugin cache is all they have.
#
# That is not a style preference, it is a hard constraint that was measured. A
# marketplace install materialises `plugins/gmcc/` alone, with no `gmk/` beside
# it and no git metadata of its own. An installer that tried to climb out of the
# cache to find the repo would run `git rev-parse --show-toplevel` and, on a
# machine whose $HOME is itself a git repository, get a confident WRONG answer
# pointing at the home directory. There is no reliable climb, so this script does
# not attempt one: it needs no repo and reads no VERSION file from disk. The one
# file it reads is the plugin's own manifest, which sits beside it.
#
# ── WHY THE PLUGIN'S VERSION RATHER THAN "LATEST" ────────────────────────────
#
# The bridge stamps `.claude-plugin/plugin.json` from gmk/VERSION, the same
# number the release is tagged with. So the plugin a session loads names exactly
# one kernel, and installing that one is what keeps the hooks, the pens and the
# daemon they dial at a single version. `--latest` is the escape hatch for a
# plugin tree whose release has not been published yet.
#
# TAG NAMESPACE MATTERS FOR --latest. The repo's history contains more than one
# kind of release tag, so GitHub's own "latest release" is the wrong question —
# it would happily hand back an app-only release cut under the retired
# `gmvibes-v*` namespace. This filters by prefix, newest `gm_kernel-v*` first,
# and falls back to the retired `daemon-v*` namespace so a machine pointed at an
# older release still installs rather than being told nothing is published.
#
# Usage:
#   install_gm.sh                   # install/upgrade binaries + app to the plugin's version
#   install_gm.sh --check           # report only; exit 1 if an install is needed
#   install_gm.sh --force           # reinstall even if that version is active
#   install_gm.sh --version 50.0.1  # install one specific version
#   install_gm.sh --latest          # the newest published release instead of the plugin's
#   install_gm.sh --no-app          # binaries only; never touch /Applications
#   install_gm.sh --app             # the app only; leave the binaries alone
#
# Env:
#   GM_FS_ROOT                      # the one filesystem root (default: $HOME/gmfs)
#   GM_APP_DEST                     # where the app goes (default: /Applications)
#   GM_DAEMON_RELEASE_REPO          # owner/name to fetch from

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_releases.sh
. "$SCRIPT_DIR/gm_releases.sh"

RELEASE_REPO="${GM_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"
API="https://api.github.com/repos/$RELEASE_REPO"

MODE="install"
WANT=""
WANT_LATEST=0
DO_BINARIES=1
DO_APP=1
while [ $# -gt 0 ]; do
    case "$1" in
        --check)   MODE="check" ;;
        --force)   MODE="force" ;;
        --version) shift; WANT="$1"; [ -n "$WANT" ] || { echo "[GMB] --version needs a value" >&2; exit 2; } ;;
        --latest)  WANT_LATEST=1 ;;
        --no-app)  DO_APP=0 ;;
        --app)     DO_BINARIES=0 ;;
        "") ;;
        *) echo "[GMB] install_gm.sh: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done

gm_resolve_fs_root
INSTALLED="$(gm_installed_version)"

# gm_plugin_version — the version this plugin tree was generated for, from the
# manifest beside this script. Empty when the tree has no manifest.
gm_plugin_version() {
    _pj="$(dirname "$SCRIPT_DIR")/.claude-plugin/plugin.json"
    [ -f "$_pj" ] || return 1
    sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$_pj" | head -1
}

# ── Resolve which version to install ─────────────────────────────────────────
#
# Parsed with grep/sed rather than jq: jq is not a dependency anywhere else on
# this path and an installer that fails on a missing JSON parser is an installer
# that fails for the exact users it exists to serve. The releases list comes back
# newest-first, so the first daemon-v tag in it is the newest daemon release.
RELEASES_JSON=""
fetch_releases() {
    [ -n "$RELEASES_JSON" ] && return 0
    RELEASES_JSON="$(curl -fsSL --retry 2 --connect-timeout 15 "$API/releases?per_page=100" 2>/dev/null || true)"
    [ -n "$RELEASES_JSON" ]
}

# The tag prefix that actually produced the version being installed. It decides
# whether a DMG can be expected in the release at all: the retired namespace
# predates the unified release and carries binaries only.
#
# Printed as `<prefix> <version>` rather than assigned to a global, because
# resolve_latest is called in a `$(...)` subshell and a variable it set there
# would not survive the return. That is the kind of bug that shows up as an
# installer confidently looking for a DMG in a release that has none.
resolve_latest() {
    fetch_releases || return 1
    for _prefix in "$GM_TAG_PREFIX" "$GM_LEGACY_TAG_PREFIX"; do
        _v="$(printf '%s' "$RELEASES_JSON" \
            | grep -o "\"tag_name\"[[:space:]]*:[[:space:]]*\"$_prefix[^\"]*\"" \
            | head -1 \
            | sed -e "s/.*\"\($_prefix[^\"]*\)\"/\1/" -e "s/^$_prefix//")"
        if [ -n "$_v" ]; then
            printf '%s %s\n' "$_prefix" "$_v"
            return 0
        fi
    done
    return 1
}

FOUND_PREFIX="$GM_TAG_PREFIX"
PLUGIN_V=""
[ "$WANT_LATEST" -eq 1 ] || PLUGIN_V="$(gm_plugin_version || true)"
if [ -n "$WANT" ]; then
    VERSION="$WANT"
elif [ -n "$PLUGIN_V" ]; then
    VERSION="$PLUGIN_V"
    echo "[GMB] plugin is v$VERSION — installing the matching release"
else
    echo "[GMB] asking $RELEASE_REPO for the newest release..."
    RESOLVED="$(resolve_latest || true)"
    # Split with `case`, not `[ x ] && y` — under `set -e` a trailing test that
    # evaluates false takes the whole script down, and here the false branch is
    # the SUCCESS path.
    VERSION=""
    case "$RESOLVED" in
        *" "*)
            FOUND_PREFIX="${RESOLVED%% *}"
            VERSION="${RESOLVED#* }"
            ;;
    esac
    if [ -z "$VERSION" ]; then
        cat >&2 <<EOF
[GMB] ERROR: no published ${GM_TAG_PREFIX}* release found on $RELEASE_REPO.

      Nothing has been released yet, or the network is unreachable.

      If you have a checkout of the repository, build instead — it needs no
      release at all:

          bash gmk/scripts/rebuild_local.sh

      Otherwise check: https://github.com/$RELEASE_REPO/releases
EOF
        exit 1
    fi
fi

TAG="$FOUND_PREFIX$VERSION"
ASSET="gm-daemon-$VERSION-macos-universal.tar.gz"
BASE="https://github.com/$RELEASE_REPO/releases/download/$TAG"

# ── WHICH SHAPE IS THIS RELEASE? ────────────────────────────────────────────
#
# Two layouts exist and both must install, because the older one is the rollback
# target for every machine already running:
#
#   current  ONE asset, the DMG. The app's executable IS the CLI, so
#            the binaries are EXTRACTED FROM THE APP rather than downloaded
#            separately. One artifact, used twice, which is what stops the
#            installed binary and the installed app from ever disagreeing.
#
#   legacy   the retired `daemon-v*` namespace: a tarball, and no DMG at all.
#            Those releases cannot be rewritten, so the tarball path stays for
#            them — and ONLY for them. Deleting it would make the entire
#            back-catalogue uninstallable.
#
# Keyed on the TAG PREFIX rather than on version arithmetic: the prefix is what
# the release actually was published under, and comparing version numbers to
# guess a layout is how an installer ends up confidently fetching an asset that
# was never uploaded.
if [ "$FOUND_PREFIX" = "$GM_LEGACY_TAG_PREFIX" ]; then
    LEGACY_NAMESPACE=1
else
    LEGACY_NAMESPACE=0
fi

# THE DMG ASSET NAME IS RESOLVED, NOT ASSUMED.
#
# The bundle was renamed GMVibes -> gm_kernel when the app became the kernel
# host, so the asset name changed with it. Every DMG PUBLISHED BEFORE that still
# carries the old name, and those releases cannot be rewritten — so an installer
# that only ever asks for `gm_kernel-<v>.dmg` 404s on its entire back-catalogue,
# including the release that was newest the day this landed.
#
# Asked of the release itself rather than inferred from the version number: a
# version comparison would need a cutover constant that is wrong the moment
# anyone re-publishes, and `gh` already knows the answer. The curl fallback keeps
# a machine without `gh` working, and defaults to the CURRENT name so a fresh
# install does not pay for the compatibility path.
resolve_dmg_asset() {
    _new="$GM_APP_NAME-$VERSION.dmg"
    _old="$GM_APP_NAME_LEGACY-$VERSION.dmg"
    if command -v gh >/dev/null 2>&1; then
        _names="$(gh release view "$TAG" --repo "$RELEASE_REPO" --json assets \
                    -q '.assets[].name' 2>/dev/null || true)"
        if [ -n "$_names" ]; then
            printf '%s\n' "$_names" | grep -qx "$_new" && { printf '%s' "$_new"; return 0; }
            printf '%s\n' "$_names" | grep -qx "$_old" && { printf '%s' "$_old"; return 0; }
        fi
    fi
    # No gh, or it told us nothing: probe the new name, fall back to the old.
    if curl -fsI --connect-timeout 10 "$BASE/$_new" >/dev/null 2>&1; then
        printf '%s' "$_new"
    elif curl -fsI --connect-timeout 10 "$BASE/$_old" >/dev/null 2>&1; then
        printf '%s' "$_old"
    else
        printf '%s' "$_new"
    fi
}
DMG_ASSET="$(resolve_dmg_asset)"

# A release under the retired namespace contains binaries only. Asking it for a
# DMG would be a guaranteed 404 dressed up as a network problem.
if [ "$FOUND_PREFIX" != "$GM_TAG_PREFIX" ] && [ "$DO_APP" -eq 1 ]; then
    echo "[GMB] $TAG predates the unified release — it has no app. Binaries only."
    DO_APP=0
    DO_BINARIES=1
fi

# ── Up-to-date checks ────────────────────────────────────────────────────────
#
# The binaries and the app are checked SEPARATELY even though they share a
# version. They can legitimately disagree — the app gets replaced by hand, an
# earlier run used --no-app, /Applications was not writable that day — and a
# single "is v$VERSION installed" question would answer yes while half the
# system sat one release behind. Each side decides for itself whether it has
# work to do, and the script exits early only when NEITHER does.
have_all() { for b in $GM_BINARIES; do [ -x "$GM_BIN/$b" ] || return 1; done; return 0; }

APP_INSTALLED="$(gm_installed_app_version)"
BIN_WORK=1
APP_WORK=1

[ "$DO_BINARIES" -eq 1 ] || BIN_WORK=0
[ "$DO_APP" -eq 1 ] || APP_WORK=0

if [ "$MODE" != "force" ]; then
    if [ "$BIN_WORK" -eq 1 ]; then
        case "$INSTALLED" in
            *-BETA)
                # A locally built, locally staged binary. A download must never
                # silently replace work someone is in the middle of testing.
                if have_all; then
                    echo "[GMB] $INSTALLED is active (a local build) — leaving the binaries alone"
                    echo "      rebuild:            bash gmk/scripts/rebuild_local.sh"
                    echo "      switch to v$VERSION: bash $SCRIPT_DIR/install_gm.sh --force"
                    BIN_WORK=0
                fi
                ;;
            "$VERSION")
                if have_all; then
                    echo "[GMB] binaries v$VERSION already active at $GM_BIN"
                    BIN_WORK=0
                fi
                ;;
        esac
    fi
    if [ "$APP_WORK" -eq 1 ] && [ "$APP_INSTALLED" = "$VERSION" ]; then
        echo "[GMB] $GM_APP_NAME $VERSION already installed at $GM_APP_DEST"
        APP_WORK=0
    fi
fi

if [ "$MODE" = "check" ]; then
    if [ "$INSTALLED" = "none" ]; then
        echo "[GMB] binaries not installed — wanted is v$VERSION"
    else
        echo "[GMB] binaries $INSTALLED active, wanted is v$VERSION"
    fi
    echo "[GMB] $GM_APP_NAME $APP_INSTALLED installed, wanted is $VERSION"
    if [ "$BIN_WORK" -eq 0 ] && [ "$APP_WORK" -eq 0 ]; then
        echo "      everything is current"
        exit 0
    fi
    echo "      run: bash $SCRIPT_DIR/install_gm.sh"
    exit 1
fi

if [ "$BIN_WORK" -eq 0 ] && [ "$APP_WORK" -eq 0 ]; then
    exit 0
fi

# ── Stop the writer FIRST ────────────────────────────────────────────────────
#
# This moved UP, from after activation to before any work, and the move is the
# whole fix for the upgrade circularity. `gm_install_app` refuses while the app
# is running; the app is now the writer and is menu-bar-resident, so it is always
# running. Retiring after activation — where `gm_retire_daemon` used to sit —
# would mean the app install had already refused by the time we stopped anything.
#
# Once, here, rather than once per section: the two sections used to each retire
# the daemon, which was harmless when it was a separate process that autostarted
# again. Now it would terminate a user's windows twice in one install.
gm_stop_kernel_and_wait 3

TMP="$(mktemp -d "${TMPDIR:-/tmp}/gm-install.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# fetch_asset <name> — download an asset and its sidecar into $TMP, then verify.
#
# Checksum BEFORE anything is unpacked or mounted. The sidecar is written as
# `<hash>  <filename>`, so it is verified from the directory where that filename
# resolves. Mounting an unverified DMG is the same class of mistake as unpacking
# an unverified tarball, and the app is the asset a user actually double-clicks.
fetch_asset() {
    _name="$1"
    if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$_name" "$BASE/$_name" \
       || ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$_name.sha256" "$BASE/$_name.sha256"; then
        cat >&2 <<EOF
[GMB] ERROR: could not download $BASE/$_name

      The release exists but the asset does not, or the network is unreachable.
      With a checkout, build instead: bash gmk/scripts/rebuild_local.sh
EOF
        if [ -n "$PLUGIN_V" ] && [ "$VERSION" = "$PLUGIN_V" ]; then
            cat >&2 <<EOF
      This plugin names v$VERSION and that release may not be published yet.
      For the newest published release instead: bash $SCRIPT_DIR/install_gm.sh --latest
EOF
        fi
        return 1
    fi
    if ! ( cd "$TMP" && shasum -a 256 -c "$_name.sha256" >/dev/null 2>&1 ); then
        echo "[GMB] ERROR: checksum mismatch on $_name — refusing to install" >&2
        echo "       expected: $(cut -d' ' -f1 < "$TMP/$_name.sha256")" >&2
        echo "       actual:   $(shasum -a 256 "$TMP/$_name" | cut -d' ' -f1)" >&2
        return 1
    fi
    return 0
}

# ── THE DMG IS THE RELEASE, so it is fetched before anything needs it ───────
#
# Both halves come out of this one file: the app is installed from it, and the
# CLI is EXTRACTED FROM THE APP INSIDE IT. That is what makes the binary in
# $GM_BIN provably the same build as the app beside it — not two artifacts that
# agree, but one artifact used twice.
#
# Staged under $GM_FS_ROOT first and used FROM the store, never straight out of
# $TMP, so a re-install or a rollback to this version needs no network.
STAGED_DMG=""
if [ "$LEGACY_NAMESPACE" -eq 0 ]; then
    STAGED_DMG="$(gm_app_dmg "$VERSION")"
    if [ ! -f "$STAGED_DMG" ] || [ "$MODE" = "force" ]; then
        echo "[GMB] fetching $TAG from $RELEASE_REPO..."
        fetch_asset "$DMG_ASSET" || exit 1
        mkdir -p "$(dirname "$STAGED_DMG")"
        cp "$TMP/$DMG_ASSET" "$STAGED_DMG"
    else
        echo "[GMB] $VERSION is already in the store — using it without a download"
    fi
fi

# ── Binaries ─────────────────────────────────────────────────────────────────
if [ "$BIN_WORK" -eq 1 ]; then
    # A version already in the store is re-activated rather than re-extracted.
    # This is what makes rolling between versions cheap and offline.
    if [ -d "$GM_DOWNLOADS/$VERSION" ] && [ "$MODE" != "force" ] \
       && gm_verify_staged "$GM_DOWNLOADS/$VERSION" 2>/dev/null; then
        echo "[GMB] binaries v$VERSION are already in the store — activating without a download"
        gm_activate downloads "$VERSION"
    elif [ "$LEGACY_NAMESPACE" -eq 1 ]; then
        # ── THE BACK-CATALOGUE PATH, and it is not optional ─────────────────
        #
        # Releases in the retired `daemon-v*` namespace carry a TARBALL and no
        # DMG. Deleting this branch along with the tarball would make every
        # release published before the cutover uninstallable — which turns a
        # rollback, the thing the release store exists for, into a dead end.
        echo "[GMB] fetching $TAG binaries from $RELEASE_REPO (legacy tarball)..."
        fetch_asset "$ASSET" || exit 1
        tar -xzf "$TMP/$ASSET" -C "$TMP"

        # Either shape: a post-collapse tarball holds the one Mach-O; a
        # pre-collapse one holds three binaries, and back then the NAMES were
        # the artifacts.
        if [ -f "$TMP/$GM_MACHO" ]; then
            _staged="$GM_MACHO"
        elif [ -f "$TMP/gm_daemon" ]; then
            echo "[GMB] $ASSET predates the kernel collapse — installing its three binaries as-is"
            _staged="gm_daemon gm_mcp gm_hook"
        else
            echo "[GMB] ERROR: $ASSET contains neither $GM_MACHO nor gm_daemon" >&2
            exit 1
        fi
        for b in $_staged; do
            [ -f "$TMP/$b" ] || {
                echo "[GMB] ERROR: $ASSET does not contain $b — refusing a partial install" >&2
                exit 1; }
        done

        DL="$(gm_stage_dir downloads "$VERSION")"
        rm -rf "$DL"; DL="$(gm_stage_dir downloads "$VERSION")"
        for b in $_staged; do cp "$TMP/$b" "$DL/$b"; chmod +x "$DL/$b"; done
        _arch_probe="$(printf '%s\n' $_staged | head -1)"
        gm_write_manifest "$DL" "$VERSION" downloads "$TAG" "$(lipo -archs "$DL/$_arch_probe" 2>/dev/null | tr ' ' ',')"
        gm_activate downloads "$VERSION"
    else
        # ── THE CURRENT PATH: the CLI comes OUT of the app ──────────────────
        echo "[GMB] extracting the CLI from $GM_APP_NAME $VERSION..."
        _mnt="$(mktemp -d "${TMPDIR:-/tmp}/gm-cli.XXXXXX")"
        hdiutil attach "$STAGED_DMG" -nobrowse -readonly -quiet -mountpoint "$_mnt" >/dev/null 2>&1 || {
            rmdir "$_mnt" 2>/dev/null || true
            echo "[GMB] ERROR: could not mount $STAGED_DMG" >&2; exit 1; }

        # EITHER BUNDLE NAME, the same allowance gm_install_app makes: a DMG
        # built before the rename carries GMVibes.app.
        _app="$_mnt/$GM_APP_NAME.app"
        [ -d "$_app" ] || _app="$_mnt/$GM_APP_NAME_LEGACY.app"

        _ok=0
        if [ -x "$_app/Contents/MacOS/$GM_MACHO" ] || [ -x "$_app/Contents/Helpers/$GM_MACHO" ]; then
            rm -rf "$GM_DOWNLOADS/$VERSION"
            if gm_stage_from_bundle "$_app" downloads "$VERSION" "$TAG" >/dev/null; then
                _ok=1
            fi
        fi

        # DETACH BEFORE DECIDING. An early exit with the image still attached
        # leaves a mount behind that the next run cannot replace.
        hdiutil detach "$_mnt" -quiet >/dev/null 2>&1 || hdiutil detach "$_mnt" -force -quiet >/dev/null 2>&1 || true
        rmdir "$_mnt" 2>/dev/null || true

        [ "$_ok" -eq 1 ] || {
            echo "[GMB] ERROR: $DMG_ASSET carries no $GM_MACHO at Contents/MacOS (nor Contents/Helpers)." >&2
            echo "       It predates the one-bundle layout but is not in the legacy" >&2
            echo "       namespace either. Install a newer version." >&2
            exit 1; }

        gm_activate downloads "$VERSION"
    fi
    echo "[GMB] installed binaries v$VERSION"
    echo "      $GM_BIN/$GM_MACHO -> releases/downloads/$VERSION/$GM_MACHO"
    echo "      entry points: $(for b in $GM_ENTRYPOINTS; do printf '%s ' "$b"; done)-> $GM_MACHO"
fi

# ── The app ──────────────────────────────────────────────────────────────────
if [ "$APP_WORK" -eq 1 ]; then
    # Before replacing: drop a GMVibes.app this library installed. Two bundles
    # sharing one identifier make LaunchServices ambiguous AND defeat the
    # same-bundle-id check a second copy uses to recognise the first.
    gm_retire_legacy_app

    if gm_install_app "$STAGED_DMG" "$VERSION"; then
        # `if`, not `[ ... ] && echo` — under `set -e` a trailing false test
        # ends the script, and "the app was already installed" is the common case.
        if [ "$APP_INSTALLED" = "none" ]; then
            echo "      (first install — $GM_APP_NAME was not on this machine before)"
        fi
    else
        echo "[GMB] the app was staged at $STAGED_DMG but not installed." >&2
        echo "      Re-run when it can be replaced: bash $SCRIPT_DIR/install_gm.sh --app" >&2
        exit 1
    fi
fi
