import Foundation
import GRDB

/// DIAGRAM domain modeling — db-persisted canvases over the dope subsystem.
///
/// One write path: `applyDiagramMutations` is the ONLY mutation body. The
/// granular node verbs build one-mutation batches over it, so granular and
/// batch semantics structurally cannot drift. Every batch (of any size) runs
/// in one transaction, bumps `diagram.revision` exactly once
/// (`bumpDiagramRevision` — the bumpScopeRevision twin: never the row's
/// optimistic-lock version) and emits exactly one DIAGRAM_CHANGE event.
///
/// dope bindings are TEXT codes resolved at READ time through the existing
/// `dopeScopeCandidates` ladder against the diagram row's own session/prompt
/// FKs. Dangling codes are a LEGAL renderable state (ghosts) — diagram
/// elements never join `requireNoExternalReferrers`, and no dope write path
/// knows diagrams exist.
extension Store {



    // MARK: - Verbs (bodies in DiagramRepository; these wrappers own the transaction)

    public func diagramInit(_ req: DiagramInitRequest) throws -> DiagramResponse {
        try dbQueue.write { db in try DiagramRepository(db: db, core: core).diagramInit(req) }
    }

    public func diagramList(_ req: DiagramListRequest) throws -> DiagramListResponse {
        try dbQueue.read { db in try DiagramRepository(db: db, core: core).diagramList(req) }
    }

    public func diagramGet(_ req: DiagramGetRequest) throws -> DiagramGetResponse {
        try dbQueue.read { db in try DiagramRepository(db: db, core: core).diagramGet(req) }
    }

    public func diagramBatchApply(_ req: DiagramBatchApplyRequest) throws -> DiagramBatchApplyResponse {
        guard !req.mutations.isEmpty else {
            throw StoreError.badRequest(detail: "batch-apply carried no mutations")
        }
        return try dbQueue.write { db in
            try DiagramRepository(db: db, core: core).diagramBatchApply(req)
        }
    }

    // MARK: - Cross-family helper forwards (bodies in DiagramRepository)

    func validateDiagramScopeBinding(
        _ db: Database, owner: DiagramOwner, code: String
    ) throws {
        try DiagramRepository(db: db, core: core)
            .validateDiagramScopeBinding(owner: owner, code: code)
    }

    func fetchDiagram(_ db: Database, uuid: String) throws -> DiagramRow? {
        try DiagramRepository(db: db, core: core).fetchDiagram(uuid: uuid)
    }

    @discardableResult
    func bumpDiagramRevision(_ db: Database, diagramUuid: String) throws -> Int64 {
        try DiagramRepository(db: db, core: core).bumpDiagramRevision(diagramUuid: diagramUuid)
    }

    func recordDiagramChange(
        _ db: Database, diagram: DiagramRow, action: String,
        elementUuid: String?, mutationCount: Int?, revision: Int64
    ) throws {
        try DiagramRepository(db: db, core: core).recordDiagramChange(
            diagram: diagram, action: action, elementUuid: elementUuid,
            mutationCount: mutationCount, revision: revision)
    }

    func resolveDiagramOwner(
        _ db: Database, projectUuid: String?, instanceUuid: String?,
        sessionUuid: String?, promptUuid: String?
    ) throws -> DiagramOwner {
        try DiagramRepository(db: db, core: core).resolveDiagramOwner(
            projectUuid: projectUuid, instanceUuid: instanceUuid,
            sessionUuid: sessionUuid, promptUuid: promptUuid)
    }

    func diagramOwnerStoragePath(_ db: Database, diagram: DiagramRow) throws -> String? {
        try DiagramRepository(db: db, core: core).diagramOwnerStoragePath(diagram: diagram)
    }

    func fetchDiagramTree(_ db: Database, diagram: DiagramRow) throws -> DiagramTree {
        try DiagramRepository(db: db, core: core).fetchDiagramTree(diagram: diagram)
    }

    func resolveDiagramBindings(
        _ db: Database, diagram: DiagramRow, tree: DiagramTree
    ) throws -> [DiagramBindingResolution] {
        try DiagramRepository(db: db, core: core)
            .resolveDiagramBindings(diagram: diagram, tree: tree)
    }

    func fetchElementInfo(_ db: Database, uuid: String) throws -> ElementRowInfo {
        try DiagramRepository(db: db, core: core).fetchElementInfo(uuid: uuid)
    }

    func validateDiagramElementShape(
        _ db: Database, diagramUuid: String, type: DiagramElementType,
        parent: ElementRowInfo?, payload: DiagramElementPayload
    ) throws {
        try DiagramRepository(db: db, core: core).validateDiagramElementShape(
            diagramUuid: diagramUuid, type: type, parent: parent, payload: payload)
    }

    func validateConnectorTarget(
        _ db: Database, diagramUuid: String, referrerUuid: String,
        parentOfReferrer: String?, targetUuid: String
    ) throws {
        try DiagramRepository(db: db, core: core).validateConnectorTarget(
            diagramUuid: diagramUuid, referrerUuid: referrerUuid,
            parentOfReferrer: parentOfReferrer, targetUuid: targetUuid)
    }

    func insertSubtypeRow(
        _ db: Database, elementUuid: String, payload: DiagramElementPayload
    ) throws {
        try DiagramRepository(db: db, core: core)
            .insertSubtypeRow(elementUuid: elementUuid, payload: payload)
    }

    // MARK: - Granular verbs (one-mutation batches; there is no second body)

    public func diagramNodeAdd(_ req: DiagramNodeAddRequest) throws -> DiagramNodeResponse {
        let batch = try diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: req.diagramUuid, mutations: [.elementAdd(req.add)]))
        let result = batch.results[0]
        return DiagramNodeResponse(uuid: result.uuid ?? "", version: result.version ?? 0,
                                   diagramUuid: batch.diagramUuid, revision: batch.revision)
    }

    public func diagramNodeUpdate(_ req: DiagramNodeUpdateRequest) throws -> DiagramNodeResponse {
        let diagramUuid = try owningDiagramUuid(elementUuid: req.update.elementUuid)
        let batch = try diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, mutations: [.elementUpdate(req.update)]))
        let result = batch.results[0]
        return DiagramNodeResponse(uuid: result.uuid ?? "", version: result.version ?? 0,
                                   diagramUuid: batch.diagramUuid, revision: batch.revision)
    }

    public func diagramNodeDelete(_ req: DiagramNodeDeleteRequest) throws -> DiagramNodeDeleteResponse {
        let diagramUuid = try owningDiagramUuid(elementUuid: req.delete.elementUuid)
        let batch = try diagramBatchApply(DiagramBatchApplyRequest(
            diagramUuid: diagramUuid, mutations: [.elementDelete(req.delete)]))
        let result = batch.results[0]
        return DiagramNodeDeleteResponse(
            deletedUuid: result.uuid ?? "", cascadedElements: result.cascadedElements ?? 1,
            diagramUuid: batch.diagramUuid, revision: batch.revision)
    }

    private func owningDiagramUuid(elementUuid: String) throws -> String {
        try dbQueue.read { db in
            guard let uuid = try String.fetchOne(
                db, sql: "SELECT diagram_uuid FROM diagram_element WHERE uuid = ?",
                arguments: [elementUuid]
            ) else {
                throw StoreError.notFound(entity: "diagram_element", key: elementUuid)
            }
            return uuid
        }
    }
}
