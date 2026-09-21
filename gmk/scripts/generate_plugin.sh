#!/bin/bash
#
# Regenerate plugins/gmcc from the agentics bridge, then sync the marketplace
# manifest's version to match.
#
# THREE STEPS AND THREE OWNERS, on purpose. `gm_kernel bridge` owns every TEXT
# file INSIDE the plugin directory and refuses to touch anything outside it —
# which is why it cannot bump `.claude-plugin/marketplace.json`, a repo-ROOT
# file in a different `.claude-plugin/` directory than the plugin's own.
# Confusing those two directories is the trap that makes a "delete the plugin"
# step delete the marketplace manifest, so the split is a guard rather than an
# inconvenience. `build_plugin_binaries.sh` owns the compiled executables
# (`hooks/bin/*` and `bin/gm_*`): the writer renders text and swaps the whole
# tree, so they are produced AFTER the swap, from the generated mains the
# writer just emitted.
#
# THE ROSTER IS WRITTEN HERE TOO, and it is the one file the bridge writes
# outside the plugin directory: `--roster-out` reflects the @Generable tool
# declarations into CdeToolRoster.generated.swift, which is SOURCE. It rides the
# gmcc emit ALONE — the gmbeta alias below reflects the same declarations, so a
# second write is the same bytes over the same file.
#
# A ROSTER THAT MOVED IS NOT SERVED BY THE KERNEL THAT JUST WROTE IT: that
# binary was compiled against the PREVIOUS roster, so its served list and the
# grants in the tree it just emitted disagree. This exits 3 in that case instead
# of finishing, and the caller is expected to build again and re-run —
# rebuild_local.sh does exactly that. GM_ROSTER_MOVED_OK=1 carries on regardless.
#
#   bash gmk/scripts/generate_plugin.sh            # regenerate + bump
#   bash gmk/scripts/generate_plugin.sh --check    # report only, change nothing
#
set -euo pipefail

# The repo root comes from the build library's own location: this script's
# destructive step must never be pointed at an unrelated enclosing repository.
# shellcheck source=gm_build.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/gm_build.sh"
gm_repo_root
REPO="$REPO_ROOT"
[ -f "$REPO/plugins/gmcc/.claude-plugin/plugin.json" ] || {
    echo "[GMB] no plugin manifest at $REPO/plugins/gmcc — refusing to regenerate into a non-plugin tree" >&2
    exit 1; }

CHECK=""
[ "${1:-}" = "--check" ] && CHECK="--check"

PLUGIN="$REPO/plugins/gmcc"
MARKETPLACE="$REPO/.claude-plugin/marketplace.json"
ROSTER="$REPO/gmk/Sources/API/Shared/GmKernelCoreShared/Protocol/CdeToolRoster.generated.swift"
VERSION="$(tr -d '[:space:]' < "$REPO/gmk/VERSION")"

echo "[GMB] repo:    $REPO"
echo "[GMB] version: $VERSION (from gmk/VERSION)"

# The generator is a personality of the kernel binary: `gm_kernel bridge <dir>`.
# The caller hands in the kernel it built as GM_KERNEL_BIN — rebuild_local.sh
# passes the exact staged Mach-O, xcode_phase.sh the bundle's executable — and
# there is deliberately no fallback build: a plugin generated from bits nobody
# staged is a plugin that disagrees with the binary beside it.
[ -x "${GM_KERNEL_BIN:-}" ] || {
    echo "[GMB] GM_KERNEL_BIN is required (the kernel that generates the plugin); rebuild_local.sh and xcode_phase.sh set it" >&2
    exit 2; }
BRIDGE=("$GM_KERNEL_BIN" bridge)
echo "[GMB] roster:  $ROSTER"
roster_sha() { shasum -a 256 "$ROSTER" 2>/dev/null | cut -d' ' -f1; }
ROSTER_BEFORE="$(roster_sha)"
# shellcheck disable=SC2086
"${BRIDGE[@]}" $CHECK --roster-out "$ROSTER" "$PLUGIN"
ROSTER_AFTER="$(roster_sha)"

if [ -z "$CHECK" ] && [ "$ROSTER_BEFORE" != "$ROSTER_AFTER" ]; then
    if [ "${GM_ROSTER_MOVED_OK:-0}" = "1" ]; then
        echo "[GMB] roster moved; carrying on because GM_ROSTER_MOVED_OK=1"
    else
        echo "[GMB] roster MOVED — the staged kernel serves the previous roster; rebuild" >&2
        exit 3
    fi
fi

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
#
# NO --roster-out EITHER. The roster is reflected from the same declarations
# whatever the plugin is called, so a second write is the same bytes — and it
# would land after the moved-roster check above had already passed.
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

# THE PLUGIN'S EXECUTABLES — the hook events, gm_mcp and gm_hook. Compiled once
# for gmcc and COPIED into gmbeta: the bytes carry no plugin name, and a second
# compile buys nothing.
bash "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/build_plugin_binaries.sh" "$PLUGIN"
rm -rf "$GMBETA/hooks/bin"
cp -R "$PLUGIN/hooks/bin" "$GMBETA/hooks/bin"
rm -f "$GMBETA"/bin/gm_* "$GMBETA/bin/.source_sha256"
cp "$PLUGIN"/bin/gm_* "$PLUGIN/bin/.source_sha256" "$GMBETA/bin/"

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
