#!/usr/bin/env bash
#
# release.sh — RETIRED. The app no longer has a release of its own.
#
# This script used to build the GMVibes DMG and publish it under its own
# `gmvibes-v<MARKETING_VERSION>` tag, independently of the binaries. That split
# is what the unified release removed, and the reasons it had to go are worth
# keeping written down:
#
#   - TWO VERSION NUMBERS, NO RELATIONSHIP. The app was tagged from
#     MARKETING_VERSION (3.9) and the runtime from gmk/VERSION (50.0.1). Nothing
#     recorded which app went with which daemon, and the wire protocol between
#     them is not version-free.
#   - THE INSTALLER COULD ONLY UPGRADE HALF THE SYSTEM. install_gm.sh fetched
#     the binary release and had no idea an app release existed, so a user who
#     upgraded got a new daemon talking to whatever app they happened to have.
#   - IT WOULD PUBLISH AN AD-HOC DMG. With no Developer ID it built unsigned and
#     shipped it with a note telling recipients to strip quarantine by hand.
#     publish_release.sh now refuses that by default (--allow-adhoc to override).
#
# This file is kept as a signpost rather than deleted: it was named by the
# `release-dmg` skill and by anything a person's shell history remembers, and a
# "command not found" says nothing about where the capability went.
#
# TO CUT A RELEASE — one command publishes the binaries AND the app at one
# version, under one `gm_kernel-v*` tag:
#
#     bash gmk/scripts/rebuild_local.sh      # build + stage <version>-BETA
#     bash gmk/scripts/publish_release.sh    # verify, build the DMG, tag, upload
#
# TO BUILD A DMG WITHOUT PUBLISHING ANYTHING — unchanged, and still the right
# tool for a one-off build you hand to someone:
#
#     bash gmk/scripts/build-dmg.sh          # build/GMVibes-<gmk/VERSION>.dmg
#     bash gmk/scripts/build-dmg.sh 1.2.3    # ...at an explicit version

cat >&2 <<'EOF'
[GMB] gmk/scripts/release.sh is retired.

      The app is no longer released on its own tag. One release now carries the
      three binaries and the GMVibes DMG at one version from gmk/VERSION.

      Publish everything:
          bash gmk/scripts/rebuild_local.sh
          bash gmk/scripts/publish_release.sh

      Just build a DMG, publishing nothing:
          bash gmk/scripts/build-dmg.sh

      See the comments at the top of this file for why the split was removed.
EOF
exit 2
