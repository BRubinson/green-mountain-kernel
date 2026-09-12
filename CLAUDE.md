# green-mountain-kernel

Monorepo for the GM-CDE (Green Mountain Contextual Development
Environment), where the GMCC toolchain is being rebuilt on native
framework/model work. GMB identity and behavioral rules are NOT here — they live
plugin-globally in `plugins/gmcc/skills/gmcc/SKILL.md` so every
gmcc-booted repo gets them, not just this one.

## READ THIS FIRST — this repo currently holds TWO stacks, on purpose

**The old stack, installed from the `gmcc-marketplace` repo, is what runs this
machine.** It is untouched by the reorg and it keeps working.

**The new stack lives in `gmk/` and is NOT live.** It is built and tested in
parallel. Nothing in `gmk/` is installed or registered, no hook calls it, and no
session boots from it.

Consequences a reader must not re-derive incorrectly:

- Everything under `plugins/gmcc/` — `commands/`, `skills/`, `hooks/`,
  `scripts/`, `.mcp.json` — is **FROZEN ON PURPOSE**. Those files still name the
  previously shipped binaries, env vars and roots, and they must keep naming
  them or the running machine breaks. That is **correct, not stale**. The
  retired-name contract in `DocsContractTests` explicitly EXEMPTS
  `plugins/gmcc/**`; the exemption carries a TODO naming cutover as the place it
  is removed.
- The plugin directory, the `gmcc:` command/skill namespace, the
  `mcp__plugin_gmcc_pen__*` pen server name, and the in-repo `.gmcc/` dope
  directory all **keep their names**. The repo deliberately holds both prefixes:
  `gm`-prefixed on the runtime side, `gmcc` on the plugin side.
- `~/gmfs` is **defined in code, not created by the build or by any test**. It is
  populated exactly once, by the explicit migration step below, as the last
  action before the reorg commit.
- **CUTOVER is a separate, later event**, gated on the full migration plus the
  initial MCP refactor. Until then: build and test outside the live ecosystem.

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
  scripts and `.mcp.json`. **Frozen** (see above). The Swift package left this
  directory; nothing else did.
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
bash gmk/scripts/build_gm.sh                        # release build → ~/gmfs/bin/
```

`build_gm.sh` is the DEVELOPER path and stamps `~/gmfs/bin/.gm_version` as
`<version>+src.<sha>`, which marks that bin directory developer-owned so a
download never replaces your build. Everyone else runs
`gmk/scripts/install_gm.sh`, which fetches the prebuilt universal binaries for
`gmk/VERSION` from the matching `daemon-v*` release and verifies their SHA-256.
Don't put compiling back on the install path.

**Neither script is exercised yet.** Running either one writes to `~/gmfs`, which
is out of scope until cutover; CI only `bash -n` syntax-checks them, and that is
a preserved invariant rather than an oversight.

Both scripts resolve the repo with `git rev-parse --show-toplevel` and a
script-directory walk as fallback, because `${CLAUDE_PLUGIN_ROOT}` — the only
anchor the plugin contract offers — now points BESIDE the package tree rather
than above it. Proving that climb against a real marketplace install is a
**cutover gate**; it cannot be exercised without installing.

There is no BuildInfo stamping step anywhere. A SwiftPM **prebuild plugin** in
`gmk/gmDaemon` does it inside the build graph, so Xcode and every CI job get it
free and a clean clone compiles with no prior shell step.

### The frozen live loop, still valid today

`plugins/gmcc/scripts/build_daemon.sh` and `plugins/gmcc/scripts/install_daemon.sh`
still build and install the currently running stack, under its own binary names,
its own runtime root and its own version stamp. Those literals are deliberately
not repeated in this file — the retired-name contract forbids them here, and the
frozen scripts themselves are the accurate source. Do not "modernize" them: the
new names do not exist on `PATH` until cutover, so a sweep through those files
breaks the machine the moment it lands.

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
`.gm_sandbox` marker, which sets `GM_FS_ROOT` to the snapshot; a sandboxed daemon
opens only the staged db and never touches prod. Nothing in a sandbox should be
pointed back at the prod runtime.

With one root variable, a sandbox is no longer a special SHAPE of the
environment — it is a different VALUE of `GM_FS_ROOT`. That is the whole
mechanism now.

## The one-time migration into `~/gmfs`

Run by `gmk/scripts/migrate_to_gmfs.sh`, **once, as the final action of the reorg
before commit** — not by the build, not by a test, not as a side effect of
anything.

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

## Working-tree note

Uncommitted reorg edits in the working tree are usually intentional — validate
against the working tree, don't "fix" them back to HEAD without asking. In
particular, a `plugins/gmcc/` file that still names the previously shipped
binaries is frozen on purpose.
