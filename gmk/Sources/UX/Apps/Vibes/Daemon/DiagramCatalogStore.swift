import Foundation
import Observation

/// Read model over DIAGRAM_LIST, plus the three writes that create or move a
/// diagram ROW (init / copy / promote). Element-level writes never come here
/// — those belong to `DiagramWorkspace`'s edit session.
///
/// App-lifetime and tier-keyed: a project rail, a session pane and every
/// prompt row read the same store, so N surfaces on one owner cost one list.
/// Refresh rides the `.diagramList(ownerUuid)` hub domain (DIAGRAM_CHANGE
/// yields on every owner uuid the event carries).
@Observable @MainActor
final class DiagramCatalogStore {

    /// DIAGRAM_LIST takes exactly ONE owner uuid and returns exactly that
    /// tier's rows — never a union, never a cross-tier ladder (the contract
    /// it inherited verbatim from DOPE_LIST).
    ///
    /// A per-prompt attached count is N parallel calls, one per prompt; widening
    /// the message to fold prompt rows in a session would break that invariant
    /// for every other caller, which is why the shortcut is off the table.
    enum Owner: Hashable {
        case project(String)
        case session(String)
        case prompt(String)

        var uuid: String {
            switch self {
            case .project(let uuid), .session(let uuid), .prompt(let uuid): uuid
            }
        }

        var listRequest: DiagramListRequest {
            switch self {
            case .project(let uuid): DiagramListRequest(projectUuid: uuid)
            case .session(let uuid): DiagramListRequest(sessionUuid: uuid)
            case .prompt(let uuid): DiagramListRequest(promptUuid: uuid)
            }
        }
    }

    /// A GALLERY page's identity — the cross-tier DIAGRAM_SEARCH surface,
    /// deliberately separate from `Owner` because it deliberately breaks the
    /// one-owner contract: the project page browses every tier, the session
    /// page that session's SESSION+PROMPT rows.
    enum GalleryScope: Hashable {
        case project(String)
        case session(projectUuid: String, sessionUuid: String)

        var projectUuid: String {
            switch self {
            case .project(let uuid): uuid
            case .session(let projectUuid, _): projectUuid
            }
        }

        var sessionUuid: String? {
            if case .session(_, let uuid) = self { return uuid }
            return nil
        }

        /// The hub domain key: the owner uuid whose DIAGRAM_CHANGE payload
        /// arm covers every row this scope can list.
        var streamKey: String { sessionUuid ?? projectUuid }
    }

    private(set) var rowsByOwner: [Owner: [DiagramRow]] = [:]
    private(set) var errorsByOwner: [Owner: String] = [:]
    private(set) var galleryByScope: [GalleryScope: [DiagramRow]] = [:]
    private(set) var galleryErrors: [GalleryScope: String] = [:]
    /// The last query each gallery ran — DIAGRAM_CHANGE refreshes re-run it
    /// so a live event never silently widens a filtered grid.
    @ObservationIgnored private var galleryQueries: [GalleryScope: String] = [:]
    /// diagram uuid -> the resolve behind its LIVE thumbnail, revision-keyed
    /// so a stale card never renders as current content.
    private(set) var thumbnailsByUuid: [String: (revision: Int64, resolved: ResolvedDiagram)] = [:]
    @ObservationIgnored private var thumbnailLoads: Set<String> = []

    private let service = GMCCDaemonService.shared
    /// Coalesced per owner: list is a pure enumeration with no
    /// read-after-write ordering requirement, so concurrent callers JOIN.
    private var inFlight: [Owner: Task<Void, Never>] = [:]

    /// Returns the diagram rows for an owner.
    ///
    /// - Parameter owner: The owner tier and uuid.
    /// - Returns: An array of rows, or an empty array if none are cached.
    func rows(_ owner: Owner) -> [DiagramRow] { rowsByOwner[owner] ?? [] }

    /// Returns the count of rows for an owner, or nil if not yet listed.
    ///
    /// Nil until the owner has been listed once; a prompt row renders no
    /// badge rather than a confident "0" when unchecked.
    ///
    /// - Parameter owner: The owner tier and uuid.
    /// - Returns: The row count, or nil if not yet loaded.
    func count(_ owner: Owner) -> Int? { rowsByOwner[owner]?.count }

    /// Refreshes the diagram list for an owner, coalescing concurrent calls.
    ///
    /// - Parameter owner: The owner tier and uuid.
    func refresh(_ owner: Owner) async {
        if let running = inFlight[owner] {
            await running.value
            return
        }
        let task = Task { await self.performRefresh(owner) }
        inFlight[owner] = task
        await task.value
        inFlight[owner] = nil
    }

    /// Refreshes the diagram lists for multiple prompts concurrently.
    ///
    /// N prompt rows want N counts; issuing them together keeps the UI's
    /// wait to one queue drain rather than N round trips of latency.
    ///
    /// - Parameter prompts: An array of prompt uuids to refresh.
    func refresh(prompts: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for uuid in prompts {
                group.addTask { await self.refresh(.prompt(uuid)) }
            }
        }
    }

    /// Performs the actual refresh of diagram rows for an owner.
    ///
    /// - Parameter owner: The owner tier and uuid.
    private func performRefresh(_ owner: Owner) async {
        do {
            let rows = try await service.diagramList(owner.listRequest)
                .sorted { $0.code < $1.code }
            if rowsByOwner[owner] != rows { rowsByOwner[owner] = rows }
            if errorsByOwner[owner] != nil { errorsByOwner[owner] = nil }
        } catch let error as DaemonError {
            errorsByOwner[owner] = error.userMessage
        } catch {
            errorsByOwner[owner] = String(describing: error)
        }
    }

    // MARK: - Gallery (DIAGRAM_SEARCH, v23)

    /// Returns the gallery rows for a scope.
    ///
    /// - Parameter scope: The gallery scope (project or session).
    /// - Returns: An array of rows, or an empty array if not yet loaded.
    func gallery(_ scope: GalleryScope) -> [DiagramRow] { galleryByScope[scope] ?? [] }

    /// Checks if a gallery has been fetched at least once.
    ///
    /// Returns false to show a spinner, not a confident empty state.
    ///
    /// - Parameter scope: The gallery scope (project or session).
    /// - Returns: True when the gallery has fetched; false otherwise.
    func galleryLoaded(_ scope: GalleryScope) -> Bool { galleryByScope[scope] != nil }

    /// Searches a gallery with a query string, updating the cached results.
    ///
    /// Empty query browses by recency; non-empty uses FTS via DIAGRAM_SEARCH.
    ///
    /// - Parameters:
    ///   - scope: The gallery scope (project or session).
    ///   - query: The search query, or an empty string to browse all.
    func searchGallery(_ scope: GalleryScope, query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        galleryQueries[scope] = trimmed
        do {
            let rows = try await service.diagramSearch(
                projectUuid: scope.projectUuid,
                sessionUuid: scope.sessionUuid,
                query: trimmed.isEmpty ? nil : trimmed
            )
            // A slower response for a superseded query must not clobber the
            // current one's rows.
            guard galleryQueries[scope] == trimmed else { return }
            if galleryByScope[scope] != rows { galleryByScope[scope] = rows }
            if galleryErrors[scope] != nil { galleryErrors[scope] = nil }
        } catch let error as DaemonError {
            galleryErrors[scope] = error.userMessage
        } catch {
            galleryErrors[scope] = String(describing: error)
        }
    }

    /// Re-runs the gallery's last query on a DIAGRAM_CHANGE event.
    ///
    /// Updates cached rows, including dropping deleted cards.
    ///
    /// - Parameter scope: The gallery scope (project or session).
    func refreshGallery(_ scope: GalleryScope) async {
        await searchGallery(scope, query: galleryQueries[scope] ?? "")
    }

    // MARK: - Thumbnails

    /// Returns the cached thumbnail resolve for a diagram row.
    ///
    /// Nil until loaded, and nil again when the row's revision moves past
    /// the cache entry.
    ///
    /// - Parameter row: The diagram row.
    /// - Returns: The resolved diagram, or nil if not cached or stale.
    func thumbnail(for row: DiagramRow) -> ResolvedDiagram? {
        guard let entry = thumbnailsByUuid[row.uuid],
            entry.revision == row.revision
        else { return nil }
        return entry.resolved
    }

    /// Lazily loads and caches the thumbnail resolve for a diagram row.
    ///
    /// Resolved against an empty dope context; ghost cards are the legal
    /// and cheap thumbnail state.
    ///
    /// - Parameter row: The diagram row to load the thumbnail for.
    func loadThumbnail(for row: DiagramRow) async {
        let key = "\(row.uuid):\(row.revision)"
        if thumbnail(for: row) != nil || thumbnailLoads.contains(key) { return }
        thumbnailLoads.insert(key)
        defer { thumbnailLoads.remove(key) }
        guard let response = try? await service.diagramGet(diagramUuid: row.uuid) else { return }
        let resolved = DiagramResolver.resolve(response.tree, dope: DiagramDopeContext())
        // Key on the revision the GET returned, not the (possibly stale) row.
        thumbnailsByUuid[row.uuid] = (response.tree.revision, resolved)
    }

    // MARK: - Delete / visibility

    /// Deletes a diagram, CAS-gated on the row's revision.
    ///
    /// Galleries refresh off the durable "deleted" event; this immediate
    /// refresh spares the deleting window the round-trip lag.
    ///
    /// - Parameters:
    ///   - row: The diagram row to delete.
    ///   - scope: The gallery scope to refresh after deletion.
    /// - Throws: An error when the daemon rejects the delete.
    func delete(_ row: DiagramRow, scope: GalleryScope) async throws {
        _ = try await service.diagramDelete(
            diagramUuid: row.uuid,
            expectedRevision: row.revision
        )
        thumbnailsByUuid[row.uuid] = nil
        await refreshGallery(scope)
    }

    /// Updates the visibility of a diagram.
    ///
    /// PUBLIC visibility is daemon-guarded to SESSION tier; refusals surface
    /// as thrown errors, never pre-blocked.
    ///
    /// - Parameters:
    ///   - row: The diagram row to update.
    ///   - visibility: The new visibility setting.
    ///   - scope: The gallery scope to refresh after the update.
    /// - Throws: An error when the daemon rejects the update.
    func setVisibility(
        _ row: DiagramRow,
        to visibility: DiagramVisibility,
        scope: GalleryScope
    ) async throws {
        _ = try await service.diagramBatchApply(
            diagramUuid: row.uuid,
            expectedRevision: nil,
            mutations: [
                .diagramUpdate(
                    DiagramRowUpdate(
                        expectedVersion: row.version,
                        visibility: visibility
                    )
                )
            ]
        )
        await refreshGallery(scope)
    }

    // MARK: - Create

    /// Creates a diagram (idempotent) and optionally seeds it from dope.
    ///
    /// The dope scaffold lives here at create time only: reseeding on every
    /// load would fight the user's layout, and toggle reseeding was removed.
    /// A returned-not-created row is left exactly as it is.
    ///
    /// - Parameters:
    ///   - owner: The owner tier and uuid.
    ///   - code: A unique code within the owner.
    ///   - name: The display name.
    ///   - projectUuid: The project uuid.
    ///   - description: Optional description.
    ///   - dopeScopeCode: Optional dope scope to seed from.
    ///   - sessionUuid: Optional session uuid (for prompt rows).
    ///   - seedFromDope: Whether to seed from dope on creation; default true.
    /// - Returns: The created or existing diagram row.
    /// - Throws: An error when the daemon rejects the creation.
    @discardableResult
    func create(
        owner: Owner,
        code: String,
        name: String,
        projectUuid: String,
        description: String? = nil,
        dopeScopeCode: String? = nil,
        sessionUuid: String? = nil,
        seedFromDope: Bool = true
    ) async throws -> DiagramRow {
        let request: DiagramInitRequest
        switch owner {
        case .project(let uuid):
            request = DiagramInitRequest(
                code: code,
                name: name,
                projectUuid: uuid,
                description: description,
                dopeScopeCode: dopeScopeCode
            )
        case .session(let uuid):
            request = DiagramInitRequest(
                code: code,
                name: name,
                sessionUuid: uuid,
                description: description,
                dopeScopeCode: dopeScopeCode
            )
        case .prompt(let uuid):
            request = DiagramInitRequest(
                code: code,
                name: name,
                promptUuid: uuid,
                description: description,
                dopeScopeCode: dopeScopeCode
            )
        }
        let response = try await service.diagramInit(request)
        if response.created, seedFromDope, let dopeScopeCode {
            await seed(
                response.diagram,
                dopeScopeCode: dopeScopeCode,
                projectUuid: projectUuid,
                sessionUuid: sessionUuid
            )
        }
        await refresh(owner)
        return response.diagram
    }

    /// Lays out a diagram's dope scope using the same `DopeCanvasLayout`.
    ///
    /// The layout uses `DopeCanvasLayout` (same as the CLI generator);
    /// card heights from the resolver ensure app and daemon never differ.
    ///
    /// - Parameters:
    ///   - diagram: The diagram row to seed.
    ///   - dopeScopeCode: The dope scope code.
    ///   - projectUuid: The project uuid.
    ///   - sessionUuid: The session uuid, if any.
    private func seed(
        _ diagram: DiagramRow,
        dopeScopeCode: String,
        projectUuid: String,
        sessionUuid: String?
    ) async {
        do {
            let dope: DopeGetResponse
            if let sessionUuid {
                dope = try await service.dopeGet(
                    sessionUuid: sessionUuid,
                    code: dopeScopeCode
                )
            } else {
                dope = try await service.dopeGet(
                    projectUuid: projectUuid,
                    code: dopeScopeCode
                )
            }
            let mutations = DopeCanvasLayout.mutations(for: dope.tree)
            guard !mutations.isEmpty else { return }
            _ = try await service.diagramBatchApply(
                diagramUuid: diagram.uuid,
                expectedRevision: diagram.revision,
                mutations: mutations
            )
        } catch {
            // A seed failure leaves an EMPTY diagram, which is a legal state
            // the editor renders fine — better than refusing to create the
            // thing the user asked for.
            errorsByOwner[.project(projectUuid)] =
                "Diagram created, but the dope "
                + "scaffold failed: \(String(describing: error))"
        }
    }

    // MARK: - Copy / promote

    /// Copies a diagram to another tier, replicating its content.
    ///
    /// Client-side composition: no DIAGRAM_COPY message exists (adding one
    /// bumps the wire). DIAGRAM_INIT for the target, then elementAdd batch
    /// replaying the source tree with clientRef/targetClientRef remapping.
    /// The pair is not atomic: a failed batch leaves an empty diagram.
    ///
    /// - Parameters:
    ///   - source: The diagram row to copy.
    ///   - owner: The target owner tier and uuid.
    ///   - code: A unique code within the target owner.
    ///   - name: The display name for the copy.
    ///   - projectUuid: The project uuid.
    /// - Returns: The newly copied diagram row.
    /// - Throws: `DiagramCopyError.contentFailed` if the batch fails.
    @discardableResult
    func copy(
        _ source: DiagramRow,
        to owner: Owner,
        code: String,
        name: String,
        projectUuid: String
    ) async throws -> DiagramRow {
        let created = try await create(
            owner: owner,
            code: code,
            name: name,
            projectUuid: projectUuid,
            description: source.description.isEmpty
                ? nil : source.description,
            dopeScopeCode: source.dopeScopeCode,
            sessionUuid: nil,
            // The COPY carries the content; a
            // scaffold on top would double it.
            seedFromDope: false
        )
        let tree = try await service.diagramGet(diagramUuid: source.uuid).tree
        let mutations = Self.replayMutations(for: tree.elements)
        guard !mutations.isEmpty else { return created }
        do {
            _ = try await service.diagramBatchApply(
                diagramUuid: created.uuid,
                expectedRevision: nil,
                mutations: mutations
            )
        } catch {
            throw DiagramCopyError.contentFailed(
                diagramName: created.name,
                underlying: String(describing: error)
            )
        }
        await refresh(owner)
        return created
    }

    /// Converts diagram elements into mutations for batch replay.
    ///
    /// Two passes: non-connectors first in pre-order (parents before children),
    /// connectors last. Connectors reference a peer of their own parent; a peer
    /// not yet added has no clientRef to name.
    ///
    /// - Parameter elements: The source diagram elements to convert.
    /// - Returns: An array of elementAdd mutations in replay order.
    static func replayMutations(for elements: [DiagramElementNode]) -> [DiagramMutation] {
        var refs: [String: String] = [:]  // source uuid -> clientRef
        var structure: [DiagramMutation] = []
        var connectors: [(node: DiagramElementNode, parentRef: String)] = []
        var counter = 0

        func walk(_ nodes: [DiagramElementNode], parentRef: String?) {
            for node in nodes {
                counter += 1
                let ref = "c\(counter)"
                refs[node.identity.uuid] = ref
                if case .connector = node.payload {
                    // Deferred to the second pass; a connector has no
                    // children, so nothing under it is lost by waiting.
                    connectors.append((node, parentRef ?? ""))
                    continue
                }
                structure.append(
                    .elementAdd(
                        DiagramElementAdd(
                            payload: node.payload,
                            clientRef: ref,
                            parentClientRef: parentRef,
                            code: node.base.code,
                            name: node.base.name,
                            description: node.base.description,
                            sortOrder: node.base.sortOrder,
                            centerX: node.base.centerX,
                            centerY: node.base.centerY,
                            elementZ: node.base.elementZ,
                            scale: node.base.scale
                        )
                    )
                )
                walk(node.children, parentRef: ref)
            }
        }
        walk(elements, parentRef: nil)

        for (node, parentRef) in connectors {
            guard case .connector(let payload) = node.payload else { continue }
            // Strip the source-side target uuid: passing both it and a
            // targetClientRef is refused, and the uuid names a row in the
            // OTHER diagram. A target outside the copied set degrades to a
            // dangling connector — the legal ghost state, not an error.
            let targetRef = payload.targetElementUuid.flatMap { refs[$0] }
            structure.append(
                .elementAdd(
                    DiagramElementAdd(
                        payload: .connector(
                            ConnectorPayload(
                                targetElementUuid: nil,
                                strokeColor: payload.strokeColor,
                                strokeWidth: payload.strokeWidth,
                                lineStyle: payload.lineStyle,
                                headKind: payload.headKind,
                                label: payload.label
                            )
                        ),
                        clientRef: refs[node.identity.uuid],
                        parentClientRef: parentRef.isEmpty ? nil : parentRef,
                        targetClientRef: targetRef,
                        code: node.base.code,
                        name: node.base.name,
                        description: node.base.description,
                        sortOrder: node.base.sortOrder,
                        centerX: node.base.centerX,
                        centerY: node.base.centerY,
                        elementZ: node.base.elementZ,
                        scale: node.base.scale
                    )
                )
            )
        }
        return structure
    }

    /// Promotes a diagram to another tier via `DiagramRowUpdate.promotion`.
    ///
    /// The row's owner chain is re-derived server-side; the diagram has no
    /// update message of its own.
    ///
    /// - Parameters:
    ///   - row: The diagram row to promote.
    ///   - tier: The target tier.
    ///   - ownerUuid: The target owner uuid.
    ///   - owner: The current owner to refresh after promotion.
    /// - Throws: An error when the daemon rejects the promotion.
    func promote(
        _ row: DiagramRow,
        to tier: DiagramTier,
        ownerUuid: String,
        from owner: Owner
    ) async throws {
        _ = try await service.diagramBatchApply(
            diagramUuid: row.uuid,
            expectedRevision: nil,
            mutations: [
                .diagramUpdate(
                    DiagramRowUpdate(
                        expectedVersion: row.version,
                        promotion: DiagramPromotion(tier: tier, ownerUuid: ownerUuid)
                    )
                )
            ]
        )
        await refresh(owner)
        switch tier {
        case .project: await refresh(.project(ownerUuid))
        case .session: await refresh(.session(ownerUuid))
        case .prompt: await refresh(.prompt(ownerUuid))
        }
    }
}

/// The one error the copy path invents: the target row exists but its
/// content did not land, and nothing can remove it.
enum DiagramCopyError: LocalizedError {
    case contentFailed(diagramName: String, underlying: String)

    var errorDescription: String? {
        switch self {
        case .contentFailed(let name, let underlying):
            return "“\(name)” was created but its contents could not be copied "
                + "(\(underlying)). The empty diagram was left in place — "
                + "there is no diagram delete verb to remove it."
        }
    }
}
