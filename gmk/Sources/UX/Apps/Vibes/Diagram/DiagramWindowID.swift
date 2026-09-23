import Foundation

/// Route payload for `Route.diagram`.
///
/// It carries the diagram's own identity with the session as an optional, because a
/// PROJECT-tier diagram has no session and one dope scope can carry many saved diagrams.
/// The optional session is still load-bearing; see `Route.sessionScopeUuid`.
struct DiagramWindowID: Codable, Hashable, Identifiable {
    /// What the canvas is.
    ///
    /// A saved row is named by uuid; a preview has no row to name, so its dope scope code IS its identity — two states
    /// that cannot share one nullable field without lying about which is which.
    enum Source: Codable, Hashable {
        case saved(diagramUuid: String)
        /// The computed, non-persisted canvas over one dope scope (the Dope
        /// pane's Diagram button, the project persistence overview). Writes
        /// go to `LocalDiagramCommitter` and die with the window. A nil code
        /// hands scope resolution to the daemon's own ladder — the project
        /// overview knows its project, not which scope answers for it.
        case dopePreview(scopeCode: String?)
    }

    var source: Source
    /// Frozen at navigation time, like `SessionWindowID.sessionName`; a live
    /// rename is read from `DiagramCatalogStore` at render time.
    var name: String
    /// The owning session, when the diagram has one (SESSION / PROMPT tiers
    /// and every session-scoped preview). nil at PROJECT tier.
    var session: SessionWindowID?
    /// Always known — every diagram, at every tier, belongs to one project.
    var projectUuid: String

    var id: String { workspaceKey }

    /// The `DiagramWorkspaceStore` key.
    ///
    /// A saved diagram is keyed by its uuid (the db's own identity); a preview by owner + scope code, since two
    /// previews of different scopes must not share card positions.
    var workspaceKey: String {
        switch source {
        case .saved(let uuid):
            return uuid
        case .dopePreview(let code):
            let owner = session?.sessionUUID.wireString ?? projectUuid
            return "preview:\(owner):\(code ?? "auto")"
        }
    }

    var savedDiagramUuid: String? {
        if case .saved(let uuid) = source { return uuid }
        return nil
    }

    var previewScopeCode: String? {
        if case .dopePreview(let code) = source { return code }
        return nil
    }

    /// Creates a diagram window ID for a saved diagram.
    ///
    /// - Parameters:
    ///   - row: The diagram row from the database.
    ///   - session: The owning session window ID, or nil at PROJECT tier.
    /// - Returns: The diagram window ID for the saved diagram.
    static func saved(_ row: DiagramRow, session: SessionWindowID?) -> DiagramWindowID {
        DiagramWindowID(
            source: .saved(diagramUuid: row.uuid),
            name: row.name,
            session: session,
            projectUuid: row.projectUuid
        )
    }
}
