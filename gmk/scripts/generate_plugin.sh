#!/bin/bash
#
# Regenerate plugins/gmcc from the agentics bridge, then sync the marketplace
# manifest's version to match.
#
# TWO STEPS AND TWO OWNERS, on purpose. `gm_kernel bridge` owns everything
# INSIDE the plugin directory and refuses to touch anything outside it — which is
# why it cannot bump `.claude-plugin/marketplace.json`, a repo-ROOT file in a
# different `.claude-plugin/` directory than the plugin's own. Confusing those
# two directories is the trap that makes a "delete the plugin" step delete the
# marketplace manifest, so the split is a guard rather than an inconvenience.
#
#   bash gmk/scripts/generate_plugin.sh            # regenerate + bump
#   bash gmk/scripts/generate_plugin.sh --check    # report only, change nothing
#
set -euo pipefail

# REPO ROOT, RESOLVED THE WAY THE OTHER SCRIPTS RESOLVE IT. A bare
# `git rev-parse --show-toplevel` can resolve to an unrelated ENCLOSING
# repository, and a $HOME under version control is the case that actually bites:
# it would point this script's destructive step at the wrong tree. So: rev-parse,
# plus a script-directory walk, plus a check that gmk/ is really there.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [ ! -d "$REPO/gmk" ] || [ ! -d "$REPO/plugins/gmcc" ]; then
    GIT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
    if [ -n "$GIT_ROOT" ] && [ -d "$GIT_ROOT/gmk" ]; then
        REPO="$GIT_ROOT"
    fi
fi
if [ ! -d "$REPO/gmk" ]; then
    echo "[GMB] cannot locate the repo root — gmk/ is not under '$REPO'" >&2
    exit 1
fi

CHECK=""
[ "${1:-}" = "--check" ] && CHECK="--check"

PLUGIN="$REPO/plugins/gmcc"
MARKETPLACE="$REPO/.claude-plugin/marketplace.json"
VERSION="$(tr -d '[:space:]' < "$REPO/gmk/VERSION")"

echo "[GMB] repo:    $REPO"
echo "[GMB] version: $VERSION (from gmk/VERSION)"

# The generator is a personality of the kernel binary: `gm_kernel bridge <dir>`.
# A caller that already holds a built kernel hands it in as GM_KERNEL_BIN
# (rebuild_local.sh passes the exact staged Mach-O); otherwise the release build
# of the package is used. The plugin directory is always an explicit argument.
if [ -n "${GM_KERNEL_BIN:-}" ] && [ -x "$GM_KERNEL_BIN" ]; then
    BRIDGE=("$GM_KERNEL_BIN" bridge)
else
    BRIDGE=(swift run -c release --package-path "$REPO/gmk" gm_kernel bridge)
fi
# shellcheck disable=SC2086
"${BRIDGE[@]}" $CHECK "$PLUGIN"

# THE gmbeta ALIAS TREE. A second emit of the SAME bridge under a different
# plugin NAME, so a beta/test GMVibes pane can load the working tree through
# `claude --plugin-dir` WITHOUT colliding with the marketplace `gmcc` (two
# plugins that share a name and an MCP server key cannot both load). The name
# override rides GM_BRIDGE_PLUGIN_NAME and flows through every derived
# qualified tool name and the `/gmbeta:` command namespace with no
# substitution — see GmBridgeClaudePlugin.pluginNameEnvVar.
#
# NO MARKETPLACE ENTRY. marketplace.json lists only `gmcc`; gmbeta exists purely
# as a --plugin-dir target and is gitignored (plugins/gmbeta/). So this emit
# deliberately does NOT touch the manifest or the version bump below.
GMBETA="$REPO/plugins/gmbeta"
echo "[GMB] gmbeta alias -> $GMBETA"
# shellcheck disable=SC2086
GM_BRIDGE_PLUGIN_NAME=gmbeta "${BRIDGE[@]}" $CHECK "$GMBETA"

if [ -n "$CHECK" ]; then
    CURRENT="$(python3 -c "import json;print(json.load(open('$MARKETPLACE'))['plugins'][0]['version'])")"
    if [ "$CURRENT" = "$VERSION" ]; then
        echo "[GMB] marketplace.json already at $VERSION"
    else
        echo "[GMB] marketplace.json would move $CURRENT -> $VERSION"
    fi
    exit 0
fi

# ONE VERSION, WRITTEN TO BOTH MANIFESTS FROM ONE SOURCE. plugin.json gets it
# from GmVersion.current inside the generator; marketplace.json gets it here.
# Both read gmk/VERSION, so the two cannot drift — which was the whole point of
# coupling them, and is the reason this is not two independently-edited numbers.
python3 - "$MARKETPLACE" "$VERSION" <<'PY'
import json, sys
path, version = sys.argv[1], sys.argv[2]
with open(path) as f:
    doc = json.load(f)
before = doc["plugins"][0]["version"]
doc["plugins"][0]["version"] = version
# indent=2 + trailing newline matches how the file is already written, so a
# version bump is a ONE-LINE diff rather than a reformat of the whole manifest.
with open(path, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
print(f"[GMB] marketplace.json {before} -> {version}")
PY

# REGENERATING THE WORKING TREE CHANGES NOTHING IN A RUNNING SESSION, and saying
# so here is the difference between a finished job and a confusing one. The
# marketplace registers a REMOTE git source and pins gmcc to a version-keyed
# cache; until this is committed and pushed, every session keeps running the
# version it installed.
echo "[GMB] done. The installed plugin is a version-keyed cache from a REMOTE"
echo "[GMB] source — commit and push before any session sees this."
