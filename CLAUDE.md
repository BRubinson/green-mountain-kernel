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
  everything else. `RetiredNameContractTests` had no path exemption for the
  plugin, and reintroducing one was never the fix for a file that tripped it.
  **That test has since been DELETED** with the rest of the contract tier, so
  the retired-name contract is now a convention nothing enforces — the rule
  stands, the scanner does not.
- The plugin directory, the `gmcc:` command/skill namespace, the
  `mcp__plugin_gmcc_*__*` pen server name and the in-repo `.gmcc/` dope
  directory all **keep the `gmcc` half of their names**. (The SERVER KEY moved
  `pen` → `cde` at v30 — see "The pen vocabulary is `cde`" — but the
  `plugin_gmcc_` prefix is fixed by the harness's plugin namespacing and is not
  ours to change.) The repo
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
  make the script read it back out. (`ReleaseStoreContractTests` used to fail
  the build on both; it is deleted, so this is now a convention.)
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
**NOTHING CHECKS THAT THE TWO COPIES AGREE ANY MORE.**
`ReleaseStoreContractTests` used to fail the build on drift and was deleted in
the test rebuild. Fix drift by COPYING, never by editing both — and know that
you will get no warning if you forget.

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
  (`gmk/gmk.xcodeproj`) over SIX shipped packages, plus one that ships
  nothing and holds the repository's ONE test suite, plus one that is
  **vendored third-party source and authored nowhere in this repo**.
  (There were seven shipped packages until v30, when `gmMcp` was deleted and its
  three sources became the `GmMcpServer` target inside `gmDaemonSdk` — see the
  entry below for why that package existed only to own them. Before that, the
  test slot held `gmToolchain`, the contract-test package, deleted in the test
  rebuild; `Gm_Kernel_test` occupies it now.)
  - **Open `gmk/gmk.xcworkspace`, not the project.** The workspace lists the
    project alongside seven packages as first-class members, which is the
    only arrangement in which Xcode generates schemes for a package's TEST
    targets — `GmKernelTests` exists under the workspace and does not exist
    under the project. (It used to name `GmToolchainTests` and `GmMcpTests`;
    both are gone, and `Gm_Kernel_test` is the sole test package now.) The project is deliberately kept
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
    writer. Ships NO test target, and its CI row is `swift build` for that
    reason. Its contract USED to be asserted by `MultiCallBinaryContractTests`,
    which read the source as a file; that test was deleted in the test rebuild,
    so argv[0]-beats-argv[1] and the exit-2 default are now conventions held by
    the code and this note alone. `Gm_Kernel_test` does exercise the binary — it
    boots one — but it does not assert the dispatch rules.
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
    It also owns `Templates/`. **`Templates/original/` IS DELETED (v30)** —
    `OriginalGmccEnums` / `OriginalGmccInstructions` / `OriginalGmccPrompts`, the
    quarantined byte-exact archive of the hand-written plugin markdown, is gone,
    and nothing referenced it. It existed to preserve what the plugin USED to say
    while the native templates were written; now that the plugin is GENERATED
    from those templates, an archive of the pre-generation text is a third
    description of the same thing and a standing invitation to generate from the
    wrong one. Git holds the history.
    Personas are `Instructions` and invocations are `Prompt`, and that split is
    load-bearing: a model obeys instructions over prompts, so caller-supplied
    text must never reach the instruction half.
    **PHASE TEXT LIVES IN `Template+GmCdeWpirWorkflowTemplate.swift`, AND THAT IS
    THE NEWER DESCRIPTION.** This file used to claim phase text was "read live
    from `WorkflowSpec.instructions(variant:phase:)`" — it never was, and the
    claim is what makes the mistake tempting. The twelve
    `GM_CDE_PHASE_*_TEMPLATE` constants are structured (**Calls** / **Gate**) and
    speak the `cde` vocabulary natively; `WorkflowSpec` is the older prose that
    only acquired those names by a mechanical rename. **The direction of travel
    is `WorkflowSpec` → the templates, never the reverse.** A v30 change briefly
    repointed the templates at `WorkflowSpec` on the theory that they were the
    duplicate, which fed the new layer the old text.
    TWO DESCRIPTIONS DO COEXIST, and the platform floor is why: `WorkflowSpec`
    lives in the macOS 14 base and is what `BOT_NEXT` serves at runtime, while
    these constants are macOS 27 and cannot be read by the daemon. They are
    reconcilable only where both are reachable — the generator.
    `AgentConfigurations/` is what ASSEMBLES all of it into native values, and it
    is the layer to read first. `AgentSessionProfile.swift` holds the
    `DynamicInstructions` + `DynamicProfile` pair, built with `Profile { }` and
    its modifier chain rather than a hand-rolled conformance. Assembly order is
    **core → personality → directive(s) → phase text → step set**, toolset
    composed last inside the dynamic body; longest-lived content first, because
    reordering on a phase change throws away the key-value cache silently. One
    wart in that order is recorded in the file: phase text is the most volatile
    block and sits ahead of the fixed step set, kept deliberately.
    Each part is wrapped as `Instructions(...)` because `String` is
    `InstructionsRepresentable` but NOT `DynamicInstructions` — `Instructions`
    itself conforms, and that single wrap is the whole adapter.
    `AgentSessionAsk.swift` is the other half: it wraps a filled ask as a
    `Prompt` and REFUSES to build one whose `{snake_case}` holes are unfilled,
    turning a visible-after-the-fact convention into a precondition.
    **IT IS NO LONGER "DECLARED, NOT WIRED"**, and the earlier claim here that it
    "deliberately sets no `.model()`" is retired: the profile calls `.model()`
    with a `ClaudeLanguageModel` from `AgentGmkDirective+ModelChoice`, so model
    selection lives IN-PACKAGE for this layer rather than being daemon-managed.
    Tool `call(arguments:)` bodies are still all stubs that throw.
    **Two reasoning knobs exist and only ONE is used.** `ClaudeModel.Effort` is
    baked into the model handle via `fixedEffort:`; the framework's own
    `.reasoningLevel()` is deliberately left UNSET. Setting both leaves two
    layers deciding one thing with no precedence between them — if reasoning ever
    moves to the framework side, delete `fixedEffort` in the same change.
    **`GmCdeRpirWorkflowPhase` is a deliberate MIRROR of `WorkflowSpec.Phase`**,
    and the source of truth for this layer. The daemon's enum could not be moved
    here: `gmDaemonSdk` is the zero-dependency base and this package already
    depends on it, so inverting the edge would cycle AND drag `unsafeFlags` plus
    the macOS 27 floor into `gm_hook`, `gm_daemon` and every CI job. The two
    enums are bridged by **exhaustive switches with no `default:`** — with the
    contract-test tier deleted, that is the only mechanism left that still fails
    the build when the daemon grows a phase. A `rawValue` bridge would compile
    forever and return `nil` for a phase the daemon had started serving.
    `Templates/Template+GmAgentTool.swift` is the tool vocabulary, authored once:
    the shared field guides are **stems plus tails** (`promptUuid` had 13 distinct
    descriptions across 13 sites, most contextually correct — collapsing them to
    one constant makes the schemas worse), and every `.anyOf` now DERIVES from its
    `GmDaemonSdk` enum. Two are deliberate non-derivations, marked as such:
    review resolution excludes `open` (not a terminal status), and the
    architecture change kind has no SDK enum — `ChangeKind` is `edit/create/...`
    for FILE changes and is a near-miss trap.
    `@Guide(description:)` and `.anyOf` accept non-literal expressions; verified
    empirically against the macOS 27 SDK, since the macro signature alone does not
    settle it.
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
  - **`gmk/gmMcp/` IS DELETED (v30).** Its three sources — `GmMcpServer.swift`,
    `FastPath.swift`, `PrimaryDoors.swift` — are the `GmMcpServer` target inside
    `gmDaemonSdk` now, beside `GmHookCli`. They belong together: both are
    harness-side CLIENTS of the daemon, both are pure relays with no persistence
    of their own, and both floor at macOS 14. The package existed only to own
    those files and a GRDB checkout it never used.
    **THE `gm_mcp` NAME IS NOT DELETED, and the distinction is load-bearing.**
    It is an ENTRYPOINT in the release-store contract — `GM_ENTRYPOINTS` in
    `gm_releases.sh`, which drives the symlink loop and the manifest's
    `entrypoints` array — plus the installer, the stale check, both CI workflows
    and `project.pbxproj`. `gm_kernel` still dispatches it through `argv[0]`.
    Deleting the PACKAGE was asked for; deleting the NAME was not, and would
    break every install that upgrades.
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
  - `gmk/Gm_Kernel_test/` — the eighth package, and the only one that **ships
    nothing** (`products: []`). The repository's ENTIRE test suite: one shared
    environment per test process, a real `gm_kernel` booted against a temporary
    root, driven over the wire and read back with read-only SQL. Subfoldered per
    package under `Tests/GmKernelTests/` for navigation, not isolation — they
    share the one environment.
    Depends on `gmDaemonSdk` (the public wire surface it is written against) and
    `gmDaemon` (for `Migrations` ONLY — never `Store`, which would be the second
    writer the ownership token forbids).
    **It replaced `gmToolchain`**, the contract-test package, which was deleted
    outright along with ~647 cases across seven targets. `RepoRoot` went with it.
    See "ONE test package — and what was given up to get it" for the full cost,
    including the ten invariants that are now unenforced.
  - `gmk/scripts/` — the build and install path for the binaries (see below),
    plus the app's DMG build and release scripts used by the `release-dmg`
    skill. Scripts live HERE and not beside the app sources: `gmk/gmVibes/` is a
    filesystem-synchronized Xcode group, so anything dropped in it becomes part
    of the app target's source directory.
  - `gmk/VERSION` — the version pin for the three shipped binaries.
- `plugins/gmcc/` — the Claude Code plugin. **ENTIRELY GENERATED SINCE v30 — DO
  NOT HAND-EDIT ANY FILE IN IT.** Every byte comes from the bridge values in
  `gmk/gmAgententicsSdk/Sources/GmAgententicsSdk/HarnessBridge/`, and the next
  regeneration overwrites whatever you changed. To change the plugin, change the
  bridge. See "The plugin is GENERATED" below.
  It ships **no Swift sources** — the package left this directory for `gmk/` and
  did not come back.
- `.gmcc/` — this repo's committed DOPE tree (Domain Optimized Project Essence);
  sessions boot-sync their dope scope from it. **The directory keeps this name.**
  Any rename pass must exclude the `.gmcc/` path segment — a blind sweep would
  break every dope-scope path at once.

Dependency graph, acyclic and 5 deep:

```
gmDaemonSdk ──┬── gmDaemon ─────────────┐      (gmDaemonSdk now also holds the
   │          ├── gmUxComponentLibrary ─┼──┐    GmMcpServer target; gmMcp the
   │          └──────────────────────────┐ │    PACKAGE is deleted)
   │                                     │ ├── gmVibesCore ── gmVibes (the app)
   │                                     │ │                  (a THIN target:
   │                                     └─┘                   @main + Assets)
   ├── gmAgententicsSdk ──┐
   │        │             │  (vendored, zero deps of its own)
   │        │  gmClaudeForFoundationModels ──┘
   │        │
   │        └── gm_bridge_writer  (executable: emits plugins/gmcc)
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
  one implementation per verb, so nothing downstream notices. (The composition
  used to be pinned by `VerbRegistryTests`; `Gm_Kernel_test` re-asserts the
  registry-row half of that check.)
- An explicit `uow:` parameter was rejected deliberately: it is the deferred
  96-handler retype wearing a different hat, because it has to appear in every
  signature the composition can reach.

**The correctness condition is checked, not assumed.** The ambient handle is
thread-local, which is only correct while the verb layer performs no thread hops
inside a boundary — true today at **zero** occurrences of `DispatchQueue`,
`Task {`, `async` or `await` under `Sources/GmDaemon/` or the handlers, and pinned
by `TransactionBoundaryTests` — **which is now deleted**. The invariant is
unchanged and unenforced: if you add a thread hop inside a boundary, nothing
will tell you. Remove the hop; do not relax the boundary.

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
because no expression exists that opens it. `KernelHostContractTests` used to
scan for a second `Store(path:` and is now deleted — the TYPE still enforces
ownership, but nothing scans for a second construction site.

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
# ONE test package. Build the kernel first — the suite BOOTS it.
swift build --package-path gmk/gmKernel
swift test  --package-path gmk/Gm_Kernel_test       # the whole suite

# The shipped packages are BUILD-only now; they carry no test targets.
swift build --package-path gmk/gmDaemonSdk
swift build --package-path gmk/gmDaemon
swift build --package-path gmk/gmUxComponentLibrary
swift build --package-path gmk/gmAgententicsSdk   # also builds gm_bridge_writer
swift build --package-path gmk/gmVibesCore
# gmk/gmMcp is GONE (v30) — GmMcpServer is a target inside gmDaemonSdk, so the
# gmDaemonSdk line above already builds it.
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

### ONE test package — and what was given up to get it

`gmk/Gm_Kernel_test` is the repository's only test package. It boots ONE real
`gm_kernel` against a temporary root and drives the whole kit through its
**public** surface — the wire protocol, a real socket — plus **read-only** SQL.

This replaced seven per-package test targets: **~647 cases, 66 files, ~19,000
lines, deleted in one commit**. That was a deliberate clean break, taken with
the cost stated in advance, and the cost is real enough to write down:

- **Ten repository contract tests are GONE and their invariants are now
  unenforced.** `LiveRuntimeIsolationTests`, `KernelHostContractTests`,
  `RetiredNameContractTests`, `DocsContractTests`, `ReleaseStoreContractTests`,
  `MultiCallBinaryContractTests`, `WorkflowSpecTests`, `HookScriptTests`,
  `VerbRegistryTests`, `TransactionBoundaryTests`. Several are named as guard
  rails elsewhere in this file; those mentions now describe history, not
  enforcement. **Nothing replaced them** — a shell-script tier and a
  compile-time substitute were both considered and declined.
  Consequences a reader must not re-derive incorrectly: the `gm_releases.sh`
  vendored twin is no longer checked for drift (fix it by COPYING, and know that
  nothing will tell you if you forget); `wire_keys.golden` is still gated by
  nothing; and no test now proves a test cannot write the production database.
- `gmk/gmToolchain` is **deleted outright** — it shipped nothing but those
  tests. `RepoRoot` went with it.
- The CI matrix rows are now `build`, with ONE `test` job.

Three rules the new suite runs on, all load-bearing:

- **`Paths.root` is a `static let` — one root per PROCESS, forever.** A
  per-suite or per-test root cannot take effect. "One shared environment" is not
  a simplification; it is the only shape the type permits.
- **DB access is READ-ONLY.** The booted kernel holds the `flock` and owns
  `gm.db` as sole writer. A test-side `Store(path:)` would be the second writer
  the ownership token exists to forbid, reintroduced inside the suite meant to
  defend it. Writes go over the wire.
- **XCTest, not swift-testing.** swift-testing parallelises by default and a
  shared append-only database will not survive that; `XCTestObservation` also
  gives real once-per-process teardown, which is what reaps the spawned kernel.

Isolation is now **by construction** rather than by a guard: the harness mints a
root under `NSTemporaryDirectory()`, string-appends every path (it never calls
`Paths.*` to DISCOVER one), and WRITES `GM_FS_ROOT` into the spawned child.
It deliberately never falls back to `~/gmfs/bin/gm_kernel` — a suite that
silently tested the last RELEASE instead of the working tree would be green for
code that is not there. Keep run ids SHORT: `sun_path` is **104 bytes** on
macOS and the kernel binds a socket under the run root.

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

### Guard rails — MOSTLY REVOKED, deliberately

**Read this before trusting any "X fails the build" claim elsewhere in this
file.** The ten repository contract tests were DELETED in the test rebuild (see
"ONE test package" above). What follows is what is still true.

**STILL ENFORCED:**

- **The dispatcher switch is exhaustive.** A new `MessageType` with no handler
  arm does not COMPILE. Same for `DaemonEventKind` in the app's event router.
  This is stronger than the test it outlived and cannot be deleted by a sweep.
- `Gm_Kernel_test` re-asserts the verb registry (every non-transport
  `MessageType` has a `VerbRegistry` row) and the m0029 schema shape, because
  both guard hazards worth keeping.
- Migrations are append-only and the ledger is asserted DENSE from 1 to head —
  a gap means a migration did not record itself.
- CI still `bash -n`s every shipped script and JSON-parses every plugin
  manifest, and still checks `gmk/VERSION` is semver.
- `Paths.assertContained` still throws on a write outside the filesystem root or
  the working repo. That was always code, never a test.

**NO LONGER ENFORCED — these are now conventions you must hold by hand:**

- The **retired-name contract**. Nothing scans for retired binaries, env vars,
  roots, db filenames or the retired sandbox vocabulary any more.
- ~~**`gm_releases.sh` exists TWICE and nothing checks the copies agree.**~~
  **THIS IS FIXED AT v30, and by construction rather than by a check.** The
  plugin's copy is GENERATED: `gm_bridge_writer` embeds the authored
  `gmk/scripts/gm_releases.sh` as a Swift constant and emits it into
  `plugins/gmcc/scripts/`. There is one authoring site, so drift is not
  something that goes unnoticed — it is something that cannot be expressed.
  Edit `gmk/scripts/gm_releases.sh` and regenerate; never edit the plugin's copy,
  which the next regeneration overwrites.
- The **docs contract** over `plugins/gmcc/` markdown, `hooks.json`,
  `settings.json` and `.mcp.json`. Largely moot since v30: those files are
  GENERATED, so the question is no longer whether they agree with the code but
  whether the bridge that emits them is right. What replaced it is the
  bidirectional roster gate — see "The plugin is GENERATED" below.
- The **release-store contract**, the **multi-call binary contract**, the
  **hook-launcher** checks, the **workflow-spec/pen-roster** cross-check and the
  **transaction-boundary** thread-hop scan.
- **`wire_keys.golden` DOES NOT EXIST ANY MORE.** This file described it as
  "gated by nothing"; in fact the fixture itself went with the deleted test tier,
  so there is no golden to diff and nothing to regenerate. The generator
  `gmk/gmDaemonSdk/scripts/wire_keys.py` still runs and still prints the
  snake_case wire contract — it is a useful thing to eyeball when changing a
  payload — but nothing compares its output to anything.
- Nothing proves a test cannot write the production database. The new harness
  achieves that BY CONSTRUCTION instead — which is stronger in practice and
  unenforced in principle.

- Wire protocol: bump `GmWireProtocol.version` only for a new message type or an
  incompatible change. Additive OPTIONAL fields on existing messages do NOT bump
  — they decode safely in both directions. Renaming a field on an existing
  message IS incompatible and DOES bump. So is REMOVING AN ENUM CASE from a type
  an existing message carries: m0028 collapsed `PromptStatus` from six arms to
  three and bumped 26 → 27 for exactly that reason.
  **Now at v30**, moved by TWO new message types — `MCP_CALL` and `HOOK_EVENT`,
  the harness envelope — landed together so the bump is spent once. They carry
  the identity triple (`client_key`, `cwd`, `project_dir`) as REQUIRED fields,
  because `ClientKey.resolve()` walks process ancestry for a `claude` parent and
  a kernel is not one; the harness-side child survives, thinned, to supply them.
  Both join `TxBatchHandler.denied`, since either would be a nesting alias.
  v28 → v29 was moved by the SIX test-lock message types — `TEST_SUITE_LIST`,
  `TEST_LOCK_STATUS`, `TEST_LOCK_ACQUIRE`, `TEST_LOCK_RELEASE`,
  `TEST_RUN_START`, `TEST_RUN_STATUS` — one bump for all six because they landed
  together. Worth recording what did NOT move it, because the rule only means
  something if the distinction is held: `PingResponse.gmfsRoot` is an additive
  optional and contributed nothing. Had the six not been in that pass, it would
  have shipped at 28. (v27 → v28 was `TX_BATCH`, on the same new-message-type
  ground; the four vitals/role fields rode along and moved nothing.)
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
  child FK clauses that already name the final table.
  m0029 deliberately takes that cost ONCE, with eyes open: `project_test_lock`
  carries an inline `UNIQUE(project_uuid)` because that constraint IS the
  one-lock-per-project rule, and a lock table without uniqueness is not a lock.

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
tarball plus its `.sha256`. The binaries are staged from their package bin
paths — `gm_daemon` from `gmDaemon`, `gm_hook` and (since v30) the pen server
from `gmDaemonSdk`.

**The fallback publishes BINARIES ONLY.** It cannot build the app, because a
release DMG must be signed with a Developer ID and notarized and the runner has
no certificate; an unsigned DMG attached there would be refused by Gatekeeper on
every machine that downloaded it. A release cut in CI is therefore missing its
app, and `install_gm.sh` skips the app step rather than 404-ing on it. Cut the
app from a Mac that holds the identity.

- ~~The binary version is DECOUPLED from the plugin version on purpose.~~
  **REVERSED AT v30: `gmk/VERSION` NOW DRIVES THE PLUGIN TOO.** It is the one
  number behind the binaries, the DMG, `plugins/gmcc/.claude-plugin/plugin.json`
  (via `GmVersion.current` inside the generator) and the `plugins[0].version`
  entry in the repo-root `.claude-plugin/marketplace.json` (written by
  `generate_plugin.sh`). Both manifests read the same source, so they cannot
  drift from each other.
  The old decoupling argument still describes a real cost, and it is now the
  ACCEPTED price rather than the avoided one: a markdown-only plugin change
  forces every install to re-download ~15MB of unchanged binaries. It was
  accepted because the plugin stopped being hand-edited markdown — it is
  generated from Swift that ships in the same release, so "the plugin changed
  but the binaries did not" is a much rarer state than it used to be.
- The app was already coupled and stays so: `gmk/VERSION` moves the DMG too.
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

## The plugin is GENERATED — `plugins/gmcc` has no hand-written files

```bash
bash gmk/scripts/generate_plugin.sh            # regenerate + bump the version
bash gmk/scripts/generate_plugin.sh --check    # report only, change nothing
```

The whole plugin is emitted from the bridge values in `gmAgententicsSdk`. The
writer imports nothing from `gmDaemonSdk`, reads no file out of the existing
plugin, and consults no hand-kept list — so "the plugin says X but the code says
Y" is not a state it can produce. Adding a file to the plugin means declaring a
bridge type; the writer itself does not change.

Consequences a reader must not re-derive incorrectly:

- **EDITING `plugins/gmcc` IS EDITING A BUILD ARTIFACT.** The tree is committed
  (a marketplace install materialises it directly, so it has to be), which makes
  it look hand-maintained. It is not. The next `generate_plugin.sh` silently
  discards the edit.
- **THE GENERATOR IS ITS OWN EXECUTABLE, and cannot be a `gm_kernel` subcommand.**
  `gmAgententicsSdk` is macOS 27 with `unsafeFlags`; the kernel is macOS 14; and
  SwiftPM checks platform floors at GRAPH RESOLUTION, before any `@available`
  scope exists. `gm_kernel bridge emit` would move `gm_hook`, `gm_daemon` and
  every CI job to 27. Reaching for `@available` is the plausible move that
  cannot work. Generation is a developer-machine act, like `rebuild_local.sh`.
- **TWO OWNERS, TWO DIRECTORIES, and confusing them is the trap.**
  `gm_bridge_writer` owns everything inside `plugins/gmcc/` and REFUSES to touch
  anything outside it — which is why it cannot bump the repo-ROOT
  `.claude-plugin/marketplace.json`, a different `.claude-plugin/` directory from
  the plugin's own. `generate_plugin.sh` does that half. A writer that could
  reach both is a writer whose delete step can eat the marketplace manifest.
- **The write is STAGE-AND-SWAP, not rm-then-write.** The tree is built beside
  the target and moved in through a trash directory, so the destructive window is
  two renames wide and a failure rolls back. The writer also refuses a target
  that exists but has no `.claude-plugin/plugin.json`, so it cannot be pointed at
  a source tree.
- **`verify()` runs before anything is deleted.** A declared file that renders
  nothing is reported, and a BOOT-CRITICAL one (the manifests, the three
  scripts) is a refusal. This is not hypothetical: all six `GmBridgeScript`
  bodies were the empty string, and a writer without this guard would have
  emitted `hooks.json` and `.mcp.json` pointing at scripts that do not exist —
  a plugin that installs, boots, and records nothing, silently, because
  `gm_hook`'s own contract is to exit 0 when its binary is missing.
- **Three scripts stopped being files** and are inline shell strings in
  `hooks.json` / `.mcp.json`: `gm_hook.sh`, `run_mcp.sh`, `check_gm_stale.sh`.
  Shell form is the ONLY hook handler type that expands
  `${GM_FS_ROOT:-$HOME/gmfs}` at hook time, and the only one that can hold the
  silent exit-0 no-op contract. `check_gm_stale.sh` could NOT become a
  `gm_hook doctor` subcommand — it works precisely because it needs no binary,
  and a subcommand cannot report that its own binary is absent.
- **`.mcp.json` runs `/bin/sh -c`, not the binary directly.** MCP stdio
  `command`/`args` substitute exactly three placeholders (`CLAUDE_PLUGIN_ROOT`,
  `CLAUDE_PLUGIN_DATA`, `CLAUDE_PROJECT_DIR`) and are spawned with NO SHELL. The
  obvious `"${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_mcp"` yields a pen that never starts
  on any machine where `GM_FS_ROOT` is unset — every first session.
- **Regenerating the working tree changes NOTHING in a running session.** The
  marketplace registers a REMOTE git source and pins `gmcc` to a version-keyed
  cache. Nothing sees a regeneration until it is committed and pushed, and every
  regeneration burns a version — which is what makes the bump the delivery
  mechanism rather than bookkeeping.
- **What the plugin lost, deliberately:** the MAW subsystem (`gm_maw_fetch`,
  `maw_web_fetch.mjs`, its skill and prompt) has no bridge representation, so the
  crunch pipeline has no fetch step. Ten commands and eight skills were
  consolidated into the concept skills. This was accepted as intentional
  re-authoring rather than discovered afterwards.

## The pen vocabulary is `cde`, and the bridge owns it

The MCP server key is **`cde`**, tools are `mcp__plugin_gmcc_cde__<name>`, and
the roster is **exactly the 50 tools `GmAgentTools` declares in the bridge** — no
more, and no fewer.

- **THE BRIDGE IS THE ONLY SOURCE OF TOOL NAMES.** A name the server invents is a
  name the generated plugin will never grant; a name the bridge declares that the
  server does not serve is a grant that resolves to nothing. Both are silent at
  runtime, which is why both are checked.
- **`GmPenTools.rosterProblems()` is BIDIRECTIONAL, and the second direction is
  the one that matters.** "Every served tool has a `VerbSpec`" passes a pen that
  serves nothing; "every declared pen tool is served" is what catches a
  capability the pen advertises and cannot deliver. Seven such gaps went
  unnoticed until the reverse check existed.
- **Tools that REFUSE are published, not omitted.** The bridge's `notSupported`
  and `notImplemented` cases are deliberate answers, and an omitted tool is
  indistinguishable from a capability nobody thought of — an agent that cannot
  see a refusal invents a workaround. They carry `refuses: true`, which is what
  exempts them from the orphan check (they have no verb by construction).
- **SERVED and GRANTABLE are different sets, and conflating them is a real
  cost.** `GmBridgeMcpTool.all` is what the server answers to; `.grantable` is
  that minus the three `*_not_supported` family placeholders, and it is what
  `allowed-tools` frontmatter is built from. A grant spends a slot in every
  skill, command and agent that takes the family — the `gmcc` skill was
  advertising `diagram_not_supported`, and the `.diagram` family contributes
  nothing else at all. Serving them keeps the answer discoverable; granting them
  buys nothing. Today: 50 served, 47 granted, and the difference is exactly
  those three.
- **A skill's reference documents are INDEXED, not orphaned.** `skills/gmcc/`
  ships four `ref/*.md` totalling ~38KB beside a ~2KB `SKILL.md`, and until v30
  nothing named them — a file on disk is not a file in context. The skill body
  now carries an index built from `GmBridgeResource.index(for:)`, so a reference
  added to the bridge is cited automatically and one removed stops being cited.
  **Do not roll their content up into the skill**: the body loads into every
  session that boots gmcc, the refs load only when a reader follows the index.
  That split is the whole point — progressive disclosure, with the index as the
  cheap thing that names the door.
- **`PenSheet.instructions` has a 2048-byte budget and the roster check enforces
  it.** It sits at ~1.8KB. If it crosses, trim PROSE, never names.

## Environment rules

- Sessions are provisioned by `gm_hook context env` at SessionStart; the only env
  vars are `GM_BOOTED`, `GM_PLUGIN_ROOT`, `GM_FS_ROOT` and `PATH`. Everything
  else: `gm_hook paths --json`.
- **ONE root VARIABLE, three possible roots.** `GM_FS_ROOT` names the top-level
  filesystem a process uses — `~/gmfs` for production, `~/beta_gmfs` and
  `~/test_gmfs` (plus its per-run roots) for the others. Each root holds both the
  runtime and the content; containment is still a single prefix test, and
  env-and-db agreement is still one var against one config row.
  **For the APP the variable is not the authority** — the bundle's baked
  `GMFSRoot` key wins, because a LaunchServices-launched app inherits no
  environment. See "THREE ENVIRONMENTS" below.
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

## THREE ENVIRONMENTS — and why this is not the deleted sandbox loop

`prod`, `beta`, `test`. Each is a COMPLETE root: its own database, socket,
pidfile, `flock`, release store and repo clone.

```
$HOME/gmfs         prod   the primary environment. NOT managed by gm_env.sh —
                          `destroy prod` is refused, on purpose.
$HOME/beta_gmfs    beta   long-lived, refreshable, for trying things
$HOME/test_gmfs    test   a CHANNEL. Runs get EPHEMERAL roots beneath it.
```

```bash
bash gmk/scripts/gm_env.sh create  beta     # stage binaries, clone repo, branch, ingest dope
bash gmk/scripts/gm_env.sh refresh beta     # same code path — a refresh IS a create
bash gmk/scripts/gm_env.sh doctor  beta
bash gmk/scripts/gm_env.sh reap    test     # drop run roots whose kernel is gone
bash gmk/scripts/rebuild_local.sh --env beta
```

**PRODUCTION KEEPS `~/gmfs`** and does not become `~/prod_gmfs`. Renaming it
means rewriting the absolute `daemon_config` roots against the documented
rollback anchor and tripping `migrate_to_gmfs.sh`'s own refusal check — a
machine-wide migration of a ~770MB database bought purely so three names look
alike.

### Why this is a DISSOLUTION and the old loop was a DETECTION

This is the crucial paragraph, because the predecessor died for a reason that
applies word-for-word to a careless version of this feature.

The old snapshot runtime was selected by `$GM_FS_ROOT`, and `Paths.root` reads
that **once per process**. A LaunchServices-launched app inherits **no shell
environment at all** — so the app always landed on `~/gmfs` no matter what the
session thought it had selected, and every available mitigation was a way to
DETECT the wrong state rather than prevent it. It was deleted for that.

A T overlay and a red bar **are detection mechanisms**. They were in the ask,
they are implemented, and they are not the safety property.

The safety property is that **the root is a property of the BITS**:

```
Paths.root =
    1. Bundle.main["GMFSRoot"]   ← BAKED IN AT BUILD TIME
    2. $GM_FS_ROOT               ← CLI only; a Mach-O has no such key
    3. ~/gmfs
```

Each bundle carries its own root, production included and set EXPLICITLY. No
launch context — Finder, Dock, `open -n`, Xcode Run, a LaunchServices
crash-relaunch — can change any app's database. There is no wrong-root state
left to detect.

Consequences that must not be re-derived incorrectly:

- **An `<EnvironmentVariables>` block in the scheme is STRICTLY WORSE than what
  was deleted.** It works only for Xcode Run, so the same bits would mean two
  different databases depending on how they were started.
- **`INFOPLIST_KEY_GMFSRoot` DOES NOT WORK.** That build-setting prefix is a
  declared allow-list; Xcode silently drops unknown keys, producing a bundle
  with no key that falls through to `~/gmfs` and writes PRODUCTION while
  believing it is isolated. Verified empirically. Hence the real
  `gmk/gmVibes/Info.plist`, and hence the `plutil` assertion in `build-dmg.sh`
  that makes a missing key FATAL.
- **Chrome is derived from the RESOLVED ROOT, never a `#if`.** A compile-time
  flag is a second source of truth, and the failure it enables is a red bar over
  live production data — the badge lying exactly when it matters.
- **Root comparison is by INODE** (`st_dev`, `st_ino` of `gm.db`), not by path.
  `standardizedFileURL` does not resolve symlinks, so a symlink or an APFS
  firmlink would make one root look like two.
- **`daemon.pid` and `daemon.sock` keep the SAME NAMES in every root.** Distinct
  roots make them safe; distinct NAMES would be a latent two-writer bug, which
  is the same reason this file has always forbidden renaming them.
- **Every environment needs a FULL release store**, not just a database. The app
  autostarts `$ROOT/bin/gm_daemon`, and `gm_hook.sh` exits 0 **silently** when
  its binary is missing — so an unpopulated `bin/` does not fail loudly, it
  records nothing at all.
- **Debug builds are the TEST environment** (`rube.GMVibes.test` → `~/test_gmfs`).
  That dissolves the "second COPY of the app" hazard this file records as having
  survived every ruling: an Xcode debug build beside the installed app is now a
  different application writing a different database.

### The concurrency AC is FREE — do not build a coordinator

`flock` is per-inode on `$ROOT/daemon.pid`. N roots are N locks over N
databases, and every instance is legitimately its own single writer. The
guarantee is not weakened; it is REPLICATED.

### TEST is N ephemeral roots, not one

A single persistent test root re-creates the collision the test lock exists to
prevent: the second agent's kernel loses the `flock` and either fails or
attaches as a CLIENT to the first run's kernel, sharing an append-only database
the first run is counting rows in. So runs get roots at
`$HOME/test_gmfs/runs/<short-id>/`.

**Run ids must be SHORT.** `sun_path` is 104 bytes on macOS and the server binds
`NWEndpoint.unix(path:)` beneath the run root; overrun it and the failure is a
listener that never binds, not an error message.

### A refresh copies the BITS and the REPO — never the database

`gm_env refresh beta` clones the repo into the environment, checks out its own
branch, registers it, and ingests dope. The environment's registered project and
its dope are the ONLY rows in that database to start.

It does **not** copy production's `gm.db`, and that is a correctness decision
rather than a shortcut. That database holds ABSOLUTE paths: `daemon_config`'s
root rows, and every instance's checkout path. A kernel on such a copy reports
one root from config while resolving another from `Paths` — one `PATHS_GET`
answer naming two roots — and `WatcherSupervisor` starts an FSEvent lane over
every instance path it finds, which means a non-production kernel WATCHING YOUR
REAL WORKING CHECKOUT and writing its `.gmcc/` tree, which write-containment
permits because that repo genuinely is a permitted root.

Instance identity is `md5(absolute repo path)`, which is what makes the clone
approach work: a checkout at its own path is legitimately its own instance.

### Schema direction, both ways

`hasPendingMigrations` catches a database BEHIND the binary and takes the
automatic pre-migration `BACKUP`. `hasBeenSuperseded` now catches one AHEAD of
it and **refuses to open**. That second case used to be silent — GRDB applies
unapplied registered migrations and does not object to applied ones it has never
heard of — and with several environments it is reachable on an ordinary day.

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
root **dissolves** the hazard instead: `GM_FS_ROOT` had exactly one legitimate
value, so there was no wrong-root state left to detect, and "the app inherits
nothing" became the correct outcome rather than a misconfiguration.

**THAT LAST SENTENCE IS NOW OUT OF DATE, AND THE WAY IT CHANGED MATTERS.** There
are three environments again — see "THREE ENVIRONMENTS" above. The hazard did
NOT come back, because the second root is no longer selected by an environment
variable the app cannot see: each bundle BAKES its root into its own Info.plist,
so "the app inherits nothing" is still the correct outcome and is no longer a
problem. The lesson survives intact: a second root selected by `$GM_FS_ROOT`
alone would reintroduce the exact deleted hazard. Do not build one.

What this costs, and it is a real cost: the snapshot WAS the rehearsal surface
for db-affecting change. So `gm_hook call BACKUP --json '{}'` stopped being
advisory. It is now taken **automatically** before any migration whose ledger
head is behind the binary's, inside `KernelWriter.start` — the machine takes the
snapshot rather than someone remembering to.

**`sandbox` is a THREE-WAY HOMONYM in this repo**, and a sweep keyed on the word
destroys two live subsystems. `RetiredNameContractTests` keyed on the runtime
vocabulary only (`.gmcc_sandbox`, `SandboxMarker`, `SandboxRetarget`,
`local_sandbox`) — **that test is deleted, so nothing enforces this now**, and
the four literals below are a rule you keep by hand. The protected spellings
were, and remain:

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
