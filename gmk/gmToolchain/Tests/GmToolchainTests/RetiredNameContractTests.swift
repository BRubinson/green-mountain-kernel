import XCTest

/// THE PREFIX-RETIREMENT CONTRACT, as a build failure.
///
/// The GMCC_ prefix was retired on the RUNTIME surface: three binaries
/// (`gm_daemon` / `gm_mcp` / `gm_hook`), one filesystem root (`~/gmfs`), and
/// three env vars (`GM_BOOTED` / `GM_PLUGIN_ROOT` / `GM_FS_ROOT`). A half-swept
/// rename is the failure mode this file exists to refuse: a stale name in a doc
/// tells a reader to run a binary that does not exist, and a stale name in
/// source is a path that resolves to nothing.
///
/// ════════════════════════════════════════════════════════════════════════════
/// THE SCOPING RULE — READ THIS BEFORE ADDING A PATTERN
/// ════════════════════════════════════════════════════════════════════════════
///
/// The scan covers `gmk/**`, `plugins/gmcc/**`, and the ROOT DOCS (`CLAUDE.md`,
/// `README.md`). That is the whole authored repository.
///
/// **CUTOVER IS COMPLETE, AND THE DELETION OF THE PLUGIN EXEMPTION IS WHAT SAYS
/// SO.** There used to be an `exemptPlugin` predicate here, because
/// `plugins/gmcc/` drove the user's machine through a runtime installed under
/// the old names: sweeping those files before the new binaries existed would
/// have broken every session the moment it landed. That is no longer true. The
/// plugin's launchers, hooks and docs now name `gm_hook`, `GM_FS_ROOT` and
/// `~/gmfs`, the binaries they name are the ones on disk, and so the contract
/// applies to them like everything else.
///
/// Do not reintroduce a path-based exemption for the plugin. A file that needs
/// one is a file that did not get swept.
///
/// ════════════════════════════════════════════════════════════════════════════
/// ALSO DELIBERATELY UNCHANGED — these are NOT retired and must never be flagged
/// ════════════════════════════════════════════════════════════════════════════
///
///   `plugins/gmcc/`          the plugin directory keeps its name
///   `.gmcc/`                 the in-repo DOPE directory keeps its name
///   `gmcc:`                  the command/skill namespace keeps its name
///   `mcp__plugin_gmcc_pen__`  the pen MCP server keeps its name
///   `gmcc`                   the dope scope code keeps its name
///   `gmcc_diagram_path`      a SHIPPED SCHEMA COLUMN — renaming it needs its
///                            own migration, and m0027 renames exactly four
///                            columns plus one config key
///   `{{GMCC_HOME}}`          a format token inside already-exported kbite
///                            zips; renaming it would make existing exports
///                            unreadable
///
/// So the repo deliberately holds BOTH prefixes: gm-prefixed on the runtime
/// side, `gmcc` on the plugin side. `testAllowedSpellingsAreNotFlagged` is what
/// keeps a future sweep from "tidying" the second list into the first.
///
/// ════════════════════════════════════════════════════════════════════════════
/// THE SANDBOX VOCABULARY — MOVED from the list above, not merely added below
/// ════════════════════════════════════════════════════════════════════════════
///
/// `.gmcc_sandbox` used to sit in the never-flag list, because the marker
/// filename was deliberately preserved while the runtime around it was renamed.
/// The snapshot runtime it named has since been DELETED outright, so the
/// spelling moved to the retired list. It had to MOVE rather than be added:
/// leaving it in both lists makes `testAllowedSpellingsAreNotFlagged` and
/// `testNoRetiredSandboxVocabulary` assert opposite things about the same
/// string, and one of them must then fail.
///
/// `sandbox` is a THREE-WAY HOMONYM in this repo, so the pattern below is keyed
/// on the runtime vocabulary and never on the bare word. These three are
/// unrelated to the deleted dev loop and must survive:
///
///   `DopeRepoSandbox`        write containment for `.gmcc/` — a value type
///                            whose public surface can only name paths under
///                            {instanceRoot}/.gmcc/. Deleting it removes dope
///                            repo writing entirely.
///   `ENABLE_APP_SANDBOX`     an Xcode build setting that must stay NO forever:
///                            an App-Sandboxed kernel cannot open the db, bind
///                            the socket, or read the user's repos.
///   `ENABLE_USER_SCRIPT_SANDBOXING`
///                            unrelated Xcode setting, stays YES.
final class RetiredNameContractTests: XCTestCase {

    // MARK: - Scope

    /// Every file the contract applies to: all six packages' sources, the test
    /// trees, the gmk-side scripts, THE WHOLE PLUGIN, plus the two root docs.
    private func scopedFiles() throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []

        for tree in [RepoRoot.gmkRoot(), RepoRoot.pluginRoot()] {
            guard let walker = fm.enumerator(at: tree, includingPropertiesForKeys: nil)
            else { continue }
            while let url = walker.nextObject() as? URL {
                // Build products are generated, not authored.
                //
                // `/build/` and `.xcarchive` are here for a reason worth
                // recording: an xcodebuild archive lands at `gmk/build/` (no
                // leading dot, so the `/.build/` test misses it) and its dSYM
                // relocation maps are `.yml` files listing every MANGLED SWIFT
                // SYMBOL in the binary. A type that has just been deleted from
                // the sources therefore lives on in those maps until the next
                // clean, and the contract would fail against a name the repo no
                // longer contains — pointing the reader at a file nobody wrote.
                // Both directories are gitignored; a retired name can only be
                // fixed where it was authored.
                if url.path.contains("/.build/") || url.path.contains("/.swiftpm/")
                    || url.path.contains("/build/") || url.path.contains(".xcarchive/") {
                    continue
                }
                if ["swift", "md", "sh", "yml", "yaml", "json"].contains(url.pathExtension) {
                    out.append(url)
                }
            }
        }
        for doc in ["CLAUDE.md", "README.md"] {
            let url = RepoRoot.resolve().appendingPathComponent(doc)
            if fm.fileExists(atPath: url.path) { out.append(url) }
        }

        // A loud failure beats a vacuous pass: a scan that stops finding files
        // reports a clean bill of health forever.
        XCTAssertGreaterThan(out.count, 100, "scoped-file walk looks broken")
        return out
    }

    private func relative(_ url: URL) -> String {
        url.path.replacingOccurrences(of: RepoRoot.resolve().path + "/", with: "")
    }

    /// Lines matching `pattern` in the scoped tree, minus the exemptions.
    private func violations(
        pattern: String,
        allowFiles: Set<String> = [],
        allowLine: ((String) -> Bool)? = nil
    ) throws -> [String] {
        let regex = try NSRegularExpression(pattern: pattern)
        var hits: [String] = []
        for file in try scopedFiles() {
            let rel = relative(file)
            guard !allowFiles.contains(rel) else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                guard regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
                else { continue }
                if let allowLine, allowLine(s) { continue }
                hits.append("\(rel):\(index + 1): \(s.trimmingCharacters(in: .whitespaces))")
            }
        }
        return hits
    }

    // MARK: - The exemptions, each naming why it is exempt

    /// The HISTORICAL RECORD. These name the old spelling because the old
    /// spelling is the subject:
    ///
    /// - `Migrations.swift` — m0001–m0026 are FROZEN (editing a shipped
    ///   migration breaks replay-from-scratch), and m0027 must name the column
    ///   it renames FROM. A migration that cannot say the old name cannot
    ///   perform the rename.
    /// - `Envelope.swift` — the wire-version ledger. The v25→v26 entry exists
    ///   to record WHICH key renamed; stripping the name leaves a version bump
    ///   with no stated cause, which is the one thing that ledger is for.
    /// - `MigrationTests.swift` — its fixtures build a PRE-m0027 database on
    ///   purpose, so they must insert into the pre-rename column.
    private let historicalRecord: Set<String> = [
        "gmk/gmDaemon/Sources/GmDaemon/Migrations.swift",
        "gmk/gmDaemonSdk/Sources/GmDaemonSdk/Protocol/Envelope.swift",
        "gmk/gmDaemon/Tests/GmDaemonTests/MigrationTests.swift",
    ]

    /// Arbitrary FIXTURE strings and doc-comment examples. `primary_path` is an
    /// opaque TEXT column in these tests — never resolved, statted or opened.
    /// See the comment in DopeCogTests for why they are left alone rather than
    /// "corrected" to a real path.
    private let fixtureStrings: Set<String> = [
        "gmk/gmDaemon/Tests/GmDaemonTests/DopeCogTests.swift",
        "gmk/gmDaemon/Tests/GmDaemonTests/BriefingTests.swift",
        "gmk/gmDaemonSdk/Tests/GmDaemonSdkTests/DopeSandboxTests.swift",
    ]

    /// This file, and the RepoRoot helper: both NAME the retired spellings in
    /// prose in order to explain the retirement.
    private let selfReferential: Set<String> = [
        "gmk/gmToolchain/Tests/GmToolchainTests/RetiredNameContractTests.swift",
        "gmk/gmToolchain/Tests/GmToolchainTests/RepoRoot.swift",
        // Its banned-token LIST necessarily spells the tokens it bans.
        "gmk/gmToolchain/Tests/GmToolchainTests/LiveRuntimeIsolationTests.swift",
    ]

    /// The one-shot migration OFF the retired stack. It is the mirror image of
    /// `historicalRecord`: that set names the old spelling to RECORD a
    /// retirement, this one names it to PERFORM one. A script that copies
    /// `~/gmcc/gmcc.db` to `~/gmfs/gm.db` cannot be written without naming both
    /// roots, and every literal in it is load-bearing:
    ///
    /// - `$HOME/gmcc` and `$HOME/gmcc_ckfs` are the SOURCE of the copy.
    /// - `gmcc.db` is the file being copied FROM, in the same line that
    ///   promises it is never written to.
    /// - `gmcc_hook call SHUTDOWN` quiesces the LIVE daemon, which is the whole
    ///   point of taking the snapshot rather than `cp`-ing a WAL-mode database
    ///   out from under a running writer. `gm_hook` cannot do it: it is not
    ///   installed until the user installs the new plugin.
    /// - `SELECT ckfs_relative_storage_path ... LIMIT 0` is the assertion that
    ///   the column is GONE rather than ALIASED. That probe exists because
    ///   m0027 was briefly a rename-to-itself, which SQLite accepts in silence
    ///   and a green suite did not catch. It cannot be written without the old
    ///   column name.
    ///
    /// Two alternatives were considered and rejected: moving the script outside
    /// `gmk/**` would hide the riskiest script in the repo from the only walk
    /// that covers scripts, and parameterising the old names into variables
    /// would make a one-shot, irreversible-if-wrong 596MB database copy harder
    /// to read in exchange for contract purity.
    ///
    /// A FOURTH path-keyed exemption category would be evidence that the SCOPE
    /// RULE is wrong, not that another file is special. Argue with this sentence
    /// before adding one.
    private let migrationOffRetiredStack: Set<String> = [
        "gmk/scripts/migrate_to_gmfs.sh",
    ]

    private var allExempt: Set<String> {
        historicalRecord
            .union(fixtureStrings)
            .union(selfReferential)
            .union(migrationOffRetiredStack)
    }

    // MARK: - Retired binaries

    func testNoRetiredBinaryNames() throws {
        // Anchored on a non-identifier boundary so a longer word cannot hide a
        // hit and a longer word cannot manufacture one.
        let hits = try violations(
            pattern: #"(?<![A-Za-z0-9_])gmcc_(daemon|mcp|hook)(?![A-Za-z0-9_])"#,
            allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired binary name in the new stack. The binaries are gm_daemon, \
            gm_mcp and gm_hook:
            \(hits.joined(separator: "\n"))
            """)
    }

    // MARK: - Retired sandbox vocabulary

    /// The snapshot dev loop is GONE, along with the second filesystem root it
    /// existed to provide. These four spellings are the runtime vocabulary of
    /// that mechanism.
    ///
    /// KEYED ON THE VOCABULARY, NEVER ON THE WORD. A pattern matching bare
    /// `sandbox` would flag `DopeRepoSandbox` (write containment for `.gmcc/`)
    /// and `ENABLE_APP_SANDBOX` (which must stay NO or the kernel cannot open
    /// its own database) — two subsystems with nothing to do with the dev loop.
    /// That is why each alternative below names a specific symbol or filename.
    func testNoRetiredSandboxVocabulary() throws {
        // CLAUDE.md is exempt for THIS pattern ONLY, and for the same reason
        // `Envelope.swift` is exempt for the wire-version ledger and
        // `migrate_to_gmfs.sh` is exempt wholesale: it is where the retirement
        // is RECORDED. Its "The sandbox dev loop is GONE" section has to name
        // the four retired spellings in order to say which sweep deleted them,
        // and — more importantly — to name the three HOMONYMS that must not be
        // swept with them. A reader who does not know that `DopeRepoSandbox` is
        // unrelated is one grep away from deleting dope repo writing.
        //
        // Scoped to this one test rather than added to `allExempt`, so CLAUDE.md
        // stays covered by the binary, env, root, filename, CKFS, module and
        // package-path patterns. A doc that may name ONE retired thing must not
        // thereby be licensed to name all of them.
        let hits = try violations(
            pattern: #"\.gmcc_sandbox|SandboxMarker|SandboxRetarget|local_sandbox"#,
            allowFiles: allExempt.union(["CLAUDE.md"]))
        XCTAssertEqual(hits, [], """
            retired sandbox vocabulary. The snapshot dev loop and its second \
            filesystem root were deleted; there is ONE root, ~/gmfs, and \
            `gm_hook call BACKUP` is the pre-risk snapshot. NOTE: DopeRepoSandbox \
            and ENABLE_APP_SANDBOX are unrelated and must NOT be swept:
            \(hits.joined(separator: "\n"))
            """)
    }

    // MARK: - Retired env vars

    /// The four that became three. `GM_FS_ROOT` subsumes both roots.
    func testNoRetiredEnvNames() throws {
        let hits = try violations(
            pattern: #"GMCC_(ROOT|CKFS_ROOT|BOOTED|PLUGIN_ROOT)\b"#,
            allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired env var in the new stack. The session provisions exactly \
            three: GM_BOOTED, GM_PLUGIN_ROOT, GM_FS_ROOT:
            \(hits.joined(separator: "\n"))
            """)
    }

    // MARK: - Retired filesystem layout

    /// `~/gmcc` and `~/gmcc_ckfs` collapsed into the single `~/gmfs`.
    ///
    /// The lookbehind is what keeps this from firing on `plugins/gmcc/` — see
    /// `testAllowedSpellingsAreNotFlagged`, which asserts that directly.
    func testNoRetiredFilesystemRoots() throws {
        let hits = try violations(
            pattern: #"(~|\$HOME)/gmcc(_ckfs)?(?![A-Za-z0-9_])"#,
            allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired filesystem root. There is ONE root now, ~/gmfs:
            \(hits.joined(separator: "\n"))
            """)
    }

    func testNoRetiredDatabaseOrStampFilenames() throws {
        let hits = try violations(
            pattern: #"gmcc\.db|\.gmcc_version"#,
            allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired filename. The database is gm.db and the stamp is \
            .gm_version:
            \(hits.joined(separator: "\n"))
            """)
    }

    // MARK: - Retired CKFS vocabulary

    /// CKFS is retired for GMFS, concept and all.
    ///
    /// THE LOOKBEHIND IS LOAD-BEARING, and it is not hypothetical: a bare
    /// case-insensitive `ckfs` match fires on `fallba` + `ckFs` + `Root` —
    /// `GmEnvironment.fallbackFsRoot`, a correctly-named symbol in the new
    /// vocabulary. Requiring that no letter precede the match is what tells a
    /// retired word apart from four letters in the middle of a live one.
    func testNoRetiredCkfsVocabulary() throws {
        let hits = try violations(
            pattern: #"(?<![A-Za-z])[Cc][Kk][Ff][Ss]"#,
            allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired CKFS vocabulary. The concept is GMFS — one top-level \
            filesystem:
            \(hits.joined(separator: "\n"))
            """)
    }

    // MARK: - Retired module and package paths

    func testNoRetiredModuleName() throws {
        let hits = try violations(
            pattern: #"GMCCDaemonKit"#, allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired module name. The modules are GmDaemonSdk, GmDaemon, \
            GmUxComponentLibrary, GmAgententicsSdk and gm_mcp:
            \(hits.joined(separator: "\n"))
            """)
    }

    /// The Swift package left `plugins/gmcc/daemon` for `gmk/`. The plugin
    /// directory itself stayed, which is why this pattern requires the
    /// `/daemon` suffix rather than banning `plugins/gmcc`.
    func testNoRetiredPackagePath() throws {
        let hits = try violations(
            pattern: #"plugins/gmcc/daemon"#, allowFiles: allExempt)
        XCTAssertEqual(hits, [], """
            retired package path. The packages live under gmk/:
            \(hits.joined(separator: "\n"))
            """)
    }

    // MARK: - The anchoring itself

    /// EVERY PATTERN ABOVE, RUN AGAINST THE SPELLINGS THAT MUST SURVIVE.
    ///
    /// This is the test that makes the two lists in the header enforceable
    /// rather than aspirational. Without it, "anchored, not substring" is a
    /// comment — and the first person to loosen a pattern to catch one more
    /// case would silently start flagging `.gmcc/`, the `gmcc:` namespace, or
    /// the pen server name, at which point the honest-looking fix is to rename
    /// those and break every dope-scope path in the repo at once.
    func testAllowedSpellingsAreNotFlagged() throws {
        let allowed = [
            "plugins/gmcc/commands/gm_task.md",
            "plugins/gmcc/skills/gmcc/SKILL.md",
            ".gmcc/scope.doped.json",
            ".gmcc/persistence/project/project.index.persistence.doped.json",
            "/gmcc:code-explorer",
            "mcp__plugin_gmcc_pen__arch_get",
            "mcp__gmcc__whatever",
            "dope scope code gmcc",
            "gmcc_diagram_path",
            "gmccDiagramPath",
            "{{GMCC_HOME}}",
            // The symbol that proves the CKFS lookbehind: four of these
            // letters spell the retired word in the middle of a live name.
            "GmEnvironment.fallbackFsRoot(env: env)",
            "let root = fallbackFsRoot()",
            // The sandbox HOMONYMS. Unrelated to the deleted dev loop, and the
            // reason the retired pattern names symbols instead of the word.
            "DopeRepoSandbox", "DopeSandboxTests", "Store+DopeRepoVerbs",
            "ENABLE_APP_SANDBOX = NO", "ENABLE_USER_SCRIPT_SANDBOXING = YES",
            // The live vocabulary must obviously survive its own contract.
            "gm_daemon", "gm_mcp", "gm_hook", "~/gmfs", "gm.db", ".gm_version",
            "GM_BOOTED", "GM_PLUGIN_ROOT", "GM_FS_ROOT",
            "gmfs_relative_storage_path", "gmfs_root",
            "gmk/gmDaemonSdk/Sources/GmDaemonSdk",
        ]
        let patterns: [(String, String)] = [
            ("binary",     #"(?<![A-Za-z0-9_])gmcc_(daemon|mcp|hook)(?![A-Za-z0-9_])"#),
            ("env",        #"GMCC_(ROOT|CKFS_ROOT|BOOTED|PLUGIN_ROOT)\b"#),
            ("fs root",    #"(~|\$HOME)/gmcc(_ckfs)?(?![A-Za-z0-9_])"#),
            ("filename",   #"gmcc\.db|\.gmcc_version"#),
            ("ckfs",       #"(?<![A-Za-z])[Cc][Kk][Ff][Ss]"#),
            ("sandbox",    #"\.gmcc_sandbox|SandboxMarker|SandboxRetarget|local_sandbox"#),
            ("module",     #"GMCCDaemonKit"#),
            ("package",    #"plugins/gmcc/daemon"#),
        ]
        for (name, pattern) in patterns {
            let regex = try NSRegularExpression(pattern: pattern)
            for line in allowed {
                XCTAssertNil(
                    regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                    """
                    the '\(name)' pattern flags '\(line)', which is DELIBERATELY \
                    unchanged. Anchor the pattern; do not rename the spelling.
                    """)
            }
        }
    }

    /// And the converse: each pattern still catches what it is for. A pattern
    /// anchored into uselessness passes every test above.
    func testRetiredSpellingsAreStillCaught() throws {
        let cases: [(String, String)] = [
            (#"(?<![A-Za-z0-9_])gmcc_(daemon|mcp|hook)(?![A-Za-z0-9_])"#, "run gmcc_hook ping"),
            (#"(?<![A-Za-z0-9_])gmcc_(daemon|mcp|hook)(?![A-Za-z0-9_])"#, "~/gmcc/bin/gmcc_daemon"),
            (#"GMCC_(ROOT|CKFS_ROOT|BOOTED|PLUGIN_ROOT)\b"#, "export GMCC_CKFS_ROOT='/x'"),
            (#"GMCC_(ROOT|CKFS_ROOT|BOOTED|PLUGIN_ROOT)\b"#, "$GMCC_BOOTED"),
            (#"(~|\$HOME)/gmcc(_ckfs)?(?![A-Za-z0-9_])"#, "cd ~/gmcc_ckfs/projects"),
            (#"(~|\$HOME)/gmcc(_ckfs)?(?![A-Za-z0-9_])"#, "$HOME/gmcc/bin"),
            (#"gmcc\.db|\.gmcc_version"#, "~/gmcc/gmcc.db is append-only"),
            (#"gmcc\.db|\.gmcc_version"#, "stat bin/.gmcc_version"),
            (#"(?<![A-Za-z])[Cc][Kk][Ff][Ss]"#, "ckfs_relative_storage_path"),
            (#"(?<![A-Za-z])[Cc][Kk][Ff][Ss]"#, "CkfsPathResolver"),
            (#"(?<![A-Za-z])[Cc][Kk][Ff][Ss]"#, "the CKFS content root"),
            (#"GMCCDaemonKit"#, "@testable import GMCCDaemonKit"),
            (#"plugins/gmcc/daemon"#, "cd plugins/gmcc/daemon && swift test"),
        ]
        for (pattern, line) in cases {
            let regex = try NSRegularExpression(pattern: pattern)
            XCTAssertNotNil(
                regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                "pattern \(pattern) no longer catches '\(line)' — it has been anchored into uselessness")
        }
    }

    // MARK: - Write containment

    /// THE WRITE-CONTAINMENT INVARIANT: never write outside gmfs or the
    /// working repo.
    ///
    /// `Paths.assertContained(_:)` is the choke point that ENFORCES it. This
    /// test guards the enforcement itself — a rule with a throwing check that
    /// nothing calls is a rule that lives in markdown after all.
    ///
    /// It bans the two doors OUT of the permitted roots: `$HOME` resolution,
    /// and `~/.claude` (the plugin cache and settings, which are emphatically
    /// not under gmfs). It does NOT try to prove every FileManager call routes
    /// through the choke point — that is not decidable from the text — but a
    /// write cannot escape the roots without first resolving a path outside
    /// them, and these are the ways to do that.
    func testNoSourceResolvesAPathOutsideThePermittedRoots() throws {
        let allowed: Set<String> = [
            // Paths.swift IS the choke point: it resolves $HOME to define the
            // root everything else is contained within.
            "gmk/gmDaemonSdk/Sources/GmDaemonSdk/Paths.swift",
            // Resolves $HOME to name where PROD lives, deliberately without
            // the override, so a sandboxed process cannot mistake itself for
            // production. It never writes there — it refuses to.
            "gmk/gmDaemon/Sources/GmDaemon/SandboxRetarget.swift",
            // The daemon-free fallback for the one root var.
            "gmk/gmDaemonSdk/Sources/GmDaemonSdk/Environment/GmEnvironment.swift",
            // The archive placeholder: exported kbites store a $HOME-relative
            // token so a zip is portable between machines. String templating,
            // not a write target.
            "gmk/gmDaemonSdk/Sources/GmDaemonSdk/Kbite/KbiteArchive.swift",
            // Seeds config DEFAULTS as values; a shipped migration body that
            // cannot be edited.
            "gmk/gmDaemon/Sources/GmDaemon/Migrations.swift",
            // The app resolves $HOME for its own probe and for user-facing
            // file pickers, which are the user's explicit choice.
            "gmk/gmVibes/GMVibesEnvironment.swift",
            // Expands a LEADING `~/` in a path a caller handed in. Purely
            // lexical — it never touches the filesystem and never writes. The
            // expansion has to happen before the containment test can be
            // applied to the result at all.
            "gmk/gmDaemonSdk/Sources/GmDaemonSdk/RepoRelativePath.swift",
        ]
        var hits: [String] = []
        for file in try scopedFiles() {
            let rel = relative(file)
            guard rel.hasSuffix(".swift"), rel.hasPrefix("gmk/"),
                  rel.contains("/Sources/"), !allowed.contains(rel)
            else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let s = String(line)
                for token in ["homeDirectoryForCurrentUser", "NSHomeDirectory", "~/.claude"]
                where s.contains(token) {
                    hits.append("\(rel):\(index + 1): \(token)")
                }
            }
        }
        XCTAssertEqual(hits, [], """
            these resolve a path outside gmfs and the working repo. Route the \
            path through Paths (and its assertContained choke point) instead — \
            the containment rule is enforced, not documented:
            \(hits.joined(separator: "\n"))
            """)
    }

    /// The choke point exists and refuses what it says it refuses. Without
    /// this, the test above could pass against an `assertContained` that
    /// returned unconditionally.
    func testContainmentChokePointActuallyRefuses() throws {
        let source = RepoRoot.package("gmDaemonSdk")
            .appendingPathComponent("Sources/GmDaemonSdk/Paths.swift")
        let text = try String(contentsOf: source, encoding: .utf8)
        XCTAssertTrue(text.contains("func assertContained"),
                      "the write-containment choke point is gone")
        XCTAssertTrue(text.contains("throw ContainmentViolation"),
                      "assertContained no longer throws — it enforces nothing")
        // standardizedFileURL is what stops `..` traversal smuggling a write
        // out of the root, and the trailing "/" is the path-component boundary
        // that stops ~/gmfs-evil counting as inside ~/gmfs.
        XCTAssertTrue(text.contains("standardizedFileURL"),
                      "assertContained compares unresolved paths — `..` escapes it")
        XCTAssertTrue(text.contains(#"hasPrefix(allowed + "/")"#),
                      "assertContained's prefix test is not on a component boundary")
    }

    /// `Paths.ensureRuntimeDirs()` must not be called from anything the build
    /// or the suite exercises. This prompt DEFINES `~/gmfs`; populating it is
    /// the migration step's job. A stray call would have the build create a
    /// runtime root as a side effect, on a machine where the old runtime is
    /// still live.
    func testNothingPopulatesTheRuntimeRoot() throws {
        // THE ONE LEGITIMATE CALLER: the kernel creating its own runtime
        // directories on first boot. Note the distinction the constraint
        // actually draws — no ensureRuntimeDirs() on a path THE BUILD OR THE
        // TESTS exercise. This one runs when a person starts the kernel, which
        // is neither, and a kernel that cannot create its own runtime root
        // would simply not work.
        //
        // MOVED with the boot path, from `gm_daemon/main.swift` into
        // `KernelOwnership.acquire()`. It is STILL one caller, and it landed
        // there rather than staying beside the boot sequence for a reason worth
        // keeping: the directories have to exist before the pidfile can be
        // opened, and the pidfile open is the first step of acquiring the lock.
        // Anything that created them later would be creating them after
        // something had already tried to lock inside them.
        let allowed: Set<String> = [
            "gmk/gmDaemon/Sources/GmKernelHost/KernelOwnership.swift",
        ]
        var hits: [String] = []
        for file in try scopedFiles() {
            let rel = relative(file)
            guard rel.hasSuffix(".swift"), rel.hasPrefix("gmk/"),
                  !rel.hasSuffix("Paths.swift"),
                  !allowed.contains(rel),
                  !selfReferential.contains(rel)
            else { continue }
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            for (index, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
            where String(line).contains("ensureRuntimeDirs") {
                hits.append("\(rel):\(index + 1)")
            }
        }
        XCTAssertEqual(hits, [], """
            ensureRuntimeDirs() is called from the built tree. This work \
            DEFINES ~/gmfs and populates nothing; creating it belongs to the \
            migration step alone:
            \(hits.joined(separator: "\n"))
            """)
    }
}
