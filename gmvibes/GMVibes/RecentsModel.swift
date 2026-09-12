import Foundation
import Observation
import GMCCDaemonKit

/// One session surfaced on the landing page's Recent Sessions strip. Recency
/// is the stub's `lastActivityAt` — computed daemon-side as MAX(session
/// updated, newest prompt update, newest file change), a strict superset of
/// the retired client-side FILE_CHANGE_LIST fold.
struct RecentSessionCard: Identifiable, Equatable {
    let windowID: SessionWindowID
    let sessionName: String
    let sessionCode: String
    let projectName: String
    let instanceName: String
    /// Wire-string instance uuid, for CheckoutWatcher lookups.
    let instanceUuid: String
    let activity: Date

    var id: UUID { windowID.sessionUUID }
}

/// Read-only derivation over the CatalogStore snapshot. Owns no persisted
/// state and issues no I/O — the landing view refreshes the catalog
/// (event-driven) and re-derives. Scoped to the Recent Sessions strip only:
/// the landing's project/instance/session rows derive from CatalogFilter
/// (the app's one tree traversal) instead.
@Observable
@MainActor
final class RecentsModel {
    private(set) var recentSessions: [RecentSessionCard] = []

    /// Cache parsed ISO-8601 timestamps so re-derivation doesn't re-parse the
    /// whole tree every event.
    private var dateCache: [String: Date] = [:]
    private static let isoFormatter = ISO8601DateFormatter()

    private let sessionLimit: Int

    init(sessionLimit: Int = 8) {
        self.sessionLimit = sessionLimit
    }

    func refresh(catalog: CatalogStore) {
        var sessions: [RecentSessionCard] = []

        for project in catalog.projects {
            for instance in catalog.instancesByProject[project.uuid] ?? [] {
                let stubs = catalog.sessionsByInstance[instance.uuid] ?? []
                guard let instanceUUID = UUID(uuidString: instance.uuid) else { continue }
                for stub in stubs {
                    // A malformed uuid must skip the row, never mint a random
                    // identity (a fabricated uuid churns SwiftUI ids).
                    guard let sessionUUID = UUID(uuidString: stub.uuid) else { continue }
                    // Defensive: lastActivityAt should always parse; an
                    // unparseable value falls back to created/updated.
                    let activity = parse(stub.lastActivityAt)
                    let fallback = max(parse(stub.createdAt), parse(stub.updatedAt))
                    sessions.append(RecentSessionCard(
                        windowID: SessionWindowID(
                            sessionUUID: sessionUUID,
                            instanceUUID: instanceUUID,
                            sessionName: stub.name
                        ),
                        sessionName: stub.name,
                        sessionCode: stub.code,
                        projectName: project.name,
                        instanceName: instance.name,
                        instanceUuid: instance.uuid,
                        activity: activity == .distantPast ? fallback : activity
                    ))
                }
            }
        }

        // Code tiebreak: lastActivityAt is seconds-granularity so ties are
        // common, Swift's sort is unstable, and an unstable order under the
        // change-gated publication below would thrash the strip (and flicker
        // sessions across the prefix boundary).
        sessions.sort {
            $0.activity == $1.activity
                ? $0.sessionCode < $1.sessionCode
                : $0.activity > $1.activity
        }
        let topSessions = Array(sessions.prefix(sessionLimit))
        if recentSessions != topSessions { recentSessions = topSessions }
    }

    private func parse(_ raw: String) -> Date {
        if let cached = dateCache[raw] { return cached }
        // The hot key is now lastActivityAt, which mints a NEW string on
        // every file change — unlike the old created/updated keys the cache
        // was designed around, it no longer saturates. Bound it.
        if dateCache.count > 2048 { dateCache.removeAll(keepingCapacity: true) }
        let parsed = Self.isoFormatter.date(from: raw) ?? .distantPast
        dateCache[raw] = parsed
        return parsed
    }
}
