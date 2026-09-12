---
name: release-dmg
description: Build the GMVibes macOS app (gmvibes/ in this monorepo) into a DMG — notarized if a Developer ID cert exists, otherwise ad-hoc — and publish it as a GitHub release asset on the gmcc-marketplace repo. Use when the user wants to cut a GMVibes release, ship a new DMG, upload a build to GitHub, or distribute the app.
---

# release-dmg

Builds the app into a distributable `.dmg` and uploads it to a GitHub release on
the `origin` repo (the **gmcc-marketplace** monorepo). Release tags are
namespaced `gmvibes-v<version>` so app releases never collide with
marketplace/plugin tags. Signing is automatic: **notarized** when a *Developer ID
Application* certificate is installed, otherwise **ad-hoc**.

The heavy lifting lives in two scripts — prefer running them over reimplementing:

- `gmvibes/scripts/build-dmg.sh` — archives the `GMVibes` scheme, signs, packages the DMG.
- `gmvibes/scripts/release.sh` — calls `build-dmg.sh`, then creates/updates the GitHub release.

## Steps

1. **Preflight.** Confirm prerequisites and report any gaps before building:
   ```sh
   gh auth status                                  # must be logged in
   git remote get-url origin                       # must point at gmcc-marketplace on GitHub
   security find-identity -v -p codesigning | grep "Developer ID Application" || true
   ```
   - If `gh` is not authenticated, stop and tell the user to run
     `! gh auth login -h github.com -s repo -w`.
   - Tell the user which signing path will be taken: **notarized** (Developer ID
     present) or **ad-hoc** (none). Don't silently ship ad-hoc if they asked for
     notarized — surface it.

2. **Pick the version/tag.** Default is `gmvibes-v<MARKETING_VERSION>` (read from
   `gmvibes/GMVibes.xcodeproj/project.pbxproj`). If the user named a version, pass it.
   If a release for that tag already exists, the asset is replaced (`--clobber`);
   warn the user rather than bumping silently.

3. **Build + publish.** Run the release script (this archives, signs/notarizes,
   builds the DMG, and uploads it):
   ```sh
   gmvibes/scripts/release.sh                 # auto: gmvibes-v<MARKETING_VERSION>
   gmvibes/scripts/release.sh 1.2.0           # explicit version
   NOTARIZE=0 gmvibes/scripts/release.sh      # skip notarization even with a Dev ID
   ```
   The build takes a minute or two — allow a generous timeout.

4. **Report.** Print the release URL (`gh release view <tag> --json url -q .url`)
   and state plainly which signing path was used.

## Notarization setup (one-time, only if using Developer ID)

Notarization needs a `notarytool` keychain profile named `gmcc-ui` (historical
name, kept so existing stored credentials keep working):
```sh
xcrun notarytool store-credentials gmcc-ui \
    --apple-id "you@example.com" --team-id "TEAMID" --password "app-specific-pw"
```
A Developer ID Application certificate requires enrollment in the Apple Developer
Program. Without it, builds are ad-hoc and recipients clear quarantine once:
`xattr -dr com.apple.quarantine /Applications/GMVibes.app`.

## Notes

- Historical releases `v1.0`–`v3.2` live on the archived `BRubinson/gmcc-ui`
  repo; everything from the monorepo transition onward ships here as
  `gmvibes-v*`.
- Build artifacts (`gmvibes/build/`, `*.dmg`) are gitignored — only the release
  asset is published, nothing is committed.
- This is distribution-only; it does not bump `MARKETING_VERSION`. Bump that in
  Xcode (or the pbxproj) first if you want a new version number.
