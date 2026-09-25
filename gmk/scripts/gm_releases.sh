#!/bin/bash
#
# gm_releases.sh — the RELEASE STORE contract, in one file.
#
# Sourced by rebuild_local.sh, publish_release.sh and install_gm.sh. It is a
# library and nothing else: it defines functions and variables, runs no work at
# source time, and never writes outside $GM_FS_ROOT.
#
# ── THE STORE ────────────────────────────────────────────────────────────────
#
#   $GM_FS_ROOT/bin/
#   ├── gm_kernel  -> releases/active/gm_kernel      the ONE staged Mach-O (prod)
#   ├── .gm_version                                  the ACTIVE version string
#   └── releases/
#       ├── active -> downloads/50.0.1               or local/50.0.1-BETA
#       ├── downloads/50.0.1/{gm_kernel,manifest.json,SHA256SUMS}
#       └── local/50.0.1-BETA/{gm_kernel,manifest.json,SHA256SUMS}
#
#   A beta or test root stages the WHOLE signed bundle instead, because nothing
#   but the app hosts a kernel and clients launch it from the store by path:
#
#   ├── gm_kernel.app -> releases/active/gm_kernel.app
#   ├── gm_kernel     -> releases/active/gm_kernel.app/Contents/MacOS/gm_kernel
#   └── releases/local/50.0.1-BETA/{gm_kernel.app,manifest.json,SHA256SUMS}
#
#   Production launches /Applications/gm_kernel.app by path.
#
#   gm_mcp and gm_hook are NOT here: they ship inside the plugin (plugins/gmcc/bin),
#   compiled with the client closure, and never pass through this store.
#
# WHY SYMLINKS RATHER THAN COPIES INTO bin/. Three reasons, in order of how much
# they bite:
#
#   1. Overwriting a signed Mach-O IN PLACE leaves the kernel's code-signature
#      cache pointing at the old inode's contents, and the next exec dies with
#      SIGKILL — exit 137, no output, no diagnostic. Every copy-based installer
#      has to remember `rm` before `cp`. A symlink swap has no in-place
#      overwrite to get wrong, because the binaries themselves are never
#      rewritten once staged.
#   2. Rollback is a symlink swap, so a bad build is survivable without a
#      network round trip: the previous version is still sitting in the store.
#   3. A version directory is IMMUTABLE once staged, so the sha256 recorded in
#      its manifest keeps describing the bytes that are actually there.
#
# THE SYMLINKS ARE RELATIVE ON PURPOSE, and the invariant outlived the reason it
# was written for. GM_FS_ROOT is overridable, and a staged tree gets copied — by
# a test harness, by a machine migration, by anyone inspecting a release — so the
# store has to resolve WITHIN ITSELF wherever it sits. Absolute links would make
# a copied tree silently drive whatever lives at the original path.
#
# ── THE TWO CHANNELS ─────────────────────────────────────────────────────────
#
#   local/     — what rebuild_local.sh builds from your working tree. ALWAYS
#                carries a -BETA suffix, with no exception and no flag to turn
#                it off. That suffix is the only thing distinguishing bits that
#                were merely built from bits that were published, and it is the
#                reason `gm_hook ping` can never make a locally-staged binary
#                look like a release.
#   downloads/ — what install_gm.sh fetched from a `daemon-v*` GitHub release,
#                checksum-verified before it was unpacked.
#
# A version directory name IS its version string, which is what lets the active
# symlink's target name the running version without a lookup table.

# ── THE APP RIDES ALONG ──────────────────────────────────────────────────────
#
#   $GM_FS_ROOT/apps/
#   ├── .gmvibes_version                     what WE last installed
#   └── downloads/50.0.2/GMVibes-50.0.2.dmg  checksum-verified before it was used
#
# The DMG is staged under the filesystem root exactly like the binaries, and for
# the same reason: the bytes that were verified are the bytes that get installed,
# and a re-install needs no second download. It is the ONE thing in this library
# that then writes outside $GM_FS_ROOT — /Applications is where a macOS app has
# to land to be launchable — and that step is a separate function so the write
# is explicit at every call site rather than buried in a download path.
#
# ── ONE VERSION ACROSS THE WHOLE RELEASE ─────────────────────────────────────
#
# `gmk/VERSION` pins the binaries AND the app: build-dmg.sh stamps
# MARKETING_VERSION from it, so the app's About box and `.gm_version` can never
# disagree. Before this they were two independently tagged tracks
# (`daemon-v*` and `gmvibes-v*`) and nothing made them meet.

# Never sourced twice.
[ -n "${GM_RELEASES_SH:-}" ] && return 0
GM_RELEASES_SH=1

# ── The binary contract: ONE Mach-O, no entry-point names ────────────────────
#
#   GM_MACHO       what gets STAGED, hashed, lipo-checked and tarred. One file.
#   GM_ENTRYPOINTS what gets SYMLINKED in $GM_BIN beside it. Empty: the headless
#                  `gm_daemon` host is retired and the app is the only writer.
#
# The variable stays so manifests keep an `entrypoints` field and the legacy
# pre-collapse arm below still reads.
GM_MACHO="gm_kernel"
GM_ENTRYPOINTS=""

# Kept as the union for the paths that genuinely mean "everything in $GM_BIN":
# the quarantine strip and the staleness stat do not care which is a real file.
GM_BINARIES="$GM_MACHO $GM_ENTRYPOINTS"

# The unified release tag namespace. GitHub's own "latest release" is the wrong
# question for a monorepo that has shipped more than one kind of artifact, so
# every lookup filters by this prefix.
GM_TAG_PREFIX="gm_kernel-v"
# The namespace this replaced. Releases published before the unification still
# carry it and still contain a usable binary tarball, so the installer falls
# back to it rather than telling a working machine that nothing is published.
GM_LEGACY_TAG_PREFIX="daemon-v"

# The app bundle's name. GMVibes became gm_kernel: the bundle IS the kernel now,
# hosting the writer rather than talking to it over a socket.
#
# The BUNDLE IDENTIFIER deliberately did NOT change (`rube.GMVibes`). A new id is
# a new NSUserDefaults domain, so window restoration, recents and every
# preference would reset once for zero functional gain — and same-bundle-id
# detection is what lets a second copy recognise the first.
GM_APP_NAME="gm_kernel"

# The name the bundle shipped under BEFORE it became the kernel host.
#
# Two things still carry it and neither can be rewritten retroactively: every
# DMG already published (the asset is `GMVibes-<version>.dmg` and it contains
# `GMVibes.app`), and any machine that installed one. A rename that cannot read
# its own back-catalogue is a rename that breaks upgrade for everyone who is
# behind — which is precisely the population an installer exists to serve.
GM_APP_NAME_LEGACY="GMVibes"

# ── Environments ─────────────────────────────────────────────────────────────
#
# THREE environments, each a complete root: prod, beta, test.
#
#   prod  $HOME/gmfs           the primary environment, what is actually used
#   beta  $HOME/beta_gmfs      a refreshable copy-of-prod for trying things
#   test  $HOME/test_gmfs      the CHANNEL under which ephemeral run roots live
#
# PRODUCTION KEEPS $HOME/gmfs and does NOT become $HOME/prod_gmfs. Renaming it
# would mean rewriting the absolute daemon_config roots against the documented
# rollback anchor and tripping migrate_to_gmfs.sh's own refusal check — a
# machine-wide migration of a ~600MB database purchased purely so three names
# look alike. A symlink buys the symmetry for anyone who wants it, and the
# inode-keyed root comparison in Paths tolerates one.
#
# Called GM_ENV rather than "channel" on purpose: `channel` already means
# `local` vs `downloads` in gm_stage_dir below, and reusing it would make two
# different axes share one word in one file.
gm_env_root() {
    case "${1:-prod}" in
        prod)  printf '%s\n' "$HOME/gmfs" ;;
        beta)  printf '%s\n' "$HOME/beta_gmfs" ;;
        test)  printf '%s\n' "$HOME/test_gmfs" ;;
        *) echo "[GMB] unknown environment '$1' (prod|beta|test)" >&2; return 2 ;;
    esac
}

# ── Roots ────────────────────────────────────────────────────────────────────
#
# ONE root variable, and now ONE resolution step: an explicit GM_FS_ROOT wins,
# otherwise the root for GM_ENV (default prod, i.e. $HOME/gmfs — unchanged for
# every existing caller).
#
# The marker walk that used to sit here selected a second, snapshot runtime. That
# runtime is gone, so the walk could only ever return the same answer — while
# still carrying the risk that made it delicate in the first place (a repo file
# being consulted by an installer). GM_FS_ROOT stays overridable, which is what
# a test harness uses; it simply no longer has a filesystem fallback to disagree
# with.
#
# EVERY environment gets a FULL release store, not just a database. A client on
# a beta or test root launches $ROOT/bin/gm_kernel.app, and without it nothing
# on that root records anything. That is why gm_env create stages the bundle
# rather than only making directories.
gm_resolve_fs_root() {
    GM_ENV="${GM_ENV:-prod}"
    GM_FS_ROOT="${GM_FS_ROOT:-$(gm_env_root "$GM_ENV")}"
    GM_BIN="$GM_FS_ROOT/bin"
    GM_RELEASES="$GM_BIN/releases"
    GM_DOWNLOADS="$GM_RELEASES/downloads"
    GM_LOCAL="$GM_RELEASES/local"
    GM_ACTIVE="$GM_RELEASES/active"
    GM_VERSION_STAMP="$GM_BIN/.gm_version"

    # The app store, alongside the binary store and under the same one root.
    GM_APPS="$GM_FS_ROOT/apps"
    GM_APP_DOWNLOADS="$GM_APPS/downloads"
    GM_APP_VERSION_STAMP="$GM_APPS/.gmvibes_version"
    # Overridable so a machine where /Applications is not writable — or a test
    # harness — can install somewhere else without editing this library.
    GM_APP_DEST="${GM_APP_DEST:-/Applications}"
}

# ── Staging ──────────────────────────────────────────────────────────────────

# gm_stage_dir <channel> <version>  ->  prints the directory, creating it.
# Channel is `local` or `downloads`; anything else is a caller bug, not input.
gm_stage_dir() {
    case "$1" in
        local)     _d="$GM_LOCAL/$2" ;;
        downloads) _d="$GM_DOWNLOADS/$2" ;;
        *) echo "[GMB] gm_stage_dir: unknown channel '$1'" >&2; return 2 ;;
    esac
    mkdir -p "$_d"
    printf '%s\n' "$_d"
}

# gm_stage_from_bundle <app-path> <channel> <version> [sha]
#
# Take the CLI Mach-O OUT of a gm_kernel.app and stage it as a version.
#
# ## Why this exists
#
# A release used to carry two artifacts: a tarball holding the Mach-O, and a DMG
# holding the app. The same code, staged twice, versioned by two mechanisms. Once
# the app hosts the writer they are literally the same binary, and shipping both
# is how the two-track drift this store was built to end comes back.
#
# So the DMG is the artifact and this is the extraction. The app's own executable
# at Contents/MacOS/gm_kernel IS the CLI; everything downstream — the version
# directory, the manifest, SHA256SUMS, the symlink activation, rollback by swap —
# is UNCHANGED. Releases before the one-Mach-O bundle carried a copy at
# Contents/Helpers, which is read only when MacOS has no kernel.
#
# ## Re-sign ONLY what does not verify on its own
#
# A Mach-O signed on its own (build-dmg.sh's Developer ID pass, or the linker's
# ad-hoc signature under CODE_SIGNING_ALLOWED=NO) keeps a valid signature when
# copied out, and re-signing it would replace a Developer ID with whatever this
# machine holds — usually nothing. A Mach-O signed AS PART OF ITS BUNDLE (what
# Xcode ⌘R produces) seals the bundle's Info.plist into its CodeDirectory;
# copied out, that seal fails and the kernel answers the exec with SIGKILL —
# exit 137, no output, and every hook, pane and MCP server on that root dies
# silently. So the copy is verified standalone, and only a failing one is
# re-signed ad-hoc, before the manifest records its bytes.
gm_stage_from_bundle() {
    _app="$1"; _channel="$2"; _version="$3"; _sha="${4:-unknown}"
    _helper="$_app/Contents/MacOS/$GM_MACHO"
    [ -x "$_helper" ] || _helper="$_app/Contents/Helpers/$GM_MACHO"

    if [ ! -x "$_helper" ]; then
        echo "[GMB] ERROR: $_app carries no Contents/MacOS/$GM_MACHO (nor a legacy Contents/Helpers copy)" >&2
        echo "       Nothing to stage. The bundle was built without the kernel install phase." >&2
        return 1
    fi

    _dir="$(gm_stage_dir "$_channel" "$_version")" || return 1
    # -p so the executable bit survives; gm_staged_binaries tests for it.
    cp -p "$_helper" "$_dir/$GM_MACHO" || return 1

    if ! codesign --verify --strict "$_dir/$GM_MACHO" >/dev/null 2>&1; then
        codesign --force --sign - --preserve-metadata=identifier,entitlements \
            "$_dir/$GM_MACHO" >/dev/null 2>&1 || return 1
        codesign --verify --strict "$_dir/$GM_MACHO" >/dev/null 2>&1 || {
            echo "[GMB] ERROR: $GM_MACHO from $_app does not verify even after an ad-hoc re-sign" >&2
            return 1; }
        echo "[GMB] re-signed $GM_MACHO ad-hoc: its bundle-sealed signature does not verify standalone" >&2
    fi

    _arches="$(lipo -archs "$_dir/$GM_MACHO" 2>/dev/null | tr ' ' ',')"
    gm_write_manifest "$_dir" "$_version" "$_channel" "$_sha" "${_arches:-unknown}" || return 1

    echo "[GMB] staged $GM_MACHO [$_arches] from $_app"
    printf '%s\n' "$_dir"
}

# gm_stage_bundle <app-path> <channel> <version> [sha]
#
# Stage the WHOLE app bundle as a version, for a beta or test root, where
# clients launch the kernel from the store.
#
# Re-sign ONLY what does not verify, exactly as gm_stage_from_bundle does for
# the Mach-O: a signed archive keeps its identity, while a scripted build
# (CODE_SIGNING_ALLOWED=NO) carries only the linker's signature, which seals no
# resources, so its staged COPY is signed ad-hoc — never the source bundle.
gm_stage_bundle() {
    _app="$1"; _channel="$2"; _version="$3"; _sha="${4:-unknown}"
    [ -x "$_app/Contents/MacOS/$GM_MACHO" ] || {
        echo "[GMB] ERROR: $_app carries no Contents/MacOS/$GM_MACHO" >&2; return 1; }

    _dir="$(gm_stage_dir "$_channel" "$_version")" || return 1
    # ditto, not cp -R: a code signature does not survive without the bundle's
    # extended attributes.
    ditto "$_app" "$_dir/$GM_APP_NAME.app" || return 1
    if ! codesign --verify --deep --strict "$_dir/$GM_APP_NAME.app" >/dev/null 2>&1; then
        codesign --force --deep --sign - --preserve-metadata=entitlements \
            "$_dir/$GM_APP_NAME.app" >/dev/null 2>&1 || return 1
        codesign --verify --deep --strict "$_dir/$GM_APP_NAME.app" >/dev/null 2>&1 || {
            echo "[GMB] ERROR: $GM_APP_NAME.app from $_app does not verify even after an ad-hoc re-sign" >&2
            return 1; }
        echo "[GMB] re-signed $GM_APP_NAME.app ad-hoc: the build carried no bundle signature" >&2
    fi

    _arches="$(lipo -archs "$_dir/$GM_APP_NAME.app/Contents/MacOS/$GM_MACHO" 2>/dev/null | tr ' ' ',')"
    gm_write_manifest "$_dir" "$_version" "$_channel" "$_sha" "${_arches:-unknown}" || return 1

    echo "[GMB] staged $GM_APP_NAME.app [$_arches] from $_app"
    printf '%s\n' "$_dir"
}

# gm_write_manifest <dir> <version> <channel> <sha> <arches>
#
# The manifest answers "what exactly is this and where did it come from" without
# running the binaries — which matters most in the case where they will not run.
gm_write_manifest() {
    _dir="$1"; _version="$2"; _channel="$3"; _sha="$4"; _arches="$5"
    cat > "$_dir/manifest.json" <<EOF
{
  "version": "$_version",
  "channel": "$_channel",
  "source_sha": "$_sha",
  "arches": "$_arches",
  "staged_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "macho": "$(gm_staged_binaries "$_dir")",
  "entrypoints": [$([ -n "$GM_ENTRYPOINTS" ] && printf '"%s", ' $GM_ENTRYPOINTS | sed 's/, $//')]
}
EOF
    # Hash WHAT IS THERE. For the kernel shape that is the one Mach-O; for a
    # pre-collapse directory it is the three binaries. Hashing the entry-point
    # NAMES would be wrong in both cases — they are symlinks created in $GM_BIN at
    # activation, and never staged files.
    ( cd "$_dir" && shasum -a 256 $(gm_staged_binaries "$_dir") > SHA256SUMS )
}

# gm_staged_binaries <dir> — the executable file set a staged version actually
# holds, as a space-separated list. Empty means the directory is not a usable
# staged version.
#
# THREE SHAPES COEXIST ON DISK, and that is not a transition artifact — it is the
# permanent consequence of keeping rollback honest. A beta or test version holds
# the whole bundle; a production version holds a single multi-call Mach-O; one
# staged before the kernel collapse holds three binaries. All must verify and
# activate, or `gm_activate local <old>-BETA` — the whole point of the store —
# refuses on exactly the day someone needs it.
gm_staged_binaries() {
    if [ -f "$1/$GM_APP_NAME.app/Contents/MacOS/$GM_MACHO" ]; then
        printf '%s' "$GM_APP_NAME.app/Contents/MacOS/$GM_MACHO"
    elif [ -f "$1/$GM_MACHO" ]; then
        printf '%s' "$GM_MACHO"
    elif [ -f "$1/gm_daemon" ]; then
        # Pre-collapse: the entry-point names WERE the artifacts.
        printf '%s' "gm_daemon gm_mcp gm_hook"
    else
        printf ''
    fi
}

# gm_verify_staged <dir> — every binary present, executable, and matching the
# SHA256SUMS recorded when it was staged. Activation is refused otherwise: a
# half-staged directory that gets activated is three dead symlinks.
gm_verify_staged() {
    _dir="$1"
    _set="$(gm_staged_binaries "$_dir")"
    if [ -z "$_set" ]; then
        echo "[GMB] ERROR: $_dir holds neither $GM_APP_NAME.app, $GM_MACHO nor gm_daemon — not a staged version" >&2
        return 1
    fi
    for b in $_set; do
        if [ ! -f "$_dir/$b" ]; then
            echo "[GMB] ERROR: $_dir is missing $b — refusing to activate a partial set" >&2
            return 1
        fi
        chmod +x "$_dir/$b"
    done
    if [ -f "$_dir/SHA256SUMS" ]; then
        if ! ( cd "$_dir" && shasum -a 256 -c SHA256SUMS >/dev/null 2>&1 ); then
            echo "[GMB] ERROR: $_dir fails its own SHA256SUMS — the staged bytes changed after staging" >&2
            return 1
        fi
    fi
    return 0
}

# ── Activation ───────────────────────────────────────────────────────────────

# gm_activate <channel> <version> — point bin/ at a staged version.
#
# ── THE SYMLINK-TO-A-DIRECTORY TRAP, WHICH BIT THIS FUNCTION ONCE ────────────
#
# `active` is a symlink TO A DIRECTORY, and both of the obvious ways to replace
# it silently do something else instead:
#
#   ln -sf  new active   → creates `active/new`, INSIDE the old target
#   mv -f   tmp  active  → moves tmp INTO the old target directory
#
# Both "succeed", both leave `active` pointing exactly where it did, and the
# stray link they deposit in a version directory is the only evidence. That is
# not hypothetical: the first version of this function used `mv -f` and promoted
# a release by writing `.active.tmp.67631 -> downloads/50.0.1` into the BETA
# directory while `.gm_version` cheerfully recorded the new version. The store
# claimed one version and executed another.
#
# `-n` on ln and `-h` on mv are the flags that mean "operate on the LINK, do not
# follow it". `mv -fh` keeps the atomic rename — there is no instant where
# `active` is missing — and actually replaces the link.
gm_activate() {
    _channel="$1"; _version="$2"
    case "$_channel" in
        local)     _rel="local/$_version" ;;
        downloads) _rel="downloads/$_version" ;;
        *) echo "[GMB] gm_activate: unknown channel '$_channel'" >&2; return 2 ;;
    esac
    _dir="$GM_RELEASES/$_rel"

    gm_verify_staged "$_dir" || return 1

    mkdir -p "$GM_BIN"
    ln -sfn "$_rel" "$GM_RELEASES/.active.tmp.$$"
    mv -fh "$GM_RELEASES/.active.tmp.$$" "$GM_ACTIVE"

    # The per-binary links are relative to $GM_BIN so the whole tree can be
    # copied anywhere and still resolve within itself.
    #
    # -h here too. These point at FILES, so today `mv -f` would replace them
    # correctly — but the flag costs nothing and stops the pair from diverging
    # the moment someone points one of them at a directory.
    # LINK BY SHAPE.
    #
    # Bundle shape: `gm_kernel.app` is what a client launches on this root, and
    # `gm_kernel` points at the Mach-O inside it so the CLI is the same bytes.
    #
    # Kernel shape: `gm_kernel` points at the ONE staged Mach-O.
    #
    # Legacy shape: each name points at ITS OWN binary, because a pre-collapse
    # version has no dispatcher to select a personality — the names were the
    # artifacts. Linking them all at one file would produce three paths to a
    # binary that only knows how to be the daemon.
    #
    # `gm_daemon` is gone from both current shapes; a link left by an earlier
    # activation would name a personality the kernel no longer has.
    _staged="$(gm_staged_binaries "$_dir")"
    if [ "$_staged" != "$GM_MACHO" ] && [ "$_staged" != "gm_daemon gm_mcp gm_hook" ]; then
        for _pair in "${GM_APP_NAME}.app:releases/active/${GM_APP_NAME}.app" \
                     "${GM_MACHO}:releases/active/${_staged}"; do
            _name="${_pair%%:*}"; _target="${_pair#*:}"
            ln -sfn "$_target" "$GM_BIN/.$_name.tmp.$$"
            mv -fh "$GM_BIN/.$_name.tmp.$$" "$GM_BIN/$_name"
        done
        rm -f "$GM_BIN/gm_daemon"
    elif [ "$_staged" = "$GM_MACHO" ]; then
        for b in $GM_MACHO $GM_ENTRYPOINTS; do
            ln -sfn "releases/active/$GM_MACHO" "$GM_BIN/.$b.tmp.$$"
            mv -fh "$GM_BIN/.$b.tmp.$$" "$GM_BIN/$b"
        done
        rm -f "$GM_BIN/$GM_APP_NAME.app" "$GM_BIN/gm_daemon"
        # A rollback FROM the kernel shape TO legacy leaves a stale `gm_kernel`
        # link behind; the reverse case removes it below.
    else
        for b in $_staged; do
            ln -sfn "releases/active/$b" "$GM_BIN/.$b.tmp.$$"
            mv -fh "$GM_BIN/.$b.tmp.$$" "$GM_BIN/$b"
        done
        # No dispatcher in this version, so a `gm_kernel` name would resolve to
        # nothing. Remove it rather than leave a dangling link that `-x` reports
        # as absent in a confusing way.
        rm -f "$GM_BIN/$GM_MACHO"
    fi

    # A failed or interrupted activation can leave a temp link behind inside a
    # version directory. Swept here rather than left to accumulate.
    rm -f "$GM_RELEASES"/*/*/.active.tmp.* "$GM_RELEASES"/.active.tmp.* 2>/dev/null || true

    printf '%s\n' "$_version" > "$GM_VERSION_STAMP"

    # curl does not set com.apple.quarantine the way a browser does, but a
    # hand-placed tarball can carry it, and a quarantined binary fails at exec
    # with a dialog no hook can surface.
    xattr -dr com.apple.quarantine "$_dir" 2>/dev/null || true

    echo "[GMB] active: $_version  ($_rel)"
    return 0
}

# gm_installed_version — the active version string, or `none`.
gm_installed_version() {
    if [ -f "$GM_VERSION_STAMP" ]; then cat "$GM_VERSION_STAMP"; else echo none; fi
}

# gm_kernel_live — true when the pidfile names a live owner.
#
# Checked before every SHUTDOWN: `gm_kernel hook call` autostarts, so a SHUTDOWN
# sent to a root with nothing running would LAUNCH the app only to quit it.
gm_kernel_live() {
    _owner="$(head -1 "$GM_FS_ROOT/daemon.pid" 2>/dev/null | tr -d '[:space:]')"
    [ -n "$_owner" ] && kill -0 "$_owner" 2>/dev/null
}

# gm_send_shutdown — SHUTDOWN to THIS root's kernel, never another's.
#
# GM_FS_ROOT is passed EXPLICITLY. Callers set it as a plain shell variable, and a
# bare Mach-O CLI with no bundle and no exported root resolves ~/gmfs — so a
# Debug build's seed would stop the PRODUCTION app.
gm_send_shutdown() {
    GM_FS_ROOT="$GM_FS_ROOT" "$GM_BIN/$GM_MACHO" hook call SHUTDOWN --json '{}' >/dev/null 2>&1 || true
}

# gm_retire_daemon — best-effort shutdown so the next client launches the
# newly activated build. SHUTDOWN asks the hosting app to quit; a running app
# holds its own inodes and would go on serving the OLD build, which presents as
# an install that silently did nothing.
gm_retire_daemon() {
    [ -x "$GM_BIN/$GM_MACHO" ] || return 0
    gm_kernel_live || return 0
    gm_send_shutdown
    echo "[GMB] retired the running kernel — the next client call launches the new build"
}

# gm_stop_kernel_and_wait — SHUTDOWN, then WAIT for the lock to actually free.
#
# ── THE CIRCULARITY THIS EXISTS TO BREAK ────────────────────────────────────
#
# `gm_install_app` refuses while the app is running, because replacing a live
# bundle corrupts it in ways that surface later as a crash rather than here as an
# error. That refusal was harmless when the writer was a separate process: the
# daemon hot-swapped by symlink and the next client autostarted it.
#
# After the collapse, "the app is running" and "the writer is running" are ONE
# STATEMENT, and a menu-bar-resident kernel is always running. So every upgrade
# now needs the writer stopped FIRST — which is why this is called before
# `gm_install_app` rather than after activation, where the old `gm_retire_daemon`
# sat.
#
# The WAIT is the load-bearing half. `SHUTDOWN` returns as soon as the verb is
# accepted, but the kernel then drains its queue, checkpoints the WAL and
# releases the flock. Firing and continuing races the install: `gm_install_app`
# would see a still-running app and refuse, and the upgrade would fail on a
# perfectly healthy machine. Polling the lock rather than the process is what
# makes this correct — the lock is what the next writer actually needs.
gm_stop_kernel_and_wait() {
    _timeout="${1:-5}"
    [ -x "$GM_BIN/$GM_MACHO" ] || return 0

    # Nothing running means nothing to stop; not an error, and no SHUTDOWN, which
    # would launch the app only to quit it.
    gm_kernel_live || return 0
    _owner="$(head -1 "$GM_FS_ROOT/daemon.pid" 2>/dev/null | tr -d '[:space:]')"
    gm_send_shutdown

    # POLL THE OWNER PROCESS, NEVER A VERB.
    #
    # The obvious probe — `gm_hook call PING` — is WRONG here, and wrong in a way
    # that inverts this function. `gm_hook call` builds a `DaemonClient()` whose
    # `autostart` defaults to TRUE, so a PING that finds nothing listening
    # LAUNCHES THE APP. This loop would then observe that it answers and time out
    # — leaving a freshly-launched writer running and `gm_install_app` refusing,
    # the exact failure the reordering exists to prevent.
    #
    # The owner pid, not the pidfile: the app unlinks the pidfile during its
    # ordered quit, a moment before the process (and its open bundle) is gone,
    # and replacing the bundle needs the process gone.
    _waited=0
    while [ "$_waited" -lt "$((_timeout * 10))" ]; do
        if ! kill -0 "$_owner" 2>/dev/null; then
            [ "$_waited" -gt 0 ] && echo "[GMB] kernel stopped after $((_waited / 10)).$((_waited % 10))s"
            return 0
        fi
        sleep 0.1
        _waited=$((_waited + 1))
    done

    echo "[GMB] WARN: the kernel still answers after ${_timeout}s — the app install may refuse." >&2
    echo "[GMB]       Quit GM Kernel from its menu bar and re-run." >&2
    return 0
}

# gm_retire_legacy_app — remove a GMVibes.app THIS library installed.
#
# The bundle was renamed GMVibes.app -> gm_kernel.app, so an upgraded machine can
# end up holding both. That is not merely untidy: they share a bundle identifier
# (deliberately — see GM_APP_NAME), so LaunchServices has two candidates for one
# id, and the same-bundle-id check that lets a second copy recognise the first
# stops meaning what it says.
#
# Gated on all THREE conditions. It never touches an app we did not install, and
# never one that is running.
gm_retire_legacy_app() {
    _legacy="$GM_APP_DEST/GMVibes.app"
    [ -d "$_legacy" ] || return 0
    if pgrep -x "GMVibes" >/dev/null 2>&1; then
        echo "[GMB] WARN: GMVibes.app is still running — leaving it in place. Quit it and re-run." >&2
        return 0
    fi
    _id="$(defaults read "$_legacy/Contents/Info.plist" CFBundleIdentifier 2>/dev/null || echo "")"
    if [ "$_id" != "rube.GMVibes" ]; then
        echo "[GMB] leaving $_legacy alone — bundle id '$_id' is not ours"
        return 0
    fi
    rm -rf "$_legacy"
    echo "[GMB] removed the superseded $_legacy"
}

# ── The app ──────────────────────────────────────────────────────────────────

# gm_app_dmg <version> — the staged path for a version's DMG. Printed, not
# created; the caller makes the directory when it actually has bytes.
gm_app_dmg() {
    printf '%s\n' "$GM_APP_DOWNLOADS/$1/$GM_APP_NAME-$1.dmg"
}

# gm_installed_app_version — the version of the app ACTUALLY on disk, or `none`.
#
# Read from the installed bundle's Info.plist rather than from our own stamp
# file. The stamp records what this library last installed; the bundle records
# what is there now, and those differ the moment someone drags a build in by
# hand. The question every caller is really asking is the second one.
gm_installed_app_version() {
    _plist="$GM_APP_DEST/$GM_APP_NAME.app/Contents/Info.plist"
    if [ -f "$_plist" ]; then
        defaults read "$_plist" CFBundleShortVersionString 2>/dev/null || echo unknown
    else
        echo none
    fi
}

# gm_app_is_running — true if the app is up.
#
# Replacing a running bundle is the app-shaped version of the in-place-overwrite
# trap documented at the top of this file: the running process keeps its open
# inodes, the on-disk bundle becomes a mixture of two versions, and the symptom
# is a crash on the next window it opens rather than an error here.
gm_app_is_running() {
    # MATCHED BY BUNDLE PATH, NOT BY PROCESS NAME.
    #
    # `pgrep -x gm_kernel` looks right and is wrong: the app's executable and the
    # CLI share that name. A `gm_kernel hook` running in a terminal would make
    # this report the APP as running, `gm_install_app` would refuse, and the
    # upgrade would fail on a machine where no app is open at all.
    #
    # The bundle path is unambiguous — only a process launched from inside the
    # .app carries it — and the legacy name is still checked so an upgrade from a
    # machine running the old bundle is caught too.
    pgrep -f "$GM_APP_DEST/$GM_APP_NAME.app/Contents/MacOS/" >/dev/null 2>&1 && return 0
    pgrep -f "$GM_APP_DEST/$GM_APP_NAME_LEGACY.app/Contents/MacOS/" >/dev/null 2>&1 && return 0
    return 1
}

# gm_install_app <dmg> <version> — mount, copy out, swap into place.
#
# THE ONE WRITE OUTSIDE $GM_FS_ROOT in this library, and deliberately its own
# function so that is visible at the call site.
#
# The swap is move-aside-then-move-in, never a copy over the top: see the
# SIGKILL note at the top of this file, which applies to the app's Mach-O just
# as it does to the daemon's. The staging copy is made INSIDE the destination
# directory so the final rename is same-filesystem and effectively atomic — a
# copy straight from the mounted image would cross devices and leave a
# half-written bundle if it failed midway.
gm_install_app() {
    _dmg="$1"; _app_version="$2"
    _app="$GM_APP_DEST/$GM_APP_NAME.app"

    [ -f "$_dmg" ] || { echo "[GMB] ERROR: no DMG at $_dmg" >&2; return 1; }

    if gm_app_is_running; then
        echo "[GMB] ERROR: $GM_APP_NAME is running — quit it and re-run." >&2
        echo "       Replacing a running app bundle corrupts it in ways that surface later." >&2
        return 1
    fi

    if [ ! -d "$GM_APP_DEST" ] || [ ! -w "$GM_APP_DEST" ]; then
        echo "[GMB] ERROR: $GM_APP_DEST is not writable." >&2
        echo "       Install elsewhere with: GM_APP_DEST=\"\$HOME/Applications\"" >&2
        return 1
    fi

    _mnt="$(mktemp -d "${TMPDIR:-/tmp}/gm-dmg.XXXXXX")"
    if ! hdiutil attach "$_dmg" -nobrowse -readonly -quiet -mountpoint "$_mnt" >/dev/null 2>&1; then
        rmdir "$_mnt" 2>/dev/null || true
        echo "[GMB] ERROR: could not mount $_dmg" >&2
        return 1
    fi

    # EITHER BUNDLE NAME. A DMG built before the rename contains GMVibes.app; one
    # built after contains gm_kernel.app. Both install to $GM_APP_NAME.app, so a
    # machine ends up with one bundle under the current name regardless of which
    # release it came from.
    _src="$_mnt/$GM_APP_NAME.app"
    if [ ! -d "$_src" ] && [ -d "$_mnt/$GM_APP_NAME_LEGACY.app" ]; then
        _src="$_mnt/$GM_APP_NAME_LEGACY.app"
        echo "[GMB] $(basename "$_dmg") predates the kernel rename — installing $GM_APP_NAME_LEGACY.app as $GM_APP_NAME.app"
    fi
    _new="$GM_APP_DEST/.$GM_APP_NAME.new.$$"
    _old="$GM_APP_DEST/.$GM_APP_NAME.old.$$"
    _rc=0

    if [ ! -d "$_src" ]; then
        echo "[GMB] ERROR: $_dmg contains neither $GM_APP_NAME.app nor $GM_APP_NAME_LEGACY.app" >&2
        _rc=1
    else
        rm -rf "$_new"
        # ditto, not cp -R: it preserves the bundle's extended attributes and
        # resource forks, and a code signature does not survive without them.
        ditto "$_src" "$_new" || _rc=1
    fi

    hdiutil detach "$_mnt" -quiet >/dev/null 2>&1 || hdiutil detach "$_mnt" -force -quiet >/dev/null 2>&1 || true
    rmdir "$_mnt" 2>/dev/null || true

    if [ "$_rc" -ne 0 ]; then
        rm -rf "$_new"
        return 1
    fi

    # A DMG fetched with curl can carry com.apple.quarantine, and a quarantined
    # app opens a Gatekeeper dialog rather than launching. Cleared on the staged
    # copy, before it becomes the live bundle.
    xattr -dr com.apple.quarantine "$_new" 2>/dev/null || true

    rm -rf "$_old"
    if [ -d "$_app" ]; then
        mv "$_app" "$_old" || { rm -rf "$_new"; echo "[GMB] ERROR: could not move the existing app aside" >&2; return 1; }
    fi
    if ! mv "$_new" "$_app"; then
        # Put the old one back rather than leaving the machine with no app.
        [ -d "$_old" ] && mv "$_old" "$_app"
        rm -rf "$_new"
        echo "[GMB] ERROR: could not move the new app into place" >&2
        return 1
    fi
    rm -rf "$_old"

    mkdir -p "$GM_APPS"
    printf '%s\n' "$_app_version" > "$GM_APP_VERSION_STAMP"
    echo "[GMB] $GM_APP_NAME $_app_version -> $_app"
    return 0
}

# gm_install_app_bundle <app> — swap a locally built bundle into $GM_APP_DEST.
#
# The production kernel is launched from $GM_APP_DEST by path, so a local build
# that is not installed leaves the OLD app answering the NEW hooks: each newer client
# asks it to quit, relaunches the same old app, and does it again. The swap is
# gm_install_app's move-aside-then-move-in, without the DMG.
gm_install_app_bundle() {
    _src="$1"
    _app="$GM_APP_DEST/$GM_APP_NAME.app"
    [ -d "$_src" ] || { echo "[GMB] ERROR: no app bundle at $_src" >&2; return 1; }
    if gm_app_is_running; then
        echo "[GMB] ERROR: $GM_APP_NAME is running — quit it and re-run." >&2
        return 1
    fi
    if [ ! -d "$GM_APP_DEST" ] || [ ! -w "$GM_APP_DEST" ]; then
        echo "[GMB] ERROR: $GM_APP_DEST is not writable." >&2
        return 1
    fi
    _new="$GM_APP_DEST/.$GM_APP_NAME.new.$$"
    _old="$GM_APP_DEST/.$GM_APP_NAME.old.$$"
    rm -rf "$_new" "$_old"
    ditto "$_src" "$_new" || { rm -rf "$_new"; return 1; }
    if [ -d "$_app" ]; then
        mv "$_app" "$_old" || { rm -rf "$_new"; echo "[GMB] ERROR: could not move the existing app aside" >&2; return 1; }
    fi
    if ! mv "$_new" "$_app"; then
        [ -d "$_old" ] && mv "$_old" "$_app"
        rm -rf "$_new"
        echo "[GMB] ERROR: could not move the new app into place" >&2
        return 1
    fi
    rm -rf "$_old"
    echo "[GMB] installed $_src -> $_app"
    return 0
}
