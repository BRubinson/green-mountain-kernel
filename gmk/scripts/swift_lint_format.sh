#!/bin/bash
#
# swift_lint_format.sh — lint (default) or format in place (--fix) every authored
# Swift source under gmk/, using the root .swift-format and the toolchain's swift-format.
#
# Usage:
#   swift_lint_format.sh                 # lint; exit 1 on any finding
#   swift_lint_format.sh --fix           # format in place, then lint
#   swift_lint_format.sh [--fix] PATH... # restrict to the given files or directories
#
# Skipped: the vendored gmClaudeForFoundationModels package, generated protobuf sources,
# and every .build directory.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
fi
GMK="$REPO_ROOT/gmk"
CONFIG="$REPO_ROOT/.swift-format"

[ -f "$CONFIG" ] || { echo "[GMB] ERROR: $CONFIG not found" >&2; exit 1; }

if command -v swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT="swift-format"
elif xcrun --find swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT="xcrun swift-format"
else
    echo "[GMB] ERROR: swift-format not found — it ships with Xcode 16+ (xcrun --find swift-format)" >&2
    exit 1
fi

FIX=0
PATHS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --fix) FIX=1 ;;
        --check) FIX=0 ;;
        -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
        -*) echo "[GMB] swift_lint_format.sh: unknown flag $1" >&2; exit 2 ;;
        *) PATHS+=("$1") ;;
    esac
    shift
done

if [ ${#PATHS[@]} -eq 0 ]; then
    for d in "$GMK"/*/; do
        d="${d%/}"
        case "$(basename "$d")" in
            gmClaudeForFoundationModels|build|scripts) continue ;;
        esac
        [ -f "$d/Package.swift" ] || [ "$(basename "$d")" = gmVibes ] || continue
        PATHS+=("$d")
    done
fi

FILES="$(mktemp)"
trap 'rm -f "$FILES"' EXIT
for p in "${PATHS[@]}"; do
    if [ -d "$p" ]; then
        find "$p" -type d \( -name .build -o -name Generated -o -name .swiftpm -o -name DerivedData \) -prune \
            -o -type f -name '*.swift' -print
    elif [ -f "$p" ]; then
        echo "$p"
    else
        echo "[GMB] ERROR: no such path $p" >&2; exit 2
    fi
done | grep -v '/gmClaudeForFoundationModels/' | sort -u > "$FILES"

COUNT="$(wc -l < "$FILES" | tr -d ' ')"
[ "$COUNT" -gt 0 ] || { echo "[GMB] swift-format: no Swift files matched" >&2; exit 0; }

if [ "$FIX" = 1 ]; then
    echo "[GMB] swift-format: formatting $COUNT files in place"
    # shellcheck disable=SC2046
    $SWIFT_FORMAT format --configuration "$CONFIG" --in-place $(cat "$FILES")
fi

echo "[GMB] swift-format: linting $COUNT files"
# shellcheck disable=SC2046
if $SWIFT_FORMAT lint --configuration "$CONFIG" --strict $(cat "$FILES"); then
    echo "[GMB] swift-format: clean"
else
    echo "[GMB] swift-format: findings above. Fix with: bash gmk/scripts/swift_lint_format.sh --fix" >&2
    exit 1
fi
