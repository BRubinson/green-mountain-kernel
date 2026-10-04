import Foundation
import GRDB

// VOCABULARY: "Repo" in this file means the USER'S GIT REPO (the {instance_root}/.gmcc tree),
// NOT the repository pattern — data access lives in DiagramRepository. Filesystem work never
// enters a db transaction (the four-phase contract below).

/// PUBLIC-diagram serialization — the dope repo verbs' twins, four-phase
/// orchestration and all. The gate is the SAME gate: only a SESSION can resolve
/// an instance root, which is why PUBLIC is SESSION-tier only.
/// Files live at `{instance_root}/.gmcc/diagrams/{code}.diagram.doped.json`.
/// write-repo is EXPLICIT, since setting PUBLIC must never churn the user's git
/// status; ingest is files→db and strictly forward-only, so a stale checkout
/// cannot clobber newer db work.
extension Store {

    static let diagramRepoSubdirectory = ".gmcc/diagrams"

    /// Returns the path to the diagram repository directory for a given root.
    ///
    /// - Parameter root: The instance root directory path.
    /// - Returns: A URL pointing to the `.gmcc/diagrams` directory.
    private func diagramRepoDirectory(root: String) -> URL {
        URL(fileURLWithPath: root)
            .appendingPathComponent(Self.diagramRepoSubdirectory, isDirectory: true)
    }

    // MARK: - write-repo

    /// Writes all public session diagrams to disk, then prunes stale files.
    ///
    /// - Parameter req: The diagram write request specifying the session and force flag.
    /// - Returns: The response with written and pruned file codes and directory path.
    /// - Throws: `StoreError` on validation, composition, revision conflict or I/O failures.
    func diagramWriteRepo(_ req: DiagramWriteRepoRequest) throws -> DiagramWriteRepoResponse {
        // FOUR-PHASE VERB — must not run inside a caller-opened transaction.
        // Phase 3 does filesystem work while holding NO db lock, by design.
        // Composing this would pin the single writer across file I/O and block
        // every other writer in the machine, hooks included, on someone else's
        // disk. Refusing loudly in five places beats maintaining a list of
        // which of ~230 verbs are composable.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "diagramWriteRepo")
        }
        let (root, projected, knownRevisions) = try diagramWriteRepoProjection(req)

        // Phase 3 — gate + write + prune, no db lock held.
        let directory = diagramRepoDirectory(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        if req.force != true {
            try diagramRepoFilesAheadGate(projected, directory: directory)
        }

        var written: [String] = []
        for item in projected {
            let url = directory.appendingPathComponent(
                DiagramDocumentCodec.fileName(code: item.code)
            )
            try DiagramDocumentCodec.encode(item.document).write(to: url, options: .atomic)
            written.append(item.code)
        }

        let pruned = pruneDiagramRepoFiles(
            directory: directory,
            written: written,
            knownRevisions: knownRevisions,
            force: req.force
        )

        try recordDiagramWriteRepo(req, written: written, pruned: pruned)
        return DiagramWriteRepoResponse(
            written: written,
            pruned: pruned,
            root: directory.path
        )
    }

    /// One PUBLIC diagram projected to its file document, with the revision it was projected at.
    private struct DiagramRepoProjection {
        let code: String
        let revision: Int64
        let document: DiagramDocument
    }

    /// Phase 1 of write-repo: root, every PUBLIC SESSION-tier tree, and every session revision.
    ///
    /// - Parameter req: The diagram write request naming the session.
    /// - Returns: The instance root, the projected public diagrams, and each session code's revision.
    /// - Throws: `StoreError` when the session is missing or a tree cannot be read.
    private func diagramWriteRepoProjection(
        _ req: DiagramWriteRepoRequest
    ) throws -> (String, [DiagramRepoProjection], [String: Int64]) {
        // Phase 1 — root + every PUBLIC SESSION-tier tree, in one read.
        try boundaryRead { db in
            let diagrams = DiagramRepository(db: db, core: self.core)
            try diagrams.requireSession(uuid: req.sessionUuid)
            let root = try self.instanceRoot(db, sessionUuid: req.sessionUuid)
            let rows = try diagrams.publicSessionDiagrams(sessionUuid: req.sessionUuid)
            let projected =
                try rows
                .map { diagram in
                    DiagramRepoProjection(
                        code: diagram.code,
                        revision: diagram.revision,
                        // Phase 2 inline — the projection is pure.
                        document: DiagramDocumentCodec.document(
                            from: try self.fetchDiagramTree(db, diagram: diagram),
                            dopeScopeCode: diagram.dopeScopeCode
                        )
                    )
                }
            // EVERY session row, any visibility — the prune gate below may
            // only delete a file the db demonstrably subsumes.
            let knownRevisions = try diagrams.sessionDiagramRevisions(
                sessionUuid: req.sessionUuid
            )
            return (root, projected, knownRevisions)
        }
    }

    /// Refuses the whole write pass when any target file on disk is stamped ahead of its row.
    ///
    /// - Parameters:
    ///   - projected: The projected diagrams about to be written.
    ///   - directory: The diagram repo directory.
    /// - Throws: `StoreError.revisionConflict` for the first file stamped ahead of its row.
    private func diagramRepoFilesAheadGate(
        _ projected: [DiagramRepoProjection],
        directory: URL
    ) throws {
        // Files-ahead gate BEFORE any write (all-or-nothing like dope's
        // whole-tree swap): one ahead file refuses the whole pass.
        for item in projected {
            let url = directory.appendingPathComponent(
                DiagramDocumentCodec.fileName(code: item.code)
            )
            if let data = try? Data(contentsOf: url),
                let onDisk = DiagramDocumentCodec.peekVersion(data),
                onDisk > item.revision
            {
                throw StoreError.revisionConflict(
                    scopeUuid: item.code,
                    expected: onDisk,
                    actual: item.revision
                )
            }
        }
    }

    /// Removes diagram files not just written that the db demonstrably subsumes.
    ///
    /// - Parameters:
    ///   - directory: The diagram repo directory.
    ///   - written: The codes written in this pass.
    ///   - knownRevisions: Every session diagram code's db revision.
    ///   - force: True to prune every unwritten diagram file regardless of rows or stamps.
    /// - Returns: The codes whose files were pruned.
    private func pruneDiagramRepoFiles(
        directory: URL,
        written: [String],
        knownRevisions: [String: Int64],
        force: Bool
    ) -> [String] {
        let fm = FileManager.default
        // Prune ONLY files the db demonstrably subsumes: a session row exists for
        // the code and the file's stamp is not ahead of that row. A file with NO
        // session row, or one stamped AHEAD, is someone else's work and survives
        // without --force.
        var pruned: [String] = []
        let keep = Set(written.map { DiagramDocumentCodec.fileName(code: $0) })
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasSuffix(DiagramDocumentCodec.fileSuffix) && !keep.contains(name) {
            let code = String(name.dropLast(DiagramDocumentCodec.fileSuffix.count))
            let url = directory.appendingPathComponent(name)
            if force != true {
                guard let known = knownRevisions[code] else { continue }
                let onDisk =
                    (try? Data(contentsOf: url))
                    .flatMap(DiagramDocumentCodec.peekVersion) ?? Int64.max
                guard onDisk <= known else { continue }
            }
            try? fm.removeItem(at: url)
            pruned.append(code)
        }
        return pruned
    }

    /// Phase 4 of write-repo: the audit event and session touch, in one write transaction.
    ///
    /// - Parameters:
    ///   - req: The diagram write request naming the session and force flag.
    ///   - written: The codes written in this pass.
    ///   - pruned: The codes pruned in this pass.
    /// - Throws: `StoreError` or database errors from the event append or session touch.
    private func recordDiagramWriteRepo(
        _ req: DiagramWriteRepoRequest,
        written: [String],
        pruned: [String]
    ) throws {
        // Phase 4 — audit event only: a projection never bumps revision,
        // which is what makes a repeat run idempotent.
        try boundary { db in
            var payload: [String: Any] = [
                "action": "diagram_write_repo",
                "session_uuid": req.sessionUuid,
                "files_written": written,
            ]
            if req.force { payload["forced"] = true }
            if !pruned.isEmpty { payload["files_pruned"] = pruned }
            try self.appendEvent(
                db,
                kind: .diagramChange,
                subjectUuid: req.sessionUuid,
                payload: Store.jsonPayload(payload)
            )
            try self.touchSession(db, uuid: req.sessionUuid)
        }
    }

    // MARK: - ingest (files → db, strictly forward-only)

    /// Reads all diagram files from disk and ingests them into the database.
    ///
    /// - Parameter req: The diagram ingest request specifying the session.
    /// - Returns: The response with ingested and skipped codes, directory path, and warnings.
    /// - Throws: `StoreError` on composition, session validation or I/O failures.
    func diagramIngest(_ req: DiagramIngestRequest) throws -> DiagramIngestResponse {
        // FOUR-PHASE VERB — must not run inside a caller-opened transaction.
        // Phase 3 does filesystem work while holding NO db lock, by design.
        // Composing this would pin the single writer across file I/O and block
        // every other writer in the machine, hooks included, on someone else's
        // disk. Refusing loudly in five places beats maintaining a list of
        // which of ~230 verbs are composable.
        guard !isInTransaction else {
            throw StoreError.notComposable(verb: "diagramIngest")
        }
        // Phase 1 — root.
        let root = try boundaryRead { db -> String in
            try DiagramRepository(db: db, core: self.core).requireSession(uuid: req.sessionUuid)
            return try self.instanceRoot(db, sessionUuid: req.sessionUuid)
        }

        // Phase 3 — read every diagram file (before any write txn opens).
        let directory = diagramRepoDirectory(root: root)
        let (documents, warnings) = readDiagramRepoFiles(directory: directory)
        guard !documents.isEmpty else {
            return DiagramIngestResponse(
                ingested: [],
                skipped: [],
                root: directory.path,
                warnings: warnings
            )
        }
        return try landIngestedDiagrams(
            documents,
            sessionUuid: req.sessionUuid,
            directory: directory,
            warnings: warnings
        )
    }

    /// Reads every well-formed diagram file in the repo directory, warning on each one skipped.
    ///
    /// - Parameter directory: The diagram repo directory.
    /// - Returns: The decoded documents in file-name order, and one warning per skipped file.
    private func readDiagramRepoFiles(directory: URL) -> ([DiagramDocument], [String]) {
        var documents: [DiagramDocument] = []
        var warnings: [String] = []
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
            .filter { $0.hasSuffix(DiagramDocumentCodec.fileSuffix) }
            .sorted()
        for name in names {
            let url = directory.appendingPathComponent(name)
            // Per-file tolerance: one corrupt or mislabeled file warns and
            // is skipped — it must never abort the rest of the family's
            // sync (the boot path prints the warning; aborting there went
            // silently dead instead).
            guard let data = try? Data(contentsOf: url) else {
                warnings.append("\(name): unreadable — skipped")
                continue
            }
            guard let document = try? DiagramDocumentCodec.decode(data) else {
                warnings.append("\(name): not a valid diagram document — skipped")
                continue
            }
            let expected = DiagramDocumentCodec.fileName(code: document.code)
            guard expected == name else {
                warnings.append(
                    "\(name): names diagram code '\(document.code)' "
                        + "(file name is identity, expected \(expected)) — skipped"
                )
                continue
            }
            documents.append(document)
        }
        return (documents, warnings)
    }

    /// Phase 4 of ingest: lands every document under the per-file rules in one transaction.
    ///
    /// - Parameters:
    ///   - documents: The decoded diagram documents to land.
    ///   - sessionUuid: The session uuid that owns the diagrams.
    ///   - directory: The diagram repo directory reported back as the root.
    ///   - warnings: The warnings gathered while reading files, extended with refusals.
    /// - Returns: The response with ingested and skipped codes, directory path, and warnings.
    /// - Throws: Non-`StoreError` database errors, which roll the whole transaction back.
    private func landIngestedDiagrams(
        _ documents: [DiagramDocument],
        sessionUuid: String,
        directory: URL,
        warnings: [String]
    ) throws -> DiagramIngestResponse {
        var warnings = warnings
        // Phase 4 — one transaction, per-file landing rules:
        //   - code matches a PRIVATE row          → skip (never clobber
        //     personal state from the repo);
        //   - file version <= db revision         → skip (forward-only);
        //   - file version >  db revision         → replace tree in place
        //     (row uuid stable — registrations/qualifications survive);
        //   - no row                              → create SESSION + PUBLIC.
        return try boundary { db in
            var ingested: [String] = []
            var skipped: [String] = []
            for document in documents {
                do {
                    let existing = try DiagramRepository(db: db, core: self.core)
                        .sessionDiagram(sessionUuid: sessionUuid, code: document.code)
                    let landed: Bool
                    if let diagram = existing {
                        landed = try self.ingestReplace(db, document: document, over: diagram)
                    } else {
                        try self.ingestCreate(db, document: document, sessionUuid: sessionUuid)
                        landed = true
                    }
                    if landed {
                        ingested.append(document.code)
                    } else {
                        skipped.append(document.code)
                    }
                } catch let error as StoreError {
                    // A refused document (validation, containment, binding tier)
                    // warns and skips — same tolerance as a corrupt file. A
                    // partial insert cannot leak: badRequest throws BEFORE any
                    // row lands for that document, and the whole txn still
                    // rolls back on non-Store errors.
                    warnings.append("\(document.code): refused — \(error)")
                    skipped.append(document.code)
                }
            }
            return DiagramIngestResponse(
                ingested: ingested,
                skipped: skipped,
                root: directory.path,
                warnings: warnings
            )
        }
    }

    /// Replace a PUBLIC session row's tree in place when the file is newer.
    ///
    /// Returns false when the document is skipped: a private row, a file at
    /// or behind the db revision, or a revision race lost at the UPDATE.
    ///
    /// - Parameters:
    ///   - db: The database connection within a transaction.
    ///   - document: The diagram document to ingest.
    ///   - diagram: The existing diagram row to replace.
    /// - Returns: True when replaced; false when skipped.
    /// - Throws: `StoreError` on validation, binding, or database errors.
    private func ingestReplace(
        _ db: Database,
        document: DiagramDocument,
        over diagram: DiagramRow
    ) throws -> Bool {
        guard diagram.visibility == DiagramVisibility.public.rawValue else { return false }
        guard document.version > diagram.revision else { return false }
        let diagrams = DiagramRepository(db: db, core: core)
        guard try diagrams.landIngestedDiagram(uuid: diagram.uuid, document: document) else {
            return false
        }
        try diagrams.deleteDiagramElements(diagramUuid: diagram.uuid)
        try insertDocumentElements(db, diagramUuid: diagram.uuid, document: document)
        guard let refreshed = try fetchDiagram(db, uuid: diagram.uuid) else {
            throw StoreError.corruptState(entity: "diagram", detail: "vanished during ingest")
        }
        try recordDiagramChange(
            db,
            diagram: refreshed,
            action: "ingest",
            elementUuid: nil,
            mutationCount: nil,
            revision: refreshed.revision
        )
        return true
    }

    /// Create a SESSION + PUBLIC row for a document with no row yet.
    ///
    /// - Parameters:
    ///   - db: The database connection within a transaction.
    ///   - document: The diagram document to ingest.
    ///   - sessionUuid: The session uuid that owns the new diagram.
    /// - Throws: `StoreError` on validation, binding, or database errors.
    private func ingestCreate(
        _ db: Database,
        document: DiagramDocument,
        sessionUuid: String
    ) throws {
        try DopeCode.validateCode(document.code, field: "diagram code")
        let owner = try resolveDiagramOwner(
            db,
            projectUuid: nil,
            instanceUuid: nil,
            sessionUuid: sessionUuid,
            promptUuid: nil
        )
        if let binding = document.dopeScopeCode {
            try validateDiagramScopeBinding(db, owner: owner, code: binding)
        }
        let uuid = try insertBase(
            db,
            table: "diagram",
            extra: [
                "project_uuid": owner.projectUuid,
                "session_uuid": owner.sessionUuid,
                "prompt_uuid": nil,
                "tier": DiagramTier.session.rawValue,
                "code": document.code,
                "name": document.name,
                "description": document.description,
                "gmcc_diagram_path": nil,
                "dope_scope_code": document.dopeScopeCode,
                "revision": document.version,
                "visibility": DiagramVisibility.public.rawValue,
            ]
        )
        try insertDocumentElements(db, diagramUuid: uuid, document: document)
        guard let created = try fetchDiagram(db, uuid: uuid) else {
            throw StoreError.corruptState(entity: "diagram", detail: "vanished after ingest insert")
        }
        try recordDiagramChange(
            db,
            diagram: created,
            action: "ingest",
            elementUuid: nil,
            mutationCount: nil,
            revision: created.revision
        )
    }

    /// Inserts diagram elements from a document in two passes.
    ///
    /// Two passes: insert every element (fresh uuids — the locked
    /// no-smart-diff consequence, exactly like dope ingest), THEN resolve
    /// connector code paths against the freshly minted uuid map. A path that
    /// resolves to nothing stays NULL — the ghost travels as a ghost.
    ///
    /// - Parameters:
    ///   - db: The database connection within a transaction.
    ///   - diagramUuid: The diagram uuid to insert elements into.
    ///   - document: The diagram document containing the elements to insert.
    /// - Throws: `StoreError` on validation, shape, or database errors.
    private func insertDocumentElements(
        _ db: Database,
        diagramUuid: String,
        document: DiagramDocument
    ) throws {
        var uuidByPath: [String: String] = [:]
        var connectorTargets: [(elementUuid: String, path: String)] = []

        func insert(
            _ doc: DiagramDocument.ElementDoc,
            parentUuid: String?,
            prefix: String
        ) throws {
            let path = prefix.isEmpty ? doc.code : "\(prefix)/\(doc.code)"
            // The write door's own shape check — files are hand-editable
            // and merge-mangled, and a row the reducer would refuse must
            // not land via ingest either.
            let parentInfo = try parentUuid.map { try fetchElementInfo(db, uuid: $0) }
            try validateDiagramElementShape(
                db,
                diagramUuid: diagramUuid,
                type: doc.payload.elementType,
                parent: parentInfo,
                payload: doc.payload
            )
            let uuid = try insertBase(
                db,
                table: "diagram_element",
                extra: [
                    "diagram_uuid": diagramUuid,
                    "parent_element_uuid": parentUuid,
                    "element_type": doc.payload.elementType.rawValue,
                    "code": doc.code,
                    "name": doc.name,
                    "description": doc.description,
                    "sort_order": doc.sortOrder,
                    "center_x": doc.centerX,
                    "center_y": doc.centerY,
                    "element_z": doc.elementZ,
                    "scale": doc.scale,
                ]
            )
            try insertSubtypeRow(
                db,
                elementUuid: uuid,
                payload: DiagramStrokeCodec.normalizedForStorage(doc.payload)
            )
            uuidByPath[path] = uuid
            if case .connector = doc.payload, let target = doc.targetCodePath {
                connectorTargets.append((uuid, target))
            }
            for child in doc.children {
                try insert(child, parentUuid: uuid, prefix: path)
            }
        }
        for element in document.elements {
            try insert(element, parentUuid: nil, prefix: "")
        }
        let diagrams = DiagramRepository(db: db, core: core)
        for target in connectorTargets {
            guard let resolved = uuidByPath[target.path] else { continue }
            try diagrams.setConnectorTarget(
                elementUuid: target.elementUuid,
                targetElementUuid: resolved
            )
        }
    }
}
