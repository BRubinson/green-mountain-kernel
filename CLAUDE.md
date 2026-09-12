# green-mountain-kernel

Monorepo for the GM-CDE (Green Mountain Contextual Development
Environment), where the GMCC toolchain is being rebuilt on native
framework/model work. GMB identity and behavioral rules are NOT here — they live
plugin-globally in `plugins/gmcc/skills/gmcc/SKILL.md` so every
gmcc-booted repo gets them, not just this one.

## READ THIS FIRST — cutover is DONE; there is ONE stack

The runtime is `gmk/`, the binaries are `gm_daemon` / `gm_mcp` / `gm_hook`, the
one filesystem root is `~/gmfs`, and `plugins/gmcc/` drives them. The previously
shipped stack, under its own binary names and its own runtime root, is retired.
Those literals are deliberately not repeated in this file — the retired-name
contract forbids them here, and `gmk/scripts/migrate_to_gmfs.sh` is the one place
that legitimately spells them, because performing a migration requires naming
what it migrates from.

Consequences a reader must not re-derive incorrectly:

- **`plugins/gmcc/` is no longer frozen.** It was, for the length of the reorg,
  because it drove the machine through a runtime installed under the old names.
  It has since been swept, and the retired-name contract now covers it like
  everything else. `RetiredNameContractTests` has no path exemption for the
  plugin, and **reintroducing one is not the fix for a file that trips it** —
  sweeping that file is.
- The plugin directory, the `gmcc:` command/skill namespace, the
  `mcp__plugin_gmcc_pen__*` pen server name, the `.gmcc_sandbox` marker filename
  and the in-repo `.gmcc/` dope directory all **keep their names**. The repo
  deliberately holds both prefixes: `gm`-prefixed on the runtime side, `gmcc` on
  the plugin/namespace side. `testAllowedSpellingsAreNotFlagged` is what stops a
  future sweep from "tidying" the second list into the first.
- **The original database is still on disk and is the rollback anchor.** The
  migration COPIED it and never wrote to it, which is what makes the whole step
  reversible. `migrate_to_gmfs.sh` names its exact path. Do not delete it
  casually.
- The `unity` kbite payload was deliberately left at the old content root, so its
  row in `gm.db` is a knowingly dangling reference. That is recorded, not
  forgotten.

## The release loop

Binaries reach `~/gmfs/bin` two ways, and only two:

```bash
bash gmk/scripts/rebuild_local.sh     # build this working tree, stage <version>-BETA, activate
bash gmk/scripts/publish_release.sh   # verify, run the suites, tag, upload, promote
```

`rebuild_local.sh` builds **universal** (arm64 + x86_64) so the artifact it
stages is already releasable — `publish_release.sh` uploads exactly those bytes
rather than rebuilding, so what you tested is what ships. `--fast` builds arm64
only for the edit-compile loop and is refused by publish, which reads slices with
`lipo` rather than trusting the manifest.

A local build is **always** stamped `-BETA`. There is no flag to suppress it: the
suffix is the only thing distinguishing bits that were merely built from bits
that were published.

Everyone who is not editing the sources runs the plugin's installer, which needs
no checkout and asks GitHub for the newest `daemon-v*` release:

```bash
bash plugins/gmcc/scripts/install_gm.sh
```

### The release store

Versions are staged immutably and selected by symlink, so rollback is a swap:

```
~/gmfs/bin/
├── gm_daemon -> releases/active/gm_daemon      relative links
├── .gm_version                                 "50.0.1" or "50.0.1-BETA"
└── releases/
    ├── active -> downloads/50.0.1
    ├── downloads/<version>/                    fetched from a release
    └── local/<version>-BETA/                   built from a working tree
```

Symlinks rather than copies because overwriting a signed Mach-O **in place**
leaves the kernel's code-signature cache pointing at the old inode and the next
exec dies with SIGKILL — exit 137, no output. Staged binaries are never
rewritten, so there is no in-place overwrite to get wrong.

`gm_releases.sh` is the store contract and **exists twice on purpose**: authored
at `gmk/scripts/`, vendored byte-identical into `plugins/gmcc/scripts/`. A
marketplace install materialises `plugins/gmcc/` alone, so the plugin's installer
cannot source a library under `gmk/`, and it must not climb out of the cache to
look for one — on a machine whose `$HOME` is a git repo, `git rev-parse
--show-toplevel` from the plugin cache confidently returns the home directory.
`ReleaseStoreContractTests` fails the build if the two copies drift; fix that by
copying, never by editing both.

**The publish path is repo-side only.** `gmk/scripts/` is not in the plugin
payload (`source: ./plugins/gmcc`), so installing the plugin does not distribute
`publish_release.sh`. On top of that it refuses unless the authenticated `gh`
user holds push on the repo.

`.github/workflows/daemon-release.yml` is the **fallback**, not the default. Its
tag trigger was deliberately removed: it would have fired on the tag
`publish_release.sh` pushes and clobbered the verified assets with a fresh build
nobody had run. Dispatch it manually when the local path is unavailable.

## Layout

- `gmk/` — the new home of every Swift deliverable: one Xcode project
  (`gmk/gmk.xcodeproj`) over six shipped packages, plus a seventh that ships
  nothing and holds the repository's own contract tests.
  - `gmk/gmDaemonSdk/` — the base layer: the wire protocol (including the
    workflow spec the bot phases are driven by), the client, and the shared
    domain layer (`Dope/`, `Diagram/` models, `Hook/`, `Kbite/`, `Environment/`,
    `Paths.swift`, `RepoRelativePath.swift`, `GitHead.swift`, `StoreError`), plus
    the `gm_hook` binary. Zero external dependencies.
  - `gmk/gmDaemon/` — persistence and the `gm_daemon` server. Owns the sole GRDB
    pin, so GRDB is not in the app's link closure.
  - `gmk/gmUxComponentLibrary/` — the shared component surface: the diagram UI
    views plus the geometry, routing, layout and organizer helpers they are built
    on. Diagrams only for now, built as a surface that expects to grow.
  - `gmk/gmAgententicsSdk/` — the agent-tool protocol declarations. Intentionally
    tiny; its emptiness is a decision, not a gap.
  - `gmk/gmMcp/` — the `gm_mcp` MCP pen server.
  - `gmk/gmVibes/` — the GMVibes macOS app (Swift/SwiftUI). Release via the
    `release-dmg` skill.
  - `gmk/gmToolchain/` — the seventh package, and the only one that **ships
    nothing** (`products: []`). Membership rule: the tests that read FILES rather
    than call symbols — the docs and hook-launcher contracts, the retired-name
    contract, the pen-roster check against `gm_mcp`'s source text, and the
    live-runtime isolation scan. None of them tests a module's internals; they
    test the repository. It also owns `RepoRoot`, the one `#filePath`-to-repo-root
    resolver, as a TARGET SOURCE rather than a library product: exporting it made
    `gmDaemonSdk` depend on this package while this package needs the SDK for
    `DopeVocabulary`, which SwiftPM rejects as a cycle. **The one dependency edge
    points DOWN at `gmDaemonSdk` and never the reverse** — the SDK has ZERO
    dependencies, and that is what keeps the graph acyclic. **Do not reintroduce
    that edge**: making `RepoRoot` a library product so other packages' test
    targets can import it is the convenient-looking change that recreates the
    cycle, and SwiftPM will reject it. Named `gmToolchain`,
    not `...Tests`, because a directory ending in "Tests" reads as a mistake the
    moment a manifest names it in a `.package(path:)` line.
  - `gmk/scripts/` — the build and install path for the binaries (see below),
    plus the app's DMG build and release scripts used by the `release-dmg`
    skill. Scripts live HERE and not beside the app sources: `gmk/gmVibes/` is a
    filesystem-synchronized Xcode group, so anything dropped in it becomes part
    of the app target's source directory.
  - `gmk/VERSION` — the version pin for the three shipped binaries.
- `plugins/gmcc/` — the Claude Code plugin: skills, commands, prompts, hooks,
  scripts and `.mcp.json`, plus the installer and the vendored release-store
  library. It ships **no Swift sources** — the package left this directory for
  `gmk/` and did not come back.
- `.gmcc/` — this repo's committed DOPE tree (Domain Optimized Project Essence);
  sessions boot-sync their dope scope from it. **The directory keeps this name.**
  Any rename pass must exclude the `.gmcc/` path segment — a blind sweep would
  break every dope-scope path at once.

Dependency graph, acyclic and 5 deep:

```
gmDaemonSdk ──┬── gmDaemon
              ├── gmUxComponentLibrary ──┐
              ├── gmMcp                  ├── gmVibes
              └──────────────────────────┘
gmAgententicsSdk (independent)
```

The forcing constraint: the wire types already reference the dope and diagram
document types, so those models cannot sit ABOVE the SDK. Any layering that
tries becomes a dependency cycle.

## Build / test loop — the `gmk/` stack

From the repo root:

```bash
swift test --package-path gmk/gmDaemonSdk           # per package; all must stay green
swift test --package-path gmk/gmDaemon
swift test --package-path gmk/gmUxComponentLibrary
swift test --package-path gmk/gmMcp
swift test --package-path gmk/gmToolchain
swift build --package-path gmk/gmAgententicsSdk     # compile-only by design
bash gmk/scripts/rebuild_local.sh                   # universal build → staged + activated
```

See **The release loop** above for how `rebuild_local.sh`, `publish_release.sh`
and the plugin's `install_gm.sh` divide the work.

CI `bash -n` syntax-checks the scripts and never runs them — they write to
`~/gmfs` and, in publish's case, tag and upload. That is a preserved invariant,
not an oversight; the packages are built directly, which is the part worth
gating. Do not "fix" it by adding a real build.

`rebuild_local.sh` and `publish_release.sh` resolve the repo with `git rev-parse
--show-toplevel` plus a script-directory walk, and then **verify `gmk/` is
actually there**. That check is not decoration: a bare `git rev-parse` can
resolve to an unrelated enclosing repository, and a `$HOME` under version control
is the case that actually bites. The plugin's installer sidesteps the problem
entirely by needing no repo at all.

There is no BuildInfo stamping step anywhere. A SwiftPM **prebuild plugin** in
`gmk/gmDaemon` does it inside the build graph, so Xcode and every CI job get it
free and a clean clone compiles with no prior shell step.

### Guard rails

- `VerbRegistryTests` fails the build when a `MessageType` ships without a
  `VerbRegistry` row. It lives in `gmDaemonSdk` (with the protocol it guards), so
  it stays armed in the base package.
- `DocsContractTests` fails the build when the plugin's docs regress (hardcoded
  binary paths, retired env names, retired DOPE acronym) or when `hooks.json` /
  `settings.json` / `.mcp.json` name a path that is not there.
- `RetiredNameContractTests` carries the **retired-name contract** — binaries,
  env vars, filesystem roots, the db and stamp filenames, the retired
  content-root vocabulary, the old module name and the old package path. It is scoped in this
  era to `gmk/**` plus `CLAUDE.md` and `README.md` only, with `plugins/gmcc/**`
  EXEMPT, because those files still name the running stack on purpose. Two narrow
  exceptions are legal by design: a record of a retirement has to be able to name
  what was retired, so the wire-version note and the migration body that perform
  the rename may spell the old column name.
- Every `#filePath`-walking test resolves the repo root through the ONE
  `RepoRoot` helper in `gmk/gmToolchain`. Copies of a directory-counting walk
  used to encode "this file is four levels below the plugin root", and every one
  of them broke when the package moved; the next move costs one edit.
- Wire protocol: bump `GmWireProtocol.version` only for a new message type or an
  incompatible change. Additive OPTIONAL fields on existing messages do NOT bump
  — they decode safely in both directions. Renaming a field on an existing
  message IS incompatible and DOES bump.
- Schema: migrations are append-only. The db is append-only history — **NEVER
  wipe it**. `gm_hook call BACKUP --json '{}'` takes the sanctioned online backup
  before risky work.

## Releasing the binaries

`gmk/VERSION` is the pin. Bump it, commit, then tag:

```bash
git tag daemon-v$(cat gmk/VERSION)
git push origin daemon-v$(cat gmk/VERSION)
```

`.github/workflows/daemon-release.yml` refuses to publish when the tag and the
file disagree, runs the suites, builds universal (arm64 + x86_64), verifies both
slices are present, and attaches the tarball plus its `.sha256`. The three
binaries are staged from THREE package bin paths — `gm_daemon` from `gmDaemon`,
`gm_mcp` from `gmMcp`, `gm_hook` from `gmDaemonSdk` — because they no longer
share one.

- The binary version is DECOUPLED from the plugin version on purpose. The plugin
  is markdown that changes constantly; the Swift is 44k lines that does not.
  Coupling them would make every prompt tweak force every install to re-download
  ~15MB of unchanged binaries. Move `gmk/VERSION` only when the code behind it
  actually changed.
- CI runs on `macos-26` because `GmAgentTool.swift` imports FoundationModels
  unconditionally, and that framework only exists in the macOS 26 SDK. An older
  runner does not degrade — the package does not compile at all.
- `.github/workflows/gmk-ci.yml` is one workflow with a matrix: one job per
  package plus an `xcodebuild` job for gmVibes, so every module gets its own
  visible check. It over-triggers by design (a gmVibes change also rebuilds
  gmDaemon) rather than carrying a hand-maintained path-filter copy of the
  dependency graph. The gmVibes job builds with `CODE_SIGNING_ALLOWED=NO`;
  release signing stays on the `release-dmg` path.

## Environment rules

- Sessions are provisioned by `gm_hook context env` at SessionStart; the only env
  vars are `GM_BOOTED`, `GM_PLUGIN_ROOT`, `GM_FS_ROOT` and `PATH`. Everything
  else: `gm_hook paths --json`.
- **ONE root variable.** `GM_FS_ROOT` points at the single top-level filesystem
  (`~/gmfs` by default), which holds both the runtime and the content that used
  to live in a second root. That is not a cosmetic collapse: env-and-db agreement
  goes from "compare two vars against two config rows, one of which may
  legitimately be absent" to "compare one always-present var against one config
  row", and containment becomes a single prefix test.
- env and db must always agree on the roots (mismatch = warning at boot).
- GMCC never writes the user's shell profile. The binaries reach a session through
  the PATH entry in that env block, and remediation lines are printed, not
  applied.

### Write containment — an invariant, not a preference

**Never write files outside `~/gmfs` (i.e. `$GM_FS_ROOT`) or the working repo,
unless explicitly asked.**

This is ENFORCED, not merely documented: `Paths.assertContained(_:)` in
`gmk/gmDaemonSdk` throws unless a URL is under the filesystem root or the working
repo, and every kit-side file write routes through it. A rule that lives only in
markdown erodes; this one fails a call.

## Sandbox dev loop

A sandbox is a full snapshot at `$GM_FS_ROOT/development/local_sandbox` — db
(`gm_hook call BACKUP --json '{}'` takes the sanctioned online copy), repo clone,
binaries, launchers. Sessions started inside the snapshot auto-sandbox via the
`.gmcc_sandbox` marker, which sets `GM_FS_ROOT` to the snapshot; a sandboxed daemon
opens only the staged db and never touches prod. Nothing in a sandbox should be
pointed back at the prod runtime.

With one root variable, a sandbox is no longer a special SHAPE of the
environment — it is a different VALUE of `GM_FS_ROOT`. That is the whole
mechanism now.

## The one-time migration into `~/gmfs` — ALREADY RUN

`gmk/scripts/migrate_to_gmfs.sh` has been executed. It is kept as the record of
what was done and as the only reversal reference; **do not run it again** — it
refuses anyway, because `~/gmfs/gm.db` already exists.

- `~/gmfs/gm.db` is created as a **quiesced copy** of the live db (shut down, then
  `sqlite3 .backup` — a raw `cp` of a ~600MB db with a live WAL can capture a
  torn page or drop committed rows). Verification is **per-table row counts**, not
  file size.
- The live db is **never written**. It is a copy, which is what makes the step
  reversible.
- Only ABSOLUTE roots in `daemon_config` are rewritten. The
  `gmfs_relative_storage_path` columns are relative by design and must NOT be
  touched — rewriting them would corrupt every project, instance, session and
  prompt path in one statement.
- Content comes across with it, because the relative paths resolve against it.

**The sandbox marker filename is `.gmcc_sandbox` and is deliberately NOT
renamed.** `HookLogic.SandboxMarker.fileName` in `gmDaemonSdk` is the authority,
and the shell launchers must agree with it: a marker only one side recognises is
a sandbox session writing the prod database. The variable INSIDE it is the single
`GM_FS_ROOT`.

## Working-tree note

Uncommitted edits in the working tree are usually intentional — validate against
the working tree, don't "fix" them back to HEAD without asking.
