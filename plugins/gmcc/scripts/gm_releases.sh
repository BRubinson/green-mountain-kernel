#!/bin/bash
#
# gm_releases.sh — the RELEASE STORE contract, in one file.
#
# Sourced by rebuild_local.sh, publish_release.sh and install_gm.sh. It is a
# library and nothing else: it defines functions and variables, runs no work at
# source time, and never writes outside $GM_FS_ROOT.
#
# ── THE STORE ────────────────────────────────────────────────────────────────
#
#   $GM_FS_ROOT/bin/
#   ├── gm_daemon  -> releases/active/gm_daemon      RELATIVE symlinks
#   ├── gm_mcp     -> releases/active/gm_mcp
#   ├── gm_hook    -> releases/active/gm_hook
#   ├── .gm_version                                  the ACTIVE version string
#   └── releases/
#       ├── active -> downloads/50.0.1               or local/50.0.1-BETA
#       ├── downloads/50.0.1/{gm_daemon,gm_mcp,gm_hook,manifest.json,SHA256SUMS}
#       └── local/50.0.1-BETA/{gm_daemon,gm_mcp,gm_hook,manifest.json,SHA256SUMS}
#
# WHY SYMLINKS RATHER THAN COPIES INTO bin/. Three reasons, in order of how much
# they bite:
#
#   1. Overwriting a signed Mach-O IN PLACE leaves the kernel's code-signature
#      cache pointing at the old inode's contents, and the next exec dies with
#      SIGKILL — exit 137, no output, no diagnostic. Every copy-based installer
#      has to remember `rm` before `cp`. A symlink swap has no in-place
#      overwrite to get wrong, because the binaries themselves are never
#      rewritten once staged.
#   2. Rollback is a symlink swap, so a bad build is survivable without a
#      network round trip: the previous version is still sitting in the store.
#   3. A version directory is IMMUTABLE once staged, so the sha256 recorded in
#      its manifest keeps describing the bytes that are actually there.
#
# THE SYMLINKS ARE RELATIVE ON PURPOSE. A sandbox is a full copy of the runtime
# tree at a different path; absolute symlinks would all point back at prod, which
# is the exact failure the sandbox exists to prevent.
#
# ── THE TWO CHANNELS ─────────────────────────────────────────────────────────
#
#   local/     — what rebuild_local.sh builds from your working tree. ALWAYS
#                carries a -BETA suffix, with no exception and no flag to turn
#                it off. That suffix is the only thing distinguishing bits that
#                were merely built from bits that were published, and it is the
#                reason `gm_hook ping` can never make a locally-staged binary
#                look like a release.
#   downloads/ — what install_gm.sh fetched from a `daemon-v*` GitHub release,
#                checksum-verified before it was unpacked.
#
# A version directory name IS its version string, which is what lets the active
# symlink's target name the running version without a lookup table.

# ── THE APP RIDES ALONG ──────────────────────────────────────────────────────
#
#   $GM_FS_ROOT/apps/
#   ├── .gmvibes_version                     what WE last installed
#   └── downloads/50.0.2/GMVibes-50.0.2.dmg  checksum-verified before it was used
#
# The DMG is staged under the filesystem root exactly like the binaries, and for
# the same reason: the bytes that were verified are the bytes that get installed,
# and a re-install needs no second download. It is the ONE thing in this library
# that then writes outside $GM_FS_ROOT — /Applications is where a macOS app has
# to land to be launchable — and that step is a separate function so the write
# is explicit at every call site rather than buried in a download path.
#
# ── ONE VERSION ACROSS THE WHOLE RELEASE ─────────────────────────────────────
#
# `gmk/VERSION` pins the binaries AND the app: build-dmg.sh stamps
# MARKETING_VERSION from it, so the app's About box and `.gm_version` can never
# disagree. Before this they were two independently tagged tracks
# (`daemon-v*` and `gmvibes-v*`) and nothing made them meet.

# Never sourced twice.
[ -n "${GM_RELEASES_SH:-}" ] && return 0
GM_RELEASES_SH=1

GM_BINARIES="gm_daemon gm_mcp gm_hook"

# The unified release tag namespace. GitHub's own "latest release" is the wrong
# question for a monorepo that has shipped more than one kind of artifact, so
# every lookup filters by this prefix.
GM_TAG_PREFIX="gm_kernel-v"
# The namespace this replaced. Releases published before the unification still
# carry it and still contain a usable binary tarball, so the installer falls
# back to it rather than telling a working machine that nothing is published.
GM_LEGACY_TAG_PREFIX="daemon-v"

GM_APP_NAME="GMVibes"

# ── Roots ────────────────────────────────────────────────────────────────────
#
# ONE root variable. An explicit GM_FS_ROOT wins; otherwise a repo carrying the
# sandbox marker selects its snapshot runtime; otherwise $HOME/gmfs.
#
# THE MARKER IS PARSED AS DATA, NEVER SOURCED. A file that lives in a repo must
# not get shell execution out of an installer. The filename is `.gmcc_sandbox`
# and it is deliberately NOT renamed — HookLogic.SandboxMarker.fileName in
# gmDaemonSdk is the authority, the Swift and the shell have to agree on it, and
# a marker that only one side recognises is a sandbox session writing the prod
# database.
gm_resolve_fs_root() {
    if [ -z "${GM_FS_ROOT:-}" ]; then
        _repo="$(git rev-parse --show-toplevel 2>/dev/null || true)"
        if [ -n "$_repo" ] && [ -f "$_repo/.gmcc_sandbox" ]; then
            _sb="$(sed -n 's/^export GM_FS_ROOT="\(.*\)"$/\1/p' "$_repo/.gmcc_sandbox" | head -1)"
            [ -n "$_sb" ] && GM_FS_ROOT="$_sb"
        fi
    fi
    GM_FS_ROOT="${GM_FS_ROOT:-$HOME/gmfs}"
    GM_BIN="$GM_FS_ROOT/bin"
    GM_RELEASES="$GM_BIN/releases"
    GM_DOWNLOADS="$GM_RELEASES/downloads"
    GM_LOCAL="$GM_RELEASES/local"
    GM_ACTIVE="$GM_RELEASES/active"
    GM_VERSION_STAMP="$GM_BIN/.gm_version"

    # The app store, alongside the binary store and under the same one root.
    GM_APPS="$GM_FS_ROOT/apps"
    GM_APP_DOWNLOADS="$GM_APPS/downloads"
    GM_APP_VERSION_STAMP="$GM_APPS/.gmvibes_version"
    # Overridable so a sandbox — or a machine where /Applications is not
    # writable — can install somewhere else without editing this library.
    GM_APP_DEST="${GM_APP_DEST:-/Applications}"
}

# ── Staging ──────────────────────────────────────────────────────────────────

# gm_stage_dir <channel> <version>  ->  prints the directory, creating it.
# Channel is `local` or `downloads`; anything else is a caller bug, not input.
gm_stage_dir() {
    case "$1" in
        local)     _d="$GM_LOCAL/$2" ;;
        downloads) _d="$GM_DOWNLOADS/$2" ;;
        *) echo "[GMB] gm_stage_dir: unknown channel '$1'" >&2; return 2 ;;
    esac
    mkdir -p "$_d"
    printf '%s\n' "$_d"
}

# gm_write_manifest <dir> <version> <channel> <sha> <arches>
#
# The manifest answers "what exactly is this and where did it come from" without
# running the binaries — which matters most in the case where they will not run.
gm_write_manifest() {
    _dir="$1"; _version="$2"; _channel="$3"; _sha="$4"; _arches="$5"
    cat > "$_dir/manifest.json" <<EOF
{
  "version": "$_version",
  "channel": "$_channel",
  "source_sha": "$_sha",
  "arches": "$_arches",
  "staged_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "binaries": [$(printf '"%s", ' $GM_BINARIES | sed 's/, $//')]
}
EOF
    ( cd "$_dir" && shasum -a 256 $GM_BINARIES > SHA256SUMS )
}

# gm_verify_staged <dir> — every binary present, executable, and matching the
# SHA256SUMS recorded when it was staged. Activation is refused otherwise: a
# half-staged directory that gets activated is three dead symlinks.
gm_verify_staged() {
    _dir="$1"
    for b in $GM_BINARIES; do
        if [ ! -f "$_dir/$b" ]; then
            echo "[GMB] ERROR: $_dir is missing $b — refusing to activate a partial set" >&2
            return 1
        fi
        chmod +x "$_dir/$b"
    done
    if [ -f "$_dir/SHA256SUMS" ]; then
        if ! ( cd "$_dir" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1 ); then
            echo "[GMB] ERROR: $_dir fails its own SHA256SUMS — the staged bytes changed after staging" >&2
            return 1
        fi
    fi
    return 0
}

# ── Activation ───────────────────────────────────────────────────────────────

# gm_activate <channel> <version> — point bin/ at a staged version.
#
# ── THE SYMLINK-TO-A-DIRECTORY TRAP, WHICH BIT THIS FUNCTION ONCE ────────────
#
# `active` is a symlink TO A DIRECTORY, and both of the obvious ways to replace
# it silently do something else instead:
#
#   ln -sf  new active   → creates `active/new`, INSIDE the old target
#   mv -f   tmp  active  → moves tmp INTO the old target directory
#
# Both "succeed", both leave `active` pointing exactly where it did, and the
# stray link they deposit in a version directory is the only evidence. That is
# not hypothetical: the first version of this function used `mv -f` and promoted
# a release by writing `.active.tmp.67631 -> downloads/50.0.1` into the BETA
# directory while `.gm_version` cheerfully recorded the new version. The store
# claimed one version and executed another.
#
# `-n` on ln and `-h` on mv are the flags that mean "operate on the LINK, do not
# follow it". `mv -fh` keeps the atomic rename — there is no instant where
# `active` is missing — and actually replaces the link.
gm_activate() {
    _channel="$1"; _version="$2"
    case "$_channel" in
        local)     _rel="local/$_version" ;;
        downloads) _rel="downloads/$_version" ;;
        *) echo "[GMB] gm_activate: unknown channel '$_channel'" >&2; return 2 ;;
    esac
    _dir="$GM_RELEASES/$_rel"

    gm_verify_staged "$_dir" || return 1

    mkdir -p "$GM_BIN"
    ln -sfn "$_rel" "$GM_RELEASES/.active.tmp.$$"
    mv -fh "$GM_RELEASES/.active.tmp.$$" "$GM_ACTIVE"

    # The per-binary links are relative to $GM_BIN so the whole tree can be
    # copied to a sandbox path and still resolve within itself.
    #
    # -h here too. These point at FILES, so today `mv -f` would replace them
    # correctly — but the flag costs nothing and stops the pair from diverging
    # the moment someone points one of them at a directory.
    for b in $GM_BINARIES; do
        ln -sfn "releases/active/$b" "$GM_BIN/.$b.tmp.$$"
        mv -fh "$GM_BIN/.$b.tmp.$$" "$GM_BIN/$b"
    done

    # A failed or interrupted activation can leave a temp link behind inside a
    # version directory. Swept here rather than left to accumulate.
    rm -f "$GM_RELEASES"/*/*/.active.tmp.* "$GM_RELEASES"/.active.tmp.* 2>/dev/null || true

    printf '%s\n' "$_version" > "$GM_VERSION_STAMP"

    # curl does not set com.apple.quarantine the way a browser does, but a
    # hand-placed tarball can carry it, and a quarantined binary fails at exec
    # with a dialog no hook can surface.
    xattr -dr com.apple.quarantine "$_dir" 2>/dev/null || true

    echo "[GMB] active: $_version  ($_rel)"
    return 0
}

# gm_installed_version — the active version string, or `none`.
gm_installed_version() {
    if [ -f "$GM_VERSION_STAMP" ]; then cat "$GM_VERSION_STAMP"; else echo none; fi
}

# gm_retire_daemon — best-effort shutdown so the next client autostarts on the
# newly activated binary. A running daemon holds its own inode and would go on
# serving the OLD build from a deleted-but-open file, which presents as an
# install that silently did nothing.
gm_retire_daemon() {
    [ -x "$GM_BIN/gm_hook" ] || return 0
    "$GM_BIN/gm_hook" call SHUTDOWN --json '{}' >/dev/null 2>&1 || true
    echo "[GMB] retired the running daemon (if any) — the next client call autostarts the new build"
}

# ── The app ──────────────────────────────────────────────────────────────────

# gm_app_dmg <version> — the staged path for a version's DMG. Printed, not
# created; the caller makes the directory when it actually has bytes.
gm_app_dmg() {
    printf '%s\n' "$GM_APP_DOWNLOADS/$1/$GM_APP_NAME-$1.dmg"
}

# gm_installed_app_version — the version of the app ACTUALLY on disk, or `none`.
#
# Read from the installed bundle's Info.plist rather than from our own stamp
# file. The stamp records what this library last installed; the bundle records
# what is there now, and those differ the moment someone drags a build in by
# hand. The question every caller is really asking is the second one.
gm_installed_app_version() {
    _plist="$GM_APP_DEST/$GM_APP_NAME.app/Contents/Info.plist"
    if [ -f "$_plist" ]; then
        defaults read "$_plist" CFBundleShortVersionString 2>/dev/null || echo unknown
    else
        echo none
    fi
}

# gm_app_is_running — true if the app is up.
#
# Replacing a running bundle is the app-shaped version of the in-place-overwrite
# trap documented at the top of this file: the running process keeps its open
# inodes, the on-disk bundle becomes a mixture of two versions, and the symptom
# is a crash on the next window it opens rather than an error here.
gm_app_is_running() {
    pgrep -x "$GM_APP_NAME" >/dev/null 2>&1
}

# gm_install_app <dmg> <version> — mount, copy out, swap into place.
#
# THE ONE WRITE OUTSIDE $GM_FS_ROOT in this library, and deliberately its own
# function so that is visible at the call site.
#
# The swap is move-aside-then-move-in, never a copy over the top: see the
# SIGKILL note at the top of this file, which applies to the app's Mach-O just
# as it does to the daemon's. The staging copy is made INSIDE the destination
# directory so the final rename is same-filesystem and effectively atomic — a
# copy straight from the mounted image would cross devices and leave a
# half-written bundle if it failed midway.
gm_install_app() {
    _dmg="$1"; _app_version="$2"
    _app="$GM_APP_DEST/$GM_APP_NAME.app"

    [ -f "$_dmg" ] || { echo "[GMB] ERROR: no DMG at $_dmg" >&2; return 1; }

    if gm_app_is_running; then
        echo "[GMB] ERROR: $GM_APP_NAME is running — quit it and re-run." >&2
        echo "       Replacing a running app bundle corrupts it in ways that surface later." >&2
        return 1
    fi

    if [ ! -d "$GM_APP_DEST" ] || [ ! -w "$GM_APP_DEST" ]; then
        echo "[GMB] ERROR: $GM_APP_DEST is not writable." >&2
        echo "       Install elsewhere with: GM_APP_DEST=\"\$HOME/Applications\"" >&2
        return 1
    fi

    _mnt="$(mktemp -d "${TMPDIR:-/tmp}/gm-dmg.XXXXXX")"
    if ! hdiutil attach "$_dmg" -nobrowse -readonly -quiet -mountpoint "$_mnt" >/dev/null 2>&1; then
        rmdir "$_mnt" 2>/dev/null || true
        echo "[GMB] ERROR: could not mount $_dmg" >&2
        return 1
    fi

    _src="$_mnt/$GM_APP_NAME.app"
    _new="$GM_APP_DEST/.$GM_APP_NAME.new.$$"
    _old="$GM_APP_DEST/.$GM_APP_NAME.old.$$"
    _rc=0

    if [ ! -d "$_src" ]; then
        echo "[GMB] ERROR: $_dmg does not contain $GM_APP_NAME.app" >&2
        _rc=1
    else
        rm -rf "$_new"
        # ditto, not cp -R: it preserves the bundle's extended attributes and
        # resource forks, and a code signature does not survive without them.
        ditto "$_src" "$_new" || _rc=1
    fi

    hdiutil detach "$_mnt" -quiet >/dev/null 2>&1 || hdiutil detach "$_mnt" -force -quiet >/dev/null 2>&1 || true
    rmdir "$_mnt" 2>/dev/null || true

    if [ "$_rc" -ne 0 ]; then
        rm -rf "$_new"
        return 1
    fi

    # A DMG fetched with curl can carry com.apple.quarantine, and a quarantined
    # app opens a Gatekeeper dialog rather than launching. Cleared on the staged
    # copy, before it becomes the live bundle.
    xattr -dr com.apple.quarantine "$_new" 2>/dev/null || true

    rm -rf "$_old"
    if [ -d "$_app" ]; then
        mv "$_app" "$_old" || { rm -rf "$_new"; echo "[GMB] ERROR: could not move the existing app aside" >&2; return 1; }
    fi
    if ! mv "$_new" "$_app"; then
        # Put the old one back rather than leaving the machine with no app.
        [ -d "$_old" ] && mv "$_old" "$_app"
        rm -rf "$_new"
        echo "[GMB] ERROR: could not move the new app into place" >&2
        return 1
    fi
    rm -rf "$_old"

    mkdir -p "$GM_APPS"
    printf '%s\n' "$_app_version" > "$GM_APP_VERSION_STAMP"
    echo "[GMB] $GM_APP_NAME $_app_version -> $_app"
    return 0
}
