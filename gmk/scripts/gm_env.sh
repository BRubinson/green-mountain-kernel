#!/bin/bash
#
# gm_env.sh — create, refresh, inspect and tear down the non-production
# environments.
#
#     bash gmk/scripts/gm_env.sh create  beta
#     bash gmk/scripts/gm_env.sh refresh beta
#     bash gmk/scripts/gm_env.sh seed    test
#     bash gmk/scripts/gm_env.sh doctor  beta
#     bash gmk/scripts/gm_env.sh destroy beta
#
# ── THE THREE ENVIRONMENTS ───────────────────────────────────────────────────
#
#   prod  $HOME/gmfs        the primary environment. NOT managed by this script:
#                           it is the thing the others exist to protect, and a
#                           tool that can rewrite it is a tool that eventually
#                           will. `destroy prod` is refused.
#   beta  $HOME/beta_gmfs   a long-lived environment for trying things, running
#                           the app against real-shaped data you do not mind
#                           losing.
#   test  $HOME/test_gmfs   the Debug build's environment: one long-lived root.
#
# Each root's kernel is its app: a beta or test root stages the whole bundle at
# bin/gm_kernel.app, and clients on that root launch it from there. Ephemeral
# isolation belongs to the XCTest suite, which hosts its own kernel in-process
# on a temporary root.
#
# ── WHAT A REFRESH ACTUALLY COPIES ───────────────────────────────────────────
#
# The BITS and the REPO. **Never the production database.**
#
# Copying prod's gm.db looks free and is not. That database holds ABSOLUTE
# paths: daemon_config's root rows, and every instance's absolute checkout path.
# A kernel booting on such a copy reports one root from config while resolving
# another from Paths — one PATHS_GET answer naming two roots — and, worse, the
# watcher supervisor starts an FSEvent lane over every instance path it finds.
# That means a non-production kernel watching YOUR REAL WORKING CHECKOUT, with
# its dope verbs writing that repo's .gmcc/ tree, which write-containment
# permits because the repo genuinely is a permitted root.
#
# So the environment gets a fresh, empty, migrated database and a CLONE of the
# repo on its own branch. Its registered project and that project's dope are the
# only rows in it to start. Nothing to rebase, nothing to collide.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_build.sh
. "$SCRIPT_DIR/gm_build.sh"
gm_repo_root

die() { echo "[GMB] $*" >&2; exit 1; }

# Refuse to manage production. Every destructive verb here would be a
# catastrophe against $HOME/gmfs, and "be careful" is not a mechanism.
guard_not_prod() {
    [ "$1" = "prod" ] && die "refusing to '$2' production — that is what the other environments are for"
    return 0
}

env_root() { gm_env_root "$1"; }

# The pid out of a root's daemon.pid, or empty if there is no live kernel.
#
# THE PIDFILE IS NOT ONE LINE. It carries the pid AND the absolute path of the
# binary that wrote it, so `kill -0 "$(cat daemon.pid)"` passes the whole blob
# and fails with `illegal pid` against a perfectly healthy kernel. Read the
# FIRST LINE.
#
# Misparsing it would make `seed` think a live app was not running.
env_live_pid() {
    [ -f "$1/daemon.pid" ] || return 1
    _pid="$(head -1 "$1/daemon.pid" 2>/dev/null | tr -d '[:space:]')"
    case "$_pid" in
        ''|*[!0-9]*) return 1 ;;
    esac
    kill -0 "$_pid" 2>/dev/null || return 1
    echo "$_pid"
}

# ── create / refresh ─────────────────────────────────────────────────────────

env_create() {
    _env="$1"; guard_not_prod "$_env" create
    _root="$(env_root "$_env")" || exit 2
    echo "[GMB] $_env -> $_root"
    mkdir -p "$_root/bin" "$_root/repos" "$_root/backups"

    # A FULL release store, not just directories. Clients on this root launch
    # $ROOT/bin/gm_kernel.app; without it nothing here records anything.
    echo "[GMB] staging the kernel app into $_root"
    GM_ENV="$_env" GM_FS_ROOT="$_root" bash "$SCRIPT_DIR/rebuild_local.sh" --fast

    env_seed_repo "$_env" "$_root"
    env_seed_plugin "$_env" "$_root"
    echo "[GMB] $_env ready. Point a session at it with:  export GM_FS_ROOT=$_root"
}

# Clone the repo into the environment and register it.
#
# The clone is a REAL checkout at its OWN path, which matters more than it
# looks: instance identity is md5(absolute repo path), so a clone elsewhere is
# legitimately a different instance with its own rows. That is why this works
# and why copying a seeded database would not — copied rows would name paths
# that resolve to somebody else's checkout.
env_seed_repo() {
    _env="$1"; _root="$2"
    _name="$(basename "$REPO_ROOT")"
    _dest="$_root/repos/$_name"
    _branch="$_env/$(date +%Y%m%d-%H%M%S)"

    if [ -d "$_dest/.git" ]; then
        echo "[GMB] refreshing clone at $_dest"
        git -C "$_dest" fetch origin --quiet || true
        git -C "$_dest" fetch "$REPO_ROOT" --quiet || true
        # KEEP THE EXISTING BRANCH. The dated branch is minted ONCE, at clone
        # time. Session identity is the branch, and `seed` now runs on every
        # ⌘R — a fresh `checkout -B` per invocation would mint a new session
        # row per build.
        echo "[GMB] $_dest stays on $(git -C "$_dest" rev-parse --abbrev-ref HEAD)"
    else
        echo "[GMB] cloning $REPO_ROOT -> $_dest"
        # Clone from the LOCAL working repo rather than from origin: the point
        # is to test what is here, including commits that have not been pushed.
        git clone --quiet --no-hardlinks "$REPO_ROOT" "$_dest"
        git -C "$_dest" checkout -q -B "$_branch"
        echo "[GMB] $_dest on branch $_branch"
    fi

    # Boot the environment's kernel so it migrates an empty database into a full
    # schema, then register the clone and validate its dope tree. Those rows —
    # and nothing else — are what this environment starts with.
    #
    # Registration goes through `context ensure`, NOT through a raw
    # `call CONTEXT_ENSURE`. The verb takes three context objects
    # (project/instance/session), not a path; ContextBuilder is what assembles
    # them from $PWD and the branch, and duplicating that assembly in shell
    # would be a second source of truth for instance identity — which is
    # md5(absolute repo path) and must agree with what a real session computes.
    # Hence the subshell cd: $PWD IS the argument.
    # The client personality of the staged kernel: `gm_kernel hook …`. The
    # store carries no gm_hook symlink; that executable ships in the plugin.
    _hook="$_root/bin/gm_kernel"
    if [ -x "$_hook" ]; then
        echo "[GMB] registering the clone"
        # Errors are SHOWN, not swallowed. These calls were previously
        # redirected to /dev/null, which turned a permanent wire-shape bug into
        # a soft "declined" note that read like a transient hiccup for as long
        # as it took someone to check the database and find it empty.
        if ! ( cd "$_dest" && GM_FS_ROOT="$_root" "$_hook" hook context ensure >/dev/null ); then
            echo "[GMB] note: context ensure declined; register by opening a session there"
        fi
        if [ -f "$_dest/.gmcc/scope.doped.json" ]; then
            # DOPE_READ_REPO parses and validates the on-disk tree; it does not
            # ingest. Shell-side ingestion is deliberately NOT attempted here:
            # the adopt sequence (READ_REPO -> LIST -> INIT -> INGEST) is
            # DopeBootSync's job, and reimplementing it in sh would be a second
            # copy of a reconciliation that has to agree about revisions. So
            # this validates the tree and says plainly that a session boot is
            # what populates it.
            if GM_FS_ROOT="$_root" "$_hook" hook call DOPE_READ_REPO \
                --json "{\"dir_path\":\"$_dest\"}" >/dev/null; then
                echo "[GMB] dope tree valid; it ingests on the first session boot there"
            else
                echo "[GMB] note: dope tree did not validate (see the error above)"
            fi
        fi
    else
        echo "[GMB] note: no kernel staged at $_hook — skipping registration"
    fi
}

# The environment's OWN plugin, generated INTO its clone by the kernel it just
# staged, so the plugin a pane loads and the kernel it dials match by
# construction. The app resolves this path at runtime (DevPluginDir); nothing
# is baked. `plugins/gmbeta` is excluded in the clone's own .git/info/exclude,
# so the clone stays clean whatever its .gitignore says.
env_seed_plugin() {
    _env="$1"; _root="$2"
    _name="$(basename "$REPO_ROOT")"
    _dest="$_root/repos/$_name"
    _plug="$_dest/plugins/gmbeta"
    _kernel="$_root/bin/gm_kernel"
    [ -x "$_kernel" ] || { echo "[GMB] note: no kernel staged at $_kernel — skipping the environment plugin"; return 0; }
    [ -d "$_dest/.git" ] || { echo "[GMB] note: no clone at $_dest — skipping the environment plugin"; return 0; }
    grep -qx 'plugins/gmbeta/' "$_dest/.git/info/exclude" 2>/dev/null \
        || echo 'plugins/gmbeta/' >> "$_dest/.git/info/exclude"
    echo "[GMB] generating the environment plugin -> $_plug"
    GM_BRIDGE_PLUGIN_NAME=gmbeta "$_kernel" bridge "$_plug" >/dev/null \
        || { echo "[GMB] ERROR: gm_kernel bridge failed for $_plug" >&2; exit 1; }
    # Compiled once in the working tree by generate_plugin.sh; copied here when
    # the sources match, compiled here when they do not.
    GM_PLUGIN_BIN_CACHE="$REPO_ROOT/plugins/gmcc" bash "$SCRIPT_DIR/build_plugin_binaries.sh" "$_plug"
    # `gmbeta` in a shell pane: $GM_FS_ROOT/bin is first on its PATH.
    cat > "$_root/bin/gmbeta" <<EOF
#!/bin/sh
# Launch Claude Code against THIS environment's kernel and plugin. Written by gm_env.sh seed.
export GM_FS_ROOT="$_root"
exec claude --plugin-dir "$_plug" "\$@"
EOF
    chmod 755 "$_root/bin/gmbeta"
    echo "[GMB] environment plugin ready; \`gmbeta\` shim at $_root/bin/gmbeta"
}

# A refresh is a create over an existing root. Deliberately the SAME code path:
# a separate "update" path is how the two drift until only one of them works.
env_refresh() {
    _env="$1"; guard_not_prod "$_env" refresh
    env_create "$_env"
}

# ── seed — the Xcode Debug phase's door ──────────────────────────────────────
#
# A FAST, IDEMPOTENT subset of create, sized to run on EVERY ⌘R (the
# TestEnvSeed aggregate calls it through xcode_phase.sh). It BUILDS NOTHING:
# the enclosing Xcode build hands it the app it just produced as GM_SEED_APP,
# and the bundle's own executable is staged through the release-store
# functions. It must not be create: create runs rebuild_local, which also
# regenerates plugins/gmcc into the source tree — a write PluginBridge gates
# to Beta builds and the Debug path must not acquire.
env_seed() {
    _env="$1"; guard_not_prod "$_env" seed
    _root="$(env_root "$_env")" || exit 2
    echo "[GMB] seed $_env -> $_root"
    mkdir -p "$_root/bin" "$_root/repos" "$_root/backups"

    _app="${GM_SEED_APP:?seed needs GM_SEED_APP (xcode_phase.sh seed sets it); by hand: bash gmk/scripts/rebuild_local.sh --env test}"
    _built="$(gm_app_kernel "$_app")"

    GM_ENV="$_env"; GM_FS_ROOT="$_root"; gm_resolve_fs_root
    _version="$(cat "$GMK/VERSION")-BETA"

    # Stage only when the bits changed. A staged binary is NEVER overwritten in
    # place — the kernel's codesign cache answers a rewritten inode with
    # SIGKILL — so a changed build re-stages its whole version directory and
    # gm_activate's symlink swap is what makes that safe.
    #
    # The comparison is against the BUNDLE's executable as recorded at the last
    # stage, not against the staged copy: an unsigned build is re-signed ad-hoc
    # on the way in (see gm_stage_bundle), so the staged bytes never equal the
    # build's and a byte comparison would re-stage on every ⌘R.
    _stage="$(gm_stage_dir local "$_version")"
    _new_sha="$(shasum -a 256 "$_built" | awk '{print $1}')"
    _old_sha=""
    [ -e "$GM_BIN/$GM_APP_NAME.app" ] && [ -f "$_stage/.bundle_sha256" ] \
        && _old_sha="$(cat "$_stage/.bundle_sha256")"
    if [ "$_new_sha" = "$_old_sha" ]; then
        echo "[GMB] staged kernel app already matches the build — skipping stage"
    else
        # A running copy of the old bundle must not be replaced under itself.
        gm_stop_kernel_and_wait
        rm -rf "$_stage"
        _src_sha="$(git -C "$REPO_ROOT" rev-parse --short HEAD 2>/dev/null || echo unknown)"
        gm_stage_bundle "$_app" local "$_version" "$_src_sha" >/dev/null \
            || { echo "[GMB] ERROR: staging $_app failed" >&2; exit 1; }
        "$_stage/$GM_APP_NAME.app/Contents/MacOS/$GM_MACHO" --version >/dev/null \
            || { echo "[GMB] ERROR: the staged $GM_MACHO does not run (exit $?) — refusing to activate it" >&2; exit 1; }
        gm_activate local "$_version"
        printf '%s\n' "$_new_sha" > "$_stage/.bundle_sha256"
    fi

    # Registration launches the staged app when nothing is serving. Quit it
    # afterwards in that case: the app Xcode is about to run would find the
    # lock held, alert, and quit. A kernel that was already up stays up.
    _was_live=0
    gm_kernel_live && _was_live=1
    env_seed_repo "$_env" "$_root"
    env_seed_plugin "$_env" "$_root"
    if [ "$_was_live" -eq 0 ] && gm_kernel_live; then
        echo "[GMB] quitting the kernel app registration launched"
        gm_stop_kernel_and_wait
    fi
    echo "[GMB] seed $_env done"
}

# ── inspect / destroy ────────────────────────────────────────────────────────

env_doctor() {
    _env="$1"; _root="$(env_root "$_env")" || exit 2
    echo "environment : $_env"
    echo "root        : $_root"
    echo "exists      : $([ -d "$_root" ] && echo yes || echo NO)"
    echo "db          : $([ -f "$_root/gm.db" ] && echo yes || echo no)"
    echo "binaries    : $([ -x "$_root/bin/gm_kernel" ] && echo yes || echo NO)"
    if [ "$_env" = "prod" ]; then
        _app="/Applications/gm_kernel.app"
    else
        _app="$_root/bin/gm_kernel.app"
    fi
    if [ ! -d "$_app" ]; then
        echo "kernel app  : NO ($_app)"
    elif codesign --verify --deep --strict "$_app" >/dev/null 2>&1; then
        echo "kernel app  : $_app (signature verifies)"
    else
        echo "kernel app  : $_app (SIGNATURE DOES NOT VERIFY)"
    fi
    echo "version     : $(cat "$_root/bin/.gm_version" 2>/dev/null || echo none)"
    echo "plugin      : $(ls -d "$_root"/repos/*/plugins/gmbeta 2>/dev/null | head -n1 || true)"
    if _pid="$(env_live_pid "$_root")"; then
        echo "daemon      : running (pid $_pid)"
    else
        echo "daemon      : not running"
    fi
    [ -d "$_root/repos" ] && for _r in "$_root"/repos/*; do
        [ -d "$_r/.git" ] && echo "repo        : $_r @ $(git -C "$_r" rev-parse --abbrev-ref HEAD)"
    done
    return 0
}

env_destroy() {
    _env="$1"; guard_not_prod "$_env" destroy
    _root="$(env_root "$_env")" || exit 2
    [ -d "$_root" ] || { echo "[GMB] $_root does not exist"; return 0; }
    GM_ENV="$_env"; GM_FS_ROOT="$_root"; gm_resolve_fs_root
    gm_stop_kernel_and_wait
    rm -rf "$_root"
    echo "[GMB] removed $_root"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

CMD="${1:-}"; shift || true
case "$CMD" in
    create)  env_create  "${1:?environment: beta|test}" ;;
    refresh) env_refresh "${1:?environment: beta|test}" ;;
    seed)    env_seed    "${1:?environment: beta|test}" ;;
    doctor)  env_doctor  "${1:-prod}" ;;
    destroy) env_destroy "${1:?environment: beta|test}" ;;
    *)
        sed -n '2,10p' "$0"
        exit 2
        ;;
esac
