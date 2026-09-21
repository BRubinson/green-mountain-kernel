import Foundation

/// The RECALL and CATALOG ops: the bodies behind `cde_session`, `cde_dope` and
/// `cde_rpir_search`, over `SEARCH`, `CATALOG_SEARCH`, `DOPE_SEARCH`,
/// `DOPE_WRITE_REPO` and `SESSION_UPDATE`, so an agent can go looking for a
/// finding somebody else wrote.

/// THE FIVE SEARCH SCOPES ARE ONE VERB. The `kinds` filter is applied HERE
/// rather than left to the caller, so "search explorations" cannot accidentally
/// mean "search everything".
private let searchScopeKinds: [String: [SearchKind]] = [
    "exploration": [.explorationSummary, .explorationFinding],
    "clarification": [.clarificationQuestion, .clarificationNote],
    "architecture": [.architectureSummary, .architectureGeneralChange, .architecturePersistenceChange],
    "architecture_option": [.architectureSummary],
    "review": [.reviewSummary, .reviewFinding],
]

/// One `SEARCH` body, pinned to the record kinds its scope is named for.
private func searchArm(kinds: [SearchKind]) -> CdeArm {
    { args, client in
        let response = try client.search(
            SearchRequest(
                query: try args.string("query"),
                sessionUuid: args.optString("session_uuid"),
                kinds: kinds,
                limit: args.optInt("limit")
            )
        )
        var pager = try makePager(args)
        return try CdeHitsPage.build(response.hits, pager: &pager)
    }
}

/// This file's contribution to `CdeDispatch`.
nonisolated(unsafe) let recallDoorArms: CdeArms = [
    "cde_session": sessionArms(),
    "cde_dope": dopeRecallArms(),
    "cde_rpir_search": searchScopeKinds.mapValues(searchArm(kinds:)),
]

private func sessionArms() -> [String: CdeArm] {
    var session: [String: CdeArm] = [:]
    session["search"] = { args, client in
        let response = try client.searchCatalog(
            CatalogSearchRequest(
                query: try args.string("query"),
                projectUuid: args.optString("project_uuid"),
                limit: args.optInt("limit")
            )
        )
        var pager = try makePager(args)
        return try CdeCatalogPage.build(response, pager: &pager)
    }
    session["update"] = { args, client in
        try client.updateSession(
            SessionUpdateRequest(
                sessionUuid: try args.string("session_uuid"),
                expectedVersion: try args.int64("expected_version"),
                name: args.optString("name"),
                backstory: args.optString("backstory"),
                goal: args.optString("goal")
            )
        )
    }
    return session
}

/// The two dope ops this file owns; `search_session` is contributed by
/// GmMcpServer.swift.
private func dopeRecallArms() -> [String: CdeArm] {
    var dope: [String: CdeArm] = [:]
    dope["search_global"] = { args, client in
        // scope .project with NO session AND NO project_uuid is what
        // makes this global: a nil project_uuid means every project, and
        // the session-scoped op's habit of resolving an absent session
        // is exactly what this one must not do. BOTH NILS ARE
        // LOAD-BEARING — filling either one in narrows this op to one
        // project or one session and silently un-globals it.
        let response = try client.dopeSearch(
            DopeSearchRequest(
                query: try args.string("query"),
                scope: .project,
                sessionUuid: nil,
                limit: args.optInt("limit")
            )
        )
        var pager = try makePager(args)
        return try CdeHitsPage.build(response.hits, pager: &pager)
    }
    dope["update_session"] = { args, client in
        try client.dopeWriteRepo(
            DopeWriteRepoRequest(
                scopeUuid: try args.string("scope_uuid"),
                force: args.optBool("force")
            )
        )
    }
    return dope
}
