# Green Mountain Kernel

Green Mountain Coding Collection — a Claude Code plugin marketplace for **contextual
development**. The `gmcc` plugin turns Claude Code into the GM-CDE (Green Mountain
Contextual Development Environment): a workflow system that authors, clarifies, plans and
implements prompts against a persistent per-repo/per-branch knowledge store on the **GMFS**
(the Green Mountain filesystem), backed by reusable knowledge bites (**kbites**).

## Requirements

| | |
|---|---|
| macOS | **26 (Tahoe) or later** — for both the binaries and the GMVibes app |
| Hardware | **Apple Silicon.** Published binaries are arm64 |
| Claude Code | the [CLI](https://claude.ai/code), installed and working |
| Developer tools | **none.** No Xcode, no Swift toolchain, no `jq` |

Everything is downloaded prebuilt and SHA-256 verified. Xcode and Swift are needed only if
you intend to work on the sources — see [Contributing](#contributing).

---

## First-time setup

Four steps, once per machine.

### 1. Add the marketplace

In Claude Code:

```
/plugin marketplace add BRubinson/green-mountain-kernel
```

…or run `/plugins`, choose **Add Marketplace**, and enter `BRubinson/green-mountain-kernel`.

### 2. Install the plugin

```
/plugin install gmcc
```

…or `/plugins` → **Install Plugin** → `gmcc`.

### 3. Install the kernel binaries and the app

The plugin is the harness integration; it does not carry the runtime. Install that with the
plugin's own installer, which needs no checkout of this repository:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh"
```

This asks GitHub for the newest `gm_kernel-v*` release and then:

- downloads the binary tarball **and** the GMVibes DMG, verifying the SHA-256 of each
  **before** anything is unpacked or mounted
- stages both under `~/gmfs/bin/releases/` so a re-install or a rollback needs no network
- symlinks the three entry points — `gm_daemon`, `gm_mcp`, `gm_hook` — at `~/gmfs/bin/`
- installs **GMVibes** to `/Applications`

If you have not installed the plugin yet, or want to run it straight from a clone, the same
script lives at `plugins/gmcc/scripts/install_gm.sh`.

**Useful flags:**

```bash
install_gm.sh --check            # report only, change nothing; exit 1 if work is needed
install_gm.sh --no-app           # binaries only, never touch /Applications
install_gm.sh --app              # the app only, leave the binaries alone
install_gm.sh --force            # reinstall even if that version is already active
install_gm.sh --version 54.0.0   # install one specific version
```

`GM_APP_DEST=~/Applications` redirects the app install if `/Applications` is not writable.

> **Quit GMVibes before installing or updating.** Replacing a running app bundle corrupts it
> in ways that surface later as a crash rather than here as an error, so the installer
> refuses while it is running.

### 4. Initialize the system

```
/gm_init
```

This creates the GMFS root at `~/gmfs/` and adds a permission grant to
`~/.claude/settings.json` so the plugin can read and write under it without prompting on
every file. **The grant takes effect on the next Claude Code restart.**

**No shell profile is ever written.** GMCC does not edit `~/.zshrc`. The environment reaches
a session through the `SessionStart` hook, and any remediation is *printed* for you to run,
never applied behind your back.

### That's it

Open Claude Code inside any git repository. The `SessionStart` hook detects the repo and
branch and auto-provisions the store — there is no per-repo or per-branch command:

```
~/gmfs/projects/{project}/instances/{checkout}/sessions/{branch}/
```

---

## Updating

One command moves the **whole** system forward:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh"
```

The binaries and the app ship in a single release at a single version, so this upgrades both
together. It checks them **separately**, because they can legitimately disagree — an earlier
run used `--no-app`, `/Applications` was not writable that day — and a single "is this
version installed?" question would answer yes while half the system sat a release behind.

Check without changing anything:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh" --check
```

**The plugin itself updates separately**, through Claude Code's own plugin mechanism
(`/plugins` → the `gmcc` entry). The marketplace pins `gmcc` to a version-keyed cache, so a
plugin update and a runtime update are two different acts. Keep them at the same version.

**A locally built runtime is left alone.** If `~/gmfs/bin/.gm_version` ends in `-BETA` the
installer will not silently replace work you are in the middle of testing; pass `--force` to
switch to the published release.

### Rolling back

Versions are staged immutably and selected by symlink, so a rollback is a swap and needs no
network if that version was installed before:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh" --version <older-version>
```

---

## Running a workflow

```
/gm_bot <short-name> <what you want to do>
```

To run an **already-drafted** prompt (one authored in the GMVibes editor, or left unfinished),
pass its numeric id with no description — `/gm_bot 2` — and it resumes from where the record
says it is. Passing a *name* always starts a new draft.

| Command | Execution model | Best for |
|---------|-----------------|----------|
| `/gm_bot` | All phases in one context; delegates only the briefing | Quick, well-scoped changes |
| `/gm_bot_rpi` | Research / Plan / Implement — spawns explore, architecture and review subagents | Medium tasks needing real exploration and review |
| `/gm_bot_team` | Agent teams — several teammates per phase, each on a different methodology | Large or high-stakes work |
| `/gm_task` | Context-loaded but **read-only** with respect to the store | A one-off that wants GMCC context without the prompt pipeline |
| `/ask` | A question against the loaded context | Answers, not changes |

`/gm_task` is read-only *with respect to the GMFS* — it still edits your repository files. It
writes nothing under `~/gmfs/` unless you ask.

Every workflow stops at a **plan gate** and waits for your approval before anything is
changed on disk.

---

## KBites

KBites are persistent knowledge directories holding pre-analyzed reference material
(documentation, API references, example sources) for cheap lookup during development.

| Command | Purpose |
|---------|---------|
| `/gm_crunch_open_maw <name>` | Open a *maw* — a temporary processing directory — and collect resources into it |
| `/gm_crunch_chew <name>` | Analyze and summarize the maw's contents into chewed files |
| `/gm_crunch_digest <name>` | Promote the chewed resources into the persistent kbite |
| `/gm_kbite_relate <a> <b> "<reason>"` | Cross-reference two kbites |
| `/gm_kbite_export [name…]` | Zip selected kbites to a portable archive |
| `/gm_kbite_import <zip>` | Import a kbite archive, asking on each name collision |

There is **no fetch step** — drop files into the maw yourself. The web-fetch command was
retired and has no replacement today.

**KBites are inherited, not trigger-matched.** Each level of the store
(project → instance → session → prompt) carries its own registry, and a prompt inherits what
is declared up its chain. A kbite enters a context only on **explicit request** ("add the
`swift_ui` kbite"); there is no trigger-word auto-activation.

```
~/gmfs/kbites/
├── {name}/KBITE_PURPOSE.md   # what this kbite is for
├── digested/{name}/…         # persisted indexes and chewed analysis
└── open/{name}/…             # in-progress maws
```

---

## Maintenance

| Command | Purpose |
|---------|---------|
| `/gm_init` | One-time machine-level initialization (see setup) |
| `/gm_cleanup` | Audit and repair the stored structure |

If a session looks wrong, the `kernel` skill carries the diagnostics; `/plugins` lists
everything the plugin ships.

---

## How it fits together

- **One binary, three personalities.** `gm_kernel` is a single Mach-O that answers as
  `gm_daemon`, `gm_mcp` or `gm_hook` depending on the name it is invoked under. Those are
  symlinks in `~/gmfs/bin`, not separate programs.
- **One filesystem root**, `~/gmfs`, holding the database, the release store and all content.
- **The plugin is generated.** Everything under `plugins/gmcc/` is emitted from Swift in
  `gmAgententicsSdk`. It is committed because a marketplace install materialises it directly,
  which makes it *look* hand-maintained — it is not. Editing it is editing a build artifact.
- **Write containment is enforced, not documented.** Nothing is written outside `$GM_FS_ROOT`
  or the working repository unless you ask; a path check in the SDK throws otherwise.
- **The database is append-only history.** It is never wiped, and migrations only ever add.

---

## Contributing

Requires Xcode 27. `gmk/` is one Xcode project with one `gm_kernel` target that compiles
every source under `gmk/Sources/`, one unit-test bundle, and one vendored third-party
package; SwiftPM is only Xcode's dependency resolver.

```bash
XCB="xcodebuild -workspace gmk/gmk.xcworkspace -scheme gm_kernel -derivedDataPath gmk/.build/DerivedData CODE_SIGNING_ALLOWED=NO"
$XCB -configuration Debug build                # build the kernel first…
$XCB -configuration Debug test                 # …the suite boots it

bash gmk/scripts/rebuild_local.sh              # build, stage <version>-BETA, activate
GM_KERNEL_BIN=~/gmfs/bin/gm_kernel bash gmk/scripts/generate_plugin.sh --check   # plugin drift check
```

**Open `gmk/gmk.xcworkspace`, not the project** — the workspace is what resolves the
packages, and its `xcshareddata/swiftpm/Package.resolved` is the one lockfile.

`gmk/VERSION` is the one version behind the binaries, the app, `plugin.json` and the
marketplace manifest. A local build is always stamped `-BETA`; there is no flag to suppress
it, because that suffix is the only thing separating bits that were merely built from bits
that were published.

**`CLAUDE.md` is the real contributor document** — the build and release loops, the
single-writer rules, the three environments, and the decisions behind them. Read it before
changing anything under `gmk/`.

---

## Uninstalling

`/plugins` → **Manage Marketplaces** → remove `green-mountain-kernel`.

Your data under `~/gmfs/` is left untouched. Delete it manually for a clean slate — but note
it is append-only history, and nothing else holds a copy.

## License

MIT — see [LICENSE](LICENSE).
