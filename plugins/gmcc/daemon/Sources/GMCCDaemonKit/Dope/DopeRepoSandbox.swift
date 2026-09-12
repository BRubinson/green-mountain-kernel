import Foundation

/// The daemon's first repo file writer — a value type whose entire public
/// surface can only name paths under `{instanceRoot}/.gmcc/`.
///
/// NOTE ON THE SWAP. `.gmcc/` is NOT exclusively dope-owned: `.screenshots/`
/// and the staging directory live there too. The old layout could
/// `replaceItemAt` the whole `.gmcc/dope` directory precisely because nothing
/// else lived in it; doing that to `.gmcc/` would delete its siblings. So the
/// write swaps the two dope-owned SUBTREES (`persistence/`, `cogs/`)
/// individually and writes `scope.doped.json` LAST. Each subtree is still
/// atomic; whole-tree atomicity across all three is traded away deliberately,
/// and the ordering makes the failure mode benign — a crash leaves an OLDER
/// index over newer subtrees, which `peekRevision` reports as behind and an
/// idempotent re-run repairs.
///
/// KbiteMawOpenHandler (writes a caller-supplied absolute path, no root, no
/// containment) is explicitly NOT the template. Three independent layers of
/// containment, because one is not enough:
///   1. `resolve` — loud pre-flight on the instance root itself,
///   2. `domainFile(code:)` — re-validates the code even for callers that
///      already validated it, so `/` and `..` can never smuggle in,
///   3. every returned URL passes a final standardized-prefix guard.
///
/// GitHead.swift documents stale instance roots as COMMON; GitHead stays
/// silent because it only reads. This type THROWS, because the next step
/// writes into a user's repo.
public struct DopeRepoSandbox: Sendable {
    public let instanceRoot: URL
    public let dopeRoot: URL

    public struct SandboxError: Error, CustomStringConvertible, Sendable {
        public let description: String
        public init(_ description: String) { self.description = description }
    }

    // MARK: - Resolution

    public static func resolve(instanceRoot raw: String) throws -> DopeRepoSandbox {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SandboxError("instance root is empty — the session's instance row has no path")
        }
        guard trimmed.hasPrefix("/") else {
            throw SandboxError("instance root is not an absolute path: \(trimmed)")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: trimmed, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw SandboxError("instance root is missing or stale: \(trimmed)")
        }
        guard GitHead.gitDirectory(repoRoot: trimmed) != nil else {
            throw SandboxError("instance root is not a git checkout: \(trimmed)")
        }
        let root = URL(fileURLWithPath: trimmed).standardizedFileURL
        let dopeRoot = root.appendingPathComponent(".gmcc", isDirectory: true)
        // Symlink guard: standardizedFileURL is lexical, so a symlinked
        // .gmcc or .gmcc/dope would redirect every "contained" path (and the
        // atomic swap) outside the repo. resolvingSymlinksInPath resolves the
        // components that exist — refuse when the resolved dope root leaves
        // the resolved instance root.
        let resolvedRoot = root.resolvingSymlinksInPath()
        let resolvedDope = dopeRoot.resolvingSymlinksInPath()
        guard resolvedDope.path.hasPrefix(resolvedRoot.path + "/") else {
            throw SandboxError(
                "refusing symlinked dope root: \(dopeRoot.path) resolves to \(resolvedDope.path)")
        }
        return DopeRepoSandbox(instanceRoot: root, dopeRoot: dopeRoot)
    }

    // MARK: - Contained paths

    public var mainFile: URL {
        dopeRoot.appendingPathComponent(DopeDocumentCodec.scopeFileName)
    }

    public var persistenceDirectory: URL {
        dopeRoot.appendingPathComponent(
            DopeDocumentCodec.persistenceDirectoryName, isDirectory: true)
    }

    public var cogsDirectory: URL {
        dopeRoot.appendingPathComponent(DopeDocumentCodec.cogsDirectoryName, isDirectory: true)
    }

    /// The retired `.gmcc/dope` tree. Named ONLY so callers can detect and
    /// report a stale checkout; nothing reads or writes through it.
    public var legacyDopeRoot: URL {
        dopeRoot.appendingPathComponent(
            DopeDocumentCodec.legacyDopeDirectoryName, isDirectory: true)
    }

    public func cogDirectory(code: String) throws -> URL {
        try DopeCode.validateCode(code, field: "cog code")
        return try contained(cogsDirectory.appendingPathComponent(code, isDirectory: true))
    }

    public func cogIndexFile(code: String) throws -> URL {
        let dir = try cogDirectory(code: code)
        return try contained(dir.appendingPathComponent(
            "\(code).index\(DopeDocumentCodec.cogFileSuffix)"))
    }

    /// One domain's directory. The layout gained a level, and the old
    /// single-flat-segment helper did not generalise — every segment below
    /// is validated here rather than assumed.
    public func domainDirectory(code: String) throws -> URL {
        try DopeCode.validateCode(code, field: "domain code")
        return try contained(persistenceDirectory.appendingPathComponent(code, isDirectory: true))
    }

    public func domainIndexFile(code: String) throws -> URL {
        let dir = try domainDirectory(code: code)
        return try contained(dir.appendingPathComponent(
            "\(code).index\(DopeDocumentCodec.persistenceFileSuffix)"))
    }

    public func domainEntityFile(domain: String, entity: String) throws -> URL {
        try DopeCode.validateCode(entity, field: "entity code")
        let dir = try domainDirectory(code: domain)
        return try contained(dir.appendingPathComponent(
            DopePersistenceIndexDocument.expectedEntityFile(domain: domain, entity: entity)))
    }

    public func domainEnumFile(domain: String, enumCode: String) throws -> URL {
        try DopeCode.validateCode(enumCode, field: "enum code")
        let dir = try domainDirectory(code: domain)
        return try contained(dir.appendingPathComponent(
            DopePersistenceIndexDocument.expectedEnumFile(domain: domain, enumCode: enumCode)))
    }

    /// The final belt-and-braces guard on every path this type hands out —
    /// symlink-resolving, not lexical (a symlinked domains/ or domain file
    /// must not smuggle a read/write outside the dope root).
    private func contained(_ url: URL) throws -> URL {
        let standardized = url.standardizedFileURL
        let resolved = standardized.resolvingSymlinksInPath()
        let resolvedRoot = dopeRoot.resolvingSymlinksInPath()
        guard resolved.path.hasPrefix(resolvedRoot.path + "/") else {
            throw SandboxError("path escapes the dope root: \(url.path)")
        }
        return standardized
    }

    // MARK: - Read

    public struct RepoBundle: Sendable {
        public let bundle: DopeDocumentBundle
        public let warnings: [String]
    }

    /// Reads `scope.doped.json`, then ONLY the files its map names — after
    /// re-deriving each value from its key — and for each domain, only the
    /// entity/enum files ITS index names, re-derived the same way. Never
    /// globs. The map is data at BOTH levels, never followed.
    public func readBundle() throws -> RepoBundle {
        let mainURL = mainFile
        guard FileManager.default.fileExists(atPath: mainURL.path) else {
            throw SandboxError("no dope tree on disk: \(mainURL.path) does not exist")
        }
        let main: DopeScopeDocument
        do {
            let data = try Data(contentsOf: mainURL)
            main = try DopeDocumentCodec.decoder.decode(DopeScopeDocument.self, from: data)
        } catch let error as DecodingError {
            throw SandboxError("\(DopeDocumentCodec.scopeFileName) failed to parse: \(error)")
        }

        var warnings: [String] = []
        var files: [DopePersistenceFileDocument] = []
        for (code, mapped) in main.persistence.sorted(by: { $0.key < $1.key }) {
            let expected = DopeScopeDocument.expectedFile(forPersistenceCode: code)
            guard mapped == expected else {
                throw SandboxError(
                    "\(DopeDocumentCodec.scopeFileName) maps persistence '\(code)' to '\(mapped)' — refused; expected '\(expected)' (the map is data, never followed)")
            }
            files.append(try readDomain(code: code, warnings: &warnings))
        }
        for orphan in try unreferencedDomainDirectories(referenced: Set(main.persistence.keys)) {
            warnings.append("unreferenced persistence directory on disk: \(orphan)")
        }

        // Cogs: same chain, same map-is-data rule.
        var cogs: [DopeCogDocument] = []
        for (code, mapped) in main.cogs.sorted(by: { $0.key < $1.key }) {
            let expected = DopeScopeDocument.expectedCogFile(forCogCode: code)
            guard mapped == expected else {
                throw SandboxError(
                    "\(DopeDocumentCodec.scopeFileName) maps cog '\(code)' to '\(mapped)' — refused; expected '\(expected)' (the map is data, never followed)")
            }
            let url = try cogIndexFile(code: code)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SandboxError("cog index missing: \(expected)")
            }
            do {
                let doc = try DopeDocumentCodec.decoder.decode(
                    DopeCogDocument.self, from: try Data(contentsOf: url))
                guard doc.body.code == code else {
                    throw SandboxError(
                        "cog index for '\(code)' declares code '\(doc.body.code)' — directory name and code must agree")
                }
                cogs.append(doc)
            } catch let error as DecodingError {
                throw SandboxError("\(expected) failed to parse: \(error)")
            }
        }
        for orphan in try unreferencedCogDirectories(referenced: Set(main.cogs.keys)) {
            warnings.append("unreferenced cog directory on disk: \(orphan)")
        }

        return RepoBundle(
            bundle: DopeDocumentBundle(main: main, domainFiles: files, cogFiles: cogs),
            warnings: warnings)
    }

    /// Assembles ONE domain from its index plus the entity/enum files the
    /// index names. The returned value is the same shape the old
    /// one-file-per-domain layout produced, so nothing downstream changes.
    private func readDomain(code: String, warnings: inout [String]) throws
        -> DopePersistenceFileDocument
    {
        let indexURL = try domainIndexFile(code: code)
        guard FileManager.default.fileExists(atPath: indexURL.path) else {
            throw SandboxError(
                "persistence index missing: \(DopeScopeDocument.expectedFile(forPersistenceCode: code))")
        }
        let index: DopePersistenceIndexDocument
        do {
            let data = try Data(contentsOf: indexURL)
            index = try DopeDocumentCodec.decoder.decode(
                DopePersistenceIndexDocument.self, from: data)
        } catch let error as DecodingError {
            throw SandboxError("\(code).index failed to parse: \(error)")
        }
        guard index.body.code == code else {
            throw SandboxError(
                "persistence index for '\(code)' declares code '\(index.body.code)' — directory name and code must agree")
        }

        var entities: [DopeEntityDocument] = []
        for (entityCode, mapped) in index.entities.sorted(by: { $0.key < $1.key }) {
            let expected = DopePersistenceIndexDocument.expectedEntityFile(
                domain: code, entity: entityCode)
            guard mapped == expected else {
                throw SandboxError(
                    "\(code) index maps entity '\(entityCode)' to '\(mapped)' — refused; expected '\(expected)' (the map is data, never followed)")
            }
            let url = try domainEntityFile(domain: code, entity: entityCode)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SandboxError("entity file missing: \(expected)")
            }
            do {
                let file = try DopeDocumentCodec.decoder.decode(
                    DopeEntityFileDocument.self, from: try Data(contentsOf: url))
                guard file.body.code == entityCode else {
                    throw SandboxError(
                        "\(expected) declares code '\(file.body.code)' — file name and code must agree")
                }
                entities.append(DopeEntityDocument(body: file.body, properties: file.properties))
            } catch let error as DecodingError {
                throw SandboxError("\(expected) failed to parse: \(error)")
            }
        }

        var enums: [DopeEnumDocument] = []
        for (enumCode, mapped) in index.enums.sorted(by: { $0.key < $1.key }) {
            let expected = DopePersistenceIndexDocument.expectedEnumFile(
                domain: code, enumCode: enumCode)
            guard mapped == expected else {
                throw SandboxError(
                    "\(code) index maps enum '\(enumCode)' to '\(mapped)' — refused; expected '\(expected)' (the map is data, never followed)")
            }
            let url = try domainEnumFile(domain: code, enumCode: enumCode)
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw SandboxError("enum file missing: \(expected)")
            }
            do {
                let file = try DopeDocumentCodec.decoder.decode(
                    DopeEnumFileDocument.self, from: try Data(contentsOf: url))
                guard file.body.code == enumCode else {
                    throw SandboxError(
                        "\(expected) declares code '\(file.body.code)' — file name and code must agree")
                }
                enums.append(DopeEnumDocument(body: file.body, options: file.options))
            } catch let error as DecodingError {
                throw SandboxError("\(expected) failed to parse: \(error)")
            }
        }

        // Unreferenced files inside a domain directory are surfaced, not
        // silently ignored — the pruning pass removes them on write.
        for orphan in try unreferencedDomainMemberFiles(domain: code, index: index) {
            warnings.append(
                "unreferenced file in persistence/\(code): \(orphan)")
        }

        return DopePersistenceFileDocument(
            version: index.version, body: index.body, entities: entities, enums: enums)
    }

    /// Peek at the on-disk revision without a full parse. Nil when no tree
    /// exists on disk.
    public func peekRevision() -> Int64? {
        guard let data = try? Data(contentsOf: mainFile),
              let main = try? DopeDocumentCodec.decoder.decode(DopeScopeDocument.self, from: data)
        else { return nil }
        return main.version
    }

    // MARK: - Write

    public struct WriteResult: Sendable {
        public let written: [String]
        public let pruned: [String]
    }

    /// Subtree-atomic write.
    ///
    /// The complete new `persistence/` (and `cogs/`) tree is staged under
    /// `.gmcc/.dope-staging-{uuid}` and swapped in with replaceItemAt — same
    /// volume by construction, so a crash mid-write leaves the previous
    /// subtree byte-intact and a reader never sees a half-written domain.
    ///
    /// `scope.doped.json` is written LAST and deliberately: it is the version
    /// authority, so a crash between the subtree swap and the index write
    /// leaves an index that reports a revision BEHIND the files. That is the
    /// benign direction — `peekRevision` sees it as stale and re-running
    /// write-repo repairs it — whereas writing the index first would claim a
    /// revision the files do not yet contain.
    ///
    /// Returned paths are instance-root-relative.
    public func writeAtomically(_ bundle: DopeDocumentBundle) throws -> WriteResult {
        let fm = FileManager.default
        let staging = dopeRoot.appendingPathComponent(
            ".dope-staging-\(UUID().uuidString.lowercased())", isDirectory: true)
        defer { try? fm.removeItem(at: staging) }

        var pruned = try unreferencedDomainDirectories(
            referenced: Set(bundle.domainFiles.map(\.body.code)))
        pruned += try unreferencedCogDirectories(
            referenced: Set(bundle.cogFiles.map(\.body.code)))
        pruned.sort()

        let stagedPersistence = staging.appendingPathComponent(
            DopeDocumentCodec.persistenceDirectoryName, isDirectory: true)
        try fm.createDirectory(at: stagedPersistence, withIntermediateDirectories: true)
        let stagedCogs = staging.appendingPathComponent(
            DopeDocumentCodec.cogsDirectoryName, isDirectory: true)
        try fm.createDirectory(at: stagedCogs, withIntermediateDirectories: true)

        var written: [String] = []
        func stage(_ data: Data, _ relative: String) throws {
            let url = staging.appendingPathComponent(relative)
            try fm.createDirectory(at: url.deletingLastPathComponent(),
                                   withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
            written.append(".gmcc/" + relative)
        }

        for file in bundle.domainFiles {
            let code = file.body.code
            try DopeCode.validateCode(code, field: "domain code")
            let dir = DopeScopeDocument.expectedDirectory(forPersistenceCode: code)

            for entity in file.entities {
                try DopeCode.validateCode(entity.body.code, field: "entity code")
                let name = DopePersistenceIndexDocument.expectedEntityFile(
                    domain: code, entity: entity.body.code)
                try stage(
                    DopeDocumentCodec.encoder.encode(
                        DopeEntityFileDocument(version: file.version, body: entity.body,
                                               properties: entity.properties)),
                    "\(dir)/\(name)")
            }
            for en in file.enums {
                try DopeCode.validateCode(en.body.code, field: "enum code")
                let name = DopePersistenceIndexDocument.expectedEnumFile(
                    domain: code, enumCode: en.body.code)
                try stage(
                    DopeDocumentCodec.encoder.encode(
                        DopeEnumFileDocument(version: file.version, body: en.body,
                                             options: en.options)),
                    "\(dir)/\(name)")
            }
            let index = DopePersistenceIndexDocument(
                version: file.version,
                body: file.body,
                entities: Dictionary(uniqueKeysWithValues: file.entities.map {
                    ($0.body.code,
                     DopePersistenceIndexDocument.expectedEntityFile(
                        domain: code, entity: $0.body.code))
                }),
                enums: Dictionary(uniqueKeysWithValues: file.enums.map {
                    ($0.body.code,
                     DopePersistenceIndexDocument.expectedEnumFile(
                        domain: code, enumCode: $0.body.code))
                }))
            try stage(DopeDocumentCodec.encoder.encode(index),
                      DopeScopeDocument.expectedFile(forPersistenceCode: code))
        }

        for cog in bundle.cogFiles {
            try DopeCode.validateCode(cog.body.code, field: "cog code")
            try stage(DopeDocumentCodec.encoder.encode(cog),
                      DopeScopeDocument.expectedCogFile(forCogCode: cog.body.code))
        }

        // Swap the dope-owned subtree only. `.gmcc/` itself is NOT replaced:
        // it holds `.screenshots/` and this staging directory, which a
        // whole-directory swap would delete.
        try fm.createDirectory(at: dopeRoot, withIntermediateDirectories: true)
        if fm.fileExists(atPath: persistenceDirectory.path) {
            _ = try fm.replaceItemAt(persistenceDirectory, withItemAt: stagedPersistence)
        } else {
            try fm.moveItem(at: stagedPersistence, to: persistenceDirectory)
        }
        if fm.fileExists(atPath: cogsDirectory.path) {
            _ = try fm.replaceItemAt(cogsDirectory, withItemAt: stagedCogs)
        } else {
            try fm.moveItem(at: stagedCogs, to: cogsDirectory)
        }

        // Index last — see the note above on the benign failure direction.
        let mainData = try DopeDocumentCodec.encoder.encode(bundle.main)
        try mainData.write(to: mainFile, options: .atomic)
        written.append(".gmcc/" + DopeDocumentCodec.scopeFileName)

        return WriteResult(written: written.sorted(), pruned: pruned)
    }

    /// Bounded stale scan: exactly one non-recursive listing of
    /// `persistence/`, yielding directories no longer referenced by the
    /// scope map.
    ///
    /// Deliberately NOT recursive. A non-recursive listing structurally
    /// cannot name a path outside the directory it lists; making the scan
    /// recursive would hand the pruner the ability to delete anywhere
    /// beneath the tree, which is a materially weaker safety property for a
    /// function whose whole job is removal. Stale files INSIDE a live
    /// domain directory are handled by replaceItemAt, which swaps the
    /// directory wholesale, so a recursive prune would buy nothing.
    private func unreferencedDomainDirectories(referenced: Set<String>) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: persistenceDirectory.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: persistenceDirectory.path)
            .filter { !referenced.contains($0) && !$0.hasPrefix(".") }
            .map { "\(DopeDocumentCodec.persistenceDirectoryName)/\($0)" }
            .sorted()
    }

    /// Cog directories no longer referenced by the scope map. Same
    /// non-recursive discipline as the persistence scan.
    private func unreferencedCogDirectories(referenced: Set<String>) throws -> [String] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: cogsDirectory.path) else { return [] }
        return try fm.contentsOfDirectory(atPath: cogsDirectory.path)
            .filter { !referenced.contains($0) && !$0.hasPrefix(".") }
            .map { "\(DopeDocumentCodec.cogsDirectoryName)/\($0)" }
            .sorted()
    }

    /// Files inside a live domain directory that its index does not name.
    /// Read-side reporting only — the write path removes them by swapping
    /// the whole directory.
    private func unreferencedDomainMemberFiles(
        domain: String, index: DopePersistenceIndexDocument
    ) throws -> [String] {
        let fm = FileManager.default
        let dir = try domainDirectory(code: domain)
        guard fm.fileExists(atPath: dir.path) else { return [] }
        var expected = Set(index.entities.values)
        expected.formUnion(index.enums.values)
        expected.insert("\(domain).index\(DopeDocumentCodec.persistenceFileSuffix)")
        return try fm.contentsOfDirectory(atPath: dir.path)
            .filter { $0.hasSuffix(DopeDocumentCodec.persistenceFileSuffix) }
            .filter { !expected.contains($0) }
            .sorted()
    }
}
