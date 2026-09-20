#!/bin/bash
#
# swift_lint_format.sh — lint (default) or format in place (--fix) every authored
# Swift source under gmk/ with swift-format, then lint it with SwiftLint.
#
# Usage:
#   swift_lint_format.sh                 # lint; exit 1 on any swift-format finding or SwiftLint error
#   swift_lint_format.sh --fix           # swift-format in place, then lint (SwiftLint never rewrites)
#   swift_lint_format.sh [--fix] PATH... # restrict to the given files or directories
#
# Configs are discovered by walking up from each file (root .swift-format, the
# gmk/Tests override, root .swiftlint.yml), so no --configuration is passed.
# SwiftLint is optional: when it is not installed the stage is skipped with a warning
# (install: bash gmk/scripts/install_swiftlint.sh).
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
cd "$REPO_ROOT"

if command -v swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT="swift-format"
elif xcrun --find swift-format >/dev/null 2>&1; then
    SWIFT_FORMAT="xcrun swift-format"
else
    echo "[GMB] ERROR: swift-format not found — it ships with Xcode 16+ (xcrun --find swift-format)" >&2
    exit 1
fi

SWIFTLINT=""
if command -v swiftlint >/dev/null 2>&1; then
    SWIFTLINT="swiftlint"
elif [ -x "${GM_FS_ROOT:-$HOME/gmfs}/bin/swiftlint" ]; then
    SWIFTLINT="${GM_FS_ROOT:-$HOME/gmfs}/bin/swiftlint"
fi
if [ -n "$SWIFTLINT" ]; then
    PIN="$(sed -n 's/^SWIFTLINT_VERSION="\(.*\)"$/\1/p' "$SCRIPT_DIR/install_swiftlint.sh")"
    HAVE="$("$SWIFTLINT" version 2>/dev/null || echo unknown)"
    if [ -n "$PIN" ] && [ "$HAVE" != "$PIN" ]; then
        echo "[GMB] WARNING: swiftlint $HAVE found, pin is $PIN — run: bash gmk/scripts/install_swiftlint.sh" >&2
    fi
fi

FIX=0
PATHS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --fix) FIX=1 ;;
        --check) FIX=0 ;;
        -h|--help) sed -n '2,17p' "$0"; exit 0 ;;
        -*) echo "[GMB] swift_lint_format.sh: unknown flag $1" >&2; exit 2 ;;
        *) PATHS+=("$1") ;;
    esac
    shift
done

if [ ${#PATHS[@]} -eq 0 ]; then
    for d in Sources Tests Plugins gmVibes; do
        [ -d "$GMK/$d" ] && PATHS+=("$GMK/$d")
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
    $SWIFT_FORMAT format --parallel --in-place $(cat "$FILES")
    # SwiftLint's autocorrect is deliberately NOT run: its fixers have changed semantics
    # (double-optional flattening, closure parameters, test base classes). SwiftLint reports; people edit.
fi

STATUS=0

echo "[GMB] swift-format: linting $COUNT files"
# shellcheck disable=SC2046
if $SWIFT_FORMAT lint --parallel --strict $(cat "$FILES"); then
    echo "[GMB] swift-format: clean"
else
    echo "[GMB] swift-format: findings above. Fix with: bash gmk/scripts/swift_lint_format.sh --fix" >&2
    STATUS=1
fi

if [ -z "$SWIFTLINT" ]; then
    echo "[GMB] swiftlint: not installed, stage skipped — run: bash gmk/scripts/install_swiftlint.sh" >&2
else
    echo "[GMB] swiftlint: linting $COUNT files"
    # Exit 2 means at least one error-severity violation; warnings alone exit 0.
    # shellcheck disable=SC2046
    if "$SWIFTLINT" lint --quiet --force-exclude $(cat "$FILES"); then
        echo "[GMB] swiftlint: no errors"
    else
        echo "[GMB] swiftlint: errors above (warnings do not fail the gate)" >&2
        STATUS=1
    fi
fi

exit $STATUS
