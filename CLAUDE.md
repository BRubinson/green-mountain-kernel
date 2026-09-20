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

`rebuild_local.sh` builds **arm64** so the artifact it stages is already
releasable — `publish_release.sh` uploads exactly those bytes rather than
rebuilding, so what you tested is what ships.

**THERE IS ONE BUILD SYSTEM, AND IT IS `xcodebuild`.** Every script that
compiles anything does it through `gm_xcb` in `gmk/scripts/gm_build.sh`, which
is the ONE place the word `xcodebuild` appears under `gmk/scripts`:

```bash
xcodebuild -workspace gmk/gmk.xcworkspace -scheme gm_kernel -configuration <Debug|Beta|Release> \
    -derivedDataPath gmk/.build/DerivedData CODE_SIGNING_ALLOWED=NO build
```

The product is `gmk/.build/DerivedData/Build/Products/<config>/gm_kernel.app`,
and the CLI is `Contents/MacOS/gm_kernel` inside it. `rebuild_local.sh` has ONE
staging path for the plain and `--app` cases — `gm_stage_from_bundle` in
`gm_releases.sh` — because both produce a bundle; `--app` adds signing through
`build-dmg.sh`. The plain path no longer strips the binary: stripping a linked
Mach-O invalidates its signature, and `codesign --verify --strict` on the staged
copy is the check that stays. `MARKETING_VERSION` is passed from `gmk/VERSION`
on both paths. `gm_build.sh` is repo-side ONLY — nothing in it goes into
`gm_releases.sh` or the plugin twin, because the plugin never builds anything.

**THIS INVERTED. It used to build universal, and `--fast` opted DOWN to arm64
and produced something publish REFUSED.** The x86_64 slice was dropped: it
doubled every compile and link, the toolchain emits "the x86_64 architecture is
deprecated for your deployment target", and the machines this ships to are Apple
Silicon. `--universal` now opts back UP; `--fast` is kept as an inert synonym for
the default so existing callers do not break. Publish still reads slices with
`lipo` rather than trusting the manifest, and still REFUSES an artifact with no
arm64 slice — only the x86_64 requirement is gone. **Published binaries no longer
run on Intel Macs, and nothing checks the host architecture at install time.**

The tarball asset name `gm-daemon-<v>-macos-universal.tar.gz` survives in ONE
place — the installer's legacy branch, which is the only thing that still fetches
one. Frozen rather than tidied: those releases are already published and cannot
be rewritten, so renaming the literal would 404 the entire back-catalogue.

**`rebuild_local.sh` ALSO GENERATES THE PLUGIN**, by calling
`generate_plugin.sh` after staging and before activation, handing it the exact
staged Mach-O as `GM_KERNEL_BIN`. It previously did not, so a build could report
success while `plugins/gmcc/` still reflected an older bridge. There is no
separate generator build: the generator is `gm_kernel bridge`, a personality of
the binary that was just staged.

A local build is **always** stamped `-BETA`. There is no flag to suppress it: the
suffix is the only thing distinguishing bits that were merely built from bits
that were published.

Everyone who is not editing the sources runs the plugin's installer, which needs
no checkout and asks GitHub for the newest `gm_kernel-v*` release:

```bash
bash plugins/gmcc/scripts/install_gm.sh          # binaries AND the app
bash plugins/gmcc/scripts/install_gm.sh --check  # report only, change nothing
```

### ONE RELEASE, ONE VERSION, ONE ARTIFACT

`gm_kernel-v<version>` carries TWO assets, both pinned by `gmk/VERSION`:

```
gm_kernel-v54.0.2
├── gm_kernel-54.0.2.dmg        THE release: the app, with the CLI inside it
└── gm_kernel-54.0.2.dmg.sha256
```

**THE TARBALL IS GONE.** It held the same Mach-O the bundle now carries at
`Contents/MacOS/gm_kernel` (it was `Contents/Helpers` until the one-Mach-O bundle) — one piece of code, staged twice, versioned by two
mechanisms (`.gm_version` for the tarball, `MARKETING_VERSION` for the app). That
is the two-track drift the single-tag release was created to end, reproduced
inside a single tag.

`install_gm.sh` mounts the DMG, installs the app, and EXTRACTS the CLI out of the
bundle into `$GM_FS_ROOT/bin`. So the binary in `bin/` is not merely the same
version as the installed app — it is the same file, taken out of it.

The price, paid knowingly: a CI runner cannot build a signed and notarized DMG,
so there is **no automated publish path at all**. Every release requires a Mac
holding the Developer ID. Both workflows were deleted rather than left to fail
(see "CI is GONE" below).

**Legacy releases still install.** The retired `daemon-v*` namespace carries a
tarball and no DMG, and those releases cannot be rewritten — so the installer
keeps the tarball path FOR THAT NAMESPACE ONLY, keyed on the tag prefix rather
than on version arithmetic. Deleting it would make the entire back-catalogue
uninstallable, which turns a rollback into a dead end.

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
while the app is running (the bundle is `gm_kernel.app`; a lingering legacy
`GMVibes.app` gets the same guard), because replacing a live bundle corrupts it in ways
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

**PUBLISH PROMOTES; IT DOES NOT BUILD.** `publish_release.sh` used to run
`build-dmg.sh` itself — a fresh archive of whatever was in the tree, which is not
the bundle anyone tested. It now requires a staged signed bundle and refuses,
loudly and without a fallback, when there is none:

```bash
bash gmk/scripts/rebuild_local.sh --app --universal   # builds, SIGNS, stages
bash gmk/scripts/publish_release.sh                   # notarizes, packages, uploads
```

There is deliberately no fall-back-to-building. A fallback is exactly how the old
behaviour survived unnoticed: it always worked, so nobody saw it was working on
the wrong bits.

Publish refuses on any of: no staged DMG, no archive beside it, a bundle whose
baked `GMFSRoot` is not `~/gmfs`, a bundle whose signature no longer verifies, an
ad-hoc signature without `--allow-adhoc`, a helper with no arm64 slice, or a
bundle version that disagrees with `gmk/VERSION`. **The baked-root check is the
important one** — publishing a Beta or Debug bundle installs it to
`/Applications` AS production and points it at the wrong database on every
machine that upgrades.

### CI is GONE — both workflows were DELETED

`.github/workflows/` no longer exists. `daemon-release.yml` went because it could
only ever publish the tarball and cannot build a signed, notarized DMG — a
workflow that cannot succeed is worse than an absent one, because it sits in the
Actions tab inviting a dispatch that cuts an empty tag. `gmk-ci.yml` went with it
by decision.

What was lost, so nobody rediscovers it as a surprise: the per-package SwiftPM
build on every push (history — those packages no longer exist), the `xcodebuild`
job for the app, `bash -n` over every shipped script, JSON-parsing of the plugin
manifests, the semver check on `gmk/VERSION`, and the one test job. **Nothing
replaced them.** Verification is now whatever a person runs:

```bash
XCB="xcodebuild -workspace gmk/gmk.xcworkspace -scheme gm_kernel -derivedDataPath gmk/.build/DerivedData CODE_SIGNING_ALLOWED=NO"
$XCB -configuration Debug build
$XCB -configuration Debug test     # no -quiet: the "' passed (" lines are the proof the run was not vacuous
```

## Layout — ONE Xcode target, ONE module, ONE binary

- `gmk/gmk.xcodeproj` — **the whole Swift deliverable is one Xcode target,
  `gm_kernel`**, and it compiles EVERY source under `gmk/Sources/` through one
  `PBXFileSystemSynchronizedRootGroup`. There is no SwiftPM manifest, no library
  product and no per-section module: the eight `Gm*` folders and `gm_kernel/`
  are ONE module, and the folders are navigation only. No `import Gm*` line
  exists anywhere under `gmk/Sources` or `gmk/Tests`. Project-level settings:
  `SWIFT_VERSION = 6.0`, `SWIFT_DEFAULT_ACTOR_ISOLATION = nonisolated`,
  `SWIFT_STRICT_CONCURRENCY = complete`, `MACOSX_DEPLOYMENT_TARGET = 27.0`.
  Only the Vibes/UX layer holds `MainActor`, and it holds it EXPLICITLY on each
  type; nothing else is re-annotated.
  - `Sources/GmDaemonSdk/` — the base: wire protocol (including the workflow
    spec), the client, the shared domain layer (`Dope/`, `Diagram/`, `Hook/`,
    `Kbite/`, `Environment/`, `Paths.swift`, `StoreError`). Imports no package
    product.
  - `Sources/GmHookCli/`, `Sources/GmMcpServer/` — the shell-client and pen
    personalities, both pure relays over the SDK. `Ops.swift`'s usage text is
    `hookUsage`, because `usage` in `main.swift` shares the module now.
  - `Sources/GmDaemon/` — persistence (`Persistence/{Migrations,Entities,Store}`),
    the only folder whose files `import GRDB`. Migrations are one file each plus
    the ordered `ladder` in `Migrations.swift`; a file without a ladder entry
    never runs, and `testTheLedgerIsDenseAndUnique` catches it.
  - `Sources/GmKernelHost/` — the server, handlers, watchers and the ownership
    primitives (`KernelOwnership` / `KernelWriter`). The checkout FSEvent lane is
    `CheckoutFSEventLane` (file and type): the Vibes UI cache is also called
    `CheckoutWatcher`, and one module cannot hold two.
  - `Sources/GmUxComponentLibrary/` — the diagram UI views and their geometry,
    routing, layout and organizer helpers.
  - `Sources/GmAgententicsSdk/` — the agent-tool surface, the templates, the
    agent configurations and **`HarnessBridge/`, which the plugin is generated
    from**. `GmBridgeCli` here is the body of `gm_kernel bridge`. The only
    folder whose files import `ClaudeForFoundationModels`. The `GmAgentOs`
    availability define and every `@available(GmAgentOs 1.0, *)` are GONE: the
    project floor is 27, so there is nothing to gate.
  - `Sources/GmITerm2Client/` — the iTerm2 transport: the committed generated
    protobuf Swift (`Generated/`; `gmk/proto/PROTO.md` carries the regeneration
    recipe), the lifted transport files, one façade. The only folder whose files
    `import SwiftProtobuf`. Blocking socket I/O runs on a
    `DispatchSerialQueue`-backed actor executor, never the cooperative pool.
    GMCC-agnostic by construction.
  - `Sources/gm_kernel/` — **the kernel, and the app.** `main.swift` is the
    dispatcher; `Vibes/` is the GM Vibes app's ~107 sources including
    `GMVibesApp.swift` (no `@main`; the dispatcher calls `GMVibesApp.main()`).
    Views, AppKit subclasses and the app delegate are `MainActor` by protocol
    inference; the `@Observable` models and the handful of plain classes carry
    `@MainActor` explicitly, because the module default is `nonisolated`. The
    `GMCCDaemonService` trampoline, the three actors and `StoreBoundary` are
    unchanged.
  - `VERSION` — the one version pin for the binary, the DMG and the plugin. It
    is a SOURCE of the target: a `PBXBuildRule` matching `*/VERSION` runs
    `scripts/stamp_build_info.sh`, which writes `GmVersion.swift` and
    `BuildInfo.swift` into `$(DERIVED_FILE_DIR)` (only when the content changed,
    so nothing recompiles needlessly), and those two files are compiled like
    any other. A build RULE rather than a run-script phase because rule outputs
    ending in `.swift` are compiled and script-phase outputs are not. It runs
    under `ENABLE_USER_SCRIPT_SANDBOXING = YES` with its inputs (`VERSION`,
    `.git/HEAD`) declared; if the sandbox ever denies `git`, the sha reads
    `unknown` — the remedy is reading `.git/HEAD` in shell, never disabling the
    sandbox on the app target.
  - `Tests/GmKernelTests/` — the ONE test target, an Xcode unit-test BUNDLE
    (subfoldered per section for navigation, not isolation).
    `Tests/.swift-format` is the nested config that allows force-try and IUOs
    there. See "ONE test target" below.
  - `gmClaudeForFoundationModels/` — Anthropic's ClaudeForFoundationModels,
    **vendored** (Apache-2.0) and consumed as an `XCLocalSwiftPackageReference`.
    The only SwiftPM package in the tree, because it is upstream source:
    `VENDORED.md` carries the commit and the re-sync recipe. Do not edit it in
    place.
  - `proto/api.proto` — the iTerm2 protobuf, a member of no target.
  - `scripts/` — build, release, environment and lint scripts, plus
    `wire_keys.py`. `gm_build.sh` is the one place that spells `xcodebuild`;
    `xcode_phase.sh` is the body of both aggregate targets;
    `stamp_build_info.sh` is the build rule. Scripts live here and never beside
    the app sources.
  - `gmVibes/` — the app target's **non-code** payload: `Info.plist` (the three
    baked keys), `Assets.xcassets`, README.
  - `gmk.xcodeproj` / `gmk.xcworkspace` — see "The app bundle" below. Open the
    WORKSPACE: it is what resolves the packages, and its
    `xcshareddata/swiftpm/Package.resolved` is the ONE lockfile.
  - `.build/DerivedData/` — where every SCRIPTED build lands (gitignored). ⌘R
    keeps Xcode's default DerivedData; the two never contend.
- `buildServer.json` (repo root) — committed, static; what lets `sourcekit-lsp`
  navigate the Xcode workspace. See "The language server" below.
- `plugins/gmcc/` — the Claude Code plugin. **ENTIRELY GENERATED — DO NOT
  HAND-EDIT.** Every byte comes from `Sources/GmAgententicsSdk/HarnessBridge/`
  through `gm_kernel bridge`; the next regeneration overwrites whatever you
  changed. See "The plugin is GENERATED" below.
- `.gmcc/` — this repo's committed DOPE tree. The directory keeps this name.

**SwiftPM survives ONLY as Xcode's dependency resolver.** The project holds
three package references and nothing else about packages: `GRDB.swift`
(remote, `upToNextMajor` from 7.0.0, resolved 7.11.1), `swift-protobuf` (remote,
from 1.28.0, resolved 1.38.1) and the vendored `gmClaudeForFoundationModels`
(local). The lockfile is `gmk/gmk.xcworkspace/xcshareddata/swiftpm/Package.resolved`
— never hand-edit it, and never archive with `-project`, which resolves against
the project's own private lockfile and mints a second one.

**Module confinement is now a CONVENTION, kept visible by
`SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY`.** With one module, "GRDB is
confined to `GmDaemon`" cannot be a target boundary; it means only files under
`Sources/GmDaemon/` write `import GRDB`, and member-import visibility is what
stops a file that does not import it from reaching its members. The same holds
for `SwiftProtobuf` under `GmITerm2Client/` and `ClaudeForFoundationModels`
under `GmAgententicsSdk/`. Nothing enforces the file placement.

### The five personalities of `gm_kernel`

argv[0] wins over argv[1] (`gm_hook call BACKUP` has `call` as argv[1]):
`gm_daemon`, `gm_mcp`, `gm_hook` are release-store symlinks at the one Mach-O.
Subcommands: `daemon`, `mcp`, `hook`, `bridge` (`gm_kernel bridge [--check]
<plugin-dir>`, the plugin generator) and `app`. **A no-argument launch runs the
app ONLY when the binary sits inside an `.app` bundle** — that is what
LaunchServices does — and a bare `gm_kernel` in a shell still prints usage and
exits 2, because a stray invocation must never become a writer. The headless
daemon personality never touches `NSApp`, so linking AppKit/SwiftUI into the
binary does not make a hook-spawned daemon an AppKit process.

The generator became a subcommand because the ONLY reason it was a separate
executable was the kernel's macOS 14 floor against the agentics section's 27.
Everything now floors at 27 through the project-level
`MACOSX_DEPLOYMENT_TARGET`, and the availability define that used to bridge the
gap no longer exists.

### The app bundle: the executable IS the kernel

`gm_kernel.app`'s `Contents/MacOS/gm_kernel` is the target's own product: the
`gm_kernel` target compiles every source under `gmk/Sources/` and links it into
the bundle's executable directly. There is no Install phase, no package
self-reference and no second build system — indexing, completion, previews and
debug symbols cover the whole tree because Xcode is the only thing that
compiles it. `rebuild_local.sh` stages that executable out of the bundle, so
the released bytes, the tested bytes and the ⌘R bytes are one build's output.
**`Contents/Helpers/` no longer exists.** The installer and release store read
`Contents/MacOS/gm_kernel` first and fall back to `Contents/Helpers` only for
the published back-catalogue.

**`ENABLE_DEBUG_DYLIB = NO` on Debug, and it is load-bearing.** Xcode's default
Debug product is a ~59KB stub whose entry point is a blank executor that loads
`gm_kernel.debug.dylib` beside it; that stub does not dispatch on `argv`, so a
Debug binary copied out of the bundle — which is what the test harness and
`gm_env.sh seed` do — is not the kernel. With the dylib off, the Debug product is
one Mach-O that answers `--version` inside the bundle and outside it.
`ENABLE_PREVIEWS` stays `YES`; the tree carries zero `#Preview` blocks, so
nothing depends on it either way.

What the target contains, and what it links:

```
gm_kernel  (one target, one module)
├── Sources/GmDaemonSdk, GmHookCli, GmMcpServer, GmDaemon, GmKernelHost,
│   GmUxComponentLibrary, GmAgententicsSdk, GmITerm2Client, gm_kernel/
│   = the CLI, the daemon, the pen, the generator AND the app
├── GRDB                      (remote package product; imported under GmDaemon/ only)
├── SwiftProtobuf             (remote package product; imported under GmITerm2Client/ only)
└── ClaudeForFoundationModels (vendored local package; imported under GmAgententicsSdk/ only)

GmKernelTests  (unit-test bundle) → the GmDaemonSdk + GmDaemon folders, GRDB
```

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
  used to be pinned by `VerbRegistryTests`; `GmKernelTests` re-asserts the
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

## THE APP IS THE KERNEL — the collapse is DONE

This section used to be "What this pass did NOT land", and it was STALE in a way
that cost real time: it listed `KernelRole`, the menu bar and ⌘Q as missing long
after they had shipped, so the next reader budgeted to build things that already
existed. Nothing in here is aspirational. If a claim below is not true of the
working tree, the section is wrong and must be corrected rather than worked
around.

**`gm_kernel.app` holds the database, serves the socket, and opens vibe windows
on demand.** `GMVibesServices.init()` calls `KernelHostRole.arbitrate()` as its
first statement — before any stored property could reach the store — and the
three outcomes are:

- **won the flock** → `KernelServices.bootWriter` opens, migrates and binds; the
  app IS the writer, and `GMCCDaemonService` adopts the in-process verb caller.
- **lost to a HEADLESS holder** (`Holder.bundlePath == nil`) → bounded takeover:
  SIGTERM, poll for the lock, boot. Falls back to client mode on timeout.
  NEVER SIGKILL — the polite signal is what runs the other kernel's ordered
  shutdown, which is the entire reason the takeover is safe.
- **lost to ANOTHER APP COPY** (`bundlePath != nil`) → client mode, no fight.
  An Xcode debug build beside the installed app is the daily case, and each is a
  different bundle id over a different root anyway.

**Reads are IN-PROCESS, and the migration was two lines.** Every one of the ~110
verb methods is declared in `extension GmVerbCaller`; `DaemonClient: GmVerbCaller
{}` is an EMPTY conformance. So the app's entire data layer — ~50 wrappers in
`GMCCDaemonService`, ~99 UI sources behind them — swaps transport by changing
what `perform` is handed. Nothing else moved.

**The trampoline in `GMCCDaemonService` is LOAD-BEARING on both transports.** It
existed because `DaemonClient` is blocking POSIX I/O; it matters at least as much
in-process, because the verb layer is SYNCHRONOUS and running it on MainActor
stalls the UI on every write. Do not "simplify" it away now that there is no
socket.

The thread-hop invariant `TransactionBoundaryTests` used to pin is, for this
caller, held by the TYPE: `inTransaction` takes a NON-`async` closure, so `await`
inside a boundary does not compile. That is NARROWER than the deleted test — it
scanned the verb-layer SOURCES — and must not be described as replacing it.

**Termination is ordered.** `GMVibesAppDelegate.applicationShouldTerminate`
flushes dirty prompt drafts on a bounded deadline and THEN calls
`shutdownKernel()`, on both the flush-completed and the timed-out path. The old
ordering inversion (the flush travelling through the socket) is gone because the
transport is in-process, not because anything was reordered around it.

**⌘Q closes every window; it does not end the kernel.** `KernelTerminationCommands`
replaces `.appTermination`. `WindowPresence` drops the activation policy to
`.accessory` on the last close, so the Dock icon and ⌘-Tab slot disappear exactly
as on a real quit. The kernel is stopped from ONE place: the menu bar's two-step
`confirmingQuit`. Filter windows on `canBecomeMain` — the MenuBarExtra's own panel
is an `NSWindow` and closing it tears down the status item.

**The bundle's executable IS the kernel.** The `gm_kernel` target compiles every
source and links the bundle executable itself; there is no copy step to get
wrong. The target keeps `ENABLE_USER_SCRIPT_SANDBOXING = YES`, which the
`VERSION` build rule runs under with its inputs declared. **That `YES` is this
target's setting, not the project's policy:** the `PluginBridge` and
`TestEnvSeed` aggregate targets set it to `NO` on their own configurations,
because they write outside the build directory. See "THREE ENVIRONMENTS".

**`eventSink` is gone; the store has a SUBSCRIBER TABLE.** It was a plain settable
property, and a second assignment displaced the first with no error anywhere. That
was survivable with one consumer. The app is now the second, so
`Store.subscribeToEvents` / `unsubscribeFromEvents` replace it and there is
deliberately NO compatibility setter — leaving one means the displacing assignment
still compiles.

Fan-out runs inside the commit hook on GRDB's writer thread. A subscriber must
hand off immediately: blocking stalls the single writer for every client, and
calling back into the store deadlocks. The app's hop to MainActor is OUTSIDE the
boundary (the commit has landed), which is why it does not violate the rule above.

### Still genuinely absent

- `TX_BATCH` has no caller. A capability the pen can use, not a path anything takes.
- **The GM pane is OUTBOUND ONLY.** `PromptRunBar` starts a Claude Code session
  in an iTerm2 window and learns nothing further about it: no return channel, no
  feedback, no hooks, no generated MCP config, and no native-model routing. The
  four amended doc comments in `Sources/gm_kernel/Vibes` say "no **RETURN** channel" for
  exactly this reason and **must not be read as promising one** — what stays true
  in all of them is that nothing comes back.
- Nothing app-side is covered by a test. `GmKernelTests` boots a headless binary
  into a temp root; XCTest cannot launch an app bundle, and the baked `GMFSRoot`
  would override `GM_FS_ROOT` anyway. Arbitration, takeover, ordered termination,
  ⌘Q and the event fan-out rest on review and on hand-running in `~/test_gmfs`.
  This was accepted explicitly, not overlooked.
- The headless personality is NOT deleted and must not be. `DaemonClient.autostart()`
  `posix_spawn`s it from hooks, SSH and CI, where LaunchServices cannot launch an
  application — and spawning a GUI binary directly there mints an AppKit process
  LaunchServices does not track, i.e. a second writer on every hook call.

## Build / test loop — the `gmk/` stack

From the repo root, everything goes through `xcodebuild` against the workspace,
the `gm_kernel` scheme and the repo-relative DerivedData:

```bash
XCB="xcodebuild -workspace gmk/gmk.xcworkspace -scheme gm_kernel -derivedDataPath gmk/.build/DerivedData CODE_SIGNING_ALLOWED=NO"
$XCB -configuration Debug   build   # the kernel (and the app code inside it) → gmk/.build/DerivedData/Build/Products/Debug/gm_kernel.app
$XCB -configuration Release build
$XCB -configuration Debug   test    # the whole suite; it BOOTS the kernel it finds in BUILT_PRODUCTS_DIR. No -quiet here.
bash gmk/scripts/rebuild_local.sh   # build → stage <version>-BETA → generate the plugin → activate
```

Scripts never spell that line themselves: they source `gmk/scripts/gm_build.sh`
and call `gm_xcb <action> <config> [args…]`, which is the ONE place
`xcodebuild` appears. `-quiet` is a caller argument, and `test` must not pass
it, or the `' passed (` lines that prove the run was not vacuous vanish with the
noise. ⌘R in Xcode uses Xcode's default DerivedData, not this one; the two
never contend, and the language server reads only the scripted one.

`gmk/gmClaudeForFoundationModels` is VENDORED and compiles as a package
dependency of the target; its own upstream suite is run by hand when re-syncing
(see `VENDORED.md`), never as a gate here.

See **The release loop** above for how `rebuild_local.sh`, `publish_release.sh`
and the plugin's `install_gm.sh` divide the work.

### Lint and format

One gate, two tools, all of it repo-side and none of it in the generated plugin:

```bash
bash gmk/scripts/swift_lint_format.sh          # lint; exit 1 on a swift-format finding or a SwiftLint error
bash gmk/scripts/swift_lint_format.sh --fix    # swift-format in place, then lint; SwiftLint never rewrites
bash gmk/scripts/install_swiftlint.sh          # pinned SwiftLint into $GM_FS_ROOT/tools, symlinked at bin/swiftlint
```

- **swift-format owns layout.** Root `.swift-format`; `gmk/Tests/.swift-format`
  is a full copy that allows force-try and IUOs (nested configs replace, they do not
  merge, and the script passes no `--configuration` so discovery reaches it).
  `.swift-format-ignore` declares vendored, generated and build output.
- **SwiftLint owns semantics and comments.** Root `.swiftlint.yml`. Errors fail the gate,
  warnings do not. The comment rules (`historical_comment`, `long_comment_run`,
  `block_comment`, `comment_line_length`) are errors and enforce the no-history-in-comments
  axiom; they are never baselined. `.swiftlint-baseline.json` exempts pre-existing warnings.
  `excluded` uses single-star paths only: a `**` globstar crashes SwiftLint 0.65.1 here.
  Not installed → the stage warns and is skipped.
- **Where it fires:** `rebuild_local.sh` before every build (and it sets `core.hooksPath`
  to `gmk/scripts/githooks` when unset); the committed pre-commit hook on staged `.swift`
  files; and `.claude/settings.json` registers `gmk/scripts/swift_lint_hook.sh` as a
  PostToolUse hook that lints the one file an agent just edited and returns the findings
  as context. The hook never formats: a rewrite between an agent's read and its next Edit
  breaks the edit. Format at a checkpoint with `--fix`.

### ONE test target — and what was given up to get it

`gmk/Tests/GmKernelTests` is the repository's only test target: an Xcode
**unit-test bundle** (`GmKernelTests.xctest`) with a synced group over its
folder, **no `TEST_HOST`** and **no `@testable import`**. It boots ONE real
`gm_kernel` against a temporary root and drives the whole kit through its
**public** surface — the wire protocol, a real socket — plus **read-only** SQL.

Two things about its shape are deliberate and easy to re-derive wrongly:

- **The in-process subjects are compiled INTO the bundle, not imported.** The
  few tests that touch types directly (`ChewedArtifact`, the migration ladder,
  `CdePaging`) need the `GmDaemonSdk` and `GmDaemon` folders, so those two
  folders are members of BOTH targets through membership exceptions on the
  `Sources` synced group, and the test target carries its own GRDB product
  dependency. The closure is the two FOLDERS, not three files: the migration
  ladder pulls the store, the store pulls the SDK. If Xcode expands the
  exception set to per-file entries, accept what it writes.
- **`TEST_HOST` was ruled out**, because hosting the tests in `gm_kernel.app`
  launches the app, and a launched app arbitrates for the `flock` and boots a
  WRITER — inside the suite whose whole design is that the booted kernel is the
  only one.

Kernel discovery has ONE path and no fallback: `GM_TEST_KERNEL_BIN` if set
(publish sets it to the staged Mach-O), else
`$BUILT_PRODUCTS_DIR/gm_kernel.app/Contents/MacOS/gm_kernel` found relative to
the test bundle. Either way the binary is **COPIED into the minted root** and
the copy is what gets spawned, so no `Info.plist` sits beside it and the
harness's `GM_FS_ROOT` wins over the baked root. It deliberately never falls
back to `~/gmfs/bin/gm_kernel` — a suite that silently tested the last RELEASE
instead of the working tree would be green for code that is not there.
`xcodebuild test -scheme gm_kernel` also runs the `TestEnvSeed` entry
(`buildForTesting = YES`, by ruling): `~/test_gmfs` is the full test
environment, the seed is idempotent and hash-skipped, and the harness's own
ephemeral roots are untouched by it.

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
- The CI matrix became `build` rows with ONE `test` job, and then CI went
  entirely (see "CI is GONE").

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
Keep run ids SHORT: `sun_path` is **104 bytes** on macOS and the kernel binds a
socket under the run root.

The scripts never ran under CI even while CI existed — they write to `~/gmfs`
and, in publish's case, tag and upload — and that stays true of any future
gate. Do not "fix" it by adding a real build.

Every repo-side script resolves the repo the same way: `gm_repo_root` in
`gm_build.sh` walks from the library's OWN location (`gmk/scripts/..`) and dies
unless `gmk/gmk.xcworkspace` is actually there. There is no `git rev-parse
--show-toplevel` anywhere under `gmk/scripts` any more: a bare `rev-parse` can
resolve to an unrelated enclosing repository, and a `$HOME` under version
control is the case that actually bites. The plugin's installer sidesteps the
problem entirely by needing no repo at all.

There is no BuildInfo stamping STEP anywhere. The `VERSION` build rule
(`scripts/stamp_build_info.sh`) does it inside the build graph, so ⌘R and every
scripted build get it free and a clean clone compiles with no prior shell step.
It re-stamps only when `VERSION` or `.git/HEAD` changes, or on a clean build.

### The language server — `buildServer.json` at the repo root

`sourcekit-lsp` selects a build system by looking for `buildServer.json` /
`compile_commands.json` / a SwiftPM manifest **at the workspace root**, in that
order, and it does **not** search downward. The editor integration launches the
server rooted at the repo root, so the repo root carries a committed, static
`buildServer.json` naming `xcode-build-server` (`brew install
xcode-build-server`), the workspace `gmk/gmk.xcworkspace`, the scheme
`gm_kernel` and `build_root: gmk/.build/DerivedData`. The paths are RELATIVE and
resolve against the server's working directory, which is the repo root — that
is what makes the file committable rather than per-machine.

Three things a reader would otherwise re-derive wrongly:

- **A manifest at the same root SHADOWS `buildServer.json`.** The old root
  manifest shim was what made navigation work under SwiftPM, and it is exactly
  what would break it now: with both present, sourcekit-lsp takes the manifest
  and finds a package with no targets. Do not bring the shim back for any
  reason.
- **Navigation follows the SCRIPTED build, not ⌘R.** `xcode-build-server` reads
  compile flags out of the DerivedData it is pointed at, and that is
  `gmk/.build/DerivedData`, which only `gm_xcb` writes. So one scripted build
  (`rebuild_local.sh`, or the Debug `build` line above) is what makes
  goToDefinition answer; ⌘R writes Xcode's default DerivedData and the server
  never sees it. Moving code INTO the Xcode project no longer reduces code
  intelligence, because the server now consumes Xcode's own build settings;
  that inversion is the whole reason the build server exists.
- **A server with no language service still publishes CLEAN diagnostics.** The
  failure mode is a false NEGATIVE, not noise, so an absence of errors is not
  evidence of correctness. `xcodebuild build` / `xcodebuild test` remain the
  verification authority; the language server is for NAVIGATION
  (goToDefinition, findReferences, workspaceSymbol). The smoke check is
  `documentSymbol` on a known file returning its expected top-level symbol — it
  fails loudly where diagnostics stay quiet.

The server starts **at session start**, so a fresh session is needed before any
change here is observable. `xcode-build-server` keeps its parsed-flags cache at
`.compile` beside `buildServer.json`; it is gitignored, and deleting it costs one
re-parse on the next request. If the relative `build_root` ever fails to resolve
under some launcher, the fallback is an absolute path in `argv` only — never a
per-machine `build_root`, which is a file that cannot be committed.

### Guard rails — MOSTLY REVOKED, deliberately

**Read this before trusting any "X fails the build" claim elsewhere in this
file.** The ten repository contract tests were DELETED in the test rebuild (see
"ONE test package" above). What follows is what is still true.

**STILL ENFORCED:**

- **The dispatcher switch is exhaustive.** A new `MessageType` with no handler
  arm does not COMPILE. Same for `DaemonEventKind` in the app's event router.
  This is stronger than the test it outlived and cannot be deleted by a sweep.
- `GmKernelTests` re-asserts the verb registry (every non-transport
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
  ~~**THIS IS FIXED AT v30, and by construction rather than by a check.**~~
  **THAT CLAIM WAS FALSE, and it was believed for two versions.** It said
  `gm_bridge_writer` "embeds the authored `gmk/scripts/gm_releases.sh`" so that
  "drift ... cannot be expressed". The writer embeds NOTHING of the sort: the
  plugin's copy is rendered from `GmBridgeScript.releaseStoreBody`, a Swift
  string constant that is a SECOND HAND-MAINTAINED COPY of the same shell.

  **SO THE FILE STILL EXISTS TWICE, and the second site is easy to miss because
  it does not look like a script.** Caught the only way it could be: a function
  added to `gmk/scripts/gm_releases.sh` regenerated the plugin cleanly and the
  plugin's copy did not have it.

  Editing the release store means editing BOTH:

  1. `gmk/scripts/gm_releases.sh` — what the repo-side scripts source.
  2. `GmBridgeScript.releaseStoreBody` — what the plugin ships.

  Then regenerate, then `diff` the two. Never edit `plugins/gmcc/scripts/gm_releases.sh`
  directly; it is the artifact, and the next regeneration overwrites it. The
  proper fix is to make the writer read the authored file at generation time —
  it runs from the repo, so it could — and that is a real follow-up, not a
  rewording.
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
  `gmk/scripts/wire_keys.py` still runs and still prints the
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

**THERE IS NO FALLBACK AND NO CI.** Both workflows are deleted. Every release
requires a Mac holding a Developer ID Application certificate, because the single
shipped asset is a signed, notarized DMG and a GitHub runner cannot produce one.

The two commands above are the whole path, and the ORDER matters: `--app` is what
builds and signs the bundle, and `publish_release.sh` promotes exactly those
bytes rather than building its own. Publishing without having run `--app` first
is refused with a pointer, not worked around.

- ~~The binary version is DECOUPLED from the plugin version on purpose.~~
  **REVERSED AT v30: `gmk/VERSION` NOW DRIVES THE PLUGIN TOO.** It is the one
  number behind the binaries, the DMG, `plugins/gmcc/.claude-plugin/plugin.json`
  (via `GmVersion.current` inside the generator) and the `plugins[0].version`
  entry in the repo-root `.claude-plugin/marketplace.json` (written by
  `generate_plugin.sh`). Both manifests read the same source, so they cannot
  drift from each other.
  The old decoupling argument still describes a real cost, and it is now the
  ACCEPTED price rather than the avoided one: a markdown-only plugin change
  forces every install to re-download the DMG. It was accepted because the plugin
  stopped being hand-edited markdown — it is generated from Swift that ships in
  the same release, so "the plugin changed but the binaries did not" is a much
  rarer state than it used to be.
- The app was already coupled and stays so: `gmk/VERSION` moves the DMG too.
- **THE macOS 27 FLOOR IS NOT A CI FACT AND SURVIVES CI'S DELETION.**
  `MACOSX_DEPLOYMENT_TARGET = 27.0` is set at PROJECT level, and the vendored
  `gmClaudeForFoundationModels` declares its own floor at 27; Xcode checks a
  package product's floor against its consumer's when it resolves the package
  graph, before a single file compiles. Lowering the deployment target does not
  degrade — the product stops resolving, and the bridge target inside the
  package stops compiling. Reaching for `@available` to lower it is the
  plausible-looking move that cannot work. (The `xcode-27` runner-label note that
  used to sit here went with the workflows: it documented a label nothing selects
  any more. The FLOOR is unrelated to runners and stays.)
## The plugin is GENERATED — `plugins/gmcc` has no hand-written files

```bash
bash gmk/scripts/generate_plugin.sh            # regenerate + bump the version
bash gmk/scripts/generate_plugin.sh --check    # report only, change nothing
```

The whole plugin is emitted from the bridge values in `Sources/GmAgententicsSdk/HarnessBridge` by `gm_kernel bridge <plugin-dir>`. The
writer imports nothing from `gmDaemonSdk`, reads no file out of the existing
plugin, and consults no hand-kept list — so "the plugin says X but the code says
Y" is not a state it can produce. Adding a file to the plugin means declaring a
bridge type; the writer itself does not change.

Consequences a reader must not re-derive incorrectly:

- **EDITING `plugins/gmcc` IS EDITING A BUILD ARTIFACT.** The tree is committed
  (a marketplace install materialises it directly, so it has to be), which makes
  it look hand-maintained. It is not. The next `generate_plugin.sh` silently
  discards the edit.
- **THE GENERATOR IS A PERSONALITY OF THE KERNEL, not a second executable.**
  `gm_kernel bridge [--check] <plugin-dir>` is a command of the shipped binary —
  the same bytes in the DMG, the app and `~/gmfs/bin` — and the plugin directory
  is always an explicit argument. `generate_plugin.sh` runs it on the kernel a
  caller hands in as `GM_KERNEL_BIN`, and **`GM_KERNEL_BIN` is REQUIRED** — it
  exits 2 with a pointer when unset. `rebuild_local.sh` passes the exact staged
  Mach-O; `xcode_phase.sh bridge` passes the product of the enclosing Beta
  build. There is no fallback build: a fallback is a second, quieter way to
  generate from bits nobody staged. What stays impossible is generating inside
  the compile itself: a build phase sandboxed to the build directory cannot
  write `plugins/gmcc`, which is committed source, and that is why the write
  lives in an aggregate target with sandboxing OFF.
- **TWO OWNERS, TWO DIRECTORIES, and confusing them is the trap.**
  `gm_kernel bridge` owns everything inside `plugins/gmcc/` and REFUSES to touch
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
the roster is **exactly the 51 tools `GmAgentTools` declares in the bridge** — no
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
  buys nothing. Today: 51 served, 48 granted, and the difference is exactly
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
- **`CdeSheet.instructions` has a 2048-byte budget and the roster check enforces
  it.** It sits at ~1.8KB. If it crosses, trim PROSE, never names.
- **PAGING LIVES IN THE CDE LAYER, NEVER IN THE DAEMON.** Every cde read is
  cut to the harness's 45,000-byte result cap by `CdePager`
  (`gmDaemonSdk/Protocol/CdePaging.swift`) over the daemon's WHOLE typed
  response, in `GmMcpServer/CdePagedResults.swift`: arrays page by row, long
  text (plan body, overviews, intent, prompt detail, one option body or
  change_code) pages as character windows, and every result carries
  `page {pageBytes, nextCursor, regions[{name, returned, total}]}`. A caller
  loops on `cursor` until `page.nextCursor` is null. The daemon's verbs and
  the wire are untouched by this — GMVibes reads whole records in-process
  through the same verb layer and is not budget-bound — so a page re-reads the
  whole record from the daemon (bounded: ≤ ~400 KB in production). Do not add
  `page_bytes`/`cursor` to a wire request; the divergence between the app and
  the MCP is presentational and belongs here. `CdeResultBudget.render`'s
  withhold envelope is the last resort, no longer a plan, and its `degrade`
  round trip is gone. The `Pen*` identifier family was renamed `Cde*` in the
  same change; "pen" survives only in prose.
- **AN UNKNOWN KEY IN `plugin.json` DISABLES THE ENTIRE PLUGIN.** Claude Code
  validates the manifest strictly and answers an unrecognised field with
  `<field>: Invalid input`, refusing to load *any* of it — commands, agents,
  hooks and the MCP server included. This is not hypothetical: v54.0.0 shipped
  an `outputStyles` key that is not in the schema and took the whole plugin down.
  **Output styles are shipped by EXISTING in `output-styles/`** and applied by
  `force-for-plugin: true` in the style file's own frontmatter; the manifest
  never lists them. The field was deleted from `GmBridgeClaudePlugin.File`
  outright so it cannot be re-added as a convenience.
- **`verify()` checks that a file RENDERED, never that it is VALID.** That is the
  exact gap the above fell through: every file rendered, verify passed, the
  artifact was unloadable. The bridge types are hand-written Swift mirrors of an
  external schema with no cross-check, so **eyeball the emitted
  `plugin.json` after any change to the bridge's manifest types.**

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
the `GmDaemonSdk` section throws unless a URL is under the filesystem root or the working
repo, and every kit-side file write routes through it. A rule that lives only in
markdown erodes; this one fails a call.

**ONE KNOWN EXCEPTION, and it is app-side.** `ITerm.writeProfile` in
`gmk/Sources/gm_kernel/Vibes/Screens/ExternalLaunchers.swift` writes an
iTerm2 Dynamic Profile under `~/Library/Application Support/iTerm2/DynamicProfiles/`
— outside `$GM_FS_ROOT` and outside the repo, with no `assertContained` call. It
arrived with the iTerm2 run bar, it is how iTerm2 is configured at all (that
directory is the only place a dynamic profile can live), and it is recorded here
rather than fixed so the sentence above is not read as an absolute that the code
does not keep. **It is the only one; do not treat it as precedent.**

## THREE ENVIRONMENTS — and why this is not the deleted sandbox loop

`prod`, `beta`, `test`. Each is a COMPLETE root: its own database, socket,
pidfile, `flock`, release store and repo clone.

```
root              env    build config   notes
$HOME/gmfs        prod   Release        the primary environment. NOT managed by
                                        gm_env.sh — `destroy prod` is refused.
$HOME/beta_gmfs   beta   Beta           long-lived, refreshable, for trying things
$HOME/test_gmfs   test   Debug          a CHANNEL. Runs get EPHEMERAL roots beneath it.
```

**EACH ENVIRONMENT HAS ITS OWN BUILD CONFIGURATION, and that is what makes it
real.** The configuration sets three build settings — `GM_FS_ROOT_BAKED`,
`GM_ENV`, `GM_BUNDLE_SUFFIX` — which the Info.plist and the bundle identifier
read. So a Beta bundle is a DIFFERENT APPLICATION to LaunchServices, holding its
own `flock` over its own root. Three roots, three locks, three legitimate single
writers: the concurrency guarantee REPLICATES rather than weakening.

`Beta` is cloned from **Release**, not Debug — it is something you hand to
someone, so it carries release optimisation and release signing. Debug exists as
the test environment only because it is what Xcode Run produces.

**`gm_kernel_beta.xcscheme` is the second shared scheme, and it is how Xcode
Run reaches Beta** — Run, Test, Profile and Analyze all on `Beta`, and it
carries the `PluginBridge` build entry. `gm_kernel.xcscheme` stays on `Debug`
in every action and carries `TestEnvSeed` — ⌘R must keep landing on
`~/test_gmfs`, because "Debug builds are the TEST environment" is the property
that dissolved the "second COPY of the app" two-writer hazard. Reaching Beta is
a scheme SWITCH, never a change to the default one. The protected property is
the Debug configuration, not the scheme file's byte-identity; the scheme also
lists `GmKernelTests` as its testable, which is what gives `xcodebuild test`
something to run.

**`TestEnvSeed` is the second aggregate target, and it is why a plain ⌘R lands
on a PROVISIONED test environment.** It DEPENDS on `gm_kernel` (a
`PBXTargetDependency`), and its whole phase is
`exec /bin/bash "${SRCROOT}/scripts/xcode_phase.sh" seed`. That script gates on
`CONFIGURATION = Debug` (anything else exits 0 with a `note:`), then runs
`gm_env.sh seed test` with `GM_SEED_APP` set to the bundle the enclosing build
just produced. **The seed BUILDS NOTHING.** It stages the kernel out of that
bundle through `gm_stage_from_bundle`, skipped when the staged Mach-O's hash
already matches, then does the rest of `create`'s idempotent subset: a
clone-ONCE of this checkout into `$ROOT/repos` (the dated branch is minted at
clone time only — a fresh branch per ⌘R would mint a session row per build),
`gm_hook context ensure` registration, and any autostarted headless kernel SHUT
DOWN so the incoming app never pays the takeover wait. It deliberately does NOT
run `rebuild_local.sh`: that would regenerate `plugins/gmcc` into the source
tree, the write PluginBridge gates to Beta behind three gates, and the Debug
path must not acquire it. Gates live IN THE SCRIPT, sandboxing is off on its own
configurations because `~/test_gmfs` is outside the build directory, and that
root is the only place it writes.

**`PluginBridge` is a `PBXAggregateTarget` that regenerates `plugins/gmcc`
during a Beta build**, and it is the one target in this project that writes into
the SOURCE TREE. Its phase is `exec /bin/bash "${SRCROOT}/scripts/xcode_phase.sh"
bridge`, which CALLS `gmk/scripts/generate_plugin.sh` with `GM_KERNEL_BIN` set
to the product of the enclosing build, and reimplements nothing — a second copy
of the generation logic is the next `gm_releases.sh`-exists-twice. Three things
about it are load-bearing:

- **It sets `ENABLE_USER_SCRIPT_SANDBOXING = NO`** on all three of its own
  configurations, because a sandboxed phase cannot write outside the build
  directory. The `gm_kernel` target keeps `YES`.
- **It STAGE-AND-SWAPS the whole committed `plugins/gmcc` tree**, so a Beta
  build can rewrite a committed directory — the largest blast radius in the
  project. Hence its gates, all inside the script rather than only in the
  scheme: `CONFIGURATION = Beta`, an empty `git ls-files -u` (any conflicted
  state, not just `MERGE_HEAD`), and a present `.claude-plugin/plugin.json`.
  Each exits 0 with a `note:`; a real generation failure fails the build.
- **Both aggregates DEPEND on `gm_kernel`, and the old "no edge" rule is
  REVERSED.** That rule bought parallelism when the aggregates ran their own
  builds beside Xcode's; now the seed stages and the bridge generates FROM THE
  PRODUCT of the enclosing build, so the product must exist first and the
  dependency edge is what makes them correct. There is no second compile left
  to parallelise, and `BuildIndependentTargetsInParallel = 1` is inert here.
  The gates run by hand too: `CONFIGURATION=Release bash
  gmk/scripts/xcode_phase.sh bridge` prints its `note:` and exits 0.

Three places cross-check the baked root, and they ask different questions:
`build-dmg.sh` (does the bundle match the configuration it was built with?),
`rebuild_local.sh` (does it match the store being staged into?), and
`publish_release.sh` (is it `~/gmfs`, i.e. may it be published at all?). A build
labelled beta that bakes `~/gmfs` is the worst outcome available on this path.

```bash
bash gmk/scripts/gm_env.sh create  beta     # stage binaries, clone repo, branch, ingest dope
bash gmk/scripts/gm_env.sh refresh beta     # same code path — a refresh IS a create
bash gmk/scripts/gm_env.sh doctor  beta
bash gmk/scripts/gm_env.sh reap    test     # drop run roots whose kernel is gone
bash gmk/scripts/rebuild_local.sh --env beta          # binaries only
bash gmk/scripts/rebuild_local.sh --env beta --app    # + the Beta app bundle
```

**`--env` AND AN INHERITED `GM_FS_ROOT` NOW REFUSE TO COEXIST.** `gm_resolve_fs_root`
lets an exported `GM_FS_ROOT` win, which is right for a harness minting a scratch
root and silently wrong the moment someone also typed `--env` — it prints one
environment name and writes another store. That combination cost real time during
the kernel collapse, so it is now an error rather than a precedence rule.

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
- **`GMDevPluginDir` is a THIRD baked key**, beside `GMFSRoot` and
  `GMEnvironment`, fed by the `GM_DEV_PLUGIN_DIR` build setting on the **Beta
  AND Debug** configurations and absent on Release — so test panes load the
  generated in-tree plugin exactly as beta panes do, staleness preflight
  included. It names the in-tree `plugins/gmcc` a
  pane is launched with (`claude --plugin-dir`), and it rides this same
  mechanism for this same reason — **the `INFOPLIST_KEY_*` allow-list trap
  applies to it verbatim**, so it is a real key in `gmk/gmVibes/Info.plist` and
  not `INFOPLIST_KEY_GMDevPluginDir`.
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
