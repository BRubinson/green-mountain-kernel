import Foundation

extension GmBridgeScript {

    // The three scripts that ship as files, embedded verbatim: the installer pair,
    // which runs BEFORE any binary exists and so cannot become kernel subcommands,
    // plus the SessionStart provisioner.
    //
    // Extended delimiters (`#"""` … `"""#`) keep the bash unescaped — backslashes
    // and `\(` are literal inside them, and the delimiter grows a `#` if a body
    // ever contains the terminator. `gm_releases.sh` is the authored `gmk/scripts/`
    // copy; emitting the plugin's from this constant makes drift unrepresentable.

    public static let sessionStartupBody = #"""
        #!/bin/bash

        # GM-CDE SessionStart bootstrap. Four jobs only: confirm we're in a git repo,
        # find the right gm_hook binary, and hand the hook payload on stdin to
        # `gm_hook context ensure`. Everything else — identity, paths, env
        # emission, the artifact home, dope boot sync, the pen sheet — is owned by
        # that binary (`context ensure` + `context env`). This script computes
        # NOTHING the daemon computes, and it does not read the payload: the session
        # uuid inside it is sliced out in Swift, so no jq is on this path either.
        #
        # Anything outside a git repo: silent exit with no GM vars set.

        # --- 0. Git-repo guard, and the repo root ------------------------------------
        #
        # REPO_ROOT is REQUIRED, not a convenience. Both `gm_hook` invocations below run
        # inside `(cd "$REPO_ROOT" && …)`, and the binary derives the project, instance
        # and session from its own working directory. An empty value makes that `cd ""`,
        # which SILENTLY SUCCEEDS and leaves the hook in whatever directory the harness
        # happened to hand it — so a session would be filed under the wrong repo, or none,
        # with no error anywhere.
        #
        # It is assigned HERE, beside the guard that proves a repo exists, rather than
        # further down: it previously lived inside the snapshot-marker block, and deleting
        # that block took the assignment with it while leaving both uses behind.
        if ! git rev-parse --git-dir > /dev/null 2>&1; then
            exit 0
        fi
        REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
        [ -n "$REPO_ROOT" ] || exit 0

        # --- 0b. The hook payload ---------------------------------------------------
        # Held verbatim and piped into `gm_hook context ensure --hook-payload`, which pins
        # its session_id to the ensured session in claude_session_binding. That
        # binding is what every later hook write resolves its gm session through, so
        # a SessionStart that drops the payload leaves the whole capture surface
        # writing nothing. `[ -t 0 ]` keeps a hand-run of this script off a blocking
        # read — under the harness stdin is always a pipe.
        payload=""
        [ -t 0 ] || payload="$(cat 2>/dev/null)"

        # --- 1. Plugin root from this script's location -----------------------------
        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        GM_PLUGIN_DIR="$(dirname "$SCRIPT_DIR")"

        # --- 2. Locate gm_hook ------------------------------------------------------
        HOOK_BIN="${GM_FS_ROOT:-$HOME/gmfs}/bin/gm_hook"
        if [ ! -x "$HOOK_BIN" ]; then
            echo "[GMB] gm_hook binary missing at $HOOK_BIN — run 'bash $GM_PLUGIN_DIR/scripts/install_gm.sh', then restart the session"
            exit 0
        fi

        # --- 3. Rows + binding + artifact home + dope boot sync (stderr = notices) --
        warnings=$( (cd "$REPO_ROOT" && printf '%s' "$payload" \
            | "$HOOK_BIN" context ensure --hook-payload >/dev/null) 2>&1 )
        if [ $? -ne 0 ]; then
            warnings="$warnings
        [GMB] daemon unavailable — context not ensured (run 'bash $GM_PLUGIN_DIR/scripts/install_gm.sh' or /gm_daemon, then 'gm_hook context ensure')"
        fi

        # --- 4. Cheatsheet into hook stdout (automatic; the agent never runs it) ----
        "$HOOK_BIN" pen-sheet 2>/dev/null || true

        # --- 5. Env contract → $CLAUDE_ENV_FILE (stdout), warnings → context --------
        if [ -n "$CLAUDE_ENV_FILE" ]; then
            warnings="$warnings
        $( (cd "$REPO_ROOT" && "$HOOK_BIN" context env --plugin-root "$GM_PLUGIN_DIR") 2>&1 >> "$CLAUDE_ENV_FILE" )"
        fi

        if [ -n "$(printf '%s' "$warnings" | tr -d '[:space:]')" ]; then
            printf '%s\n' "$warnings"
        fi

        exit 0
        """#

    public static let installBody = #"""
        #!/bin/bash
        #
        # install_gm.sh — THE FRONT DOOR for everyone who is not editing the sources.
        #
        # Fetches the newest published `gm_kernel-v*` release, verifies every checksum,
        # stages it under the release store, activates the binaries and installs the app.
        #
        # ── IT UPGRADES THE WHOLE SYSTEM, NOT HALF OF IT ─────────────────────────────
        #
        # One release carries the three binaries AND the GMVibes DMG at one version, so
        # one command moves a machine forward. This used to be impossible: the app was
        # published on its own `gmvibes-v*` tag with its own version number by a script
        # that shared no code with the publisher, and nothing here fetched it — a user
        # who ran this got a new daemon and kept whatever app they had.
        #
        # The DMG is staged under $GM_FS_ROOT like everything else and installed from
        # there. /Applications is the one write outside the root; it is what makes a
        # macOS app launchable, it is confined to gm_install_app in the shared library,
        # and --no-app turns it off.
        #
        # ── WHY THIS LIVES IN THE PLUGIN AND NOT IN gmk/scripts ──────────────────────
        #
        # Because of who runs it. Somebody with a CHECKOUT builds: they have the sources
        # and `rebuild_local.sh` is strictly better for them. Somebody with only the
        # PLUGIN downloads — and the plugin cache is all they have.
        #
        # That is not a style preference, it is a hard constraint that was measured. A
        # marketplace install materialises `plugins/gmcc/` alone, with no `gmk/` beside
        # it and no git metadata of its own. An installer that tried to climb out of the
        # cache to find the repo would run `git rev-parse --show-toplevel` and, on a
        # machine whose $HOME is itself a git repository, get a confident WRONG answer
        # pointing at the home directory. There is no reliable climb, so this script does
        # not attempt one: it needs no repo, reads no VERSION file from disk, and asks
        # GitHub what the newest release is.
        #
        # ── WHY "LATEST" RATHER THAN A PIN ───────────────────────────────────────────
        #
        # The plugin carries no runtime version. If it did, that number would be a second
        # thing to bump on every release and it could silently disagree with gmk/VERSION.
        # Asking for the newest `daemon-v*` release means the plugin cannot drift from
        # what was actually published.
        #
        # TAG NAMESPACE MATTERS HERE. The repo's history contains more than one kind of
        # release tag, so GitHub's own "latest release" is the wrong question — it would
        # happily hand back an app-only release cut under the retired `gmvibes-v*`
        # namespace. This filters by prefix, newest `gm_kernel-v*` first, and falls back
        # to the retired `daemon-v*` namespace so a machine pointed at an older release
        # still installs rather than being told nothing is published.
        #
        # Usage:
        #   install_gm.sh                   # install/upgrade binaries + app
        #   install_gm.sh --check           # report only; exit 1 if an install is needed
        #   install_gm.sh --force           # reinstall even if that version is active
        #   install_gm.sh --version 50.0.1  # install one specific version
        #   install_gm.sh --no-app          # binaries only; never touch /Applications
        #   install_gm.sh --app             # the app only; leave the binaries alone
        #
        # Env:
        #   GM_FS_ROOT                      # the one filesystem root (default: $HOME/gmfs)
        #   GM_APP_DEST                     # where the app goes (default: /Applications)
        #   GM_DAEMON_RELEASE_REPO          # owner/name to fetch from

        set -e

        SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
        # shellcheck source=gm_releases.sh
        . "$SCRIPT_DIR/gm_releases.sh"

        RELEASE_REPO="${GM_DAEMON_RELEASE_REPO:-BRubinson/green-mountain-kernel}"
        API="https://api.github.com/repos/$RELEASE_REPO"

        MODE="install"
        WANT=""
        DO_BINARIES=1
        DO_APP=1
        while [ $# -gt 0 ]; do
            case "$1" in
                --check)   MODE="check" ;;
                --force)   MODE="force" ;;
                --version) shift; WANT="$1"; [ -n "$WANT" ] || { echo "[GMB] --version needs a value" >&2; exit 2; } ;;
                --no-app)  DO_APP=0 ;;
                --app)     DO_BINARIES=0 ;;
                "") ;;
                *) echo "[GMB] install_gm.sh: unknown flag $1" >&2; exit 2 ;;
            esac
            shift
        done

        gm_resolve_fs_root
        INSTALLED="$(gm_installed_version)"

        # ── Resolve which version to install ─────────────────────────────────────────
        #
        # Parsed with grep/sed rather than jq: jq is not a dependency anywhere else on
        # this path and an installer that fails on a missing JSON parser is an installer
        # that fails for the exact users it exists to serve. The releases list comes back
        # newest-first, so the first daemon-v tag in it is the newest daemon release.
        RELEASES_JSON=""
        fetch_releases() {
            [ -n "$RELEASES_JSON" ] && return 0
            RELEASES_JSON="$(curl -fsSL --retry 2 --connect-timeout 15 "$API/releases?per_page=100" 2>/dev/null || true)"
            [ -n "$RELEASES_JSON" ]
        }

        # The tag prefix that actually produced the version being installed. It decides
        # whether a DMG can be expected in the release at all: the retired namespace
        # predates the unified release and carries binaries only.
        #
        # Printed as `<prefix> <version>` rather than assigned to a global, because
        # resolve_latest is called in a `$(...)` subshell and a variable it set there
        # would not survive the return. That is the kind of bug that shows up as an
        # installer confidently looking for a DMG in a release that has none.
        resolve_latest() {
            fetch_releases || return 1
            for _prefix in "$GM_TAG_PREFIX" "$GM_LEGACY_TAG_PREFIX"; do
                _v="$(printf '%s' "$RELEASES_JSON" \
                    | grep -o "\"tag_name\"[[:space:]]*:[[:space:]]*\"$_prefix[^\"]*\"" \
                    | head -1 \
                    | sed -e "s/.*\"\($_prefix[^\"]*\)\"/\1/" -e "s/^$_prefix//")"
                if [ -n "$_v" ]; then
                    printf '%s %s\n' "$_prefix" "$_v"
                    return 0
                fi
            done
            return 1
        }

        FOUND_PREFIX="$GM_TAG_PREFIX"
        if [ -n "$WANT" ]; then
            VERSION="$WANT"
        else
            echo "[GMB] asking $RELEASE_REPO for the newest release..."
            RESOLVED="$(resolve_latest || true)"
            # Split with `case`, not `[ x ] && y` — under `set -e` a trailing test that
            # evaluates false takes the whole script down, and here the false branch is
            # the SUCCESS path.
            VERSION=""
            case "$RESOLVED" in
                *" "*)
                    FOUND_PREFIX="${RESOLVED%% *}"
                    VERSION="${RESOLVED#* }"
                    ;;
            esac
            if [ -z "$VERSION" ]; then
                cat >&2 <<EOF
        [GMB] ERROR: no published ${GM_TAG_PREFIX}* release found on $RELEASE_REPO.

              Nothing has been released yet, or the network is unreachable.

              If you have a checkout of the repository, build instead — it needs no
              release at all:

                  bash gmk/scripts/rebuild_local.sh

              Otherwise check: https://github.com/$RELEASE_REPO/releases
        EOF
                exit 1
            fi
        fi

        TAG="$FOUND_PREFIX$VERSION"
        ASSET="gm-daemon-$VERSION-macos-universal.tar.gz"
        BASE="https://github.com/$RELEASE_REPO/releases/download/$TAG"

        # ── WHICH SHAPE IS THIS RELEASE? ────────────────────────────────────────────
        #
        # Two layouts exist and both must install, because the older one is the rollback
        # target for every machine already running:
        #
        #   current  ONE asset, the DMG. The app carries the CLI at Contents/Helpers, so
        #            the binaries are EXTRACTED FROM THE APP rather than downloaded
        #            separately. One artifact, used twice, which is what stops the
        #            installed binary and the installed app from ever disagreeing.
        #
        #   legacy   the retired `daemon-v*` namespace: a tarball, and no DMG at all.
        #            Those releases cannot be rewritten, so the tarball path stays for
        #            them — and ONLY for them. Deleting it would make the entire
        #            back-catalogue uninstallable.
        #
        # Keyed on the TAG PREFIX rather than on version arithmetic: the prefix is what
        # the release actually was published under, and comparing version numbers to
        # guess a layout is how an installer ends up confidently fetching an asset that
        # was never uploaded.
        if [ "$FOUND_PREFIX" = "$GM_LEGACY_TAG_PREFIX" ]; then
            LEGACY_NAMESPACE=1
        else
            LEGACY_NAMESPACE=0
        fi

        # THE DMG ASSET NAME IS RESOLVED, NOT ASSUMED.
        #
        # The bundle was renamed GMVibes -> gm_kernel when the app became the kernel
        # host, so the asset name changed with it. Every DMG PUBLISHED BEFORE that still
        # carries the old name, and those releases cannot be rewritten — so an installer
        # that only ever asks for `gm_kernel-<v>.dmg` 404s on its entire back-catalogue,
        # including the release that was newest the day this landed.
        #
        # Asked of the release itself rather than inferred from the version number: a
        # version comparison would need a cutover constant that is wrong the moment
        # anyone re-publishes, and `gh` already knows the answer. The curl fallback keeps
        # a machine without `gh` working, and defaults to the CURRENT name so a fresh
        # install does not pay for the compatibility path.
        resolve_dmg_asset() {
            _new="$GM_APP_NAME-$VERSION.dmg"
            _old="$GM_APP_NAME_LEGACY-$VERSION.dmg"
            if command -v gh >/dev/null 2>&1; then
                _names="$(gh release view "$TAG" --repo "$RELEASE_REPO" --json assets \
                            -q '.assets[].name' 2>/dev/null || true)"
                if [ -n "$_names" ]; then
                    printf '%s\n' "$_names" | grep -qx "$_new" && { printf '%s' "$_new"; return 0; }
                    printf '%s\n' "$_names" | grep -qx "$_old" && { printf '%s' "$_old"; return 0; }
                fi
            fi
            # No gh, or it told us nothing: probe the new name, fall back to the old.
            if curl -fsI --connect-timeout 10 "$BASE/$_new" >/dev/null 2>&1; then
                printf '%s' "$_new"
            elif curl -fsI --connect-timeout 10 "$BASE/$_old" >/dev/null 2>&1; then
                printf '%s' "$_old"
            else
                printf '%s' "$_new"
            fi
        }
        DMG_ASSET="$(resolve_dmg_asset)"

        # A release under the retired namespace contains binaries only. Asking it for a
        # DMG would be a guaranteed 404 dressed up as a network problem.
        if [ "$FOUND_PREFIX" != "$GM_TAG_PREFIX" ] && [ "$DO_APP" -eq 1 ]; then
            echo "[GMB] $TAG predates the unified release — it has no app. Binaries only."
            DO_APP=0
            DO_BINARIES=1
        fi

        # ── Up-to-date checks ────────────────────────────────────────────────────────
        #
        # The binaries and the app are checked SEPARATELY even though they share a
        # version. They can legitimately disagree — the app gets replaced by hand, an
        # earlier run used --no-app, /Applications was not writable that day — and a
        # single "is v$VERSION installed" question would answer yes while half the
        # system sat one release behind. Each side decides for itself whether it has
        # work to do, and the script exits early only when NEITHER does.
        have_all() { for b in $GM_BINARIES; do [ -x "$GM_BIN/$b" ] || return 1; done; return 0; }

        APP_INSTALLED="$(gm_installed_app_version)"
        BIN_WORK=1
        APP_WORK=1

        [ "$DO_BINARIES" -eq 1 ] || BIN_WORK=0
        [ "$DO_APP" -eq 1 ] || APP_WORK=0

        if [ "$MODE" != "force" ]; then
            if [ "$BIN_WORK" -eq 1 ]; then
                case "$INSTALLED" in
                    *-BETA)
                        # A locally built, locally staged binary. A download must never
                        # silently replace work someone is in the middle of testing.
                        if have_all; then
                            echo "[GMB] $INSTALLED is active (a local build) — leaving the binaries alone"
                            echo "      rebuild:            bash gmk/scripts/rebuild_local.sh"
                            echo "      switch to v$VERSION: bash $SCRIPT_DIR/install_gm.sh --force"
                            BIN_WORK=0
                        fi
                        ;;
                    "$VERSION")
                        if have_all; then
                            echo "[GMB] binaries v$VERSION already active at $GM_BIN"
                            BIN_WORK=0
                        fi
                        ;;
                esac
            fi
            if [ "$APP_WORK" -eq 1 ] && [ "$APP_INSTALLED" = "$VERSION" ]; then
                echo "[GMB] $GM_APP_NAME $VERSION already installed at $GM_APP_DEST"
                APP_WORK=0
            fi
        fi

        if [ "$MODE" = "check" ]; then
            if [ "$INSTALLED" = "none" ]; then
                echo "[GMB] binaries not installed — newest published is v$VERSION"
            else
                echo "[GMB] binaries $INSTALLED active, newest published is v$VERSION"
            fi
            echo "[GMB] $GM_APP_NAME $APP_INSTALLED installed, newest published is $VERSION"
            if [ "$BIN_WORK" -eq 0 ] && [ "$APP_WORK" -eq 0 ]; then
                echo "      everything is current"
                exit 0
            fi
            echo "      run: bash $SCRIPT_DIR/install_gm.sh"
            exit 1
        fi

        if [ "$BIN_WORK" -eq 0 ] && [ "$APP_WORK" -eq 0 ]; then
            exit 0
        fi

        # ── Stop the writer FIRST ────────────────────────────────────────────────────
        #
        # This moved UP, from after activation to before any work, and the move is the
        # whole fix for the upgrade circularity. `gm_install_app` refuses while the app
        # is running; the app is now the writer and is menu-bar-resident, so it is always
        # running. Retiring after activation — where `gm_retire_daemon` used to sit —
        # would mean the app install had already refused by the time we stopped anything.
        #
        # Once, here, rather than once per section: the two sections used to each retire
        # the daemon, which was harmless when it was a separate process that autostarted
        # again. Now it would terminate a user's windows twice in one install.
        gm_stop_kernel_and_wait 3

        TMP="$(mktemp -d "${TMPDIR:-/tmp}/gm-install.XXXXXX")"
        trap 'rm -rf "$TMP"' EXIT

        # fetch_asset <name> — download an asset and its sidecar into $TMP, then verify.
        #
        # Checksum BEFORE anything is unpacked or mounted. The sidecar is written as
        # `<hash>  <filename>`, so it is verified from the directory where that filename
        # resolves. Mounting an unverified DMG is the same class of mistake as unpacking
        # an unverified tarball, and the app is the asset a user actually double-clicks.
        fetch_asset() {
            _name="$1"
            if ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$_name" "$BASE/$_name" \
               || ! curl -fsSL --retry 2 --connect-timeout 15 -o "$TMP/$_name.sha256" "$BASE/$_name.sha256"; then
                cat >&2 <<EOF
        [GMB] ERROR: could not download $BASE/$_name

              The release exists but the asset does not, or the network is unreachable.
              With a checkout, build instead: bash gmk/scripts/rebuild_local.sh
        EOF
                return 1
            fi
            if ! ( cd "$TMP" && shasum -a 256 -c "$_name.sha256" >/dev/null 2>&1 ); then
                echo "[GMB] ERROR: checksum mismatch on $_name — refusing to install" >&2
                echo "       expected: $(cut -d' ' -f1 < "$TMP/$_name.sha256")" >&2
                echo "       actual:   $(shasum -a 256 "$TMP/$_name" | cut -d' ' -f1)" >&2
                return 1
            fi
            return 0
        }

        # ── THE DMG IS THE RELEASE, so it is fetched before anything needs it ───────
        #
        # Both halves come out of this one file: the app is installed from it, and the
        # CLI is EXTRACTED FROM THE APP INSIDE IT. That is what makes the binary in
        # $GM_BIN provably the same build as the app beside it — not two artifacts that
        # agree, but one artifact used twice.
        #
        # Staged under $GM_FS_ROOT first and used FROM the store, never straight out of
        # $TMP, so a re-install or a rollback to this version needs no network.
        STAGED_DMG=""
        if [ "$LEGACY_NAMESPACE" -eq 0 ]; then
            STAGED_DMG="$(gm_app_dmg "$VERSION")"
            if [ ! -f "$STAGED_DMG" ] || [ "$MODE" = "force" ]; then
                echo "[GMB] fetching $TAG from $RELEASE_REPO..."
                fetch_asset "$DMG_ASSET" || exit 1
                mkdir -p "$(dirname "$STAGED_DMG")"
                cp "$TMP/$DMG_ASSET" "$STAGED_DMG"
            else
                echo "[GMB] $VERSION is already in the store — using it without a download"
            fi
        fi

        # ── Binaries ─────────────────────────────────────────────────────────────────
        if [ "$BIN_WORK" -eq 1 ]; then
            # A version already in the store is re-activated rather than re-extracted.
            # This is what makes rolling between versions cheap and offline.
            if [ -d "$GM_DOWNLOADS/$VERSION" ] && [ "$MODE" != "force" ] \
               && gm_verify_staged "$GM_DOWNLOADS/$VERSION" 2>/dev/null; then
                echo "[GMB] binaries v$VERSION are already in the store — activating without a download"
                gm_activate downloads "$VERSION"
            elif [ "$LEGACY_NAMESPACE" -eq 1 ]; then
                # ── THE BACK-CATALOGUE PATH, and it is not optional ─────────────────
                #
                # Releases in the retired `daemon-v*` namespace carry a TARBALL and no
                # DMG. Deleting this branch along with the tarball would make every
                # release published before the cutover uninstallable — which turns a
                # rollback, the thing the release store exists for, into a dead end.
                echo "[GMB] fetching $TAG binaries from $RELEASE_REPO (legacy tarball)..."
                fetch_asset "$ASSET" || exit 1
                tar -xzf "$TMP/$ASSET" -C "$TMP"

                # Either shape: a post-collapse tarball holds the one Mach-O; a
                # pre-collapse one holds three binaries, and back then the NAMES were
                # the artifacts.
                if [ -f "$TMP/$GM_MACHO" ]; then
                    _staged="$GM_MACHO"
                elif [ -f "$TMP/gm_daemon" ]; then
                    echo "[GMB] $ASSET predates the kernel collapse — installing its three binaries as-is"
                    _staged="gm_daemon gm_mcp gm_hook"
                else
                    echo "[GMB] ERROR: $ASSET contains neither $GM_MACHO nor gm_daemon" >&2
                    exit 1
                fi
                for b in $_staged; do
                    [ -f "$TMP/$b" ] || {
                        echo "[GMB] ERROR: $ASSET does not contain $b — refusing a partial install" >&2
                        exit 1; }
                done

                DL="$(gm_stage_dir downloads "$VERSION")"
                rm -rf "$DL"; DL="$(gm_stage_dir downloads "$VERSION")"
                for b in $_staged; do cp "$TMP/$b" "$DL/$b"; chmod +x "$DL/$b"; done
                _arch_probe="$(printf '%s\n' $_staged | head -1)"
                gm_write_manifest "$DL" "$VERSION" downloads "$TAG" "$(lipo -archs "$DL/$_arch_probe" 2>/dev/null | tr ' ' ',')"
                gm_activate downloads "$VERSION"
            else
                # ── THE CURRENT PATH: the CLI comes OUT of the app ──────────────────
                echo "[GMB] extracting the CLI from $GM_APP_NAME $VERSION..."
                _mnt="$(mktemp -d "${TMPDIR:-/tmp}/gm-cli.XXXXXX")"
                hdiutil attach "$STAGED_DMG" -nobrowse -readonly -quiet -mountpoint "$_mnt" >/dev/null 2>&1 || {
                    rmdir "$_mnt" 2>/dev/null || true
                    echo "[GMB] ERROR: could not mount $STAGED_DMG" >&2; exit 1; }

                # EITHER BUNDLE NAME, the same allowance gm_install_app makes: a DMG
                # built before the rename carries GMVibes.app.
                _app="$_mnt/$GM_APP_NAME.app"
                [ -d "$_app" ] || _app="$_mnt/$GM_APP_NAME_LEGACY.app"

                _ok=0
                if [ -x "$_app/Contents/Helpers/$GM_MACHO" ]; then
                    rm -rf "$GM_DOWNLOADS/$VERSION"
                    if gm_stage_from_bundle "$_app" downloads "$VERSION" "$TAG" >/dev/null; then
                        _ok=1
                    fi
                fi

                # DETACH BEFORE DECIDING. An early exit with the image still attached
                # leaves a mount behind that the next run cannot replace.
                hdiutil detach "$_mnt" -quiet >/dev/null 2>&1 || hdiutil detach "$_mnt" -force -quiet >/dev/null 2>&1 || true
                rmdir "$_mnt" 2>/dev/null || true

                [ "$_ok" -eq 1 ] || {
                    echo "[GMB] ERROR: $DMG_ASSET carries no $GM_MACHO at Contents/Helpers." >&2
                    echo "       It predates the one-bundle layout but is not in the legacy" >&2
                    echo "       namespace either. Install a newer version." >&2
                    exit 1; }

                gm_activate downloads "$VERSION"
            fi
            echo "[GMB] installed binaries v$VERSION"
            echo "      $GM_BIN/$GM_MACHO -> releases/downloads/$VERSION/$GM_MACHO"
            echo "      entry points: $(for b in $GM_ENTRYPOINTS; do printf '%s ' "$b"; done)-> $GM_MACHO"
        fi

        # ── The app ──────────────────────────────────────────────────────────────────
        if [ "$APP_WORK" -eq 1 ]; then
            # Before replacing: drop a GMVibes.app this library installed. Two bundles
            # sharing one identifier make LaunchServices ambiguous AND defeat the
            # same-bundle-id check a second copy uses to recognise the first.
            gm_retire_legacy_app

            if gm_install_app "$STAGED_DMG" "$VERSION"; then
                # `if`, not `[ ... ] && echo` — under `set -e` a trailing false test
                # ends the script, and "the app was already installed" is the common case.
                if [ "$APP_INSTALLED" = "none" ]; then
                    echo "      (first install — $GM_APP_NAME was not on this machine before)"
                fi
            else
                echo "[GMB] the app was staged at $STAGED_DMG but not installed." >&2
                echo "      Re-run when it can be replaced: bash $SCRIPT_DIR/install_gm.sh --app" >&2
                exit 1
            fi
        fi
        """#

    public static let releaseStoreBody = #"""
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
        #   ├── gm_daemon  -> releases/active/gm_daemon      RELATIVE symlinks
        #   ├── gm_mcp     -> releases/active/gm_mcp
        #   ├── gm_hook    -> releases/active/gm_hook
        #   ├── .gm_version                                  the ACTIVE version string
        #   └── releases/
        #       ├── active -> downloads/50.0.1               or local/50.0.1-BETA
        #       ├── downloads/50.0.1/{gm_daemon,gm_mcp,gm_hook,manifest.json,SHA256SUMS}
        #       └── local/50.0.1-BETA/{gm_daemon,gm_mcp,gm_hook,manifest.json,SHA256SUMS}
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

        # ── The binary contract: ONE Mach-O, THREE entry-point names ────────────────
        #
        # These were one variable when there were three binaries. They are two now
        # because the two lists mean genuinely different things, and conflating them is
        # how a staged kernel ends up with entry points that resolve to nothing:
        #
        #   GM_MACHO       what gets STAGED, hashed, lipo-checked and tarred. One file.
        #   GM_ENTRYPOINTS what gets SYMLINKED in $GM_BIN. Names, not files.
        #
        # The entry-point names are load-bearing rather than cosmetic. `hooks.json`,
        # `settings.json`, `.mcp.json` and `check_gm_stale.sh` each resolve a binary BY
        # NAME, and the kernel dispatches on `basename(argv[0])` — so the symlink name is
        # what selects the personality. A staged kernel whose symlinks are missing is not
        # a degraded install; it is a hook that cannot launch.
        # MultiCallBinaryContractTests asserts this list and the dispatcher agree.
        GM_MACHO="gm_kernel"
        GM_ENTRYPOINTS="gm_daemon gm_mcp gm_hook"

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
        # EVERY environment gets a FULL release store, not just a database. The app
        # autostarts $ROOT/bin/gm_daemon, and the hook shim exits 0 SILENTLY when its
        # binary is missing — so a root with an unpopulated bin/ does not fail loudly,
        # it simply records nothing. That is why gm_env create stages binaries rather
        # than only making directories.
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
        # So the DMG is the artifact and this is the extraction. The app carries the CLI
        # at Contents/Helpers/gm_kernel; everything downstream — the version directory,
        # the manifest, SHA256SUMS, the symlink activation, rollback by swap — is
        # UNCHANGED. Only the source of the bytes moved.
        #
        # ## Do not re-sign what comes out
        #
        # A helper copied out of a signed bundle keeps its signature, and re-signing it
        # here would replace a Developer ID signature with whatever this machine happens
        # to hold — usually nothing.
        gm_stage_from_bundle() {
            _app="$1"; _channel="$2"; _version="$3"; _sha="${4:-unknown}"
            _helper="$_app/Contents/Helpers/$GM_MACHO"

            if [ ! -x "$_helper" ]; then
                echo "[GMB] ERROR: $_app carries no Contents/Helpers/$GM_MACHO" >&2
                echo "       Nothing to stage. The bundle was built without the embed phase." >&2
                return 1
            fi

            _dir="$(gm_stage_dir "$_channel" "$_version")" || return 1
            # -p so the executable bit survives; gm_staged_binaries tests for it.
            cp -p "$_helper" "$_dir/$GM_MACHO" || return 1

            _arches="$(lipo -archs "$_dir/$GM_MACHO" 2>/dev/null | tr ' ' ',')"
            gm_write_manifest "$_dir" "$_version" "$_channel" "$_sha" "${_arches:-unknown}" || return 1

            echo "[GMB] staged $GM_MACHO [$_arches] from $_app"
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
          "entrypoints": [$(printf '"%s", ' $GM_ENTRYPOINTS | sed 's/, $//')]
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
        # TWO SHAPES COEXIST ON DISK, and that is not a transition artifact — it is the
        # permanent consequence of keeping rollback honest. A version staged before the
        # kernel collapse holds three binaries; one staged after holds a single
        # multi-call Mach-O. Both must verify and both must activate, or
        # `gm_activate local <old>-BETA` — the whole point of the store — refuses on
        # exactly the day someone needs it.
        gm_staged_binaries() {
            if [ -f "$1/$GM_MACHO" ]; then
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
                echo "[GMB] ERROR: $_dir holds neither $GM_MACHO nor gm_daemon — not a staged version" >&2
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
            # Kernel shape: every name points at the ONE staged Mach-O. `gm_kernel` gets
            # its own name so a person can invoke it directly; the three entry points get
            # theirs so argv[0] dispatch selects a personality and every command string in
            # hooks.json / .mcp.json keeps resolving.
            #
            # Legacy shape: each name points at ITS OWN binary, because a pre-collapse
            # version has no dispatcher to select a personality — the names were the
            # artifacts. Linking them all at one file would produce three paths to a
            # binary that only knows how to be the daemon.
            _staged="$(gm_staged_binaries "$_dir")"
            if [ "$_staged" = "$GM_MACHO" ]; then
                for b in $GM_MACHO $GM_ENTRYPOINTS; do
                    ln -sfn "releases/active/$GM_MACHO" "$GM_BIN/.$b.tmp.$$"
                    mv -fh "$GM_BIN/.$b.tmp.$$" "$GM_BIN/$b"
                done
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

        # gm_retire_daemon — best-effort shutdown so the next client autostarts on the
        # newly activated binary. A running daemon holds its own inode and would go on
        # serving the OLD build from a deleted-but-open file, which presents as an
        # install that silently did nothing.
        gm_retire_daemon() {
            [ -x "$GM_BIN/gm_hook" ] || return 0
            "$GM_BIN/gm_hook" call SHUTDOWN --json '{}' >/dev/null 2>&1 || true
            echo "[GMB] retired the running kernel (if any) — the next client call autostarts the new build"
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
            _timeout="${1:-3}"
            [ -x "$GM_BIN/gm_hook" ] || return 0

            # Nothing listening means nothing to stop; not an error.
            "$GM_BIN/gm_hook" call SHUTDOWN --json '{}' >/dev/null 2>&1 || true

            # POLL THE LOCK OWNER, NEVER A VERB.
            #
            # The obvious probe — `gm_hook call PING` — is WRONG here, and wrong in a way
            # that inverts this function. `gm_hook call` builds a `DaemonClient()` whose
            # `autostart` defaults to TRUE, so a PING that finds nothing listening SPAWNS
            # A KERNEL. This loop would then shut the writer down, immediately restart it
            # while checking whether it had stopped, observe that it answers, and time out
            # — leaving a freshly-spawned writer running and `gm_install_app` refusing, the
            # exact failure the reordering exists to prevent.
            #
            # The pidfile is the lock file, its first line is the owner's pid, and the
            # kernel unlinks it on the way out. Reading it starts nothing.
            _pidfile="$GM_FS_ROOT/daemon.pid"
            _waited=0
            while [ "$_waited" -lt "$((_timeout * 10))" ]; do
                # No pidfile means a clean exit already unlinked it.
                if [ ! -f "$_pidfile" ]; then
                    [ "$_waited" -gt 0 ] && echo "[GMB] kernel stopped after $((_waited / 10)).$((_waited % 10))s"
                    return 0
                fi
                # A pidfile whose owner is gone is a crash leftover, not a live writer.
                # The flock auto-released with the process, so the db is free.
                _owner="$(head -1 "$_pidfile" 2>/dev/null | tr -d '[:space:]')"
                if [ -z "$_owner" ] || ! kill -0 "$_owner" 2>/dev/null; then
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
            # headless CLI now share that name. A `gm_kernel daemon` running in a terminal
            # would make this report the APP as running, `gm_install_app` would refuse,
            # and the upgrade would fail on a machine where no app is open at all.
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
        """#
}
