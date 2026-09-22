# green-mountain-kernel

GM-CDE monorepo. GMB rules live in `plugins/gmcc/skills/gmcc/SKILL.md`; the data model lives in `.gmcc/`. This file holds only what the tree cannot tell you: invariants nothing enforces.

## Commands

```bash
XCB="xcodebuild -workspace gmk/gmk.xcworkspace -scheme gm_kernel -derivedDataPath gmk/.build/DerivedData CODE_SIGNING_ALLOWED=NO"
$XCB -configuration Debug build
$XCB -configuration Debug test          # never -quiet: the "' passed (" lines prove the run was not vacuous
bash gmk/scripts/swift_lint_format.sh   # --fix formats in place; the PostToolUse hook only lints
bash gmk/scripts/rebuild_local.sh       # build → stage <version>-BETA → generate plugin → activate
bash gmk/scripts/rebuild_local.sh --app # + signed bundle; required before publish
bash gmk/scripts/publish_release.sh     # promotes the staged bundle; never builds
bash gmk/scripts/generate_plugin.sh     # GM_KERNEL_BIN required; --check reports only
bash gmk/scripts/gm_env.sh create|refresh|doctor|reap beta|test
```

`gm_xcb` in `gmk/scripts/gm_build.sh` is the one place `xcodebuild` is spelled. Scripted builds land in `gmk/.build/DerivedData`, which `buildServer.json` and the language server read; ⌘R uses Xcode's own. There is no CI.

## Do not re-derive these wrongly

### Build and tests
- The test bundle's membership-exception list in `project.pbxproj` names files ONE BY ONE (244 today; folder entries are inert). A new file under `API/Shared/GmKernelCoreShared`, `API/Servers/GmKernelCoreServer`, `Persistence` or `GmKernelCoreClient/GmKernelClient` must be added by hand or the test bundle fails to link.
- A folder move made behind Xcode's back DROPS every exception under the old path, silently. Dump the list first, remap, write back, assert each entry resolves on disk, re-record the count here.
- No `TEST_HOST`: a hosted app boots a second writer inside the suite. No fallback to `~/gmfs/bin`: discovery is `GM_TEST_KERNEL_BIN` or `BUILT_PRODUCTS_DIR`, copied into a temp root.
- `Paths.root` is one `static let` per process. Run ids must be short: `sun_path` is 104 bytes and an overrun is a listener that never binds.
- Tests write only over the wire; a test-side `Store(path:)` is a second writer. XCTest, never swift-testing.
- Keep `ENABLE_DEBUG_DYLIB = NO` on Debug: the default stub does not dispatch on argv, so a binary copied out of the bundle is not the kernel.
- Keep `ENABLE_APP_SANDBOX = NO` forever. `ENABLE_USER_SCRIPT_SANDBOXING` is YES on `gm_kernel`, NO on the two aggregates.
- `MACOSX_DEPLOYMENT_TARGET` is 26 in all three configurations and `build_plugin_binaries.sh` targets `macosx26.0`: one floor spelled twice. The only macOS-27 API left is the `@available`-gated `languageModelProfile()` in `AgentSessionProfile.swift`; a new 27-only call anywhere else raises the floor for the DMG and every hook binary. The Claude-for-FoundationModels package is gone; the bridge's effort enum is its own.
- No root SwiftPM manifest: it shadows `buildServer.json`. Never archive with `-project`; the workspace lockfile is the only one.
- Confinement is convention: `import GRDB` only under `Persistence/` and `GmKernelCoreServer/GmDaemon/`; `SwiftProtobuf` only under `ITerm2Client/`.
- No thread hop inside a store boundary or the handlers; the ambient handle is thread-local. Remove the hop, never relax the boundary.

### Release
- Publish promotes the staged signed bundle and refuses without one. Never add a fallback build.
- `gm_releases.sh` exists TWICE: `gmk/scripts/gm_releases.sh` and `GmBridgeScript.releaseStoreBody`. Nothing checks they agree. Edit both, regenerate, `diff`. Never edit `plugins/gmcc/scripts/gm_releases.sh`.
- `MARKETING_VERSION` is a build-setting override from `gmk/VERSION`; never hand-edit it in `project.pbxproj`. `gmk/VERSION` also drives the plugin and marketplace versions.
- `GM_TAG_PREFIX` in `gm_releases.sh` is the only spelling of the release namespace. `release.sh` is retired.
- The `gm-daemon-<v>-macos-universal.tar.gz` literal and the `daemon-v*` branch in the installer are frozen: they install the back-catalogue.
- Staged binaries are never overwritten in place (stale signature cache → SIGKILL 137). Symlink swap only. Local builds are always `-BETA`.
- Publish refuses an ad-hoc signature without `--allow-adhoc`, a missing arm64 slice, or a baked root other than `~/gmfs`.
- The pre-migration database at the path `migrate_to_gmfs.sh` names is the rollback anchor. Do not delete it; do not run that script again.

### Plugin
- `plugins/gmcc/` is a build artifact. Every byte comes from `Sources/AgenticsClaudeHarnessPluginBridge` via `gm_kernel bridge`; hand edits are discarded.
- `CdeToolRoster.generated.swift` is reflected from the `@Generable` tools under `AgenticsCore/Tools/`; property names ARE the wire argument names (snake_case). An edited declaration without regeneration compiles and serves the old shape.
- An unknown key in `plugin.json` disables the ENTIRE plugin. Output styles ship by existing in `output-styles/` with `force-for-plugin: true`; the manifest never lists them. `verify()` checks that files rendered, not that they are valid: eyeball the manifest after any bridge change.
- Regeneration changes nothing in a running session; only a committed, pushed, version-bumped tree does.
- `hooks/bin/*` and `bin/{gm_mcp,gm_hook}` are committed arm64 Mach-Os compiled by `build_plugin_binaries.sh` with the client closure only (no GRDB, no server). Hooks exit 0 silently when a binary is missing; the pen exits 1 loudly.
- Repo-root `.claude-plugin/marketplace.json` is written by `generate_plugin.sh`; the bridge writes nothing outside `plugins/gmcc/` except the roster file.
- `gmcc`-prefixed names (plugin dir, `gmcc:` namespace, `mcp__plugin_gmcc_cde__`, `.gmcc/`) stay; the runtime side is `gm_`. Do not tidy one into the other.

### Kernel and roots
- Never rename `daemon.pid` or `daemon.sock`: a differently named lock is a different lock, and two writers share one db.
- Never delete the headless `gm_kernel daemon` personality. Hooks, SSH and CI `posix_spawn` it; a GUI binary spawned there is an untracked second writer.
- Takeover of a headless holder is SIGTERM and poll, never SIGKILL. A second app COPY gets client mode, no fight.
- The root is a property of the bits: `Bundle.main["GMFSRoot"]`, then `$GM_FS_ROOT` (CLI only), then `~/gmfs`. A LaunchServices app inherits no environment.
- `INFOPLIST_KEY_GMFSRoot` DOES NOT WORK (Xcode drops it; the bundle falls through to production). The key lives in `Sources/UX/Apps/Vibes/Info.plist`; `build-dmg.sh` asserts it with `plutil`.
- Never add an `<EnvironmentVariables>` block to a scheme, and never build a second root selected only by `$GM_FS_ROOT`. `--env` and an inherited `GM_FS_ROOT` refuse to coexist.
- Three roots: `~/gmfs` prod/Release (not managed by `gm_env.sh`), `~/beta_gmfs` beta/Beta, `~/test_gmfs` test/Debug with ephemeral runs under `runs/<short-id>/`. Debug builds ARE the test environment; reach Beta via the `gm_kernel_beta` scheme, never by changing the default.
- Every root needs a full release store: an empty `bin/` records nothing, silently.
- A refresh clones bits and repo, never the database: `gm.db` holds absolute paths, and a copy makes a non-production kernel watch your real checkout.
- Root comparison is by inode, not path. Chrome derives from the resolved root, never a `#if`.
- `PluginBridge` (Beta only) and `TestEnvSeed` (Debug only) DEPEND on `gm_kernel` and act on its product; gates live in `xcode_phase.sh`. Debug must never regenerate the plugin.
- `Paths.assertContained` throws outside `$GM_FS_ROOT` or the working repo. The one exception is `ITerm.writeProfile`; it is not precedent.
- "sandbox" is a homonym: `DopeRepoSandbox`, `ENABLE_APP_SANDBOX = NO` and `HookScriptTests.Sandbox` are live; `.gmcc_sandbox` is retired.
- `GmPersonality` resolves from `argv[0]` then `gm_`+`argv[1]`; `gm_daemon` is the only release-store symlink and `DaemonClient.autostart()` spawns it BY NAME. A bare `gm_kernel` in a shell prints usage; only inside a bundle does a no-arg launch open the app.
- The `GMCCDaemonService` trampoline is load-bearing in-process (the verb layer is synchronous). Event subscribers run inside the commit hook: hand off immediately, never call back into the store.
- ⌘Q closes windows; only the menu bar's two-step quit stops the kernel. Nothing app-side is tested; arbitration, takeover and termination rest on hand-running in `~/test_gmfs`.

### Persistence and wire
- Migrations are append-only, one file each plus the `ladder`; the db is never wiped. `gm_hook call BACKUP --json '{}'` before risky work (automatic before a pending migration). A db AHEAD of the binary refuses to open.
- Dropping an inline UNIQUE/CHECK means the 12-step table rebuild: copy `id` explicitly (FTS5 keys on rowid), recreate the AFTER triggers, keep `legacy_alter_table = ON` across renames. All three fail silently.
- Bump `GmWireProtocol.version` (now 30) only for a new message type, a renamed field or a removed enum case. Additive optional fields never bump. `wire_keys.py` output is gated by nothing.
- `TX_BATCH` uses a deny-list of control verbs; `checkpointTruncate` and the four-phase repo verbs refuse to compose. No session-scoped begin/commit. The in-process boundary buys no throughput.

### CDE surface
- Server key `cde`, 14 served / 11 grantable; the three `*_not_supported` tools are served so a refusal is discoverable, never granted. `rosterProblems()` is bidirectional at generation and at startup.
- Five tools carry `anthropic/alwaysLoad`; no server-wide pin. `CdeSheet.instructions` has a 2048-byte budget: trim prose, never names.
- Paging (45,000-byte cap) lives in `CdePager` in the MCP layer; never add `page_bytes`/`cursor` to a wire request.
- `cde_prompt op=file_changes` is search-only; capture belongs to the PostToolUse hook alone.
- Phase instructions live in the twelve `cde_rpir_<phase>` skills; do not re-inline them into commands. Skill `ref/*.md` are indexed, never rolled up.
- Prompt lifecycle is three states; `BRIEFING_OPEN` performs draft→initiated, loading never does; summaries open explicitly.

### Lint
- swift-format owns layout; SwiftLint owns semantics and the comment rules (errors, never baselined). `excluded` uses single-star paths: `**` crashes SwiftLint 0.65.1. The PostToolUse hook never formats.

## Working-tree note

Uncommitted edits are usually intentional. Validate against the working tree; don't "fix" them back to HEAD without asking.
