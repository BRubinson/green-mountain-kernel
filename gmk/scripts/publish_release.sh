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
# ── THE TAG / VERSION AGREEMENT ──────────────────────────────────────────────
#
# gmk/VERSION and the `daemon-v<version>` tag are two statements of one fact. If
# they disagree, the asset name encodes one version while every installer asks
# for the other, and the result is a 404 that reads like a network problem.
# daemon-release.yml enforces the same rule from the CI side.
#
# Usage:
#   publish_release.sh            # publish gmk/VERSION from the staged BETA
#   publish_release.sh --dry-run  # every check, no tag, no push, no upload
#
# Env:
#   GM_FS_ROOT                    # the one filesystem root (default: $HOME/gmfs)
#   GM_DAEMON_RELEASE_REPO        # owner/name to publish to

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=gm_releases.sh
. "$SCRIPT_DIR/gm_releases.sh"

DRY=0
[ "${1:-}" = "--dry-run" ] && DRY=1
[ -n "${1:-}" ] && [ "$1" != "--dry-run" ] && {
    echo "[GMB] publish_release.sh: unknown flag $1" >&2; exit 2; }

REPO_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT/gmk" ]; then
    REPO_ROOT="$(dirname "$(dirname "$SCRIPT_DIR")")"
fi
GMK="$REPO_ROOT/gmk"
RELEASE_REPO="${GM_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"

VERSION="$(cat "$GMK/VERSION")"
TAG="daemon-v$VERSION"
ASSET="gm-daemon-$VERSION-macos-universal.tar.gz"
STAGE_VERSION="$VERSION-BETA"

gm_resolve_fs_root
STAGE="$GM_LOCAL/$STAGE_VERSION"

say() { printf '\n\033[1m%s\033[0m\n' "$*"; }
die() { printf '\n\033[31mFATAL: %s\033[0m\n' "$*" >&2; exit 1; }

# ── 1. Permission ────────────────────────────────────────────────────────────
say "1/7  PERMISSION"
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
say "2/7  WORKING TREE"
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
say "3/7  STAGED ARTIFACT"
[ -d "$STAGE" ] || die "nothing staged at $STAGE
       Run: bash $SCRIPT_DIR/rebuild_local.sh"
gm_verify_staged "$STAGE" || die "the staged build does not match its own SHA256SUMS"

# lipo, not the manifest. The manifest records what the build INTENDED; lipo
# reads the bytes that are actually there. A --fast build is caught right here,
# which is the whole reason that flag is allowed to exist.
for b in $GM_BINARIES; do
    archs="$(lipo -archs "$STAGE/$b")"
    case "$archs" in
        *arm64*) ;;
        *) die "$b is missing the arm64 slice (has: $archs)" ;;
    esac
    case "$archs" in
        *x86_64*) ;;
        *) die "$b is missing the x86_64 slice (has: $archs).
       This looks like a --fast build. Re-run: bash $SCRIPT_DIR/rebuild_local.sh" ;;
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
say "4/7  TESTS — never ship what was not tested"
for p in gmDaemonSdk gmDaemon gmUxComponentLibrary gmMcp gmToolchain; do
    echo "  swift test $p"
    swift test --package-path "$GMK/$p" >/dev/null || die "$p tests failed — not publishing"
done
swift build --package-path "$GMK/gmAgententicsSdk" >/dev/null || die "gmAgententicsSdk does not compile"
echo "  all suites green"

# ── 5. Package ───────────────────────────────────────────────────────────────
say "5/7  PACKAGE"
# Flat archive with the three binaries at the root and no version directory to
# guess — byte-for-byte the shape daemon-release.yml produces, so the installer
# cannot tell a locally published asset from a CI-built one.
PKG="$GM_RELEASES/.publish.$VERSION"
rm -rf "$PKG"; mkdir -p "$PKG"
( cd "$STAGE" && tar -czf "$PKG/$ASSET" $GM_BINARIES )
( cd "$PKG" && shasum -a 256 "$ASSET" > "$ASSET.sha256" )
echo "  $PKG/$ASSET  ($(du -h "$PKG/$ASSET" | cut -f1))"
echo "  $(cat "$PKG/$ASSET.sha256")"

if [ "$DRY" -eq 1 ]; then
    say "DRY RUN — every check passed. Nothing was tagged, pushed or uploaded."
    echo "  re-run without --dry-run to publish $TAG"
    exit 0
fi

# ── 6. Tag + upload ──────────────────────────────────────────────────────────
say "6/7  TAG + UPLOAD"
# The tag is pushed BEFORE the release is created: `gh release create` against a
# tag the remote does not have creates the tag from the default branch instead,
# which silently ships whatever is on main rather than what was verified here.
git -C "$REPO_ROOT" tag "$TAG"
git -C "$REPO_ROOT" push origin "$TAG"
echo "  pushed $TAG"

cat > "$PKG/notes.md" <<NOTES
Universal (arm64 + x86_64) macOS binaries for \`gm_daemon\`, \`gm_mcp\`, \`gm_hook\`.

Built from \`$HEAD_SHA\` and published with \`gmk/scripts/publish_release.sh\`.

Installed by the plugin's \`install_gm.sh\`, which fetches the latest
\`daemon-v*\` release, verifies the SHA-256 sidecar before unpacking, and stages
it under \`\$GM_FS_ROOT/bin/releases/downloads/$VERSION/\`.
NOTES

gh release create "$TAG" --repo "$RELEASE_REPO" \
    --title "GM daemon v$VERSION" --notes-file "$PKG/notes.md"
gh release upload "$TAG" --repo "$RELEASE_REPO" \
    "$PKG/$ASSET" "$PKG/$ASSET.sha256" --clobber
echo "  uploaded $ASSET + .sha256"

# ── 7. Promote locally ───────────────────────────────────────────────────────
say "7/7  PROMOTE"
# The published bytes are the staged bytes, so this machine moves off -BETA onto
# the release without a download. Copied rather than moved: the BETA directory
# stays put, which is what makes `gm_activate local` a working rollback.
DL="$(gm_stage_dir downloads "$VERSION")"
rm -rf "$DL"; DL="$(gm_stage_dir downloads "$VERSION")"
for b in $GM_BINARIES; do cp "$STAGE/$b" "$DL/$b"; done
gm_write_manifest "$DL" "$VERSION" downloads "$HEAD_SHA" "arm64,x86_64"
gm_activate downloads "$VERSION"
gm_retire_daemon
rm -rf "$PKG"

say "PUBLISHED $TAG"
echo "  https://github.com/$RELEASE_REPO/releases/tag/$TAG"
echo "  this machine is now running v$VERSION (was $STAGE_VERSION)"
