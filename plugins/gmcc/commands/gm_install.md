---
description: Install or upgrade the gm_kernel app and binaries to the version this plugin was generated for. Reads the plugin's own version, checks what is active, and fetches the matching GitHub release DMG only when they differ.
argument-hint: "[--check | --force | --app | --no-app | --latest]"
disable-model-invocation: true
allowed-tools: Bash, Read, Glob, AskUserQuestion
---

Bring the installed kernel and app to the version THIS plugin was generated for.

**Steps:**
    1. Read the plugin's version from `$CLAUDE_PLUGIN_ROOT/.claude-plugin/plugin.json`. That number is the release tag (`gm_kernel-v<version>`) the plugin expects.
    2. Run `bash "$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh" --check` and report its lines verbatim: binaries active, app installed, wanted.
    3. If everything is current, or the active kernel is a `-BETA` local build, stop and say so.
    4. Otherwise run `bash "$CLAUDE_PLUGIN_ROOT/scripts/install_gm.sh"` with the flags the Endotherm passed (`--force`, `--app`, `--no-app`, `--latest`). It downloads the DMG, verifies the SHA-256 sidecar, stages it under `$GM_FS_ROOT`, activates the binaries and installs the app.
    5. Re-run `--check` and quote the result. The app must be quit first; the installer refuses to replace a running bundle and says so.

**Contract:**
    1. The installer resolves the plugin's own version. `--latest` is the only way to fetch a newer release, and it is passed only when asked.
    2. A `-BETA` kernel is somebody's local build. Never replace it without `--force`.
    3. Quote the installer's output. A summary of an install is not the install.
