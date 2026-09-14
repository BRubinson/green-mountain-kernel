import Foundation
import GmDaemonSdk

/// The nine RECALL and CATALOG tools the agentics bridge declares and the pen
/// did not serve.
///
/// THESE ARE NOT NEW CAPABILITIES — every one is a verb the daemon has always
/// had (`SEARCH`, `CATALOG_SEARCH`, `DOPE_SEARCH`, `DOPE_WRITE_REPO`,
/// `SESSION_UPDATE`). What was missing is the pen's side of them, which meant an
/// agent could WRITE a finding but never go looking for one somebody else had
/// written. The bridge models the whole surface; the server had grown only the
/// half the current workflow happened to walk.
///
/// THE BRIDGE'S SPELLINGS WIN. `rpir_search_exploration`, `dope_search_global`
/// and the rest are the names `GmAgentTools` declares, and the generated plugin
/// grants exactly those. Coining a different name here — even a tidier one —
/// puts a tool in every agent's `allowed-tools` that resolves to nothing.
///
/// THE FIVE `rpir_search_*` ARE ONE VERB WITH FIVE SCOPES. `SEARCH` is full-text
/// over the whole record and takes a `kinds` filter; a caller looking for an old
/// finding does not want questions and plans in the result. Five named doors over
/// one verb read better at the call site than one door with a required enum
/// nobody remembers the cases of — and the filter is applied HERE rather than
/// left to the caller, so "search explorations" cannot accidentally mean
/// "search everything".
func makeRecallDoors() -> [Tool] {

    /// One `SEARCH` door, pinned to the record kinds it is named for.
    func searchDoor(
        name: String, description: String, kinds: [SearchKind]
    ) -> Tool {
        Tool(
            name: name,
            description: description,
            params: [
                ("query", "string", "The search query (full text)", true),
                ("session_uuid", "string", "Restrict to one session (default: the resolved session)", false),
                ("limit", "number", "Max hits", false),
            ],
            narrowing: PenNarrowing(
                parameters: ["limit", "session_uuid"],
                retryWith: "\(name) with a smaller limit, or session_uuid set"),
            run: { args, client in
                try client.search(SearchRequest(
                    query: try args.string("query"),
                    sessionUuid: args.optString("session_uuid"),
                    kinds: kinds,
                    limit: args.optInt("limit")))
            })
    }

    return [
        searchDoor(
            name: "rpir_search_exploration",
            description: "Find old exploration findings by words in them.",
            kinds: [.explorationSummary, .explorationFinding]),
        searchDoor(
            name: "rpir_search_clarification",
            description: "Find old clarification questions and notes by words in them.",
            kinds: [.clarificationQuestion, .clarificationNote]),
        searchDoor(
            name: "rpir_search_architecture",
            description: "Find old architecture plans by words in them — summaries and their change rows.",
            kinds: [.architectureSummary, .architectureGeneralChange, .architecturePersistenceChange]),
        searchDoor(
            name: "rpir_search_architecture_option",
            description: "Find one architect's proposed option by words in it.",
            kinds: [.architectureSummary]),
        searchDoor(
            name: "rpir_search_review",
            description: "Find old review findings by words in them.",
            kinds: [.reviewSummary, .reviewFinding]),

        Tool(
            name: "dope_search_global",
            description: "FTS over the dope trees of ALL projects and sessions, not just this one.",
            params: [
                ("query", "string", "The search query", true),
                ("limit", "number", "Max hits", false),
            ],
            narrowing: PenNarrowing(
                parameters: ["limit"],
                retryWith: "dope_search_global with a smaller limit, or dope_search_session to stay local"),
            run: { args, client in
                // scope .project with NO session is what makes this global: the
                // session-scoped door resolves a session when one is absent, and
                // that resolution is precisely what this tool must not do.
                try client.dopeSearch(DopeSearchRequest(
                    query: try args.string("query"),
                    scope: .project,
                    sessionUuid: nil,
                    limit: args.optInt("limit")))
            }),
        Tool(
            name: "dope_update_session",
            description: "Write the session's dope tree back to its repo — many dope nodes to disk at once.",
            params: [
                ("scope_uuid", "string", "The dope scope to write", true),
                ("force", "boolean", "Write even when the repo has diverged", false),
            ],
            run: { args, client in
                try client.dopeWriteRepo(DopeWriteRepoRequest(
                    scopeUuid: try args.string("scope_uuid"),
                    force: args.optBool("force")))
            }),
        Tool(
            name: "projects_search",
            description: "Find projects, instances and sessions by name or id.",
            params: [
                ("query", "string", "Name or id fragment", true),
                ("project_uuid", "string", "Restrict to one project", false),
                ("limit", "number", "Max hits", false),
            ],
            narrowing: PenNarrowing(
                parameters: ["limit", "project_uuid"],
                retryWith: "projects_search with a smaller limit, or project_uuid set"),
            run: { args, client in
                try client.searchCatalog(CatalogSearchRequest(
                    query: try args.string("query"),
                    projectUuid: args.optString("project_uuid"),
                    limit: args.optInt("limit")))
            }),
        Tool(
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
                try client.updateSession(SessionUpdateRequest(
                    sessionUuid: try args.string("session_uuid"),
                    expectedVersion: try args.int64("expected_version"),
                    name: args.optString("name"),
                    backstory: args.optString("backstory"),
                    goal: args.optString("goal")))
            }),
    ]
}
