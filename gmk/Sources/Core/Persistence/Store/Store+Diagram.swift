import Foundation
import GRDB

/// DIAGRAM domain modeling — db-persisted canvases over the dope subsystem.
///
/// One write path: `applyDiagramMutations` is the ONLY mutation body, and the
/// granular node verbs build one-mutation batches over it, so granular and batch
/// semantics cannot drift. Every batch runs in one transaction, bumps
/// `diagram.revision` exactly once and emits one DIAGRAM_CHANGE event.
/// dope bindings are TEXT codes resolved at READ time, and a dangling code is a
/// LEGAL renderable ghost; no dope write path knows diagrams exist.
extension Store {

    // MARK: - Verbs (bodies in DiagramRepository; these wrappers own the transaction)

    /// Initializes a new diagram with the given request parameters.
    ///
    /// - Parameter req: The diagram initialization request.
    /// - Returns: The response containing the new diagram's uuid and metadata.
    /// - Throws: `StoreError` if initialization fails or the request is invalid.
    func diagramInit(_ req: DiagramInitRequest) throws -> DiagramResponse {
        try boundary { db in try DiagramRepository(db: db, core: core).diagramInit(req) }
    }

    /// Lists diagrams matching the request criteria.
    ///
    /// - Parameter req: The list request with optional filters.
    /// - Returns: A list of diagrams and their metadata.
    /// - Throws: `StoreError` if the query fails.
    func diagramList(_ req: DiagramListRequest) throws -> DiagramListResponse {
        try boundaryRead { db in try DiagramRepository(db: db, core: core).diagramList(req) }
    }

    /// Fetches a diagram and its elements by uuid.
    ///
    /// - Parameter req: The get request containing the diagram uuid.
    /// - Returns: The diagram and its element tree.
    /// - Throws: `StoreError` if the diagram is not found.
    func diagramGet(_ req: DiagramGetRequest) throws -> DiagramGetResponse {
        try boundaryRead { db in try DiagramRepository(db: db, core: core).diagramGet(req) }
    }

    /// Applies a batch of diagram mutations in a single transaction.
    ///
    /// - Parameter req: The batch request containing mutations to apply.
    /// - Returns: The batch response with results and updated diagram revision.
    /// - Throws: `StoreError` if the batch is empty or any mutation fails.
    func diagramBatchApply(_ req: DiagramBatchApplyRequest) throws -> DiagramBatchApplyResponse {
        guard !req.mutations.isEmpty else {
            throw StoreError.badRequest(detail: "batch-apply carried no mutations")
        }
        return try boundary { db in
            try DiagramRepository(db: db, core: core).diagramBatchApply(req)
        }
    }

    // MARK: - Cross-family helper forwards (bodies in DiagramRepository)

    /// Validates that a dope binding code is valid for a diagram owner.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - owner: The diagram owner (project, instance, session, or prompt).
    ///   - code: The dope scope binding code to validate.
    /// - Throws: `StoreError` if the binding code is invalid for the owner.
    func validateDiagramScopeBinding(
        _ db: Database,
        owner: DiagramOwner,
        code: String
    ) throws {
        try DiagramRepository(db: db, core: core)
            .validateDiagramScopeBinding(owner: owner, code: code)
    }

    /// Fetches a diagram row by uuid.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - uuid: The diagram uuid.
    /// - Returns: The diagram row, or nil if not found.
    /// - Throws: `StoreError` if the query fails.
    func fetchDiagram(_ db: Database, uuid: String) throws -> DiagramRow? {
        try DiagramRepository(db: db, core: core).fetchDiagram(uuid: uuid)
    }

    /// Increments a diagram's revision number.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagramUuid: The diagram uuid.
    /// - Returns: The new revision number.
    /// - Throws: `StoreError` if the diagram is not found or the update fails.
    @discardableResult
    func bumpDiagramRevision(_ db: Database, diagramUuid: String) throws -> Int64 {
        try DiagramRepository(db: db, core: core).bumpDiagramRevision(diagramUuid: diagramUuid)
    }

    /// Records a change to a diagram for audit and history tracking.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagram: The diagram row being changed.
    ///   - action: The action name (e.g., `init`, `elementAdd`, `elementUpdate`).
    ///   - elementUuid: The uuid of the affected element, if any.
    ///   - mutationCount: The number of mutations applied, if a batch.
    ///   - revision: The diagram revision after the change.
    /// - Throws: `StoreError` if the record fails.
    func recordDiagramChange(
        _ db: Database,
        diagram: DiagramRow,
        action: String,
        elementUuid: String?,
        mutationCount: Int?,
        revision: Int64
    ) throws {
        try DiagramRepository(db: db, core: core)
            .recordDiagramChange(
                diagram: diagram,
                action: action,
                elementUuid: elementUuid,
                mutationCount: mutationCount,
                revision: revision
            )
    }

    /// Determines which entity owns a diagram from owner identifiers.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - projectUuid: The project uuid, if the owner is a project.
    ///   - instanceUuid: The instance uuid, if the owner is an instance.
    ///   - sessionUuid: The session uuid, if the owner is a session.
    ///   - promptUuid: The prompt uuid, if the owner is a prompt.
    /// - Returns: A `DiagramOwner` value representing the resolved owner.
    /// - Throws: `StoreError` if no owner is specified or resolution fails.
    func resolveDiagramOwner(
        _ db: Database,
        projectUuid: String?,
        instanceUuid: String?,
        sessionUuid: String?,
        promptUuid: String?
    ) throws -> DiagramOwner {
        try DiagramRepository(db: db, core: core)
            .resolveDiagramOwner(
                projectUuid: projectUuid,
                instanceUuid: instanceUuid,
                sessionUuid: sessionUuid,
                promptUuid: promptUuid
            )
    }

    /// Gets the file system path where a diagram's owner stores resources.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagram: The diagram row whose owner path is needed.
    /// - Returns: The storage path for the owner, or nil if the owner is not file-backed.
    /// - Throws: `StoreError` if the path cannot be resolved.
    func diagramOwnerStoragePath(_ db: Database, diagram: DiagramRow) throws -> String? {
        try DiagramRepository(db: db, core: core).diagramOwnerStoragePath(diagram: diagram)
    }

    /// Fetches the complete element tree of a diagram.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagram: The diagram row whose tree is to be fetched.
    /// - Returns: The diagram tree with all elements and their hierarchy.
    /// - Throws: `StoreError` if the tree cannot be fetched.
    func fetchDiagramTree(_ db: Database, diagram: DiagramRow) throws -> DiagramTree {
        try DiagramRepository(db: db, core: core).fetchDiagramTree(diagram: diagram)
    }

    /// Resolves dope binding codes in a diagram to their actual references.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagram: The diagram containing bindings.
    ///   - tree: The diagram element tree.
    /// - Returns: An array of resolved diagram binding references.
    /// - Throws: `StoreError` if resolution fails.
    func resolveDiagramBindings(
        _ db: Database,
        diagram: DiagramRow,
        tree: DiagramTree
    ) throws -> [DiagramBindingResolution] {
        try DiagramRepository(db: db, core: core)
            .resolveDiagramBindings(diagram: diagram, tree: tree)
    }

    /// Fetches metadata about a diagram element.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - uuid: The element uuid.
    /// - Returns: The element's row information including type and parent.
    /// - Throws: `StoreError` if the element is not found.
    func fetchElementInfo(_ db: Database, uuid: String) throws -> ElementRowInfo {
        try DiagramRepository(db: db, core: core).fetchElementInfo(uuid: uuid)
    }

    /// Validates that an element's payload matches its type and parent constraints.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagramUuid: The uuid of the containing diagram.
    ///   - type: The element type.
    ///   - parent: The parent element info, or nil for a root element.
    ///   - payload: The element's payload to validate.
    /// - Throws: `StoreError` if validation fails.
    func validateDiagramElementShape(
        _ db: Database,
        diagramUuid: String,
        type: DiagramElementType,
        parent: ElementRowInfo?,
        payload: DiagramElementPayload
    ) throws {
        try DiagramRepository(db: db, core: core)
            .validateDiagramElementShape(
                diagramUuid: diagramUuid,
                type: type,
                parent: parent,
                payload: payload
            )
    }

    /// Validates that a connector element can target another element.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - diagramUuid: The uuid of the containing diagram.
    ///   - referrerUuid: The uuid of the connector element.
    ///   - parentOfReferrer: The uuid of the connector's parent, if any.
    ///   - targetUuid: The uuid of the target element.
    /// - Throws: `StoreError` if the target is invalid for the connector.
    func validateConnectorTarget(
        _ db: Database,
        diagramUuid: String,
        referrerUuid: String,
        parentOfReferrer: String?,
        targetUuid: String
    ) throws {
        try DiagramRepository(db: db, core: core)
            .validateConnectorTarget(
                diagramUuid: diagramUuid,
                referrerUuid: referrerUuid,
                parentOfReferrer: parentOfReferrer,
                targetUuid: targetUuid
            )
    }

    /// Inserts a subtype-specific database row for a diagram element.
    ///
    /// - Parameters:
    ///   - db: The database connection.
    ///   - elementUuid: The element's uuid.
    ///   - payload: The element's payload containing type-specific data.
    /// - Throws: `StoreError` if the insert fails.
    func insertSubtypeRow(
        _ db: Database,
        elementUuid: String,
        payload: DiagramElementPayload
    ) throws {
        try DiagramRepository(db: db, core: core)
            .insertSubtypeRow(elementUuid: elementUuid, payload: payload)
    }

    // MARK: - Granular verbs (one-mutation batches; there is no second body)

    /// Adds a new node to a diagram.
    ///
    /// - Parameter req: The add request containing the element to add.
    /// - Returns: The response with the new node's uuid, version and diagram revision.
    /// - Throws: `StoreError` if the add fails or the diagram does not exist.
    func diagramNodeAdd(_ req: DiagramNodeAddRequest) throws -> DiagramNodeResponse {
        let batch = try diagramBatchApply(
            DiagramBatchApplyRequest(
                diagramUuid: req.diagramUuid,
                mutations: [.elementAdd(req.add)]
            )
        )
        let result = batch.results[0]
        return DiagramNodeResponse(
            uuid: result.uuid ?? "",
            version: result.version ?? 0,
            diagramUuid: batch.diagramUuid,
            revision: batch.revision
        )
    }

    /// Updates an existing diagram node.
    ///
    /// - Parameter req: The update request containing the element uuid and new values.
    /// - Returns: The response with the node's uuid, version and diagram revision.
    /// - Throws: `StoreError` if the node is not found or the update fails.
    func diagramNodeUpdate(_ req: DiagramNodeUpdateRequest) throws -> DiagramNodeResponse {
        let diagramUuid = try owningDiagramUuid(elementUuid: req.update.elementUuid)
        let batch = try diagramBatchApply(
            DiagramBatchApplyRequest(
                diagramUuid: diagramUuid,
                mutations: [.elementUpdate(req.update)]
            )
        )
        let result = batch.results[0]
        return DiagramNodeResponse(
            uuid: result.uuid ?? "",
            version: result.version ?? 0,
            diagramUuid: batch.diagramUuid,
            revision: batch.revision
        )
    }

    /// Deletes a diagram node and its descendants.
    ///
    /// - Parameter req: The delete request containing the element uuid.
    /// - Returns: The response with the deleted uuid, cascaded element count and diagram revision.
    /// - Throws: `StoreError` if the node is not found or the delete fails.
    func diagramNodeDelete(_ req: DiagramNodeDeleteRequest) throws -> DiagramNodeDeleteResponse {
        let diagramUuid = try owningDiagramUuid(elementUuid: req.delete.elementUuid)
        let batch = try diagramBatchApply(
            DiagramBatchApplyRequest(
                diagramUuid: diagramUuid,
                mutations: [.elementDelete(req.delete)]
            )
        )
        let result = batch.results[0]
        return DiagramNodeDeleteResponse(
            deletedUuid: result.uuid ?? "",
            cascadedElements: result.cascadedElements ?? 1,
            diagramUuid: batch.diagramUuid,
            revision: batch.revision
        )
    }

    /// Gets the uuid of the diagram containing an element.
    ///
    /// - Parameter elementUuid: The element uuid.
    /// - Returns: The uuid of the containing diagram.
    /// - Throws: `StoreError` if the element is not found.
    private func owningDiagramUuid(elementUuid: String) throws -> String {
        try boundaryRead { db in
            try DiagramRepository(db: db, core: core).owningDiagramUuid(elementUuid: elementUuid)
        }
    }
}
