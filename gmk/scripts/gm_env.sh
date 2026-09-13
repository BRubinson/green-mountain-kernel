#!/bin/bash
#
# gm_env.sh — create, refresh, inspect and tear down the non-production
# environments.
#
#     bash gmk/scripts/gm_env.sh create  beta
#     bash gmk/scripts/gm_env.sh refresh beta
#     bash gmk/scripts/gm_env.sh doctor  beta
#     bash gmk/scripts/gm_env.sh run     test -- swift test --package-path ...
#     bash gmk/scripts/gm_env.sh reap    test
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
#   test  $HOME/test_gmfs   a CHANNEL, not a single environment. Individual test
#                           runs get EPHEMERAL roots beneath it.
#
# ── WHY `test` IS N ROOTS AND NOT ONE ────────────────────────────────────────
#
# A single persistent test root re-creates the exact collision the test lock
# exists to prevent. Two agents testing at once: the second one's kernel loses
# the flock on $HOME/test_gmfs/daemon.pid and either fails outright or attaches
# as a CLIENT to the first run's kernel — at which point both runs share one
# append-only database while one of them is counting rows in it.
#
# Ephemeral roots at $HOME/test_gmfs/runs/<id>/ dissolve that: every run has its
# own database, its own socket, its own pidfile, its own flock. Each is
# legitimately a single writer, and nothing needs to arbitrate.
#
# RUN IDS ARE SHORT, and that is a hard constraint rather than a style choice.
# sun_path is 104 BYTES on macOS and the server binds a unix socket beneath the
# run root; a timestamp-and-pid id blows that budget on a long home directory,
# and the failure mode is a listener that will not bind.
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
# shellcheck source=gm_releases.sh
. "$SCRIPT_DIR/gm_releases.sh"

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
fi

die() { echo "[GMB] $*" >&2; exit 1; }

# Refuse to manage production. Every destructive verb here would be a
# catastrophe against $HOME/gmfs, and "be careful" is not a mechanism.
guard_not_prod() {
    [ "$1" = "prod" ] && die "refusing to '$2' production — that is what the other environments are for"
    return 0
}

env_root() { gm_env_root "$1"; }

# ── create / refresh ─────────────────────────────────────────────────────────

env_create() {
    _env="$1"; guard_not_prod "$_env" create
    _root="$(env_root "$_env")" || exit 2
    echo "[GMB] $_env -> $_root"
    mkdir -p "$_root/bin" "$_root/repos" "$_root/backups"

    # A FULL release store, not just directories. The app autostarts
    # $ROOT/bin/gm_daemon, and the hook shim exits 0 SILENTLY when its binary is
    # absent — so an unpopulated bin/ does not fail loudly, it records nothing.
    echo "[GMB] staging binaries into $_root"
    GM_ENV="$_env" GM_FS_ROOT="$_root" bash "$SCRIPT_DIR/rebuild_local.sh" --fast

    env_seed_repo "$_env" "$_root"
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
    else
        echo "[GMB] cloning $REPO_ROOT -> $_dest"
        # Clone from the LOCAL working repo rather than from origin: the point
        # is to test what is here, including commits that have not been pushed.
        git clone --quiet --no-hardlinks "$REPO_ROOT" "$_dest"
    fi
    git -C "$_dest" checkout -q -B "$_branch"
    echo "[GMB] $_dest on branch $_branch"

    # Boot the environment's kernel so it migrates an empty database into a full
    # schema, then register the clone and ingest its dope. Those rows — and
    # nothing else — are what this environment starts with.
    _hook="$_root/bin/gm_hook"
    if [ -x "$_hook" ]; then
        echo "[GMB] registering the clone"
        GM_FS_ROOT="$_root" "$_hook" call CONTEXT_ENSURE \
            --json "{\"repo_path\":\"$_dest\"}" >/dev/null 2>&1 \
            || echo "[GMB] note: CONTEXT_ENSURE declined; register by opening a session there"
        if [ -d "$_dest/.gmcc" ]; then
            GM_FS_ROOT="$_root" "$_hook" call DOPE_READ_REPO \
                --json "{\"repo_path\":\"$_dest\"}" >/dev/null 2>&1 \
                || echo "[GMB] note: dope ingestion declined"
        fi
    else
        echo "[GMB] note: no gm_hook staged at $_hook — skipping registration"
    fi
}

# A refresh is a create over an existing root. Deliberately the SAME code path:
# a separate "update" path is how the two drift until only one of them works.
env_refresh() {
    _env="$1"; guard_not_prod "$_env" refresh
    env_create "$_env"
}

# ── ephemeral test runs ──────────────────────────────────────────────────────

# Mint a run root, run a command against it, tear it down.
#
# The id is SHORT for the sun_path reason at the top of this file. Six hex
# characters under $HOME/test_gmfs/runs/ leaves ample headroom for
# `<root>/daemon.sock` inside 104 bytes on any plausible home directory.
env_run() {
    _root="$(env_root test)"
    _id="$(hexdump -n3 -e '"%06x"' /dev/urandom)"
    _run="$_root/runs/$_id"
    mkdir -p "$_run/bin"
    # Stage by SYMLINK from the channel's store rather than rebuilding: a run is
    # supposed to test the bits that are already there, and a per-run build
    # would make every run test something slightly different.
    if [ -d "$_root/bin/releases" ]; then
        ln -sfn "$_root/bin/releases" "$_run/bin/releases"
        for _n in gm_kernel gm_daemon gm_mcp gm_hook; do
            [ -e "$_root/bin/$_n" ] && ln -sfn "$_root/bin/$_n" "$_run/bin/$_n"
        done
    fi
    echo "[GMB] run root $_run"
    # The lock file this run's holder flocks. Its EXISTENCE plus an flock is the
    # liveness signal the daemon probes — no TTL anywhere in the scheme.
    : > "$_run/run.lock"
    set +e
    GM_FS_ROOT="$_run" "$@"
    _rc=$?
    set -e
    GM_FS_ROOT="$_run" "$_run/bin/gm_hook" call SHUTDOWN --json '{}' >/dev/null 2>&1 || true
    rm -rf "$_run"
    return $_rc
}

# Remove run roots whose kernel is gone. Lazy, like the lock's own reaping —
# there is no timer anywhere in this design.
env_reap() {
    _root="$(env_root test)"
    [ -d "$_root/runs" ] || { echo "[GMB] no runs"; return 0; }
    for _run in "$_root"/runs/*; do
        [ -d "$_run" ] || continue
        if [ -f "$_run/daemon.pid" ] && kill -0 "$(cat "$_run/daemon.pid" 2>/dev/null)" 2>/dev/null; then
            echo "[GMB] live: $_run"
        else
            echo "[GMB] reaping $_run"
            rm -rf "$_run"
        fi
    done
}

# ── inspect / destroy ────────────────────────────────────────────────────────

env_doctor() {
    _env="$1"; _root="$(env_root "$_env")" || exit 2
    echo "environment : $_env"
    echo "root        : $_root"
    echo "exists      : $([ -d "$_root" ] && echo yes || echo NO)"
    echo "db          : $([ -f "$_root/gm.db" ] && echo yes || echo no)"
    echo "binaries    : $([ -x "$_root/bin/gm_hook" ] && echo yes || echo NO)"
    echo "version     : $(cat "$_root/bin/.gm_version" 2>/dev/null || echo none)"
    if [ -f "$_root/daemon.pid" ] && kill -0 "$(cat "$_root/daemon.pid" 2>/dev/null)" 2>/dev/null; then
        echo "daemon      : running (pid $(cat "$_root/daemon.pid"))"
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
    GM_FS_ROOT="$_root" "$_root/bin/gm_hook" call SHUTDOWN --json '{}' >/dev/null 2>&1 || true
    rm -rf "$_root"
    echo "[GMB] removed $_root"
}

# ── dispatch ─────────────────────────────────────────────────────────────────

CMD="${1:-}"; shift || true
case "$CMD" in
    create)  env_create  "${1:?environment: beta|test}" ;;
    refresh) env_refresh "${1:?environment: beta|test}" ;;
    doctor)  env_doctor  "${1:-prod}" ;;
    destroy) env_destroy "${1:?environment: beta|test}" ;;
    reap)    env_reap ;;
    run)
        shift 2>/dev/null || true
        [ "${1:-}" = "--" ] && shift
        [ $# -gt 0 ] || die "gm_env.sh run test -- <command>"
        env_run "$@"
        ;;
    *)
        sed -n '2,12p' "$0"
        exit 2
        ;;
esac
