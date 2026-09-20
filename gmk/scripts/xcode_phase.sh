#!/bin/bash
#
# xcode_phase.sh <bridge|seed> — the bodies of the PluginBridge and TestEnvSeed
# aggregate targets. Each pbxproj run-script phase is one line, an exec of
# this script, so the gates and the work are lintable, diffable and runnable
# by hand:
#
#     CONFIGURATION=Release bash gmk/scripts/xcode_phase.sh bridge   # note, exit 0
#
# Runs with ENABLE_USER_SCRIPT_SANDBOXING=NO (the aggregates' own setting): it
# writes into the source tree and into $HOME/test_gmfs. That is why it is NOT
# merged with stamp_build_info.sh, which runs sandboxed under a build rule.
#
# THE GATES LIVE HERE, not only in the scheme: a scheme gate is bypassed by
# anyone who builds a target directly or drags it into another scheme. Each
# gate exits 0 with a `note:` naming itself; a real failure fails the build —
# no `|| true`, no fallback, because a green build over a stale plugin or an
# unseeded root is the silent-wrong these targets exist to prevent.
set -euo pipefail

# shellcheck source=gm_build.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gm_build.sh"
gm_repo_root

# Regenerate plugins/gmcc from the kernel this build just produced.
# CALLS generate_plugin.sh AND REIMPLEMENTS NOTHING.
phase_bridge() {
    # Gate 1 — Beta only. Keeps a source-tree write off the Release path that
    # publish_release.sh requires clean, and off the Debug path (Cmd-R).
    [ "${CONFIGURATION:-}" = "Beta" ] || {
        echo "note: plugin generation is Beta-only (CONFIGURATION=${CONFIGURATION:-})"; exit 0; }

    # Gate 2 — no unmerged index entries. `ls-files -u` rather than MERGE_HEAD:
    # a conflicted rebase, cherry-pick, revert or stash pop leaves no MERGE_HEAD
    # but does leave unmerged entries, and the writer's stage-and-swap would
    # happily rename a half-resolved tree into its trash directory.
    if [ -n "$(git -C "$REPO_ROOT" ls-files -u)" ]; then
        echo "note: tree has unmerged paths - skipping plugin generation"; exit 0
    fi

    # Gate 3 — the target is a plugin tree, so the refusal lands here with a
    # readable message rather than deep inside the writer.
    [ -f "$REPO_ROOT/plugins/gmcc/.claude-plugin/plugin.json" ] || {
        echo "error: no plugin manifest at plugins/gmcc" >&2; exit 1; }

    _kernel="$(gm_app_kernel "${BUILT_PRODUCTS_DIR:?bridge runs from an Xcode phase}/$GM_APP_NAME.app")"
    GM_KERNEL_BIN="$_kernel" bash "$GMK/scripts/generate_plugin.sh"

    # Validate what was emitted: the writer's verify() checks a file RENDERED,
    # never that it is VALID, and an unknown manifest key disables the whole
    # plugin. Plain, not --strict (--strict fails on the missing `author`).
    # A GUI-launched Xcode inherits launchd's PATH, which lacks claude's
    # directory, so the binary is looked for rather than hoped for — and a
    # skip is LOUD, because a silent skip logs identically to a pass.
    PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.claude/local:$PATH"
    if command -v claude >/dev/null 2>&1; then
        claude plugin validate "$REPO_ROOT/plugins/gmcc"
    else
        echo "note: claude not on this phase's PATH - plugin.json was NOT validated"
    fi
}

# Seed $HOME/test_gmfs from the app this build just produced, so a plain
# Cmd-R lands on a provisioned environment. CALLS gm_env.sh seed AND
# REIMPLEMENTS NOTHING.
phase_seed() {
    [ "${CONFIGURATION:-}" = "Debug" ] || {
        echo "note: env seeding is Debug-only (CONFIGURATION=${CONFIGURATION:-})"; exit 0; }
    _app="${BUILT_PRODUCTS_DIR:?seed runs from an Xcode phase}/$GM_APP_NAME.app"
    GM_SEED_APP="$_app" bash "$GMK/scripts/gm_env.sh" seed test
}

case "${1:-}" in
    bridge) phase_bridge ;;
    seed)   phase_seed ;;
    *) echo "usage: xcode_phase.sh <bridge|seed>" >&2; exit 2 ;;
esac
