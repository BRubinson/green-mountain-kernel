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

# Never sourced twice.
[ -n "${GM_RELEASES_SH:-}" ] && return 0
GM_RELEASES_SH=1

GM_BINARIES="gm_daemon gm_mcp gm_hook"

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
