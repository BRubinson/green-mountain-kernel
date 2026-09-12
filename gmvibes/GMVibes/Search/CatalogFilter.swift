import Foundation
import GMCCDaemonKit

/// The ONE project → instance → session tree traversal.
///
/// Inclusion rule, stated once: keep a node if it matches the query, an
/// ancestor matches (the whole subtree is relevant), or a descendant matches
/// (ancestors stay visible so the hit is reachable). Matching reuses the
/// `SearchQuery` / `matches(_:)` primitives on the kit rows.
///
/// The traversal also owns what every browse surface was hand-rolling around
/// it: instance ordering (alphabetical for the drill-down pages — the
/// CatalogStore snapshot keeps its recency sort for other consumers),
/// per-instance session limits, active-session hoisting, and the
/// checked-out exclusion the inactive-sessions sheet needs.
///
/// House rule (from InactiveSessionsSheet): surfaces derive a
/// `FilteredCatalog` into `@State` on change — never in a computed property —
/// so typing a character rescans the tree once, not once per body pass.
struct CatalogFilter: Equatable {
    enum InstanceOrder: Equatable {
        /// Case-insensitive by instance name — the drill-down pages' order.
        case alphabetical
        /// Keep the catalog snapshot's order (updatedAt desc).
        case recency
    }

    var query: SearchQuery
    /// Scope to one project (project page); nil = all.
    var projectUuid: String? = nil
    /// Scope to one instance (instance page); nil = all.
    var instanceUuid: String? = nil
    var instanceOrder: InstanceOrder = .alphabetical
    /// Per-instance session cap AFTER ordering/hoisting; nil = all.
    var sessionsPerInstance: Int? = nil
    /// Daemon-resolved active session uuid per instance uuid — a snapshot, so
    /// the filter stays Equatable and derivable.
    var activeSessionByInstance: [String: String] = [:]
    /// Put the active session first (the catalog's recency order follows).
    var hoistActive = true
    /// Checked-out session code per instance uuid; only consulted when
    /// `excludeCheckedOut` is set.
    var checkedOutCodeByInstance: [String: String] = [:]
    var excludeCheckedOut = false
    /// Keep projects whose kept-instance list is empty. The browse tree
    /// (ProjectsView) wants them (it renders a "No instances." row); the
    /// drill-down cards do NOT — an instance-less project would be a dead
    /// card, which the traversal this replaced explicitly refused.
    var includeEmptyProjects = false

    @MainActor
    func apply(to catalog: CatalogStore) -> FilteredCatalog {
        var outProjects: [ProjectRow] = []
        var outInstances: [String: [InstanceRow]] = [:]
        var outSessions: [String: [SessionStub]] = [:]
        var totals: [String: Int] = [:]
        var expanded: Set<String> = []

        for project in catalog.projects {
            if let projectUuid, project.uuid != projectUuid { continue }
            let projectMatched = !query.isActive || project.matches(query)

            var keptInstances: [InstanceRow] = []
            var projectHasDescendantMatch = false

            for instance in catalog.instances(of: project) {
                if let instanceUuid, instance.uuid != instanceUuid { continue }
                let instanceMatched = instance.matches(query)

                var sessions = catalog.sessions(of: instance)
                if excludeCheckedOut,
                   let checkedOut = checkedOutCodeByInstance[instance.uuid] {
                    sessions = sessions.filter { $0.code != checkedOut }
                }

                let matchingSessions = query.isActive
                    ? sessions.filter { $0.matches(query) }
                    : sessions
                let sessionMatch = query.isActive && !matchingSessions.isEmpty

                // Inclusion: self, ancestor, or descendant match.
                let keepInstance = !query.isActive || projectMatched
                    || instanceMatched || sessionMatch
                guard keepInstance else { continue }

                // Ancestor match ⇒ whole subtree; else only the matching leaves.
                var kept = (projectMatched || instanceMatched) ? sessions : matchingSessions

                if hoistActive, let active = activeSessionByInstance[instance.uuid],
                   let idx = kept.firstIndex(where: { $0.uuid == active }), idx != 0 {
                    kept.insert(kept.remove(at: idx), at: 0)
                }
                totals[instance.uuid] = kept.count
                if let cap = sessionsPerInstance { kept = Array(kept.prefix(cap)) }

                keptInstances.append(instance)
                outSessions[instance.uuid] = kept

                if sessionMatch { expanded.insert(instance.uuid) }
                if instanceMatched || sessionMatch { projectHasDescendantMatch = true }
            }

            guard projectMatched || projectHasDescendantMatch else { continue }
            guard !keptInstances.isEmpty || (projectMatched && includeEmptyProjects) else { continue }

            if instanceOrder == .alphabetical {
                keptInstances.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }

            outProjects.append(project)
            outInstances[project.uuid] = keptInstances
            if query.isActive && projectHasDescendantMatch { expanded.insert(project.uuid) }
        }

        return FilteredCatalog(
            projects: outProjects,
            instancesByProject: outInstances,
            sessionsByInstance: outSessions,
            totalSessions: totals,
            expandedAncestors: expanded
        )
    }
}

/// One filtered, ordered, limited snapshot of the catalog tree — Equatable so
/// surfaces can change-gate their `@State` copy (the app's anti-thrash idiom).
struct FilteredCatalog: Equatable {
    var projects: [ProjectRow] = []
    var instancesByProject: [String: [InstanceRow]] = [:]
    var sessionsByInstance: [String: [SessionStub]] = [:]
    /// Pre-cap counts, for "N sessions" affordances next to a limited list.
    var totalSessions: [String: Int] = [:]
    /// Ancestor uuids of every match — drives search auto-expansion.
    var expandedAncestors: Set<String> = []

    func instances(of project: ProjectRow) -> [InstanceRow] {
        instancesByProject[project.uuid] ?? []
    }

    func sessions(of instance: InstanceRow) -> [SessionStub] {
        sessionsByInstance[instance.uuid] ?? []
    }
}
