#!/usr/bin/env bash
#
# migrate_to_gmfs.sh — populate ~/gmfs from the live ~/gmcc runtime.
#
# Implements architecture rows M1-M5 of prompt 1 (re-organize). This is the
# LAST action of that prompt, run after every code row landed and the suite
# was green.
#
# WHAT IT DOES, and what it deliberately does not:
#
#   - COPIES the live database. `~/gmcc/gmcc.db` is never written, moved, or
#     deleted. That is what makes this reversible and it is why the user's
#     "I dont want to lose anything" is satisfied by construction rather than
#     by care.
#   - MOVES the kbite payloads, because copying 26G of them was explicitly not
#     wanted. `unity` is left behind on purpose.
#   - COPIES the small content roots (projects/, _archive/, README.md), because
#     they are cheap enough that keeping a fallback costs nothing.
#
# WHY NOT `cp` FOR THE DATABASE: it is 596M in WAL mode with a multi-megabyte
# -wal file and a running writer. A raw copy can capture a torn page or silently
# drop everything still in the WAL. The daemon is retired first and the snapshot
# is taken with `sqlite3 .backup`, which is consistent by construction.
#
# WHY THE REAL DAEMON APPLIES m0027 RATHER THAN HAND-WRITTEN SQL: migrations run
# through GRDB's DatabaseMigrator, which records applied migrations in
# `grdb_migrations` (by identifier) IN ADDITION to this schema's own
# `schema_migrations` (by integer version). Hand-applying the ALTER TABLEs and
# inserting only the `schema_migrations` row would leave GRDB believing m0027
# had never run — it would then re-run it against an already-renamed column and
# FAIL TO OPEN THE DATABASE. That failure would land immediately after install,
# which is the worst possible moment. Running the real binary writes both tables
# correctly and exercises the migration for real, which is the whole reason
# m0027 was shipped rather than dropped.
#
# WHY THIS SCRIPT REWRITES THE CONFIG VALUES AND m0027 DOES NOT: m0027's own
# comment says it renames the KEY and leaves the VALUE, because "rewriting
# values here would mean this migration guessed at a filesystem layout it cannot
# see". This script CAN see the layout, so the value rewrite belongs here.
#
# Usage:
#   ./migrate_to_gmfs.sh            # DRY RUN — prints the plan, changes nothing
#   ./migrate_to_gmfs.sh --execute  # actually do it
#
set -euo pipefail

DRY=1
[[ "${1:-}" == "--execute" ]] && DRY=0

OLD_ROOT="$HOME/gmcc"
OLD_CONTENT="$HOME/gmcc_ckfs"
NEW_ROOT="$HOME/gmfs"
OLD_DB="$OLD_ROOT/gmcc.db"
NEW_DB="$NEW_ROOT/gm.db"

# Every kbite EXCEPT unity. unity stays at the old content root by explicit
# instruction; its rows in the migrated db become knowingly dangling references,
# which is reported rather than hidden.
SKIP_KBITE="unity"

# The tables whose cardinality is compared before and after the snapshot. Not
# exhaustive on purpose — these are the substantive ones, and a torn copy would
# show up here.
COUNT_TABLES=(
  project instance session prompt
  daemon_config schema_migrations grdb_migrations
  file_change exploration_finding review_finding
  architecture_persistence_change architecture_general_change
)

say  () { printf '\n\033[1m%s\033[0m\n' "$*"; }
step () { printf '  %s\n' "$*"; }
run  () {
  if (( DRY )); then printf '  [dry] %s\n' "$*"
  else printf '  + %s\n' "$*"; eval "$@"
  fi
}
die  () { printf '\n\033[31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# $1 = db path. $2 = "ro" to open read-only.
#
# READ-ONLY IS ONLY SAFE ON THE LIVE DATABASE, and only because the running
# daemon has already created its `-shm` file. A read-only open of a WAL-mode
# database must create `-shm` if it is missing, so `mode=ro` against a FRESH
# `.backup` artifact fails on every table and reports ABSENT — which looks
# exactly like a short copy. That cost one false alarm; the copy was perfect.
# The snapshot is ours, so it is opened read-write.
counts_of () {
  local db="$1" mode="${2:-rw}" t n
  for t in "${COUNT_TABLES[@]}"; do
    if [[ "$mode" == "ro" ]]; then
      n=$(sqlite3 "file:$db?mode=ro" "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo "ABSENT")
    else
      n=$(sqlite3 "$db" "SELECT COUNT(*) FROM $t;" 2>/dev/null || echo "ABSENT")
    fi
    printf '%s=%s\n' "$t" "$n"
  done
}

# ---------------------------------------------------------------- preflight
say "PREFLIGHT"
[[ -f "$OLD_DB" ]] || die "live db not found at $OLD_DB"
step "live db:      $OLD_DB ($(du -h "$OLD_DB" | cut -f1))"
step "journal mode: $(sqlite3 "file:$OLD_DB?mode=ro" 'PRAGMA journal_mode;')"
step "quick_check:  $(sqlite3 "file:$OLD_DB?mode=ro" 'PRAGMA quick_check;' | head -1)"
step "schema ver:   $(sqlite3 "file:$OLD_DB?mode=ro" 'SELECT MAX(version) FROM schema_migrations;')"

if [[ -e "$NEW_DB" ]]; then
  die "$NEW_DB already exists. Refusing to overwrite a migrated database.
       Move it aside deliberately if you intend to re-run this."
fi

NEW_DAEMON="$NEW_ROOT/bin/gm_daemon"
NEW_HOOK="$NEW_ROOT/bin/gm_hook"
if [[ ! -x "$NEW_DAEMON" || ! -x "$NEW_HOOK" ]]; then
  step "NOTE: new binaries are not at $NEW_ROOT/bin yet."
  step "      Phase 4 needs them, because the REAL daemon must apply m0027."
  step "      Run: bash gmk/scripts/rebuild_local.sh"
fi

# ------------------------------------------------------------------ phase 1
say "PHASE 1 — baseline row counts from the LIVE database (read-only)"
BASELINE=$(counts_of "$OLD_DB" ro)
echo "$BASELINE" | sed 's/^/  /'

# ------------------------------------------------------------------ phase 2
say "PHASE 2 — retire the running daemon, then snapshot"
step "the OLD daemon is retired so the snapshot is quiesced; it autostarts again"
step "on the next client call, so this session's pen access returns by itself"
run "gmcc_hook call SHUTDOWN --json '{}' || true"
run "mkdir -p '$NEW_ROOT'"
run "sqlite3 '$OLD_DB' \".backup '$NEW_DB'\""

# ------------------------------------------------------------------ phase 3
say "PHASE 3 — verify the snapshot by ROW COUNT, not by file size"
if (( DRY )); then
  step "[dry] would compare each table in the copy against the baseline"
else
  COPY=$(counts_of "$NEW_DB")
  if [[ "$BASELINE" == "$COPY" ]]; then
    step "all $(echo "$BASELINE" | wc -l | tr -d ' ') tables match exactly"
    echo "$COPY" | sed 's/^/    /'
  else
    printf '  baseline:\n%s\n  copy:\n%s\n' \
      "$(echo "$BASELINE" | sed 's/^/    /')" "$(echo "$COPY" | sed 's/^/    /')"
    die "ROW COUNT MISMATCH — the copy is short. The live db is untouched;
       delete $NEW_DB and investigate. Do NOT proceed to the path rewrite."
  fi
fi

# ------------------------------------------------------------------ phase 4
say "PHASE 4 — apply m0027 through the REAL daemon (never hand-written SQL)"
step "GRDB tracks migrations in grdb_migrations by identifier AND this schema"
step "tracks them in schema_migrations by version. Only the real binary writes"
step "both; hand-applied SQL would make GRDB re-run m0027 and fail to open."
run "GM_FS_ROOT='$NEW_ROOT' '$NEW_HOOK' ping"
run "GM_FS_ROOT='$NEW_ROOT' '$NEW_HOOK' call SHUTDOWN --json '{}' || true"

if (( ! DRY )); then
  GOT_V=$(sqlite3 "$NEW_DB" "SELECT MAX(version) FROM schema_migrations;")
  GOT_ID=$(sqlite3 "$NEW_DB" "SELECT identifier FROM grdb_migrations ORDER BY rowid DESC LIMIT 1;")
  step "schema_migrations max = $GOT_V   (expect 27)"
  step "grdb_migrations last  = $GOT_ID  (expect m0027_ckfsToGmfs)"
  [[ "$GOT_V" == "27" ]] || die "m0027 did not apply: schema_migrations is $GOT_V"
  [[ "$GOT_ID" == "m0027_ckfsToGmfs" ]] || die "GRDB did not record m0027: last is $GOT_ID"
  for t in project instance session prompt; do
    sqlite3 "$NEW_DB" "SELECT gmfs_relative_storage_path FROM $t LIMIT 0;" \
      >/dev/null 2>&1 || die "$t has no gmfs_relative_storage_path column after m0027"
    if sqlite3 "$NEW_DB" "SELECT ckfs_relative_storage_path FROM $t LIMIT 0;" >/dev/null 2>&1; then
      die "$t STILL has ckfs_relative_storage_path — the column was aliased, not renamed"
    fi
  done
  step "all four columns renamed, old name gone (not aliased)"
fi

# ------------------------------------------------------------------ phase 5
say "PHASE 5 — rewrite the ABSOLUTE roots (m0027 deliberately leaves values alone)"
step "RELATIVE storage paths are NOT touched. They resolve against the content"
step "root; rewriting them would corrupt every prompt path in one statement."
# A SINGLE SAMPLE ROW IS NOT ENOUGH, and the first version of this check proved
# it: `IS NOT NULL` matched a row whose path was the EMPTY STRING, so BEFORE and
# AFTER were both "" and the guard compared nothing while reporting success.
# Cardinality AND total string length per table is the cheap check that cannot
# pass vacuously — a replace() that touched these columns would move the sum.
rel_fingerprint () {
  local t
  for t in project instance session prompt; do
    printf '%s=%s\n' "$t" \
      "$(sqlite3 "$1" "SELECT COUNT(*) || '/' || COALESCE(SUM(LENGTH(gmfs_relative_storage_path)),0) FROM $t;")"
  done
}
if (( ! DRY )); then
  BEFORE_REL=$(rel_fingerprint "$NEW_DB")
  step "relative-path fingerprint BEFORE: $(echo "$BEFORE_REL" | tr '\n' ' ')"
fi
run "sqlite3 '$NEW_DB' \"
  UPDATE daemon_config SET config_value = replace(config_value, '$OLD_CONTENT', '$NEW_ROOT')
   WHERE config_value LIKE '$OLD_CONTENT%';
  UPDATE daemon_config SET config_value = replace(config_value, '$OLD_DB', '$NEW_DB')
   WHERE config_value LIKE '$OLD_DB%';
  UPDATE daemon_config SET config_value = replace(config_value, '$OLD_ROOT', '$NEW_ROOT')
   WHERE config_value LIKE '$OLD_ROOT%';
\""
if (( ! DRY )); then
  AFTER_REL=$(rel_fingerprint "$NEW_DB")
  step "relative-path fingerprint AFTER:  $(echo "$AFTER_REL" | tr '\n' ' ')"
  [[ "$BEFORE_REL" == "$AFTER_REL" ]] || die "a RELATIVE storage path changed — that must never happen.
       Expected: $(echo "$BEFORE_REL" | tr '\n' ' ')
       Got:      $(echo "$AFTER_REL" | tr '\n' ' ')"
  for t in project instance session prompt; do
    n=$(sqlite3 "$NEW_DB" "SELECT COUNT(*) FROM $t WHERE gmfs_relative_storage_path LIKE '/%';")
    [[ "$n" == "0" ]] || die "$n rows in $t have an ABSOLUTE storage path — the rewrite leaked"
  done
  step "relative paths verified unchanged, and still relative in all four tables"
  say "  daemon_config after rewrite:"
  sqlite3 "$NEW_DB" "SELECT config_key, config_value FROM daemon_config ORDER BY config_key;" | sed 's/^/    /'
  LEFT=$(sqlite3 "$NEW_DB" "SELECT COUNT(*) FROM daemon_config WHERE config_value LIKE '%gmcc%';")
  step "config rows still naming the old roots: $LEFT (expect 0)"
fi

# ------------------------------------------------------------------ phase 6
say "PHASE 6 — MOVE the kbite payloads (unity stays behind)"
run "mkdir -p '$NEW_ROOT/kbites/digested' '$NEW_ROOT/kbites/open'"
for tier in digested open; do
  src="$OLD_CONTENT/kbites/$tier"
  [[ -d "$src" ]] || continue
  for d in "$src"/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    if [[ "$name" == "$SKIP_KBITE" ]]; then
      step "SKIP  $tier/$name  (left at the old root on purpose; its db rows dangle by design)"
      continue
    fi
    run "mv '$d' '$NEW_ROOT/kbites/$tier/'"
  done
done

# ------------------------------------------------------------------ phase 7
say "PHASE 7 — COPY the content roots so relative paths still resolve"
step "this is the step the original instruction did not name: without projects/,"
step "every relative storage path in the migrated db would dangle invisibly"
for item in projects _archive README.md; do
  [[ -e "$OLD_CONTENT/$item" ]] || { step "absent, skipping: $item"; continue; }
  run "cp -R '$OLD_CONTENT/$item' '$NEW_ROOT/'"
done
step "development/ is deliberately NOT copied — it holds a regenerable sandbox"

# ------------------------------------------------------------------ phase 8
say "PHASE 8 — end-to-end check and restore this session's daemon"
if (( ! DRY )); then
  REL=$(sqlite3 "$NEW_DB" "SELECT gmfs_relative_storage_path FROM prompt WHERE code='re-organize' LIMIT 1;")
  step "this prompt's stored path: $REL"
  if [[ -n "$REL" && -d "$NEW_ROOT/$REL" ]]; then
    step "RESOLVES under $NEW_ROOT — the relative-path contract holds end to end"
  else
    step "WARNING: $NEW_ROOT/$REL does not exist. Report this; do not paper over it."
  fi
  step "live db untouched: $(du -h "$OLD_DB" | cut -f1) at $OLD_DB"
  step "unity left behind:  $(du -sh "$OLD_CONTENT/kbites/digested/$SKIP_KBITE" 2>/dev/null | cut -f1)"
fi
run "gmcc_hook ping"

# `${DRY:+...}` expands whenever DRY is non-empty, and "0" is non-empty — so the
# first version printed "dry run — nothing changed" after a REAL migration. That
# is the most misleading line this script could possibly end on.
if (( DRY )); then say "DONE (dry run — nothing changed)"
else                say "DONE — migration applied"
fi
(( DRY )) && printf '  re-run with --execute to perform the migration\n'
