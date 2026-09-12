# GM Vibes

A native macOS app for browsing and managing the **GMCC** (Green Mountain
Compiler Collection) contextual knowledge file system — projects, sessions,
prompts, and knowledge bites (kbites) — with a modern SwiftUI interface.

GM Vibes is the desktop companion to the GMCC plugin. It reads the same
`GM_*` environment and `~/gmfs` layout that the GM-CDE toolchain produces, so
what you see in the app is the live state of your GMCC workspace.

## Companion plugin

This app is the UI half of the GMCC toolchain and lives in the same
**green-mountain-kernel** monorepo as the plugin (slash commands, GM-CDE protocols,
the gmfs schema): https://github.com/BRubinson/green-mountain-kernel

Install the plugin first so the `GM_*` environment is set up; GM Vibes then
surfaces that workspace visually. Without the plugin, the app launches but has
no gmfs to read.

## Requirements

- macOS 26.1 (Tahoe) or later
- Xcode 26.x (to build from source)
- The [green-mountain-kernel](https://github.com/BRubinson/green-mountain-kernel) plugin,
  for a populated workspace

## Install

The app ships **inside the unified release** alongside the daemon binaries, at
one version pinned by `gmk/VERSION`. The plugin's installer fetches and installs
both, and is the recommended path — it verifies the SHA-256 sidecar before
mounting anything:

```sh
bash plugins/gmcc/scripts/install_gm.sh          # binaries + app
bash plugins/gmcc/scripts/install_gm.sh --app    # just the app
```

Quit GM Vibes first if it is running: the installer refuses to replace a live
app bundle.

### By hand

1. Download `GMVibes-<version>.dmg` from the
   [Releases](https://github.com/BRubinson/green-mountain-kernel/releases) page
   (tags `gm_kernel-v*`; the retired `gmvibes-v*` tags are app-only and frozen).
2. Open the DMG and drag **GM Vibes** to **Applications**.

If the build is **ad-hoc / unsigned** (no Apple notarization), macOS Gatekeeper
will block it on first launch. Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine "/Applications/GMVibes.app"
```

…or right-click the app → **Open** → **Open** in the dialog. Notarized builds
install with no extra steps.

## Build from source

GM Vibes lives in the green-mountain-kernel monorepo under `gmk/gmVibes/`. It
is one target in the single `gmk.xcodeproj`, building directly against the
sibling packages `gmDaemonSdk` and `gmUxComponentLibrary` by local path (no
vendored copy). It does NOT link `gmDaemon`, so GRDB is not in its link
closure:

```sh
git clone https://github.com/BRubinson/green-mountain-kernel.git
cd green-mountain-kernel/gmk
open gmk.xcworkspace            # build & run in Xcode (scheme: GMVibes)
```

## Build a DMG

```sh
scripts/build-dmg.sh            # → build/GMVibes.dmg
```

The script auto-detects signing:

- **Developer ID Application cert installed** → signs with the hardened runtime.
  Run `NOTARIZE=1 scripts/build-dmg.sh` to notarize + staple (requires a
  `notarytool` keychain profile — see the header of the script).
- **No Developer ID** → ad-hoc signs and packages a DMG that works locally;
  recipients clear quarantine as shown above.

## License

TBD.
