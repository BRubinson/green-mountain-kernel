import XCTest
@testable import GMCCDaemonKit

final class DopeSandboxTests: XCTestCase {

    private var repoRoot: URL!

    override func setUpWithError() throws {
        repoRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("dope-sandbox-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: repoRoot.appendingPathComponent(".git", isDirectory: true),
            withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: repoRoot)
    }

    private func makeBundle(version: Int64 = 1, domains: [String] = ["core"]) -> DopeDocumentBundle {
        DopeDocumentBundle(
            main: DopeScopeDocument(
                version: version,
                scope: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                persistence: Dictionary(uniqueKeysWithValues: domains.map {
                    ($0, DopeScopeDocument.expectedFile(forPersistenceCode: $0))
                })),
            domainFiles: domains.map {
                DopePersistenceFileDocument(
                    version: version,
                    body: DopePersistenceBody(code: $0, name: $0.capitalized,
                                         description: "", sortOrder: 0),
                    entities: [], enums: [])
            })
    }

    // MARK: - Resolution pre-flight

    func testResolveRejectsMissingStaleAndNonGitRoots() throws {
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(instanceRoot: ""))
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(instanceRoot: "relative/path"))
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(
            instanceRoot: "/nonexistent/definitely-stale-\(UUID().uuidString)")) { error in
            XCTAssertTrue("\(error)".contains("missing or stale"), "\(error)")
        }
        let notGit = FileManager.default.temporaryDirectory
            .appendingPathComponent("not-git-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: notGit, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: notGit) }
        XCTAssertThrowsError(try DopeRepoSandbox.resolve(instanceRoot: notGit.path)) { error in
            XCTAssertTrue("\(error)".contains("not a git checkout"), "\(error)")
        }
        XCTAssertNoThrow(try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path))
    }

    // MARK: - Containment

    func testDomainPathsRefuseEscapes() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        // The layout gained a level, so EVERY segment is validated now, not
        // just the single flat one the old helper checked.
        for bad in ["../escape", "a/b", "..", "UPPER", ""] {
            XCTAssertThrowsError(try sandbox.domainDirectory(code: bad))
            XCTAssertThrowsError(try sandbox.domainIndexFile(code: bad))
            XCTAssertThrowsError(try sandbox.domainEntityFile(domain: "core", entity: bad))
            XCTAssertThrowsError(try sandbox.domainEnumFile(domain: "core", enumCode: bad))
        }
        for good in [try sandbox.domainDirectory(code: "core"),
                     try sandbox.domainIndexFile(code: "core"),
                     try sandbox.domainEntityFile(domain: "core", entity: "user"),
                     try sandbox.domainEnumFile(domain: "core", enumCode: "status")] {
            XCTAssertTrue(good.path.hasPrefix(sandbox.dopeRoot.path + "/"))
        }
    }

    func testReadRefusesTamperedDomainMap() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle())
        // Tamper: point the map outside domains/.
        let tampered = """
            {"version": 1,
             "scope": {"code": "gmcc", "name": "GMCC", "description": ""},
             "persistence": {"core": "../../../etc/passwd"}}
            """
        try Data(tampered.utf8).write(to: sandbox.mainFile)
        XCTAssertThrowsError(try sandbox.readBundle()) { error in
            XCTAssertTrue("\(error)".contains("never followed"), "\(error)")
        }
    }

    // MARK: - Round trip + atomicity

    func testWriteReadRoundTripAndIdempotence() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let bundle = makeBundle(domains: ["core", "billing"])
        let first = try sandbox.writeAtomically(bundle)
        XCTAssertEqual(first.written.count, 3, "scope index + 2 domain index files")

        let read = try sandbox.readBundle()
        XCTAssertEqual(read.bundle.main, bundle.main)
        // The reader returns files sorted by code; sort_order carries the
        // semantic order, so compare order-insensitively.
        XCTAssertEqual(read.bundle.domainFiles.sorted { $0.body.code < $1.body.code },
                       bundle.domainFiles.sorted { $0.body.code < $1.body.code })
        XCTAssertTrue(read.warnings.isEmpty)

        // Idempotence: identical bytes after a second write.
        let mainBefore = try Data(contentsOf: sandbox.mainFile)
        _ = try sandbox.writeAtomically(bundle)
        XCTAssertEqual(try Data(contentsOf: sandbox.mainFile), mainBefore)
    }

    func testWritePrunesStaleDomainDirectories() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle(domains: ["core", "billing"]))

        let second = try sandbox.writeAtomically(makeBundle(version: 2, domains: ["core"]))
        XCTAssertEqual(second.pruned, ["persistence/billing"])
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: sandbox.persistenceDirectory.appendingPathComponent("billing").path))
    }

    /// `.gmcc/` is NOT exclusively dope-owned — `.screenshots/` lives there
    /// too. The old layout could replaceItemAt the whole `.gmcc/dope`
    /// directory precisely because nothing else was in it; swapping `.gmcc/`
    /// wholesale would delete its siblings, so the write swaps only the
    /// dope-owned subtrees.
    func testWritePreservesGmccSiblings() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle())

        let shots = sandbox.dopeRoot.appendingPathComponent(".screenshots", isDirectory: true)
        try FileManager.default.createDirectory(at: shots, withIntermediateDirectories: true)
        let keep = shots.appendingPathComponent("keep.png")
        try Data("png".utf8).write(to: keep)

        _ = try sandbox.writeAtomically(makeBundle(version: 2))

        XCTAssertTrue(FileManager.default.fileExists(atPath: keep.path),
                      ".gmcc siblings must survive a write-repo")
    }

    /// Pins the ACTUAL on-disk shape against the layout the prompt
    /// specifies, so a refactor cannot quietly drift the file names.
    func testOnDiskLayoutMatchesTheSpecifiedShape() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let bundle = DopeDocumentBundle(
            main: DopeScopeDocument(
                version: 1,
                scope: DopeScopeBody(code: "gmcc", name: "GMCC", description: ""),
                persistence: ["core": DopeScopeDocument.expectedFile(forPersistenceCode: "core")]),
            domainFiles: [DopePersistenceFileDocument(
                version: 1,
                body: DopePersistenceBody(code: "core", name: "Core",
                                          description: "", sortOrder: 0),
                entities: [DopeEntityDocument(
                    body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                         description: "", sortOrder: 0,
                                         repoRepresentativeFile: nil, baseComposableRef: nil),
                    properties: [])],
                enums: [DopeEnumDocument(
                    body: DopeEnumBody(code: "status", name: "Status", description: "",
                                       sortOrder: 0, repoRepresentativeFile: nil),
                    options: [])])])
        let result = try sandbox.writeAtomically(bundle)

        XCTAssertEqual(result.written, [
            ".gmcc/persistence/core/core.entity.user.persistence.doped.json",
            ".gmcc/persistence/core/core.enum.status.persistence.doped.json",
            ".gmcc/persistence/core/core.index.persistence.doped.json",
            ".gmcc/scope.doped.json",
        ])

        // No dope/ level, and the old names are gone.
        let fm = FileManager.default
        XCTAssertFalse(fm.fileExists(atPath: sandbox.dopeRoot
            .appendingPathComponent("dope").path))
        XCTAssertFalse(fm.fileExists(atPath: sandbox.dopeRoot
            .appendingPathComponent("main.doped.json").path))
        XCTAssertFalse(fm.fileExists(atPath: sandbox.dopeRoot
            .appendingPathComponent("drawing_config.doped.json").path))

        // And it reads back to exactly what went in.
        let read = try sandbox.readBundle()
        XCTAssertEqual(read.bundle.main, bundle.main)
        XCTAssertEqual(read.bundle.domainFiles, bundle.domainFiles)
        XCTAssertTrue(read.warnings.isEmpty)
    }

    /// Cogs must actually reach disk in the shape the goal specifies, and
    /// come back identical.
    func testCogsRoundTripThroughTheirOwnDirectory() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        let cog = DopeCogDocument(
            body: DopeCogBody(code: "gm_daemon", name: "GM Daemon",
                              description: "", sortOrder: 0),
            elements: [DopeCogElementDocument(
                code: "gm_daemon", name: "GM Daemon", description: "", sortOrder: 0,
                elementType: "Hull", primaryPath: "plugins/gmcc/daemon",
                links: DopeCogLinks(persistenceOwners: ["agentics", "doped"]))])
        let base = makeBundle()
        let bundle = DopeDocumentBundle(
            main: DopeScopeDocument(
                version: base.main.version, scope: base.main.scope,
                persistence: base.main.persistence,
                cogs: ["gm_daemon": DopeScopeDocument.expectedCogFile(forCogCode: "gm_daemon")]),
            domainFiles: base.domainFiles,
            cogFiles: [cog])

        let written = try sandbox.writeAtomically(bundle)
        XCTAssertTrue(
            written.written.contains(".gmcc/cogs/gm_daemon/gm_daemon.index.cog.doped.json"),
            "cog index must land at the specified path: \(written.written)")

        let read = try sandbox.readBundle()
        XCTAssertEqual(read.bundle.cogFiles, [cog])
        XCTAssertTrue(read.warnings.isEmpty)
    }

    /// A tampered cogs map is refused the same way a tampered persistence
    /// map is — the contract applies to both areas, not just the one that
    /// had it first.
    func testReadRefusesTamperedCogMap() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle())
        let tampered = """
            {"version": 1,
             "scope": {"code": "gmcc", "name": "GMCC", "description": ""},
             "persistence": {"core": "persistence/core/core.index.persistence.doped.json"},
             "cogs": {"gm_daemon": "../../../etc/passwd"}}
            """
        try Data(tampered.utf8).write(to: sandbox.mainFile)
        XCTAssertThrowsError(try sandbox.readBundle()) { error in
            XCTAssertTrue("\(error)".contains("never followed"), "\(error)")
        }
    }

    func testPeekRevision() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        XCTAssertNil(sandbox.peekRevision())
        _ = try sandbox.writeAtomically(makeBundle(version: 7))
        XCTAssertEqual(sandbox.peekRevision(), 7)
    }

    func testFailedWriteLeavesOldTreeIntactAndNoStaging() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        _ = try sandbox.writeAtomically(makeBundle(version: 1))
        let mainBefore = try Data(contentsOf: sandbox.mainFile)

        // A bundle whose domain code fails validation mid-staging throws
        // AFTER main has been staged — the old tree must be untouched.
        let bad = DopeDocumentBundle(
            main: makeBundle(version: 2).main,
            domainFiles: [DopePersistenceFileDocument(
                version: 2,
                body: DopePersistenceBody(code: "Bad-Code", name: "x", description: "", sortOrder: 0),
                entities: [], enums: [])])
        XCTAssertThrowsError(try sandbox.writeAtomically(bad))

        XCTAssertEqual(try Data(contentsOf: sandbox.mainFile), mainBefore,
                       "old tree must survive a failed write")
        let gmcc = repoRoot.appendingPathComponent(".gmcc")
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: gmcc.path)
            .filter { $0.hasPrefix(".dope-staging") }
        XCTAssertTrue(leftovers.isEmpty, "staging directory leaked: \(leftovers)")
    }

    /// Containment must resolve symlinks — a symlinked `.gmcc` would
    /// redirect every contained path (and the subtree swap) outside the repo
    /// while every lexical prefix check still passed. The guard moved up a
    /// level with the layout: `.gmcc` IS the dope root now, so `.gmcc`
    /// itself is what must be refused.
    func testSymlinkedDopeRootRefused() throws {
        let fm = FileManager.default
        let outside = fm.temporaryDirectory
            .appendingPathComponent("dope-outside-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: outside, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: outside) }

        try fm.createSymbolicLink(
            at: repoRoot.appendingPathComponent(".gmcc"),
            withDestinationURL: outside)

        XCTAssertThrowsError(
            try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)) { error in
            XCTAssertTrue("\(error)".contains("symlink"), "\(error)")
        }
    }

    func testMissingTreeReadIsLoud() throws {
        let sandbox = try DopeRepoSandbox.resolve(instanceRoot: repoRoot.path)
        XCTAssertThrowsError(try sandbox.readBundle()) { error in
            XCTAssertTrue("\(error)".contains("no dope tree on disk"), "\(error)")
        }
    }
}
