#!/bin/bash
#
# swift_lint_format.sh — lint (default) or format in place (--fix) every authored
# Swift source under gmk/ with swift-format, then lint it with SwiftLint, then check
# doc-comment completeness with swift_doc_check.py.
#
# Usage:
#   swift_lint_format.sh                 # lint; exit 1 on any swift-format, doc-check or SwiftLint error
#   swift_lint_format.sh --fix           # swift-format in place, then lint (SwiftLint never rewrites)
#   swift_lint_format.sh [--fix] PATH... # restrict stages 1-3 to the given files or directories
#   swift_lint_format.sh --no-tree-check # skip stage 4 (pre-commit runs it over the staged tree)
#
# Configs are discovered by walking up from each file (root .swift-format, the
# gmk/Tests override, root .swiftlint.yml), so no --configuration is passed.
# SwiftLint is optional: when it is not installed the stage is skipped with a warning
# (install: bash gmk/scripts/install_swiftlint.sh). Stage 4, gm_tree_check.py, checks the
# whole tree whatever PATHs are given.
#
# Skipped: every path gm_lint_skip (gm_build.sh) names.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_build.sh
. "$SCRIPT_DIR/gm_build.sh"
gm_repo_root
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
TREE_CHECK=1
PATHS=()
while [ $# -gt 0 ]; do
    case "$1" in
        --fix) FIX=1 ;;
        --check) FIX=0 ;;
        --no-tree-check) TREE_CHECK=0 ;;
        -h|--help) sed -n '2,19p' "$0"; exit 0 ;;
        -*) echo "[GMB] swift_lint_format.sh: unknown flag $1" >&2; exit 2 ;;
        *) PATHS+=("$1") ;;
    esac
    shift
done

if [ ${#PATHS[@]} -eq 0 ]; then
    for d in Sources Tests; do
        [ -d "$GMK/$d" ] && PATHS+=("$GMK/$d")
    done
fi

# A `*/NAME/*` skip glob also prunes NAME during the walk, so build output is never descended.
PRUNE=(-false)
for _glob in "${GM_LINT_SKIP_GLOBS[@]}"; do
    _name="${_glob#\*/}"; _name="${_name%/\*}"
    case "$_glob" in '*/'*'/*') case "$_name" in */*) ;; *) PRUNE+=(-o -name "$_name") ;; esac ;; esac
done

FILES="$(mktemp)"
trap 'rm -f "$FILES"' EXIT
for p in "${PATHS[@]}"; do
    if [ -d "$p" ]; then
        find "$p" -type d \( "${PRUNE[@]}" \) -prune -o -type f -name '*.swift' -print
    elif [ -f "$p" ]; then
        echo "$p"
    else
        echo "[GMB] ERROR: no such path $p" >&2; exit 2
    fi
done | while IFS= read -r f; do
    gm_lint_skipped "${f#"$REPO_ROOT"/}" || printf '%s\n' "$f"
done | sort -u > "$FILES"

COUNT="$(wc -l < "$FILES" | tr -d ' ')"
STATUS=0

# lint_files — stages 1-3 over the collected files; each failing stage sets STATUS=1.
lint_files() {
    if [ "$FIX" = 1 ]; then
        echo "[GMB] swift-format: formatting $COUNT files in place"
        # shellcheck disable=SC2046
        $SWIFT_FORMAT format --parallel --in-place $(cat "$FILES")
        # SwiftLint's autocorrect is deliberately NOT run: its fixers have changed semantics
        # (double-optional flattening, closure parameters, test base classes). SwiftLint reports; people edit.
    fi

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

    # Stage 3: every function, init and subscript documents its summary, parameters, return and
    # throws. No baseline: every finding fails. Style: .claude/skills/swift-doc-comments/SKILL.md
    echo "[GMB] doc-check: checking $COUNT files"
    # shellcheck disable=SC2046
    if ! python3 "$SCRIPT_DIR/swift_doc_check.py" $(cat "$FILES"); then
        echo "[GMB] doc-check: findings above need a hand edit at the reported line" >&2
        STATUS=1
    fi
}

if [ "$COUNT" -gt 0 ]; then
    lint_files
else
    echo "[GMB] swift-format: no Swift files matched; stages 1-3 skipped" >&2
fi

# Stage 4: the tree invariants no compiler or linter sees; `gm_tree_check.py --list` names them.
if [ "$TREE_CHECK" = 1 ]; then
    echo "[GMB] tree-check: checking the tree"
    if ! python3 "$SCRIPT_DIR/gm_tree_check.py"; then
        echo "[GMB] tree-check: findings above" >&2
        STATUS=1
    fi
fi

exit $STATUS
