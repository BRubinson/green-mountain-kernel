import Foundation
import Observation

/// The whole project → instance → session tree, fetched in three unfiltered
/// Listing calls and grouped in memory.
///
/// At gmfs scale: cheaper than per-level tree walk, deletes browse polling, pre-plumbs cross-instance search.
/// Refreshes driven by .topology invalidations; store owns no timer, groups sorted at refresh time only.
@Observable @MainActor
final class CatalogStore {
    private(set) var projects: [ProjectRow] = []
    /// Newest-first per group, sorted at refresh.
    private(set) var instancesByProject: [String: [InstanceRow]] = [:]
    private(set) var sessionsByInstance: [String: [SessionStub]] = [:]
    /// By uuid — the session-window path derivations read these.
    private(set) var sessionsByUuid: [String: SessionStub] = [:]
    private(set) var instancesByUuid: [String: InstanceRow] = [:]
    private(set) var lastError: String?
    private(set) var hasLoaded = false

    private let service = GMCCDaemonService.shared
    private var inFlight: Task<Void, Never>?

    /// Refreshes the store from the daemon, coalescing multiple requests.
    ///
    /// The store is process-wide and every window's topology loop calls this
    /// per invalidation, but N windows still cost three LIST calls, not 3N, on
    /// the daemon's fairness-free serial queue.
    func refresh() async {
        if let running = inFlight {
            await running.value
            return
        }
        let task = Task { await self.performRefresh() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    /// Fetches and groups projects, instances, and sessions from the daemon.
    ///
    /// - Throws: `DaemonError` on daemon failures or other unexpected errors.
    private func performRefresh() async {
        do {
            let projects = try await service.listProjects()
            let instances = try await service.listInstances()
            let sessions = try await service.listSessions()

            let newProjects = projects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            let newInstances = Dictionary(grouping: instances, by: \.projectUuid)
                .mapValues { $0.sorted { $0.updatedAt > $1.updatedAt } }
            // SESSION_LIST is ORDER BY code — recency sorting is client-side.
            // lastActivityAt is fixed-width ISO-8601 seconds-Z, so lexicographic
            // IS chronological (the daemon's stated contract); no parsing. The
            // code tiebreak matters: Swift's sort is unstable, and an unstable
            // order under equal timestamps would defeat the change-gated
            // publication below and thrash selection state.
            let newSessions = Dictionary(grouping: sessions, by: \.instanceUuid)
                .mapValues {
                    $0.sorted {
                        $0.lastActivityAt == $1.lastActivityAt
                            ? $0.code < $1.code
                            : $0.lastActivityAt > $1.lastActivityAt
                    }
                }
            let newSessionsByUuid = Dictionary(sessions.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
            let newInstancesByUuid = Dictionary(
                instances.map { ($0.uuid, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            // Change-gated publication (the app's anti-thrash idiom).
            if self.projects != newProjects { self.projects = newProjects }
            if self.instancesByProject != newInstances { self.instancesByProject = newInstances }
            if self.sessionsByInstance != newSessions { self.sessionsByInstance = newSessions }
            if self.sessionsByUuid != newSessionsByUuid { self.sessionsByUuid = newSessionsByUuid }
            if self.instancesByUuid != newInstancesByUuid { self.instancesByUuid = newInstancesByUuid }
            if lastError != nil { lastError = nil }
        } catch let error as DaemonError {
            lastError = error.userMessage
        } catch {
            lastError = String(describing: error)
        }
        // Set on every path: a daemon-up failure must be distinguishable from
        // "still loading" (Landing renders lastError, not an empty launcher).
        hasLoaded = true
    }

    /// Fetches the instances in a project.
    ///
    /// - Parameter project: The project to fetch instances for.
    /// - Returns: The instances in the project, or an empty array if none exist.
    func instances(of project: ProjectRow) -> [InstanceRow] {
        instancesByProject[project.uuid] ?? []
    }

    /// Fetches the sessions in an instance.
    ///
    /// - Parameter instance: The instance to fetch sessions for.
    /// - Returns: The sessions in the instance, or an empty array if none exist.
    func sessions(of instance: InstanceRow) -> [SessionStub] {
        sessionsByInstance[instance.uuid] ?? []
    }

    /// Fetches a project by its UUID.
    ///
    /// The lookup is linear over a handful of projects, deliberately not a
    /// second index. The settings sheet re-reads through this on every submit
    /// to lock against the current version rather than a stale one, avoiding
    /// VERSION_CONFLICT on save.
    ///
    /// - Parameter uuid: The project UUID.
    /// - Returns: The project with the given UUID, or nil if not found.
    func project(uuid: String) -> ProjectRow? {
        projects.first { $0.uuid == uuid }
    }

    /// Fetches an instance by its UUID.
    ///
    /// - Parameter uuid: The instance UUID.
    /// - Returns: The instance with the given UUID, or nil if not found.
    func instance(uuid: String) -> InstanceRow? {
        instancesByUuid[uuid]
    }

    /// Fetches a session by its UUID.
    ///
    /// - Parameter uuid: The session UUID.
    /// - Returns: The session with the given UUID, or nil if not found.
    func session(uuid: String) -> SessionStub? {
        sessionsByUuid[uuid]
    }

    // MARK: - Mutation

    /// Sets a project's primary branch.
    ///
    /// The daemon emits `updateProject`, which DaemonConnectionModel already
    /// routes to a `.topology` invalidation. This call also refreshes the store
    /// (coalesced) so the sheet's row is current when it dismisses, not a socket
    /// round trip later.
    ///
    /// - Parameters:
    ///   - projectUuid: The project UUID.
    ///   - expectedVersion: The version the caller last read.
    ///   - branch: The new primary branch name.
    /// - Throws: `DaemonError` on daemon failures or version conflicts.
    func setPrimaryBranch(
        projectUuid: String,
        expectedVersion: Int64,
        branch: String
    ) async throws {
        _ = try await service.updateProject(
            ProjectUpdateRequest(
                projectUuid: projectUuid,
                expectedVersion: expectedVersion,
                primaryProjectBranch: branch
            )
        )
        await refresh()
    }

    /// Creates a SessionWindowID from a search hit's session UUID.
    ///
    /// Joins the sessionUuid to its owning instance so the hit can address
    /// `Route.session`. SearchHit carries sessionUuid/sessionCode but no
    /// instanceUuid, and SessionWindowID requires one. Returns nil if the hit
    /// is not navigable (session missing or malformed UUID); the caller
    /// renders an inert row rather than a fabricated identity.
    ///
    /// - Parameters:
    ///   - sessionUuid: The session UUID from the search hit.
    ///   - targetPromptUuid: An optional target prompt UUID to navigate to.
    /// - Returns: A SessionWindowID for routing, or nil if the session is missing.
    func sessionWindowID(
        forSessionUuid sessionUuid: String,
        targetPromptUuid: String? = nil
    ) -> SessionWindowID? {
        guard let stub = session(uuid: sessionUuid),
            let sessionUUID = UUID(uuidString: stub.uuid),
            let instanceUUID = UUID(uuidString: stub.instanceUuid)
        else { return nil }
        return SessionWindowID(
            sessionUUID: sessionUUID,
            instanceUUID: instanceUUID,
            sessionName: stub.name,
            targetPromptUUID: targetPromptUuid.flatMap(UUID.init(uuidString:))
        )
    }

}

// MARK: - Search matching over kit rows

nonisolated extension ProjectRow {
    /// Tests whether the project matches a search query.
    ///
    /// - Parameter q: The search query.
    /// - Returns: True if the project's name, code, or git repository name matches.
    func matches(_ q: SearchQuery) -> Bool {
        q.matchesAny(name, code, gitRepoName)
    }
}

nonisolated extension InstanceRow {
    /// Tests whether the instance matches a search query.
    ///
    /// - Parameter q: The search query.
    /// - Returns: True if the instance's name, code, or file path matches.
    func matches(_ q: SearchQuery) -> Bool {
        q.matchesAny(name, code, absoluteFileSystemPath)
    }
}

nonisolated extension SessionStub {
    /// Tests whether the session matches a search query.
    ///
    /// - Parameter q: The search query.
    /// - Returns: True if the session's name or code matches.
    func matches(_ q: SearchQuery) -> Bool {
        q.matchesAny(name, code) || q.matchesAnySlugged(code)
    }
}
