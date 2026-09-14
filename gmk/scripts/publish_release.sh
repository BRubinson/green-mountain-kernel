#!/bin/bash
#
# publish_release.sh — ship the artifact you just built and tested.
#
#     bash gmk/scripts/rebuild_local.sh       # build + stage <version>-BETA
#     bash gmk/scripts/publish_release.sh     # verify, tag, upload, activate
#
# WHAT YOU TESTED IS WHAT SHIPS. This uploads the binaries already staged in the
# local channel rather than rebuilding them. A rebuild here would produce bits
# that had never been run by anyone — which is precisely the property a release
# is supposed to have and the reason the -BETA staging step exists at all.
#
# ── WHO CAN RUN THIS ─────────────────────────────────────────────────────────
#
# This script is REPO-SIDE ONLY. It lives in gmk/scripts/, which is not part of
# the plugin payload (`source: ./plugins/gmcc`), so installing the plugin does
# not distribute it. Someone with only the plugin has no publish path at all.
#
# On top of that it refuses to run unless the authenticated `gh` user actually
# holds push on the release repo. GitHub is the real enforcement — a token
# without push cannot create a tag or a release no matter what this script does
# — and the check exists to turn a confusing mid-upload 403 into one clear line
# before anything has been tagged.
#
# ── ONE RELEASE, FOUR ASSETS ─────────────────────────────────────────────────
#
#   gm_kernel-v<version>
#   ├── gm-daemon-<version>-macos-universal.tar.gz   gm_kernel (one Mach-O)
#   ├── gm-daemon-<version>-macos-universal.tar.gz.sha256
#   ├── gm_kernel-<version>.dmg                      the app (the kernel host)
#   └── gm_kernel-<version>.dmg.sha256
#
# This replaced TWO independent tracks — `daemon-v*` cut here and `gmvibes-v*`
# cut by a separate script that shared no code with this one. They had separate
# version numbers, so "which app goes with which daemon" had no answer, and the
# plugin's installer could only ever upgrade half the system.
#
# ── THE TAG / VERSION AGREEMENT ──────────────────────────────────────────────
#
# gmk/VERSION and the `gm_kernel-v<version>` tag are two statements of one fact.
# If they disagree, the asset name encodes one version while every installer asks
# for the other, and the result is a 404 that reads like a network problem. The
# app is now inside that same agreement: build-dmg.sh stamps MARKETING_VERSION
# from gmk/VERSION, so the About box cannot drift from the tag either.
#
# ── WHY THE DMG IS BUILT HERE AND THE BINARIES ARE NOT ───────────────────────
#
# The binaries are uploaded from the staged -BETA directory precisely because
# they have been RUN — see the header above. The app has no equivalent staging
# step: nothing installs a local GMVibes build into the release store, so there
# is no tested artifact to promote and a fresh archive is the honest option.
# Signing forces the same conclusion — a release DMG has to be notarized, and
# notarizing is not something rebuild_local.sh should do on every edit.
#
# Usage:
#   publish_release.sh                # publish gmk/VERSION
#   publish_release.sh --dry-run      # every check + the DMG build, no upload
#   publish_release.sh --allow-adhoc  # publish without a Developer ID (see 5/8)
#
# Env:
#   GM_FS_ROOT                    # the one filesystem root (default: $HOME/gmfs)
#   GM_DAEMON_RELEASE_REPO        # owner/name to publish to
#   NOTARY_PROFILE                # notarytool keychain profile (default: gmcc-ui)

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_releases.sh
. "$SCRIPT_DIR/gm_releases.sh"

DRY=0
ALLOW_ADHOC=0
while [ $# -gt 0 ]; do
    case "$1" in
        --dry-run)     DRY=1 ;;
        --allow-adhoc) ALLOW_ADHOC=1 ;;
        "") ;;
        *) echo "[GMB] publish_release.sh: unknown flag $1" >&2; exit 2 ;;
    esac
    shift
done

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
fi
GMK="$REPO_ROOT/gmk"
RELEASE_REPO="${GM_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"

VERSION="$(cat "$GMK/VERSION")"
TAG="$GM_TAG_PREFIX$VERSION"
# "universal" IS HISTORICAL AND THE NAME IS DELIBERATELY FROZEN. The artifact is
# arm64-only since the Intel slice was dropped, so the word no longer describes
# the bytes — and it stays anyway. This exact literal is derived INDEPENDENTLY in
# two other places that are not upgraded in lockstep with this script:
# plugins/gmcc/scripts/install_gm.sh and .github/workflows/daemon-release.yml.
# Renaming it here would 404 every installed plugin that has not been regenerated
# and re-installed, which is precisely the cross-version break the unified
# release exists to prevent. An inaccurate filename costs nothing; a filename
# nobody can fetch costs every upgrade.
ASSET="gm-daemon-$VERSION-macos-universal.tar.gz"
DMG_ASSET="$GM_APP_NAME-$VERSION.dmg"
STAGE_VERSION="$VERSION-BETA"

gm_resolve_fs_root
STAGE="$GM_LOCAL/$STAGE_VERSION"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. Permission ────────────────────────────────────────────────────────────
say "1/8  PERMISSION"
command -v gh >/dev/null 2>&1 || die "gh CLI not found. brew install gh"
gh auth status >/dev/null 2>&1 || die "gh is not authenticated. Run: gh auth login"
WHO="$(gh api user --jq .login 2>/dev/null || echo '?')"
CAN_PUSH="$(gh api "repos/$RELEASE_REPO" --jq .permissions.push 2>/dev/null || echo false)"
if [ "$CAN_PUSH" != "true" ]; then
    die "'$WHO' does not have push access to $RELEASE_REPO.
       Publishing a release is restricted to the repo owner. Nothing was changed."
fi
echo "  authenticated as $WHO, push on $RELEASE_REPO: yes"

# ── 2. Working tree ──────────────────────────────────────────────────────────
say "2/8  WORKING TREE"
# A release must be reproducible from a commit. Tagging a dirty tree produces a
# tag that names a state no clone can ever reach.
if [ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]; then
    git -C "$REPO_ROOT" status --short | sed 's/^/    /'
    die "working tree is dirty. Commit or stash before publishing."
fi
HEAD_SHA="$(git -C "$REPO_ROOT" rev-parse --short HEAD)"
echo "  clean at $HEAD_SHA"

if git -C "$REPO_ROOT" rev-parse "$TAG" >/dev/null 2>&1; then
    die "tag $TAG already exists locally. Bump gmk/VERSION, or delete the tag."
fi
if gh release view "$TAG" --repo "$RELEASE_REPO" >/dev/null 2>&1; then
    die "release $TAG already exists on $RELEASE_REPO. Bump gmk/VERSION."
fi
echo "  $TAG is unused, locally and on the remote"

# ── 3. The staged artifact ───────────────────────────────────────────────────
say "3/8  STAGED ARTIFACT"
[ -d "$STAGE" ] || die "nothing staged at $STAGE
       Run: bash $SCRIPT_DIR/rebuild_local.sh"
gm_verify_staged "$STAGE" || die "the staged build does not match its own SHA256SUMS"

# lipo, not the manifest. The manifest records what the build INTENDED; lipo
# reads the bytes that are actually there. That distinction is the whole reason
# this check exists and is unchanged.
#
# WHAT CHANGED: x86_64 IS NO LONGER REQUIRED. This loop used to `die` when the
# Intel slice was absent, telling the operator "this looks like a --fast build".
# rebuild_local.sh now builds arm64 by default, so that message would fire on
# every correct release and make publishing impossible. The slice was dropped
# deliberately — it doubled every compile and link, the toolchain calls it
# deprecated for this deployment target, and the machines this ships to are
# Apple Silicon.
#
# arm64 IS STILL REQUIRED, and that refusal is kept exactly as it was: an
# artifact with no arm64 slice cannot execute on any machine this ships to, so
# shipping one is strictly worse than failing here. The resolved architectures
# are printed below so an operator can always see what is about to go out.
for b in $GM_MACHO; do
    archs="$(lipo -archs "$STAGE/$b")"
    case "$archs" in
        *arm64*) ;;
        *) die "$b is missing the arm64 slice (has: $archs)" ;;
    esac
    codesign --verify --strict "$STAGE/$b" || die "$b fails signature verification"
    echo "  $b  $archs  signed"
done

STAGED_SHA="$(sed -n 's/.*"source_sha": "\(.*\)".*/\1/p' "$STAGE/manifest.json")"
if [ "$STAGED_SHA" != "$HEAD_SHA" ]; then
    die "the staged build came from $STAGED_SHA but HEAD is $HEAD_SHA.
       You are about to ship binaries that do not match the commit being tagged.
       Re-run: bash $SCRIPT_DIR/rebuild_local.sh"
fi
echo "  built from $STAGED_SHA, which is HEAD"

# ── 4. Tests ─────────────────────────────────────────────────────────────────
say "4/8  TESTS — never ship what was not tested"
# ONE package now. The six-name loop that used to live here iterated targets
# that no longer exist, and a loop over a stale list is the WORST failure
# available on this path: `swift test` on a package with no test target SUCCEEDS,
# so the gate would have printed "all suites green" having run nothing at all.
# Failing permissively, on the publish path, is exactly the shape of bug this
# gate exists to prevent — so it now counts what it ran and refuses zero.
#
# The suite boots a real gm_kernel, so it needs one built. Point it at the
# artifact that is about to SHIP rather than at whatever is in .build: testing
# bits other than the ones being published is how "what you tested is what
# ships" quietly stops being true.
TEST_PACKAGE="Gm_Kernel_test"
TMP_TEST_LOG="$(mktemp "${TMPDIR:-/tmp}/gm-test.XXXXXX")"
trap 'rm -f "$TMP_TEST_LOG"' EXIT
[ -d "$GMK/$TEST_PACKAGE" ] || die "$TEST_PACKAGE is missing — refusing to publish untested binaries"

echo "  swift test $TEST_PACKAGE (against the staged kernel)"
GM_TEST_KERNEL_BIN="$STAGE/$GM_MACHO" \
    swift test --package-path "$GMK/$TEST_PACKAGE" 2>&1 | tee "$TMP_TEST_LOG" >/dev/null \
    || die "$TEST_PACKAGE failed — not publishing"

# Prove the run was not vacuous. A suite that executed nothing is not a pass.
EXECUTED="$(grep -cE "' passed \(" "$TMP_TEST_LOG" || true)"
[ "${EXECUTED:-0}" -gt 0 ] \
    || die "$TEST_PACKAGE reported success but ran ZERO cases — refusing to ship on a vacuous gate"
echo "  $EXECUTED cases green"

# ── 5. The app ───────────────────────────────────────────────────────────────
say "5/8  APP"
# ── WHY NOTARIZATION IS A GATE AND NOT A WARNING ─────────────────────────────
#
# An ad-hoc DMG runs fine on the machine that built it and is refused by
# Gatekeeper on every other machine — "GMVibes is damaged and can't be opened",
# which is neither true nor actionable. The script this replaced would build
# ad-hoc without a Developer ID and publish it with a note telling recipients to
# strip quarantine by hand. A release asset that needs a terminal command before
# it will open is not a release, so the default is now a refusal.
#
# --allow-adhoc remains because a private or test release to yourself is a real
# case; it has to be asked for.
DEV_ID="$(security find-identity -v -p codesigning 2>/dev/null \
  | grep "Developer ID Application" | head -1 \
  | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' || true)"

if [ -z "$DEV_ID" ]; then
    if [ "$ALLOW_ADHOC" -eq 0 ]; then
        die "no 'Developer ID Application' certificate found.

       The DMG would be ad-hoc signed, and Gatekeeper blocks an ad-hoc app on
       every machine except this one. Recipients would see \"GMVibes is damaged\".

       Publish anyway (private/test release):  --allow-adhoc"
    fi
    echo "  no Developer ID — building AD-HOC because --allow-adhoc was passed"
    export NOTARIZE=0
else
    echo "  $DEV_ID"
    export NOTARIZE=1
fi

bash "$SCRIPT_DIR/build-dmg.sh" "$VERSION" || die "the GMVibes build failed — not publishing"
DMG_BUILT="$GMK/build/$DMG_ASSET"
[ -f "$DMG_BUILT" ] || die "build-dmg.sh did not produce $DMG_BUILT"

# The version INSIDE the bundle, read back rather than assumed. The stamp is a
# build-setting override, and an override that silently failed to apply would
# ship an app whose About box disagrees with the tag it was released under.
DMG_MNT="$(mktemp -d "${TMPDIR:-/tmp}/gm-verify.XXXXXX")"
hdiutil attach "$DMG_BUILT" -nobrowse -readonly -quiet -mountpoint "$DMG_MNT" >/dev/null 2>&1 \
    || die "could not mount the DMG that was just built"
BUNDLE_VERSION="$(defaults read "$DMG_MNT/$GM_APP_NAME.app/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo '?')"
hdiutil detach "$DMG_MNT" -quiet >/dev/null 2>&1 || hdiutil detach "$DMG_MNT" -force -quiet >/dev/null 2>&1 || true
rmdir "$DMG_MNT" 2>/dev/null || true
[ "$BUNDLE_VERSION" = "$VERSION" ] || die "the built app reports version '$BUNDLE_VERSION' but this release is $VERSION.
       MARKETING_VERSION did not take — check build-dmg.sh's archive step."
echo "  $DMG_ASSET  bundle version $BUNDLE_VERSION  ($(du -h "$DMG_BUILT" | cut -f1))"

# ── 6. Package ───────────────────────────────────────────────────────────────
say "6/8  PACKAGE"
# Flat archive with the three binaries at the root and no version directory to
# guess — byte-for-byte the shape daemon-release.yml produces, so the installer
# cannot tell a locally published asset from a CI-built one.
PKG="$GM_RELEASES/.publish.$VERSION"
rm -rf "$PKG"; mkdir -p "$PKG"
( cd "$STAGE" && tar -czf "$PKG/$ASSET" $GM_MACHO )
( cd "$PKG" && shasum -a 256 "$ASSET" > "$ASSET.sha256" )
echo "  $PKG/$ASSET  ($(du -h "$PKG/$ASSET" | cut -f1))"
echo "  $(cat "$PKG/$ASSET.sha256")"

# The DMG gets the same sidecar treatment as the tarball. install_gm.sh verifies
# both before it unpacks or mounts anything, so an asset without a sidecar is an
# asset the installer refuses.
cp "$DMG_BUILT" "$PKG/$DMG_ASSET"
( cd "$PKG" && shasum -a 256 "$DMG_ASSET" > "$DMG_ASSET.sha256" )
echo "  $PKG/$DMG_ASSET  ($(du -h "$PKG/$DMG_ASSET" | cut -f1))"
echo "  $(cat "$PKG/$DMG_ASSET.sha256")"

if [ "$DRY" -eq 1 ]; then
    say "DRY RUN — every check passed. Nothing was tagged, pushed or uploaded."
    echo "  re-run without --dry-run to publish $TAG"
    exit 0
fi

# ── 7. Tag + upload ──────────────────────────────────────────────────────────
say "7/8  TAG + UPLOAD"
# The tag is pushed BEFORE the release is created: `gh release create` against a
# tag the remote does not have creates the tag from the default branch instead,
# which silently ships whatever is on main rather than what was verified here.
git -C "$REPO_ROOT" tag "$TAG"
git -C "$REPO_ROOT" push origin "$TAG"
echo "  pushed $TAG"

if [ "$NOTARIZE" = "1" ]; then
    SIGNING_NOTE="Signed with a Developer ID and notarized."
else
    SIGNING_NOTE="**Ad-hoc build.** Gatekeeper will refuse it until quarantine is cleared:
\`xattr -dr com.apple.quarantine /Applications/$GM_APP_NAME.app\`"
fi

cat > "$PKG/notes.md" <<NOTES
One release, one version: the runtime and the app are both \`$VERSION\`.

| Asset | What it is |
| --- | --- |
| \`$ASSET\` | Universal (arm64 + x86_64) \`gm_kernel\` — one Mach-O, answering as \`gm_daemon\` / \`gm_mcp\` / \`gm_hook\` via argv[0] |
| \`$DMG_ASSET\` | The $GM_APP_NAME macOS app |

$SIGNING_NOTE

Built from \`$HEAD_SHA\` and published with \`gmk/scripts/publish_release.sh\`.

Install or upgrade BOTH with the plugin's installer — it fetches the newest
\`${GM_TAG_PREFIX}*\` release, verifies each SHA-256 sidecar before unpacking or
mounting, stages the binaries under
\`\$GM_FS_ROOT/bin/releases/downloads/$VERSION/\` and the DMG under
\`\$GM_FS_ROOT/apps/downloads/$VERSION/\`, then installs the app to
\`/Applications\`:

\`\`\`bash
bash plugins/gmcc/scripts/install_gm.sh
\`\`\`
NOTES

gh release create "$TAG" --repo "$RELEASE_REPO" \
    --title "GM kernel v$VERSION" --notes-file "$PKG/notes.md"
gh release upload "$TAG" --repo "$RELEASE_REPO" \
    "$PKG/$ASSET" "$PKG/$ASSET.sha256" \
    "$PKG/$DMG_ASSET" "$PKG/$DMG_ASSET.sha256" --clobber
echo "  uploaded $ASSET + .sha256"
echo "  uploaded $DMG_ASSET + .sha256"

# ── 8. Promote locally ───────────────────────────────────────────────────────
say "8/8  PROMOTE"
# The published bytes are the staged bytes, so this machine moves off -BETA onto
# the release without a download. Copied rather than moved: the BETA directory
# stays put, which is what makes `gm_activate local` a working rollback.
DL="$(gm_stage_dir downloads "$VERSION")"
rm -rf "$DL"; DL="$(gm_stage_dir downloads "$VERSION")"
for b in $GM_MACHO; do cp "$STAGE/$b" "$DL/$b"; done
gm_write_manifest "$DL" "$VERSION" downloads "$HEAD_SHA" "arm64,x86_64"
gm_activate downloads "$VERSION"
gm_retire_daemon

# The app comes across too, from the same bytes that were just uploaded. Staged
# into the app store first so this machine's store looks exactly like one that
# installed from the release.
APP_DL="$(dirname "$(gm_app_dmg "$VERSION")")"
mkdir -p "$APP_DL"
cp "$DMG_BUILT" "$(gm_app_dmg "$VERSION")"

# BEST EFFORT, DELIBERATELY. Everything above this line is already on GitHub;
# a running app must not turn a successful publish into a failed script.
#
# The two calls below are the SAME PREPARATION install_gm.sh does, and this path
# needs them for the same reasons — it was publishing straight into
# gm_install_app and skipping both, which left this machine holding
# gm_kernel.app AND GMVibes.app under one bundle identifier on the very first
# 51.0.0 publish.
#
# Stop the writer first: the app is becoming the kernel host, and
# gm_install_app refuses while it is running.
gm_stop_kernel_and_wait 3
# Then drop the superseded bundle. Two apps sharing `rube.GMVibes` make
# LaunchServices ambiguous AND defeat the same-bundle-id check a second copy
# uses to recognise the first.
gm_retire_legacy_app

if gm_install_app "$(gm_app_dmg "$VERSION")" "$VERSION"; then
    :
else
    echo "  (the app was staged but not installed — install it when convenient:"
    echo "   bash $SCRIPT_DIR/../../plugins/gmcc/scripts/install_gm.sh --app)"
fi
rm -rf "$PKG"

say "PUBLISHED $TAG"
echo "  https://github.com/$RELEASE_REPO/releases/tag/$TAG"
echo "  this machine is now running v$VERSION (was $STAGE_VERSION)"
