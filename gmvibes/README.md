# GM Vibes

A native macOS app for browsing and managing the **GMCC** (Green Mountain
Compiler Collection) contextual knowledge file system — projects, sessions,
prompts, and knowledge bites (kbites) — with a modern SwiftUI interface.

GM Vibes is the desktop companion to the GMCC plugin. It reads the same
`GMCC_*` environment and ckfs layout that the GM-CDE toolchain produces, so what
you see in the app is the live state of your GMCC workspace.

## Companion plugin

This app is the UI half of the GMCC toolchain and lives in the same
**gmcc-marketplace** monorepo as the plugin (slash commands, GM-CDE protocols,
the ckfs schema): https://github.com/BRubinson/gmcc-marketplace

Install the plugin first so the `GMCC_*` environment is set up; GM Vibes then
surfaces that workspace visually. Without the plugin, the app launches but has
no ckfs to read.

## Requirements

- macOS 26.1 (Tahoe) or later
- Xcode 26.x (to build from source)
- The [gmcc-marketplace](https://github.com/BRubinson/gmcc-marketplace) plugin,
  for a populated workspace

## Install (DMG)

1. Download the latest `GMVibes.dmg` from the
   [Releases](https://github.com/BRubinson/gmcc-marketplace/releases (tags `gmvibes-v*`)) page.
2. Open the DMG and drag **GM Vibes** to **Applications**.

If the build is **ad-hoc / unsigned** (no Apple notarization), macOS Gatekeeper
will block it on first launch. Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine "/Applications/GMVibes.app"
```

…or right-click the app → **Open** → **Open** in the dialog. Notarized builds
install with no extra steps.

## Build from source

GM Vibes lives in the gmcc-marketplace monorepo under `gmvibes/`, building
directly against the daemon package at `plugins/gmcc/daemon` (no vendored
copy):

```sh
git clone https://github.com/BRubinson/gmcc-marketplace.git
cd gmcc-marketplace/gmvibes
open GMVibes.xcodeproj          # build & run in Xcode (scheme: GMVibes)
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
