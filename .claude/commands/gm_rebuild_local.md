---
name: gm_rebuild_local
description: Build the gmk Swift stack from the current checkout, stage it in the release store as <version>-BETA, and activate it. The local half of the release loop; pair with /gm_publish_release when the build is ready to ship. Requires a checkout of green-mountain-kernel — the plugin ships no Swift sources.
argument-hint: "[--fast]"
disable-model-invocation: true
allowed-tools: Bash, Read
---

# /gm_rebuild_local

Build the three binaries from the working tree and make them live.

**This needs a checkout.** `gmk/scripts/rebuild_local.sh` is not part of the
plugin payload (`source: ./plugins/gmcc`), so it exists only where the repo
does. If the user is not in a green-mountain-kernel checkout, say so and stop —
point them at `install_gm.sh` (the plugin's installer) instead, which needs no
sources at all.

## Run it

```bash
bash gmk/scripts/rebuild_local.sh $ARGUMENTS
```

Confirm first with `git rev-parse --show-toplevel` and check that `gmk/` is
there. A bare `git rev-parse` can resolve to an unrelated enclosing repository
— a `$HOME` under version control is the case that actually bites — so verify
`gmk/VERSION` exists rather than trusting the toplevel answer.

## What it does

1. Builds all five packages, release configuration, **arm64 + x86_64** so the
   artifact is releasable as-is. `--fast` builds arm64 only for the
   edit-compile loop, and `/gm_publish_release` will refuse the result.
2. Strips debug symbols, then re-signs ad-hoc — in that order, because the
   strip invalidates the signature and arm64 will not exec an unsigned Mach-O.
3. Stages into `$GM_FS_ROOT/bin/releases/local/<version>-BETA/` with a manifest
   and `SHA256SUMS`, rebuilt from scratch so a binary that stopped being
   produced cannot linger.
4. Activates it: `bin/gm_*` symlinks point at `releases/active`, which points
   at the staged directory. `.gm_version` becomes `<version>-BETA`.
5. Retires the running daemon so the next client call autostarts the new build.
   A running daemon holds its own inode and would otherwise keep serving the
   old binary from a replaced file — an install that silently did nothing.

## The -BETA suffix is not optional

There is no flag to suppress it. It is the only thing distinguishing bits that
were merely built from bits that were published, and it is why `install_gm.sh`
refuses to replace a local build without `--force`.

## After it runs

```bash
gm_hook ping        # autostarts the new daemon; check build_sha
gm_hook status      # schema version, db path, table counts
```

Report the staged path, the architectures, and the active version. If the build
fails, surface the failing package name — each is built separately precisely so
the failure names a module rather than producing one opaque graph error.
