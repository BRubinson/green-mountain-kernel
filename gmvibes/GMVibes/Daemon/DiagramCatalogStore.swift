import Foundation
import Observation
import GMCCDaemonKit

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
    /// it inherited verbatim from DOPE_LIST). So a per-prompt attached count
    /// is N parallel calls, one per prompt; widening the message to fold
    /// prompt rows in under a session would break that invariant for every
    /// other caller, which is why the shortcut is off the table.
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

    func rows(_ owner: Owner) -> [DiagramRow] { rowsByOwner[owner] ?? [] }

    /// nil until this owner has been listed once — a prompt row renders no
    /// badge rather than a confident "0" it has not checked.
    func count(_ owner: Owner) -> Int? { rowsByOwner[owner]?.count }

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

    /// The per-prompt fan-out, run concurrently: N prompt rows want N counts
    /// and the daemon queue is serial, so issuing them together at least
    /// keeps the UI's wait to one queue drain rather than N round trips of
    /// latency.
    func refresh(prompts: [String]) async {
        await withTaskGroup(of: Void.self) { group in
            for uuid in prompts {
                group.addTask { @MainActor in await self.refresh(.prompt(uuid)) }
            }
        }
    }

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

    func gallery(_ scope: GalleryScope) -> [DiagramRow] { galleryByScope[scope] ?? [] }

    /// Has this gallery fetched at least once? (nil = show a spinner, not a
    /// confident empty state.)
    func galleryLoaded(_ scope: GalleryScope) -> Bool { galleryByScope[scope] != nil }

    /// Run (and remember) a query for one gallery. Empty query = browse-all
    /// by recency; non-empty = FTS — both are the daemon's DIAGRAM_SEARCH.
    func searchGallery(_ scope: GalleryScope, query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        galleryQueries[scope] = trimmed
        do {
            let rows = try await service.diagramSearch(
                projectUuid: scope.projectUuid, sessionUuid: scope.sessionUuid,
                query: trimmed.isEmpty ? nil : trimmed)
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

    /// DIAGRAM_CHANGE wake: re-run whatever the gallery was last showing —
    /// including dropping a card the "deleted" action just removed.
    func refreshGallery(_ scope: GalleryScope) async {
        await searchGallery(scope, query: galleryQueries[scope] ?? "")
    }

    // MARK: - Thumbnails

    /// The cached resolve behind a card's live thumbnail — nil until loaded,
    /// and nil again the moment the row's revision moves past the cache.
    func thumbnail(for row: DiagramRow) -> ResolvedDiagram? {
        guard let entry = thumbnailsByUuid[row.uuid],
              entry.revision == row.revision else { return nil }
        return entry.resolved
    }

    /// One lazy DIAGRAM_GET per card, resolved against an EMPTY dope context
    /// (ghost cards are the legal — and cheap — thumbnail state).
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

    /// DIAGRAM_DELETE, CAS-gated on the revision the card was rendered from.
    /// The galleries refresh off the durable "deleted" event; the immediate
    /// refresh here just spares the deleting window the round-trip lag.
    func delete(_ row: DiagramRow, scope: GalleryScope) async throws {
        _ = try await service.diagramDelete(diagramUuid: row.uuid,
                                            expectedRevision: row.revision)
        thumbnailsByUuid[row.uuid] = nil
        await refreshGallery(scope)
    }

    /// The v23 visibility axis, ridden on batch-apply like promotion. PUBLIC
    /// is daemon-guarded to SESSION tier — refusals surface as thrown errors,
    /// never pre-blocked here.
    func setVisibility(_ row: DiagramRow, to visibility: DiagramVisibility,
                       scope: GalleryScope) async throws {
        _ = try await service.diagramBatchApply(
            diagramUuid: row.uuid, expectedRevision: nil,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: row.version, visibility: visibility))])
        await refreshGallery(scope)
    }

    // MARK: - Create

    /// DIAGRAM_INIT (create-or-return, idempotent per owner+code), then the
    /// ONE-TIME dope scaffold.
    ///
    /// The scaffold lives here, at create time, and nowhere else: seeding on
    /// every load would fight the user's own layout, and re-seeding on a
    /// filter toggle was the delete-and-recreate this whole commit removed.
    /// A returned-not-created row is left exactly as it is.
    @discardableResult
    func create(owner: Owner, code: String, name: String,
                description: String? = nil,
                dopeScopeCode: String? = nil,
                projectUuid: String,
                sessionUuid: String? = nil,
                seedFromDope: Bool = true) async throws -> DiagramRow {
        let request: DiagramInitRequest
        switch owner {
        case .project(let uuid):
            request = DiagramInitRequest(projectUuid: uuid, code: code, name: name,
                                         description: description,
                                         dopeScopeCode: dopeScopeCode)
        case .session(let uuid):
            request = DiagramInitRequest(sessionUuid: uuid, code: code, name: name,
                                         description: description,
                                         dopeScopeCode: dopeScopeCode)
        case .prompt(let uuid):
            request = DiagramInitRequest(promptUuid: uuid, code: code, name: name,
                                         description: description,
                                         dopeScopeCode: dopeScopeCode)
        }
        let response = try await service.diagramInit(request)
        if response.created, seedFromDope, let dopeScopeCode {
            await seed(response.diagram, dopeScopeCode: dopeScopeCode,
                       projectUuid: projectUuid, sessionUuid: sessionUuid)
        }
        await refresh(owner)
        return response.diagram
    }

    /// Lay the bound dope scope out once, through the same `DopeCanvasLayout`
    /// the CLI generator uses (card heights come from the resolver, so the
    /// app and the daemon can never lay out differently).
    private func seed(_ diagram: DiagramRow, dopeScopeCode: String,
                      projectUuid: String, sessionUuid: String?) async {
        do {
            let dope: DopeGetResponse
            if let sessionUuid {
                dope = try await service.dopeGet(sessionUuid: sessionUuid,
                                                 code: dopeScopeCode)
            } else {
                dope = try await service.dopeGet(projectUuid: projectUuid,
                                                 code: dopeScopeCode)
            }
            let mutations = DopeCanvasLayout.mutations(for: dope.tree)
            guard !mutations.isEmpty else { return }
            _ = try await service.diagramBatchApply(
                diagramUuid: diagram.uuid, expectedRevision: diagram.revision,
                mutations: mutations)
        } catch {
            // A seed failure leaves an EMPTY diagram, which is a legal state
            // the editor renders fine — better than refusing to create the
            // thing the user asked for.
            errorsByOwner[.project(projectUuid)] = "Diagram created, but the dope "
                + "scaffold failed: \(String(describing: error))"
        }
    }

    // MARK: - Copy / promote

    /// Copy a diagram to another tier.
    ///
    /// Client-side composition, deliberately: there is no DIAGRAM_COPY
    /// message and adding one would bump the wire. So it is DIAGRAM_INIT for
    /// the target, then ONE elementAdd batch replaying the source tree with
    /// clientRef / targetClientRef remapping — parents and connector targets
    /// are named by temp id because the target's uuids do not exist until the
    /// batch runs. Accepted cost: the pair is NOT atomic. A failed batch
    /// leaves an empty diagram behind (there is no DIAGRAM_DELETE to clean it
    /// up with), so the error says so rather than pretending nothing
    /// happened.
    @discardableResult
    func copy(_ source: DiagramRow, to owner: Owner, code: String, name: String,
              projectUuid: String) async throws -> DiagramRow {
        let created = try await create(owner: owner, code: code, name: name,
                                       description: source.description.isEmpty
                                           ? nil : source.description,
                                       dopeScopeCode: source.dopeScopeCode,
                                       projectUuid: projectUuid,
                                       sessionUuid: nil,
                                       // The COPY carries the content; a
                                       // scaffold on top would double it.
                                       seedFromDope: false)
        let tree = try await service.diagramGet(diagramUuid: source.uuid).tree
        let mutations = Self.replayMutations(for: tree.elements)
        guard !mutations.isEmpty else { return created }
        do {
            _ = try await service.diagramBatchApply(
                diagramUuid: created.uuid, expectedRevision: nil,
                mutations: mutations)
        } catch {
            throw DiagramCopyError.contentFailed(
                diagramName: created.name, underlying: String(describing: error))
        }
        await refresh(owner)
        return created
    }

    /// The source tree as an add batch. Two passes on purpose: connectors
    /// reference a PEER of their own parent, and a peer that has not been
    /// added yet has no clientRef to name — so every non-connector element
    /// goes first in pre-order (parents before children), connectors last.
    static func replayMutations(for elements: [DiagramElementNode]) -> [DiagramMutation] {
        var refs: [String: String] = [:]     // source uuid -> clientRef
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
                structure.append(.elementAdd(DiagramElementAdd(
                    clientRef: ref, parentClientRef: parentRef,
                    code: node.base.code, name: node.base.name,
                    description: node.base.description, sortOrder: node.base.sortOrder,
                    centerX: node.base.centerX, centerY: node.base.centerY,
                    elementZ: node.base.elementZ, scale: node.base.scale,
                    payload: node.payload)))
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
            structure.append(.elementAdd(DiagramElementAdd(
                clientRef: refs[node.identity.uuid],
                parentClientRef: parentRef.isEmpty ? nil : parentRef,
                targetClientRef: targetRef,
                code: node.base.code, name: node.base.name,
                description: node.base.description, sortOrder: node.base.sortOrder,
                centerX: node.base.centerX, centerY: node.base.centerY,
                elementZ: node.base.elementZ, scale: node.base.scale,
                payload: .connector(ConnectorPayload(
                    targetElementUuid: nil, strokeColor: payload.strokeColor,
                    strokeWidth: payload.strokeWidth, lineStyle: payload.lineStyle,
                    headKind: payload.headKind, label: payload.label)))))
        }
        return structure
    }

    /// MOVE the diagram to another tier (the row's own owner chain is
    /// re-derived server-side). Rides `DiagramRowUpdate.promotion` through
    /// batch-apply — the diagram row has no update message of its own.
    func promote(_ row: DiagramRow, to tier: DiagramTier, ownerUuid: String,
                 from owner: Owner) async throws {
        _ = try await service.diagramBatchApply(
            diagramUuid: row.uuid, expectedRevision: nil,
            mutations: [.diagramUpdate(DiagramRowUpdate(
                expectedVersion: row.version,
                promotion: DiagramPromotion(tier: tier, ownerUuid: ownerUuid)))])
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
