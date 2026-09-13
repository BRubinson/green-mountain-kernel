# green-mountain-kernel

Monorepo for the GM-CDE (Green Mountain Contextual Development
Environment), where the GMCC toolchain is being rebuilt on native
framework/model work. GMB identity and behavioral rules are NOT here — they live
plugin-globally in `plugins/gmcc/skills/gmcc/SKILL.md` so every
gmcc-booted repo gets them, not just this one.

## READ THIS FIRST — cutover is DONE; there is ONE stack

The runtime is `gmk/`, the binary is **ONE multi-call Mach-O, `gm_kernel`**,
which answers as `gm_daemon` / `gm_mcp` / `gm_hook` through `argv[0]` — those are
SYMLINK names in `~/gmfs/bin`, not separate binaries. The one filesystem root is
`~/gmfs`, and `plugins/gmcc/` drives it. The previously
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
  `mcp__plugin_gmcc_pen__*` pen server name and the in-repo `.gmcc/` dope
  directory all **keep their names**. The repo
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
no checkout and asks GitHub for the newest `gm_kernel-v*` release:

```bash
bash plugins/gmcc/scripts/install_gm.sh          # binaries AND the app
bash plugins/gmcc/scripts/install_gm.sh --check  # report only, change nothing
```

### ONE RELEASE, ONE VERSION — the app ships with the binaries

`gm_kernel-v<version>` carries four assets, all pinned by `gmk/VERSION`:

```
gm_kernel-v50.0.2
├── gm-daemon-50.0.2-macos-universal.tar.gz   gm_kernel (ONE Mach-O)
├── gm-daemon-50.0.2-macos-universal.tar.gz.sha256
├── gm_kernel-50.0.2.dmg                      the app — and the writer
└── gm_kernel-50.0.2.dmg.sha256
```

The tarball still ships, for ONE more release. It is the only thing a CI-cut
release can publish — `daemon-release.yml` cannot build a signed and notarized
DMG, because the runner holds no Developer ID — so dropping it would make a
fallback publish produce an empty tag. Retiring it is its own later change, and
`gmk/scripts/release.sh` is the precedent for how (exit 2 with a pointer).

This replaced **two independent tracks** — `daemon-v*` from `gmk/VERSION` and
`gmvibes-v*` from the app's hand-edited `MARKETING_VERSION` — published by two
scripts that shared no code. Nothing recorded which app went with which daemon,
even though they speak a versioned wire protocol, and `install_gm.sh` could only
ever upgrade half a system. Consequences that follow, and must not be re-derived
the other way:

- **`build-dmg.sh` STAMPS `MARKETING_VERSION` from `gmk/VERSION`** as a build
  setting override. Do not hand-edit the version in `project.pbxproj` and do not
  make the script read it back out — `ReleaseStoreContractTests` fails on both.
  The override is used rather than a file edit so a build never dirties the tree
  that publish requires to be clean.
- **`GM_TAG_PREFIX` in `gm_releases.sh` is the only spelling of the namespace.**
  The publisher and the installer both derive from it. A literal `gm_kernel-v` in
  either script is the drift that the old two-track layout institutionalised.
- **`gmk/scripts/release.sh` is RETIRED** and exits 2 with a pointer. It is kept
  as a signpost, not revived: a second publisher means two tags again.
- **Publish refuses an un-notarized DMG** unless `--allow-adhoc` is passed. An
  ad-hoc app is Gatekeeper-blocked on every machine except the one that built it,
  and the retired script would happily ship one.
- The installer still falls back to the retired `daemon-v*` namespace so an older
  release installs rather than reporting that nothing is published. Those
  releases have no DMG, and the app step is skipped with a line saying so.

The DMG is staged under `$GM_FS_ROOT/apps/downloads/<version>/` and installed
from there to `/Applications`. That install is the **one** write outside the
filesystem root on this path: it is confined to `gm_install_app` in the shared
library, `GM_APP_DEST` redirects it, and `--no-app` turns it off. It refuses
while GMVibes is running, because replacing a live bundle corrupts it in ways
that surface later as a crash rather than here as an error.

### The release store

Versions are staged immutably and selected by symlink, so rollback is a swap:

```
~/gmfs/bin/
├── gm_kernel -> releases/active/gm_kernel      the ONE staged Mach-O
├── gm_daemon -> releases/active/gm_kernel      entry points: all three point
├── gm_mcp    -> releases/active/gm_kernel      at the SAME binary, and argv[0]
├── gm_hook   -> releases/active/gm_kernel      selects the personality
├── .gm_version                                 "50.0.1" or "50.0.1-BETA"
└── releases/
    ├── active -> downloads/50.0.1
    ├── downloads/<version>/                    fetched from a release
    └── local/<version>-BETA/                   built from a working tree
```

`gm_releases.sh` splits this into two variables, and the split is the contract:
**`GM_MACHO`** is what gets staged, hashed, lipo-checked and tarred (one file);
**`GM_ENTRYPOINTS`** is what gets symlinked (three names). The names are
load-bearing rather than cosmetic — `hooks.json`, `settings.json`, `.mcp.json`
and `check_gm_stale.sh` each resolve a binary BY NAME, and the kernel dispatches
on `basename(argv[0])`. A staged kernel whose entry symlinks are missing is not a
degraded install; it is a hook that cannot launch.

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
  (`gmk/gmk.xcodeproj`) over seven shipped packages, plus an eighth that ships
  nothing and holds the repository's own contract tests, plus a ninth that is
  **vendored third-party source and authored nowhere in this repo**.
  - **Open `gmk/gmk.xcworkspace`, not the project.** The workspace lists the
    project alongside seven packages as first-class members, which is the
    only arrangement in which Xcode generates schemes for a package's TEST
    targets — `GmToolchainTests` and `GmMcpTests` exist under the workspace and
    do not exist under the project. The project is deliberately kept
    SELF-SUFFICIENT anyway (it still carries its own local package references),
    because `gmk-ci.yml` and `build-dmg.sh` both drive it with `-project`;
    the workspace is an additional door, not a replacement, and neither file
    needed to change.
  - `gmk/gmDaemonSdk/` — the base layer: the wire protocol (including the
    workflow spec the bot phases are driven by), the client, and the shared
    domain layer (`Dope/`, `Diagram/` models, `Hook/`, `Kbite/`, `Environment/`,
    `Paths.swift`, `RepoRelativePath.swift`, `GitHead.swift`, `StoreError`), plus
    **`GmHookCli`**, the shell-client personality as a LIBRARY, and a four-line
    `gm_hook` shim over it. Still zero external dependencies — the library split
    added none, and that property is the whole point of this manifest.
  - `gmk/gmDaemon/` — persistence plus **`GmKernelHost`**: the server, the
    handlers, the watchers, and the ownership primitives
    (`KernelOwnership` / `KernelWriter`). Owns the sole GRDB pin.
    **The app DOES now link this**, reversing what this file said for the whole
    life of the split — see the manifest's own header for why, and why the
    single-writer guarantee got STRONGER rather than weaker in the process.
  - `gmk/gmKernel/` — the multi-call binary: ONE Mach-O linking `GmKernelHost`,
    `GmMcpServer` and `GmHookCli`, dispatching on `basename(argv[0])` and then on
    a subcommand. **argv[0] must win**, because `gm_hook call BACKUP` has `call`
    as `argv[1]` and a subcommand-first rule would try to dispatch it. A bare
    `gm_kernel` prints usage and **exits 2** — of every possible dispatch default
    that is the one that could cost data, so it deliberately does not become a
    writer. Ships NO test target; its contract is asserted by
    `MultiCallBinaryContractTests` in `gmToolchain`, and its CI row is
    `swift build` for that reason.
  - `gmk/gmUxComponentLibrary/` — the shared component surface: the diagram UI
    views plus the geometry, routing, layout and organizer helpers they are built
    on. Diagrams only for now, built as a surface that expects to grow.
  - `gmk/gmAgententicsSdk/` — the agent-tool surface: seven `GmAgentTool`
    families declared against Apple's FoundationModels `Tool` protocol, with
    `@Generable` argument/result schemas and `@Guide`-carried invariants.
    **Declared, not wired** — every `call(arguments:)` throws and names the
    daemon verb it will send. It **depends on `gmDaemonSdk`** so the tool
    vocabulary IS the wire vocabulary and cannot drift from it; that edge was
    added deliberately and it replaced an earlier decision that this package stay
    empty. It is the only package carrying `unsafeFlags` (the `GmAgentOs 1.0`
    availability define), which permanently bars it from being consumed as a
    versioned remote dependency — free today, since every gmk package is a local
    `path:` dependency, and the direct cause of the vendoring below.
    It also owns `Templates/`, which is split in two **SEALED** halves.
    **`Templates/original/` is a quarantined ARCHIVE** — `OriginalGmccEnums` /
    `OriginalGmccInstructions` / `OriginalGmccPrompts`, one artifact in three
    files, every block a byte-exact copy of `plugins/gmcc/` markdown. Re-sync it
    by COPYING, never by editing one side. New work goes in `Templates/` proper.
    **Neither half references the other, in either direction.** That is why
    `OriginalGmccRole` and `GmAgentRole` are near-identical twins rather than one
    shared enum: a shared enum means every later edit to the live vocabulary
    silently rewrites what the archive claims the plugin said, which is the one
    failure the archive exists to prevent. **The duplication is load-bearing —
    do not "unify" them.** They are expected to diverge; if that stops being
    true, the question is whether the archive still needs to exist, not whether
    to reintroduce the coupling. The archive holds the GMCC
    personas and command contracts compiled
    in as FoundationModels `Instructions` and `Prompt` values, copied VERBATIM
    from `plugins/gmcc/` markdown. Personas are `Instructions`, invocations are
    `Prompt`, and the split is load-bearing: a model obeys instructions over
    prompts, so caller-supplied text must never reach the instruction half.
    Phase text is NOT copied — it is read live from
    `WorkflowSpec.instructions(variant:phase:)`.
    `Templates/GmAgentInstruction.swift` is the first thing that ASSEMBLES that
    archive: a `DynamicInstructions` + `DynamicProfile` pair keyed on
    `WorkflowSpec.Phase`, so one session's active persona follows the phase
    instead of a fresh subagent per phase. **A stub** — it builds nothing and
    sends nothing, and it deliberately sets no `.model()`, because models stay
    daemon-managed. Its bodies append longest-lived content first (core contract
    → persona → phase text → methodology → tools); reordering on phase throws
    away the key-value cache silently, which is why the order is documented
    rather than incidental.
    **Its floor is macOS 27, not 26** — see the runner note below.
  - `gmk/gmClaudeForFoundationModels/` — the ninth package: Anthropic's
    **ClaudeForFoundationModels, vendored** (Apache-2.0). It conforms Claude to
    Apple's `LanguageModel` protocol so a `LanguageModelSession` can be driven by
    a server-side Claude model. **Do not edit it** — the only local modification
    is a provenance header on its `Package.swift`; everything else is
    byte-identical to the recorded upstream commit, and `VENDORED.md` carries the
    commit, what was left behind, and the re-sync recipe. Fix a problem upstream
    or in the re-sync, never in place.
    **Vendored rather than pinned by URL, and that asymmetry with GRDB is the
    point**: `unsafeFlags` bars `gmAgententicsSdk` from remote resolution, so every
    `gmk/` package is consumed by local `path:`, and anything joining that graph
    must be reachable the same way. Zero external dependencies of its own, which
    is what keeps it a self-contained copy rather than the head of a tree.
  - `gmk/gmMcp/` — the `gm_mcp` MCP pen server.
  - `gmk/gmVibes/` — the GMVibes macOS app target, and now a **THIN** one: it
    holds `GMVibesApp.swift` (the `@main` entry point), `Assets.xcassets` and a
    README, and nothing else. Release via the `release-dmg` skill.
  - `gmk/gmVibesCore/` — the seventh shipped package, holding the app's ~99
    sources. They
    moved out of the Xcode target so that **sourcekit-lsp can resolve them**: the
    language server reads SwiftPM, `compile_commands.json` or `buildServer.json`
    and is **not** an Xcode client, so a source that lives only in an Xcode
    target gets no build settings and reports `No such module 'GmDaemonSdk'` on
    every import. See the root `Package.swift` note below. Depends on
    `gmDaemonSdk` and `gmUxComponentLibrary` and on nothing else — **not** on
    `gmDaemon`: the app target links `GmKernelHost` for future writer hosting but
    nothing imports it, so that link stays on the APP target.
    Its manifest is **swift-tools-version 6.2** while the rest of the repo is on
    6.0, because `defaultIsolation` does not exist before 6.2. That setting is
    not a preference: `project.pbxproj` compiles the app target with
    `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and `SWIFT_VERSION = 5.0`, these
    sources were written against both, and the package restates them in
    `appTargetSettings`. **The two halves compile the same code — if the app
    target's settings move, these must move with them.**
    The app/package boundary is deliberately narrow. `GMVibesServices` exposes a
    four-property FACADE (`vitalsReport`, `kernelRole`, `protocolVersion`,
    `buildSha`) rather than a public `daemon`, because publishing
    `DaemonConnectionModel` would drag an entire observable model into the public
    surface to serve a handful of reads. Raise nothing to `public` that
    `GMVibesApp.swift` does not name.
  - `gmk/gmToolchain/` — the eighth package, and the only one that **ships
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
gmDaemonSdk ──┬── gmDaemon ─────────────┐
              ├── gmUxComponentLibrary ─┼── gmVibesCore ── gmVibes  (the app)
              ├── gmMcp ────────────────┤                  (a THIN target:
              ├─────────────────────────┘                   @main + Assets)
              ├── gmAgententicsSdk ──┐
              │                      │  (vendored, zero deps of its own)
              │ gmClaudeForFoundationModels ──┘
              │
              └── gmKernel  ← links GmKernelHost + GmMcpServer + GmHookCli
                              (the CLI half: one Mach-O, three personalities)
```

`gmVibes` now takes an edge on `gmDaemon` — the LINK is in place and the app is
where the writer will be hosted. **It does not host it yet**; see "What this pass
did NOT land" below before assuming otherwise.

`gmKernel` cannot cycle: nothing depends on it. It is a leaf that happens to link
three libraries.

The forcing constraint: the wire types already reference the dope and diagram
document types, so those models cannot sit ABOVE the SDK. Any layering that
tries becomes a dependency cycle.

`gmAgententicsSdk` was drawn standing alone until its tool surface was filled
in. It joined the graph because every tool schema speaks the daemon's vocabulary
(`ExplorationFindingKind`, `SearchKind`, `ReviewVerdict`, `PromptStatus`…), and
the alternative was a hand-maintained second copy of a dozen enums whose raw
values are load-bearing on the wire AND in db CHECK constraints. The edge cannot
cycle — nothing depends on that package — and `gmDaemonSdk` does not inherit its
`unsafeFlags`, because SwiftPM target settings apply only to the declaring
target.

It has since taken a **second** edge, to the vendored
`gmClaudeForFoundationModels`. That one also cannot cycle, for a stronger reason:
the vendored package has zero dependencies of its own. Its cost is the platform
floor — it requires macOS 27, a dependency may not have a floor above its
consumer's, and **SwiftPM checks floors at GRAPH RESOLUTION, before any
`@available` scope exists**. So `gmAgententicsSdk` had to move to 27 as well, and
the CI runners with it. Reaching for `@available` to keep the floor at 26 is the
plausible-looking move that cannot work.

## The shared service layer — what "shared memory" actually meant

**Scope note, so the tense below is not misread: the kernel-services and relayed
MCP halves of this are BUILT and tested. The UI half is not — the app still reads
over the socket. See "What this pass did NOT land".**

The kernel collapse was asked for in terms of shared memory. Exploration verified
that `SystemLanguageModel` appears **nowhere** under `gmk/` and the only model
in-tree is the vendored HTTP+SSE Claude client, so no process merge could put a
model weight in our address space. Restated in terms of what a merge actually
buys, the requirement was: **one db connection pool and real transaction
boundaries** shared by the UI, the relayed MCP surface, and the kernel's own
background services.

**The verb layer was already built for this and nobody had noticed.**
`RepositoryContext` is `{ db, core }` plus its accessors, `StoreCore` holds no
queue and exposes no verb *by design*, and every verb body was already written
against an **injected** `Database`. The only hard-wired thing was the boundary —
in 133 places in one directory. So composition needed no new vocabulary:

- `StoreBoundary.swift` makes the boundary **ambient and re-entrant**, and the
  133 sites became `boundary` / `boundaryRead`.
- `inTransaction { }` is the ONE new public API. The ~120 already-`public` verbs
  on the `Store+*` extensions compose inside it unchanged, so there is exactly
  one implementation per verb and `VerbRegistryTests` never notices.
- An explicit `uow:` parameter was rejected deliberately: it is the deferred
  96-handler retype wearing a different hat, because it has to appear in every
  signature the composition can reach.

**The correctness condition is checked, not assumed.** The ambient handle is
thread-local, which is only correct while the verb layer performs no thread hops
inside a boundary — true today at **zero** occurrences of `DispatchQueue`,
`Task {`, `async` or `await` under `Sources/GmDaemon/` or the handlers, and pinned
by `TransactionBoundaryTests`. If that test goes red, remove the hop; do not relax
the boundary.

**Two families cannot compose, and both refuse loudly** (`StoreError.notComposable`):
`checkpointTruncate`, because a WAL checkpoint inside a transaction is illegal in
SQLite; and the four-phase repo verbs, because their phase 3 does filesystem work
holding no db lock, and composing one would pin the single writer across disk I/O.
A refusal in five places beats an enrolment table listing which of ~230 verbs are
composable, which nobody would keep accurate.

`TX_BATCH` extends the same property to the relayed MCP surface: N request lines,
one transaction, results buffered until after the commit, any inner failure
rolling the whole batch back and naming the failing index. It uses a **deny-list
of 5 control verbs** rather than an allow-list of ~230, because an allow-list
silently omits every verb added later — failing in the permissive direction.
Session-scoped `TX_BEGIN`/`TX_COMMIT` is explicitly rejected: it would park the
single writer across unbounded model latency and stall every hook write.

**What the collapse does NOT buy: throughput.** It removes only the MIDDLE of
three stacked serialization points (the socket hop); the server's serial queue and
GRDB's `DatabaseQueue` remain. That expectation is killed here rather than in a
bug report.

## Single-writer is now a TYPE, and one hazard survived

The old guarantee was "only `gm_daemon` constructs a `Store`, and it takes a
`flock` first" — true, but enforced by convention.

`KernelOwnership.Token` is `~Copyable` with a `fileprivate` initialiser that only
a won `flock` can produce, and `KernelWriter.start` — the **sole** `Store(path:)`
site in the tree — consumes one. A losing instance cannot open the database
because no expression exists that opens it. `KernelHostContractTests` scans for a
second `Store(path:` so that stays true.

**`daemon.pid` and `daemon.sock` are deliberately NOT renamed.** This is the most
dangerous cosmetic edit available in this area: a new instance locking
`kernel.pid` while an older one still holds `daemon.pid` takes a **different
lock**, and both would write the same database believing each was alone. The word
"daemon" in a runtime filename costs nothing.

**A headless personality survives, and it is load-bearing.** An app-only writer
was seriously considered and is cleaner — it reduces two-writers to one possible
cause. It fails on autostart: `DaemonClient.autostart()` `posix_spawn`s a binary
from Claude Code hooks, over SSH and in CI, none of which can launch an
application, and spawning a GUI binary directly yields an AppKit process
LaunchServices does not know about — a second writer created on every hook call.
So `gm_kernel daemon` stays, AppKit-free, and `spawnDaemon` names the personality
explicitly rather than relying on which name the path resolved under.

**THE HAZARD THAT SURVIVED EVERY RULING: a second COPY of the app.**
Deleting the sandbox removed the wrong-ROOT case. It did not remove the
two-WRITERS case. LaunchServices gives one instance per bundle PATH, so an Xcode
debug build beside the installed app, a copy in `~/Downloads`, or `open -n` each
produce a second process — and the Xcode case is now the realistic DAILY one. The
ownership token makes it safe (the loser cannot open the db), and the intended
UI answer is a DEGRADED client mode rather than a refusal, because a refusal on
the daily debug path is a guard that gets deleted.

## What this pass did NOT land

Recorded because every reviewer found the same thing: the documentation above
described the finished shape while several pieces of it were absent. A gap that is
written down is a decision; a gap that is not is a lie the next reader inherits.

**The app does not host the writer yet.** `GmKernelHost` is linked into the app
target and nothing imports it. Every read still goes over the socket, exactly as
before. So Q1's shared pool and transaction boundaries are REAL for kernel
services and for relayed MCP tool bodies, and NOT YET real for the UI.

Missing, all of it named in the approved architecture:

- `KernelRole` / `KernelWriterBridge` — ownership arbitration on the app's first
  line of `init()`, the bounded takeover from a headless writer, and the
  client-only degradation when another app copy holds the lock.
- `KernelLifecycle` — the ordered termination path. `SHUTDOWN` still means
  `exit(0)`, and the draft flush still goes THROUGH THE SOCKET, which is the
  ordering inversion the plan called out: it must move in-process and run before
  `closeDatabase()`.
- `KernelServices` — the public façade over `inTransaction`. The mechanism exists
  in `StoreBoundary`; the named entry point does not.
- ⌘Q is still `NSApp.terminate`. `CommandGroup(replacing: .appTermination)` is
  what Q6's "Cmd-Q closes a window, the writer survives" actually requires.
- `Contents/Helpers/` is never populated. `build-dmg.sh` signs helpers inside-out
  and the loop is guarded by `[ -d ]`, so today it is a correct no-op — the DMG
  carries no CLI, and the binaries come from the tarball Q4 kept for one release.
- `TX_BATCH` has no caller. It is a capability the pen can use, not a path
  anything currently takes.
- The `KernelEventBus` fan-in graft from `aggressive` did not land; `eventSink` is
  still a single assign-once closure. It has one consumer today, so it works —
  and it will silently displace the first the moment the app becomes the second.
- `publish_release.sh` still BUILDS the DMG fresh rather than re-signing staged
  bits, so "what you tested is what ships" remains false for the app.

**What this means for the release:** the binaries are the deliverable. The app
ships renamed, menu-bar-resident and reading vitals off the wire, but it is still
a client. Nothing above is load-bearing for the binary path.

## Build / test loop — the `gmk/` stack

From the repo root:

```bash
swift test --package-path gmk/gmDaemonSdk           # per package; all must stay green
swift test --package-path gmk/gmDaemon
swift test --package-path gmk/gmUxComponentLibrary
swift test --package-path gmk/gmMcp
swift test --package-path gmk/gmToolchain
swift test --package-path gmk/gmAgententicsSdk      # roster + template contracts
swift test --package-path gmk/gmVibesCore           # the app's code
swift build --package-path gmk/gmKernel            # BUILD, not test — see below
# gmk/gmClaudeForFoundationModels is VENDORED. It gets NO CI job of its own, and
# that is a decision, not an oversight: it is already COMPILE-GATED in CI as a
# dependency of gmAgententicsSdk, so a vendored break that can affect us fails
# that job. What we deliberately do not run is UPSTREAM'S OWN SUITE — it can
# only fail for reasons we did not cause and cannot fix in-tree (the fix is a
# re-sync, never a patch), and gating our PRs on it would make someone else's
# red build our red build. Run it by hand when re-syncing; see VENDORED.md.
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

### The language server, and why `Package.swift` sits at the repo root

The root `Package.swift` is a **tooling-only shim**: no targets, no products, and
nothing in the repo reads it. It exists because `sourcekit-lsp` selects a build
system by looking for `Package.swift` / `compile_commands.json` /
`buildServer.json` **at the workspace root**, and it does **not** search
downward. The editor integration launches the server rooted at the repo root, so
without a manifest there every request fails `No language service found` — which
is what the whole `gmk/` tree did before this landed.

Three things a reader would otherwise re-derive wrongly:

- **sourcekit-lsp is not an Xcode client.** It reads neither `.xcworkspace` nor
  `.xcodeproj`, and Xcode's `DerivedData/Index.noindex` is private to Xcode. So
  moving code TOWARD the Xcode project **reduces** code intelligence — the exact
  opposite of the natural assumption, and the reason `gmVibesCore` exists. This
  is unrelated to "Open `gmk/gmk.xcworkspace`, not the project" above, which is
  about Xcode generating schemes for package test targets.
- **A server with no language service still publishes CLEAN diagnostics.** The
  failure mode is a false NEGATIVE, not noise, so an absence of errors is not
  evidence of correctness. `swift build` / `swift test` / `xcodebuild` remain the
  verification authority; the language server is for NAVIGATION
  (goToDefinition, findReferences, workspaceSymbol). The smoke check is
  `documentSymbol` on a known file returning its expected top-level symbol — it
  fails loudly where diagnostics stay quiet.
- The server starts **at session start**, so a fresh session is needed before any
  change here is observable.

Cross-file search additionally needs an index store, which plain `swift build`
does not write. Background indexing is the current answer; index-while-building
(`-Xswiftc -index-store-path`) is a deliberate follow-up, not an oversight.

`Package.swift` itself reports `No such module 'PackageDescription'` forever — a
manifest belongs to no target, so it gets the same fallback settings described
above. Harmless; do not chase it.

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
  message IS incompatible and DOES bump. So is REMOVING AN ENUM CASE from a type
  an existing message carries: m0028 collapsed `PromptStatus` from six arms to
  three and bumped 26 → 27 for exactly that reason.
  **Now at v28**, moved by `TX_BATCH` — a NEW MESSAGE TYPE. Worth recording what
  did NOT move it in the same change, because the rule only means something if
  the distinction is held: the four vitals/role fields added to `PingResponse` and
  `StatusResponse` are additive optionals and contributed nothing. Had `TX_BATCH`
  not been in that pass, those four would have shipped at 27.
- **`wire_keys.golden` is NOT gated by any test**, and it was stale for many
  versions before this pass — still carrying the retired root vocabulary this
  repo renamed away from, and missing whole type families. Nothing reads the fixture (`WireKeyTests` does
  not), and `.golden` is not in `RetiredNameContractTests`' extension list, so
  neither guard could see it. Regenerate it with
  `python3 gmk/gmDaemonSdk/scripts/wire_keys.py > <the golden>` whenever a
  `Protocol/` type changes, and diff before accepting: the generator is the
  authority, so a wholesale regeneration accepts all pending drift as intentional.
- Schema: migrations are append-only. The db is append-only history — **NEVER
  wipe it**. `gm_hook call BACKUP --json '{}'` takes the sanctioned online backup
  before risky work.
- **Dropping an inline `UNIQUE` or `CHECK` means rebuilding the table.** SQLite
  backs an inline constraint with a `sqlite_autoindex_*` that `DROP INDEX`
  refuses, so m0028 runs the documented 12-step rebuild over seven tables. Three
  things it must get right, all of which fail SILENTLY: copy `id` explicitly
  (the FTS5 indexes are EXTERNAL CONTENT keyed on `rowid`, so regenerated ids
  leave search pointing at the wrong rows), recreate the AFTER
  INSERT/UPDATE/DELETE triggers that die with the table, and keep
  `legacy_alter_table = ON` across the renames so SQLite does not rewrite the
  child FK clauses that already name the final table. `MigrationTests`'
  m0002 case is the reference for what to assert afterwards: uuid→id PAIRS,
  child FK clauses, indexes, UNIQUEs and `sqlite_sequence`.

### The prompt lifecycle is THREE states

`draft → initiated → done`, plus `done → draft` to re-open a finished prompt for
editing. There are no states between start and finish, and no gates on the
moves: **phase is derived from db evidence at every `BOT_NEXT`**, so where a
prompt is in its workflow is a question for the machine, not for `prompt.status`.

Consequences that are easy to re-derive wrongly:

- **`BRIEFING_OPEN` performs `draft → initiated`**, daemon-side and idempotently.
  Loading a prompt does NOT — a read that advances the prompt makes inspection
  destructive, which an append-only db cannot take back.
- **Summaries are opened explicitly** (`CLARIFY_OPEN`, `ARCH_OPEN`,
  `REVIEW_OPEN`). They used to appear as a side effect of a status move; that
  side effect went with the states.
- **The activation claim moved earlier**, to `initiated`, so briefing and
  exploration now run under it too.
- The per-prompt `UNIQUE` constraints on the five summary tables and
  `care_package` were dropped in the same migration — a re-opened prompt needs a
  second set of summaries, and the constraints made that impossible.

## Releasing

`gmk/VERSION` is the pin for the three binaries **and** the app. Bump it, commit,
then publish locally — that is the default path and it needs no tag command,
because `publish_release.sh` creates and pushes the tag itself:

```bash
bash gmk/scripts/rebuild_local.sh
bash gmk/scripts/publish_release.sh          # --dry-run to rehearse
```

`.github/workflows/daemon-release.yml` is the **fallback**, dispatched manually:

```bash
gh workflow run daemon-release.yml -f version=$(cat gmk/VERSION)
```

It refuses to publish when the tag and the file disagree, runs the suites, builds
universal (arm64 + x86_64), verifies both slices are present, and attaches the
tarball plus its `.sha256`. The three binaries are staged from THREE package bin
paths — `gm_daemon` from `gmDaemon`, `gm_mcp` from `gmMcp`, `gm_hook` from
`gmDaemonSdk` — because they no longer share one.

**The fallback publishes BINARIES ONLY.** It cannot build the app, because a
release DMG must be signed with a Developer ID and notarized and the runner has
no certificate; an unsigned DMG attached there would be refused by Gatekeeper on
every machine that downloaded it. A release cut in CI is therefore missing its
app, and `install_gm.sh` skips the app step rather than 404-ing on it. Cut the
app from a Mac that holds the identity.

- The binary version is DECOUPLED from the plugin version on purpose. The plugin
  is markdown that changes constantly; the Swift is 44k lines that does not.
  Coupling them would make every prompt tweak force every install to re-download
  ~15MB of unchanged binaries. Move `gmk/VERSION` only when the code behind it
  actually changed.
- That decoupling is PLUGIN-vs-BINARIES and is unrelated to the app, which IS
  coupled: `gmk/VERSION` now moves the DMG too, so an app-only change costs a
  binary re-download. That was the accepted price of one release with one
  version — the alternative was keeping two numbers whose relationship nothing
  recorded.
- **CI runs on `xcode-27`, and that is NOT a typo for `macos-27`.** GitHub
  publishes no `macos-27` label at all — the macOS 27 image ships under the
  Xcode-versioned name (`xcode-27` / `xcode-27-xlarge`), arm64 only, GA since
  2026-09-10; `macos-latest` still resolves to macOS 26. "Correcting" it to
  `macos-27` yields an unresolvable label and a job that never starts.
  The floor is 27 rather than 26 because `gmAgententicsSdk` depends on the
  vendored `gmClaudeForFoundationModels`, whose own floor is 27, and floors are
  checked at graph resolution. An older runner does not degrade — the package
  does not resolve at all. This moved with the SDK once already (26 → 27) and
  will again.
- All four jobs share the one label so the repo has ONE runner story. Only the
  `packages` matrix and the `daemon-release` test loop strictly need 27; `gmvibes`
  and `contracts` moved for consistency and can drop back safely if
  `xcode-27` capacity ever makes them queue.
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

## The sandbox dev loop is GONE — and `BACKUP` is what replaced it

There used to be a full snapshot runtime under `$GM_FS_ROOT/development/`, with
its own db, repo clone, binaries and launchers, selected by a marker file at a
repo root that set `GM_FS_ROOT` to the snapshot. **All of it was deleted**, and
the reason is worth keeping because it is not "we stopped using it":

Four independent exploration passes converged on the same silent-data hazard.
`Paths.root` is resolved ONCE per process from `$GM_FS_ROOT`, and a
LaunchServices-launched app **inherits no shell environment at all** — so under
the kernel collapse a snapshot session's hooks would have talked to a socket
nobody was listening on while the kernel wrote **prod**, with no error and no
signal. Every available mitigation was a detection mechanism. Deleting the second
root **dissolves** the hazard instead: `GM_FS_ROOT` now has exactly one
legitimate value, so there is no wrong-root state left to detect, and "the app
inherits nothing" became the correct outcome rather than a misconfiguration.

What this costs, and it is a real cost: the snapshot WAS the rehearsal surface
for db-affecting change. So `gm_hook call BACKUP --json '{}'` stopped being
advisory. It is now taken **automatically** before any migration whose ledger
head is behind the binary's, inside `KernelWriter.start` — the machine takes the
snapshot rather than someone remembering to.

**`sandbox` is a THREE-WAY HOMONYM in this repo**, and a sweep keyed on the word
destroys two live subsystems. `RetiredNameContractTests` keys on the runtime
vocabulary only (`.gmcc_sandbox`, `SandboxMarker`, `SandboxRetarget`,
`local_sandbox`) and explicitly allows:

- **`DopeRepoSandbox`** — write containment for `.gmcc/`, a value type whose
  public surface can only name paths under `{instanceRoot}/.gmcc/`. Deleting it
  removes dope repo writing entirely.
- **`ENABLE_APP_SANDBOX = NO`** — must stay `NO` **forever**. An App-Sandboxed
  kernel cannot open the db, bind the socket, or read the user's repos.
- **`HookScriptTests.Sandbox`** — that file's own temp-directory fixture.

`.gmcc_sandbox` **moved** from the allowed-spellings list to the retired list. It
had to move rather than be added: a spelling in both lists makes
`testAllowedSpellingsAreNotFlagged` and `testNoRetiredSandboxVocabulary` assert
opposite things, and one of them must then fail.

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

`migrate_to_gmfs.sh` is one of TWO files deliberately spared from the sandbox
sweep (the other is the sealed `Templates/original/` archive). A record of a
retirement has to be able to name what it retired, which is the same exemption
that lets it spell the retired runtime names.

## Working-tree note

Uncommitted edits in the working tree are usually intentional — validate against
the working tree, don't "fix" them back to HEAD without asking.
