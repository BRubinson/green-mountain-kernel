#!/bin/bash
#
# swift_lint_hook.sh — Claude Code PostToolUse hook: lint the one .swift file that was
# just edited and hand the findings back to the agent as context.
#
# Lint only. It never formats: a rewrite between an agent's read and its next Edit makes
# the edit's old_string stop matching. Exits 0 on every path so it can never block a tool.

set -u

command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat)"
FILE="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$FILE" ] || exit 0
case "$FILE" in *.swift) ;; *) exit 0 ;; esac
[ -f "$FILE" ] || exit 0
case "$FILE" in
    */Generated/*|*/.build/*|*/plugins/*|*/Package.swift) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-}"
[ -n "$ROOT" ] || ROOT="$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$ROOT" ] && [ -f "$ROOT/.swift-format" ] || exit 0
cd "$ROOT" || exit 0

FINDINGS=""
if command -v swift-format >/dev/null 2>&1; then
    OUT="$(swift-format lint --strict "$FILE" 2>&1 || true)"
elif xcrun --find swift-format >/dev/null 2>&1; then
    OUT="$(xcrun swift-format lint --strict "$FILE" 2>&1 || true)"
else
    OUT=""
fi
[ -n "$OUT" ] && FINDINGS="$OUT"

SWIFTLINT=""
if command -v swiftlint >/dev/null 2>&1; then
    SWIFTLINT="swiftlint"
elif [ -x "${GM_FS_ROOT:-$HOME/gmfs}/bin/swiftlint" ]; then
    SWIFTLINT="${GM_FS_ROOT:-$HOME/gmfs}/bin/swiftlint"
fi
if [ -n "$SWIFTLINT" ]; then
    OUT="$("$SWIFTLINT" lint --quiet --force-exclude "$FILE" 2>/dev/null || true)"
    [ -n "$OUT" ] && FINDINGS="${FINDINGS:+$FINDINGS
}$OUT"
fi

[ -n "$FINDINGS" ] || exit 0

REL="${FILE#"$ROOT"/}"
MSG="swift lint findings for $REL:
$FINDINGS
Formatting findings (Indentation, LineLength, Spacing, AddLines, RemoveLine, TrailingComma, OrderedImports): run /gm_swift_lint --fix $REL once the edit sequence is complete. Every other finding needs a hand edit at the reported line."

jq -n --arg msg "$MSG" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $msg}}'
exit 0
