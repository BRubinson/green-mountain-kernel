import Foundation
import GRDB

// VOCABULARY: "Repo" in this file means the USER'S GIT REPO (the {instance_root}/.gmcc tree),
// NOT the repository pattern — data access lives in DiagramRepository. Filesystem work never
// enters a db transaction (the four-phase contract below).

/// PUBLIC-diagram serialization — the dope repo verbs' twins, four-phase
/// orchestration and all (db read / pure projection / fs with no db lock /
/// db audit or ingest write). The gate is the SAME gate: only a SESSION can
/// resolve an instance root, which is why PUBLIC is SESSION-tier only.
///
/// Files live at `{instance_root}/.gmcc/diagrams/{code}.diagram.doped.json`.
/// write-repo is EXPLICIT (setting PUBLIC never writes files — a pencil
/// stroke must never churn the user's git status); ingest is files→db and
/// strictly forward-only (a stale checkout can never clobber newer db work).
extension Store {

    static let diagramRepoSubdirectory = ".gmcc/diagrams"

    private func diagramRepoDirectory(root: String) -> URL {
        URL(fileURLWithPath: root)
            .appendingPathComponent(Self.diagramRepoSubdirectory, isDirectory: true)
    }

    // MARK: - write-repo

    public func diagramWriteRepo(_ req: DiagramWriteRepoRequest) throws -> DiagramWriteRepoResponse {
        // Phase 1 — root + every PUBLIC SESSION-tier tree, in one read.
        struct Projected {
            let code: String
            let revision: Int64
            let document: DiagramDocument
        }
        let (root, projected, knownRevisions):
            (String, [Projected], [String: Int64]) = try dbQueue.read { db in
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [req.sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: req.sessionUuid)
            }
            let root = try self.instanceRoot(db, sessionUuid: req.sessionUuid)
            let rows = try Row.fetchAll(db, sql: """
                \(DiagramRepository.diagramSelect)
                 WHERE d.tier = ? AND d.session_uuid = ? AND d.visibility = ?
                 ORDER BY d.code
                """, arguments: [DiagramTier.session.rawValue, req.sessionUuid,
                                 DiagramVisibility.public.rawValue])
            let projected = try rows.map(DiagramRepository.diagramRow).map { diagram in
                Projected(
                    code: diagram.code, revision: diagram.revision,
                    // Phase 2 inline — the projection is pure.
                    document: DiagramDocumentCodec.document(
                        from: try self.fetchDiagramTree(db, diagram: diagram),
                        dopeScopeCode: diagram.dopeScopeCode))
            }
            // EVERY session row, any visibility — the prune gate below may
            // only delete a file the db demonstrably subsumes.
            var knownRevisions: [String: Int64] = [:]
            for row in try Row.fetchAll(db, sql: """
                SELECT code, revision FROM diagram
                 WHERE tier = ? AND session_uuid = ?
                """, arguments: [DiagramTier.session.rawValue, req.sessionUuid]) {
                knownRevisions[row["code"]] = row["revision"]
            }
            return (root, projected, knownRevisions)
        }

        // Phase 3 — gate + write + prune, no db lock held.
        let directory = diagramRepoDirectory(root: root)
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // Files-ahead gate BEFORE any write (all-or-nothing like dope's
        // whole-tree swap): one ahead file refuses the whole pass.
        if req.force != true {
            for item in projected {
                let url = directory.appendingPathComponent(
                    DiagramDocumentCodec.fileName(code: item.code))
                if let data = try? Data(contentsOf: url),
                   let onDisk = DiagramDocumentCodec.peekVersion(data),
                   onDisk > item.revision {
                    throw StoreError.revisionConflict(
                        scopeUuid: item.code, expected: onDisk, actual: item.revision)
                }
            }
        }

        var written: [String] = []
        for item in projected {
            let url = directory.appendingPathComponent(
                DiagramDocumentCodec.fileName(code: item.code))
            try DiagramDocumentCodec.encode(item.document).write(to: url, options: .atomic)
            written.append(item.code)
        }

        // Prune — but ONLY files the db demonstrably subsumes: a session
        // row exists for the code (demoted/deleted-to-PRIVATE) AND the
        // file's stamp is not ahead of that row. A file with NO session row
        // (a teammate's diagram pulled but not yet ingested) or a file
        // stamped AHEAD is someone else's work and survives without
        // --force — the same gate the write path honors, applied to the
        // delete path it used to bypass.
        var pruned: [String] = []
        let keep = Set(written.map { DiagramDocumentCodec.fileName(code: $0) })
        for name in (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        where name.hasSuffix(DiagramDocumentCodec.fileSuffix) && !keep.contains(name) {
            let code = String(name.dropLast(DiagramDocumentCodec.fileSuffix.count))
            let url = directory.appendingPathComponent(name)
            if req.force != true {
                guard let known = knownRevisions[code] else { continue }
                let onDisk = (try? Data(contentsOf: url))
                    .flatMap(DiagramDocumentCodec.peekVersion) ?? Int64.max
                guard onDisk <= known else { continue }
            }
            try? fm.removeItem(at: url)
            pruned.append(code)
        }

        // Phase 4 — audit event only: a projection never bumps revision,
        // which is what makes a repeat run idempotent.
        try dbQueue.write { db in
            var payload: [String: Any] = [
                "action": "diagram_write_repo",
                "session_uuid": req.sessionUuid,
                "files_written": written,
            ]
            if req.force { payload["forced"] = true }
            if !pruned.isEmpty { payload["files_pruned"] = pruned }
            try self.appendEvent(db, kind: .diagramChange, subjectUuid: req.sessionUuid,
                                 payload: Store.jsonPayload(payload))
            try self.touchSession(db, uuid: req.sessionUuid)
        }
        return DiagramWriteRepoResponse(written: written, pruned: pruned,
                                        root: directory.path)
    }

    // MARK: - ingest (files → db, strictly forward-only)

    public func diagramIngest(_ req: DiagramIngestRequest) throws -> DiagramIngestResponse {
        // Phase 1 — root.
        let root = try dbQueue.read { db -> String in
            guard try Row.fetchOne(
                db, sql: "SELECT 1 FROM session WHERE uuid = ?", arguments: [req.sessionUuid]
            ) != nil else {
                throw StoreError.notFound(entity: "session", key: req.sessionUuid)
            }
            return try self.instanceRoot(db, sessionUuid: req.sessionUuid)
        }

        // Phase 3 — read every diagram file (before any write txn opens).
        let directory = diagramRepoDirectory(root: root)
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
                warnings.append("\(name): names diagram code '\(document.code)' "
                                + "(file name is identity, expected \(expected)) — skipped")
                continue
            }
            documents.append(document)
        }
        guard !documents.isEmpty else {
            return DiagramIngestResponse(ingested: [], skipped: [],
                                         warnings: warnings, root: directory.path)
        }

        // Phase 4 — one transaction, per-file landing rules:
        //   - code matches a PRIVATE row          → skip (never clobber
        //     personal state from the repo);
        //   - file version <= db revision         → skip (forward-only);
        //   - file version >  db revision         → replace tree in place
        //     (row uuid stable — registrations/qualifications survive);
        //   - no row                              → create SESSION + PUBLIC.
        return try dbQueue.write { db in
            var ingested: [String] = []
            var skipped: [String] = []
            for document in documents {
              do {
                let existing = try Row.fetchOne(db, sql: """
                    \(DiagramRepository.diagramSelect)
                     WHERE d.tier = ? AND d.session_uuid = ? AND d.code = ?
                    """, arguments: [DiagramTier.session.rawValue, req.sessionUuid,
                                     document.code]).map(DiagramRepository.diagramRow)
                if let diagram = existing {
                    guard diagram.visibility == DiagramVisibility.public.rawValue else {
                        skipped.append(document.code)
                        continue
                    }
                    guard document.version > diagram.revision else {
                        skipped.append(document.code)
                        continue
                    }
                    try db.execute(sql: """
                        UPDATE diagram
                           SET name = ?, description = ?, dope_scope_code = ?,
                               revision = ?, updated_at = ?
                         WHERE uuid = ? AND revision < ?
                        """, arguments: [document.name, document.description,
                                         document.dopeScopeCode, document.version,
                                         Store.isoNow(), diagram.uuid, document.version])
                    guard db.changesCount > 0 else {
                        skipped.append(document.code)
                        continue
                    }
                    try db.execute(
                        sql: "DELETE FROM diagram_element WHERE diagram_uuid = ?",
                        arguments: [diagram.uuid])
                    try self.insertDocumentElements(
                        db, diagramUuid: diagram.uuid, document: document)
                    guard let refreshed = try self.fetchDiagram(db, uuid: diagram.uuid) else {
                        throw StoreError.corruptState(
                            entity: "diagram", detail: "vanished during ingest")
                    }
                    try self.recordDiagramChange(
                        db, diagram: refreshed, action: "ingest", elementUuid: nil,
                        mutationCount: nil, revision: refreshed.revision)
                    ingested.append(document.code)
                } else {
                    try DopeCode.validateCode(document.code, field: "diagram code")
                    if let binding = document.dopeScopeCode {
                        let owner = try self.resolveDiagramOwner(
                            db, projectUuid: nil, instanceUuid: nil,
                            sessionUuid: req.sessionUuid, promptUuid: nil)
                        try self.validateDiagramScopeBinding(db, owner: owner, code: binding)
                    }
                    let owner = try self.resolveDiagramOwner(
                        db, projectUuid: nil, instanceUuid: nil,
                        sessionUuid: req.sessionUuid, promptUuid: nil)
                    let uuid = try self.insertBase(db, table: "diagram", extra: [
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
                    ])
                    try self.insertDocumentElements(
                        db, diagramUuid: uuid, document: document)
                    guard let created = try self.fetchDiagram(db, uuid: uuid) else {
                        throw StoreError.corruptState(
                            entity: "diagram", detail: "vanished after ingest insert")
                    }
                    try self.recordDiagramChange(
                        db, diagram: created, action: "ingest", elementUuid: nil,
                        mutationCount: nil, revision: created.revision)
                    ingested.append(document.code)
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
            return DiagramIngestResponse(ingested: ingested, skipped: skipped,
                                         warnings: warnings, root: directory.path)
        }
    }

    /// Two passes: insert every element (fresh uuids — the locked
    /// no-smart-diff consequence, exactly like dope ingest), THEN resolve
    /// connector code paths against the freshly minted uuid map. A path
    /// that resolves to nothing stays NULL — the ghost travels as a ghost.
    private func insertDocumentElements(
        _ db: Database, diagramUuid: String, document: DiagramDocument
    ) throws {
        var uuidByPath: [String: String] = [:]
        var connectorTargets: [(elementUuid: String, path: String)] = []

        func insert(_ doc: DiagramDocument.ElementDoc,
                    parentUuid: String?, prefix: String) throws {
            let path = prefix.isEmpty ? doc.code : "\(prefix)/\(doc.code)"
            // The write door's own shape check — files are hand-editable
            // and merge-mangled, and a row the reducer would refuse must
            // not land via ingest either.
            let parentInfo = try parentUuid.map { try fetchElementInfo(db, uuid: $0) }
            try validateDiagramElementShape(
                db, diagramUuid: diagramUuid, type: doc.payload.elementType,
                parent: parentInfo, payload: doc.payload)
            let uuid = try insertBase(db, table: "diagram_element", extra: [
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
            ])
            try insertSubtypeRow(
                db, elementUuid: uuid,
                payload: DiagramStrokeCodec.normalizedForStorage(doc.payload))
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
        for target in connectorTargets {
            guard let resolved = uuidByPath[target.path] else { continue }
            try db.execute(sql: """
                UPDATE diagram_connector SET target_element_uuid = ?
                 WHERE element_uuid = ?
                """, arguments: [resolved, target.elementUuid])
        }
    }
}
