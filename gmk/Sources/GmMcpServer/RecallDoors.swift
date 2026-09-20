import Foundation

/// The RECALL and CATALOG tools: pen doors over `SEARCH`, `CATALOG_SEARCH`,
/// `DOPE_SEARCH`, `DOPE_WRITE_REPO` and `SESSION_UPDATE`, so an agent can go
/// looking for a finding somebody else wrote.
///
/// THE BRIDGE'S SPELLINGS WIN: the generated plugin grants exactly the names
/// `GmAgentTools` declares, so a tidier name coined here resolves to nothing.

/// THE FIVE `rpir_search_*` ARE ONE VERB WITH FIVE SCOPES. The `kinds` filter
/// is applied HERE rather than left to the caller, so "search explorations"
/// cannot accidentally mean "search everything".
/// One `SEARCH` door, pinned to the record kinds it is named for.
private func searchDoor(
    name: String,
    description: String,
    kinds: [SearchKind]
) -> CdeTool {
    CdeTool(
        name: name,
        description: description,
        params: [
            ("query", "string", "The search query (full text)", true),
            ("session_uuid", "string", "Restrict to one session (default: the resolved session)", false),
            ("limit", "number", "Max hits", false),
        ] + pageParams,
        narrowing: pagedNarrowing(name),
        run: { args, client in
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
    )
}

func makeRecallDoors() -> [CdeTool] {
    [
        searchDoor(
            name: "rpir_search_exploration",
            description: "Find old exploration findings by words in them.",
            kinds: [.explorationSummary, .explorationFinding]
        ),
        searchDoor(
            name: "rpir_search_clarification",
            description: "Find old clarification questions and notes by words in them.",
            kinds: [.clarificationQuestion, .clarificationNote]
        ),
        searchDoor(
            name: "rpir_search_architecture",
            description: "Find old architecture plans by words in them — summaries and their change rows.",
            kinds: [.architectureSummary, .architectureGeneralChange, .architecturePersistenceChange]
        ),
        searchDoor(
            name: "rpir_search_architecture_option",
            description: "Find one architect's proposed option by words in it.",
            kinds: [.architectureSummary]
        ),
        searchDoor(
            name: "rpir_search_review",
            description: "Find old review findings by words in them.",
            kinds: [.reviewSummary, .reviewFinding]
        ),

        CdeTool(
            name: "dope_search_global",
            description: "FTS over the dope trees of ALL projects and sessions, not just this one.",
            params: [
                ("query", "string", "The search query", true),
                ("limit", "number", "Max hits", false),
            ] + pageParams,
            narrowing: pagedNarrowing("dope_search_global"),
            run: { args, client in
                // scope .project with NO session AND NO project_uuid is what
                // makes this global: a nil project_uuid means every project, and
                // the session-scoped door's habit of resolving an absent session
                // is exactly what this tool must not do. BOTH NILS ARE
                // LOAD-BEARING — filling either one in narrows this tool to one
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
        ),
        CdeTool(
            name: "dope_update_session",
            description: "Write the session's dope tree back to its repo — many dope nodes to disk at once.",
            params: [
                ("scope_uuid", "string", "The dope scope to write", true),
                ("force", "boolean", "Write even when the repo has diverged", false),
            ],
            run: { args, client in
                try client.dopeWriteRepo(
                    DopeWriteRepoRequest(
                        scopeUuid: try args.string("scope_uuid"),
                        force: args.optBool("force")
                    )
                )
            }
        ),
        CdeTool(
            name: "projects_search",
            description: "Find projects, instances and sessions by name or id.",
            params: [
                ("query", "string", "Name or id fragment", true),
                ("project_uuid", "string", "Restrict to one project", false),
                ("limit", "number", "Max hits", false),
            ] + pageParams,
            narrowing: pagedNarrowing("projects_search"),
            run: { args, client in
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
        ),
        CdeTool(
            name: "projects_update_session",
            description: "Change a session's name, backstory or goal.",
            params: [
                ("session_uuid", "string", "The session to update", true),
                ("expected_version", "number", "The session version this write is based on", true),
                ("name", "string", "New name", false),
                ("backstory", "string", "New backstory", false),
                ("goal", "string", "New goal", false),
            ],
            run: { args, client in
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
        ),
    ]
}
