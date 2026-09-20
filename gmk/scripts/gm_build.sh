#!/bin/bash
#
# gm_build.sh — the repo-side build library, sourced by every gmk/scripts caller.
#
# One home for the things the build scripts used to each spell privately: the
# repo root, the environment ↔ configuration table, the one xcodebuild line,
# the built product's path, the bundle's kernel and baked keys, and the
# Developer ID lookup.
#
# REPO-SIDE ONLY. Nothing here goes into gm_releases.sh: that library is
# vendored into the plugin and must not carry a build table the installer
# never uses. This file sources gm_releases.sh itself, so a caller needs only
# this one line:
#
#     . "$(dirname "$0")/gm_build.sh"; gm_repo_root

# Never sourced twice.
[ -n "${GM_BUILD_SH:-}" ] && return 0
GM_BUILD_SH=1

GM_BUILD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=gm_releases.sh
. "$GM_BUILD_DIR/gm_releases.sh"

# gm_repo_root — sets GMK and REPO_ROOT from this file's own location.
#
# No git call: asking git for the toplevel can name an unrelated enclosing
# repository (a version-controlled $HOME). The walk from here is deterministic
# and the workspace check is the only test needed.
gm_repo_root() {
    GMK="$(cd "$GM_BUILD_DIR/.." && pwd)"
    REPO_ROOT="$(cd "$GMK/.." && pwd)"
    [ -d "$GMK/gmk.xcworkspace" ] || {
        echo "[GMB] ERROR: no gmk.xcworkspace under $GMK" >&2; return 1; }
}

# gm_env_config <env> — the build configuration that bakes this environment's
# root: prod→Release, beta→Beta, test→Debug.
gm_env_config() {
    case "${1:-}" in
        prod) printf 'Release\n' ;;
        beta) printf 'Beta\n' ;;
        test) printf 'Debug\n' ;;
        *) echo "[GMB] no build configuration for environment '${1:-}' (prod|beta|test)" >&2; return 2 ;;
    esac
}

# gm_config_env <config> — the inverse table. The root that goes with it is
# `gm_env_root "$(gm_config_env C)"` from gm_releases.sh.
gm_config_env() {
    case "${1:-}" in
        Release) printf 'prod\n' ;;
        Beta)    printf 'beta\n' ;;
        Debug)   printf 'test\n' ;;
        *) echo "[GMB] unknown build configuration '${1:-}' (Release|Beta|Debug)" >&2; return 2 ;;
    esac
}

# gm_xcb_arch <arm64|universal> — the ARCHS overrides for gm_xcb, as words a
# caller expands unquoted. The universal list is spelled `$(ARCHS_STANDARD)`
# so it stays ONE word through shell expansion; xcodebuild expands it.
gm_xcb_arch() {
    case "${1:-}" in
        arm64)     printf 'ARCHS=arm64\n' ;;
        universal) printf 'ARCHS=$(ARCHS_STANDARD) ONLY_ACTIVE_ARCH=NO\n' ;;
        *) echo "[GMB] gm_xcb_arch: arm64 or universal, not '${1:-}'" >&2; return 2 ;;
    esac
}

# gm_xcb <action> <config> [xcodebuild args…] — THE xcodebuild line.
#
# Always the workspace (one lockfile), the gm_kernel scheme, DerivedData under
# gmk/.build, and no signing (build-dmg.sh signs inside-out afterwards).
# `-quiet` is a CALLER argument: `test` must not pass it, or the per-case
# "' passed (" lines publish_release.sh counts vanish.
gm_xcb() {
    _action="$1"; _config="$2"; shift 2
    xcodebuild -workspace "$GMK/gmk.xcworkspace" -scheme gm_kernel \
        -configuration "$_config" -derivedDataPath "$GMK/.build/DerivedData" \
        CODE_SIGNING_ALLOWED=NO "$@" "$_action"
}

# gm_xcb_app <config> — where `gm_xcb build <config>` leaves the bundle.
gm_xcb_app() {
    printf '%s\n' "$GMK/.build/DerivedData/Build/Products/$1/$GM_APP_NAME.app"
}

# gm_app_kernel <app> — the bundle's executable, which IS the kernel CLI.
# Refuses a bundle whose executable is missing or does not answer `--version`
# as the kernel: install_gm.sh takes the CLI out of the app, and a helperless
# app installs cleanly and records nothing.
gm_app_kernel() {
    _kernel="$1/Contents/MacOS/$GM_MACHO"
    [ -x "$_kernel" ] || {
        echo "[GMB] ERROR: $1 carries no Contents/MacOS/$GM_MACHO" >&2; return 1; }
    "$_kernel" --version 2>/dev/null | grep -q "gm_kernel protocol" || {
        echo "[GMB] ERROR: $_kernel does not answer as gm_kernel" >&2; return 1; }
    printf '%s\n' "$_kernel"
}

# gm_app_baked <app> — prints "<GMEnvironment> <GMFSRoot>" raw from the
# bundle's Info.plist, the root in its tilde form.
#
# An absent or unexpanded GMFSRoot is FATAL: the app resolves its root from
# this key first, and without it falls through to ~/gmfs and writes PRODUCTION
# while believing it is isolated. (INFOPLIST_KEY_GMFSRoot is silently dropped
# by Xcode's allow-list, hence the real Info.plist and hence this check.)
gm_app_baked() {
    _plist="$1/Contents/Info.plist"
    _root="$(plutil -extract GMFSRoot raw "$_plist" 2>/dev/null || true)"
    case "$_root" in
        ""|*'$('*)
            echo "[GMB] ERROR: $1 has no usable GMFSRoot in Info.plist (got '${_root:-<absent>}')." >&2
            echo "       Without it the app falls through to ~/gmfs and writes PRODUCTION." >&2
            return 1 ;;
    esac
    _env="$(plutil -extract GMEnvironment raw "$_plist" 2>/dev/null || echo '?')"
    printf '%s %s\n' "$_env" "$_root"
}

# gm_dev_id — the "Developer ID Application: …" signing identity, or nothing.
gm_dev_id() {
    security find-identity -v -p codesigning 2>/dev/null \
        | grep "Developer ID Application" | head -1 \
        | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true
}
