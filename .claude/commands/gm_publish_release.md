---
name: gm_publish_release
description: Publish the locally staged BETA build as a gm_kernel-v* GitHub release — verify, run the suites, tag, upload, and promote the machine onto the release. Owner-only and repo-side; requires a checkout and push access. Pair with /gm_rebuild_local, which produces the artifact this ships.
argument-hint: "[--dry-run]"
disable-model-invocation: true
allowed-tools: Bash, Read, AskUserQuestion
---

# /gm_publish_release

Ship the artifact that `/gm_rebuild_local` staged and that this machine has
been running.

## This is restricted, in three independent ways

1. **Not in the plugin payload.** `gmk/scripts/publish_release.sh` lives in
   `gmk/scripts/`, and the plugin package is `source: ./plugins/gmcc`. Anyone
   who installed the plugin has no publish script at all.
2. **Needs push access.** The script refuses unless the authenticated `gh` user
   holds push on the release repo. GitHub is the real enforcement — a token
   without push cannot create a tag or a release regardless — and the check
   exists to turn a mid-upload 403 into one clear line before anything is
   tagged.
3. **Needs a clean tree at the staged commit.** A release must be reproducible
   from a commit, so a dirty tree is refused, and the staged build's recorded
   `source_sha` must equal `HEAD`.

If any of those fail, report the reason and stop. Do not attempt to work around
them, and do not offer to.

## Run it

Always offer `--dry-run` first when the user has not published before — it runs
every check, including the full suite, and stops before the tag:

```bash
bash gmk/scripts/publish_release.sh --dry-run
```

Then, once they confirm:

```bash
bash gmk/scripts/publish_release.sh
```

## What it checks, in order

1. `gh` authenticated, and push on the repo.
2. Working tree clean; `gm_kernel-v<version>` unused both locally and on the remote.
3. The staged `<version>-BETA` exists, matches its own `SHA256SUMS`, carries
   **both** arm64 and x86_64 slices (read with `lipo`, not from the manifest —
   a `--fast` build is caught exactly here), is signed, and was built from
   `HEAD`.
4. Every suite green: the five test packages plus a compile of
   `gmAgententicsSdk`. Never ship what was not tested.

## What it then does

Packages a flat tarball byte-identical in shape to what `daemon-release.yml`
produces, pushes the tag **before** creating the release — `gh release create`
against a tag the remote lacks would create one from the default branch and
silently ship main instead of what was verified — uploads the asset plus its
`.sha256`, then promotes this machine from `<version>-BETA` onto the published
version without a download, since the bytes are identical.

## Bumping the version

`gmk/VERSION` is the pin, and the tag is derived from it. To cut a new version:
edit `gmk/VERSION`, commit, re-run `/gm_rebuild_local` (so the staged build's
`source_sha` matches the new HEAD), then publish. Moving the file without
rebuilding is caught by check 3, not discovered after the tag exists.

Report the release URL and the newly active version.
