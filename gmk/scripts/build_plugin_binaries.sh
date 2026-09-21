#!/bin/bash
#
# Compile the executables the plugin ships: every generated main under
# <plugin>/hooks/src/ and <plugin>/bin/src/, each built with the CLIENT CLOSURE
# of gmk/Sources plus the folders its own `// gm-closure:` line names, written
# beside its src/ (hooks/bin/<name>, bin/<name>). The binaries are committed
# with the plugin, so nothing on the hook or pen path needs a release, a DMG or
# an install step.
#
#   bash gmk/scripts/build_plugin_binaries.sh plugins/gmcc
#
# Skipped per directory when nothing changed: the sha256 of every input (base
# closure, that directory's mains and their extra folders, swiftc version) is
# stamped beside the binaries.
set -euo pipefail

# shellcheck source=gm_build.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gm_build.sh"
gm_repo_root

[ $# -eq 1 ] || { echo "usage: build_plugin_binaries.sh <plugin-dir>" >&2; exit 2; }
PLUGIN="$(cd "$1" && pwd)"
S="$REPO_ROOT/gmk/Sources"

# THE BASE CLIENT CLOSURE, by FOLDER: the shared wire base, the socket client,
# the hook feedback layer and the shell scanner. No server, no persistence, no
# GRDB. A file in these folders that reaches for a server or bridge type fails
# here, loudly, which is the check that keeps the closure a closure.
BASE_LIST="$(mktemp)"
trap 'rm -f "$BASE_LIST"' EXIT
find "$S/API/Shared/GmKernelCoreShared" \
     "$S/API/Clients/GmKernelCoreClient/GmKernelClient" \
     "$S/AgenticsCore/Feedback" \
     "$S/Util" \
     -name '*.swift' | sort > "$BASE_LIST"

SWIFTC="$(xcrun --find swiftc)"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
# Same language mode the Xcode target compiles under, so a source cannot
# compile here and fail there or the reverse.
FLAGS=(-O -swift-version 6 -strict-concurrency=complete -default-isolation nonisolated
       -sdk "$SDK" -target arm64-apple-macosx26.0 -Xlinker -dead_strip)

# extra_folders <main.swift> — the folders named on the file's gm-closure line.
extra_folders() {
    sed -n 's|^// gm-closure: *||p' "$1" | head -n1
}

# closure_files <main.swift> — the base list plus the extra folders' sources.
closure_files() {
    cat "$BASE_LIST"
    for _f in $(extra_folders "$1"); do
        find "$S/$_f" -name '*.swift' | sort
    done
}

build_dir() {
    _dir="$1"                       # hooks | bin
    _src="$PLUGIN/$_dir/src"
    [ -d "$_src" ] || { echo "[GMB] no generated mains at $_src — run gm_kernel bridge first" >&2; return 1; }
    case "$_dir" in
        hooks) _out="$PLUGIN/hooks/bin" ;;
        *)     _out="$PLUGIN/$_dir" ;;
    esac

    _stamp="$( { for _m in "$_src"/*.swift; do closure_files "$_m" | xargs cat; cat "$_m"; done; "$SWIFTC" --version 2>&1; printf '%s\n' "${FLAGS[@]}"; } \
        | shasum -a 256 | cut -d' ' -f1)"
    if [ "$(cat "$_out/.source_sha256" 2>/dev/null || true)" = "$_stamp" ] && ls "$_out"/gm_* >/dev/null 2>&1; then
        echo "[GMB] $_dir binaries up to date in $_out"
        return 0
    fi

    mkdir -p "$_out"
    rm -f "$_out"/gm_* "$_out/.source_sha256"

    # THE CACHE: another plugin tree (the working tree's committed plugins/gmcc)
    # whose binaries were built from the same stamp. Bytes are plugin-name
    # agnostic, so an environment seed after a rebuild is a copy, not a compile.
    if [ -n "${GM_PLUGIN_BIN_CACHE:-}" ]; then
        case "$_dir" in
            hooks) _cache="$GM_PLUGIN_BIN_CACHE/hooks/bin" ;;
            *)     _cache="$GM_PLUGIN_BIN_CACHE/$_dir" ;;
        esac
        if [ "$(cat "$_cache/.source_sha256" 2>/dev/null || true)" = "$_stamp" ] && ls "$_cache"/gm_* >/dev/null 2>&1; then
            cp "$_cache"/gm_* "$_out/"
            echo "$_stamp" > "$_out/.source_sha256"
            echo "[GMB] $_dir binaries copied from $_cache (same sources)"
            return 0
        fi
    fi

    _pids=(); _names=()
    for _m in "$_src"/*.swift; do
        _name="$(basename "$_m" .swift)"
        _names+=("$_name")
        _list="$(mktemp)"
        closure_files "$_m" > "$_list"
        (
            "$SWIFTC" "${FLAGS[@]}" -module-name "$_name" "$_m" @"$_list" -o "$_out/$_name.unstripped" \
                && strip -o "$_out/$_name" "$_out/$_name.unstripped" \
                && rm -f "$_out/$_name.unstripped" \
                && chmod 755 "$_out/$_name"
            _rc=$?; rm -f "$_list"; exit $_rc
        ) > "$_out/.$_name.log" 2>&1 &
        _pids+=($!)
    done

    _status=0
    for _i in "${!_pids[@]}"; do
        if ! wait "${_pids[$_i]}"; then
            echo "[GMB] ${_names[$_i]} FAILED to compile:" >&2
            cat "$_out/.${_names[$_i]}.log" >&2
            _status=1
        fi
        rm -f "$_out/.${_names[$_i]}.log"
    done
    [ "$_status" -eq 0 ] || return 1

    for _name in "${_names[@]}"; do
        codesign --verify "$_out/$_name"
        lipo -info "$_out/$_name" | grep -q arm64 || { echo "[GMB] $_name has no arm64 slice" >&2; return 1; }
    done
    echo "$_stamp" > "$_out/.source_sha256"
    echo "[GMB] built ${#_names[@]} $_dir binaries into $_out: ${_names[*]}"
}

build_dir hooks
build_dir bin
