import Foundation
import FoundationModels
import GmDaemonSdk

// The dope family: two searches and the reconciler's batch update.
//
// A NOTE ON "FUZZY", because it is promised loosely and delivered precisely.
// The store is SQLite and the search is FTS5: token matching with bm25 ranking.
// It is NOT trigram fuzzy matching, so a misspelled term returns nothing rather
// than a near hit, and a query with no searchable tokens is a BAD_REQUEST
// rather than an empty result. Spotlight-style matching is wanted later; these
// descriptions describe what exists.

/// Shared argument shape for both dope searches.
///
/// One struct for two tools, which is the exception rather than the pattern
/// here: the two searches differ ONLY in scope, and scope is fixed by the tool
/// rather than chosen by the caller, so there is genuinely nothing to vary.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentDopeSearchArguments: Sendable {
    @Guide(description: "Words to look for. Whole words match; misspellings find nothing.")
    public var query: String

    @Guide(description: """
        Which kinds of dope rows to search. Leave empty to search all of them. \
        Use this to ask for only persistence rows, or only cogs.
        """)
    public var sources: [String]

    @Guide(description: "How many hits to return, 1 to 500.", .range(1...500))
    public var limit: Int

    public init(query: String, sources: [String] = [], limit: Int = 50) {
        self.query = query
        self.sources = sources
        self.limit = limit
    }

    /// The declared strings mapped onto the wire enum, dropping anything
    /// unrecognised.
    ///
    /// Taking `[String]` rather than `[DopeSearchSource]` is deliberate: the
    /// @Generable macro would need the enum itself to be Generable to nest it,
    /// and making a wire enum Generable in this package would put a
    /// FoundationModels conformance on a gmDaemonSdk type from outside it.
    /// Mapping here keeps the dependency pointing one way. The @Guide
    /// description carries the vocabulary instead.
    public var resolvedSources: [DopeSearchSource] {
        sources.compactMap(DopeSearchSource.init(rawValue:))
    }
}

/// Look in ALL projects and sessions for doped data.
///
/// DECLARED BUT NOT BACKED, and this one is not a wiring gap — the verb cannot
/// express it. `DopeSearchScope` has exactly three arms, prompt / session /
/// project, and `project` still takes a single `projectUuid`. There is no
/// all-projects scope to ask for.
///
/// Closing it means one of: a new `DopeSearchScope` case (an enum widening on an
/// existing message, which is NOT decode-safe for a stale peer and so is not
/// free), or a client-side fan-out over `PROJECT_LIST` issuing one search per
/// project. The second is available today and is probably right; it is left
/// undone rather than guessed at.
@available(GmAgentOs 1.0, *)
public struct GmAgentDopeSearchGlobalTool: GmAgentDopeTool {
    public let name = "dope_search_global"
    public let description = "Look in ALL projects and sessions for doped data."

    public init() {}

    public func call(arguments: GmAgentDopeSearchArguments) async throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                DOPE_SEARCH has no all-projects scope — DopeSearchScope is \
                prompt|session|project and project still requires one \
                project_uuid. Reaching every project means fanning out over \
                PROJECT_LIST client-side, or widening the enum (not decode-safe \
                for a stale peer).
                """)
    }
}

/// Look in THIS session only for doped data.
///
/// Fully backed: `DopeSearchRequest(scope: .session, sessionUuid:)`, with the
/// `sources` filter added alongside this surface.
@available(GmAgentOs 1.0, *)
public struct GmAgentDopeSearchSessionTool: GmAgentDopeTool {
    public let name = "dope_search_session"
    public let description = "Look in THIS session only for doped data."

    public init() {}

    public func call(arguments: GmAgentDopeSearchArguments) async throws -> String {
        throw GmAgentToolError.notWired(tool: name, verb: "DOPE_SEARCH")
    }
}

/// One node's worth of change in a batch dope update.
@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentDopeNodeUpdate: Sendable {
    @Guide(description: "Dot-path code of the node to change, like domain.entity.property.")
    public var code: String

    @Guide(description: "New title for the node, or empty to leave it alone.")
    public var title: String

    @Guide(description: "New body text for the node, or empty to leave it alone.")
    public var body: String

    public init(code: String, title: String = "", body: String = "") {
        self.code = code
        self.title = title
        self.body = body
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentDopeUpdateSessionArguments: Sendable {
    @Guide(description: "All the node changes to make in one go.")
    public var updates: [GmAgentDopeNodeUpdate]

    public init(updates: [GmAgentDopeNodeUpdate]) {
        self.updates = updates
    }
}

/// Change many session dopes on disk at once.
///
/// For the dope_reconciler agent, which is meant to run in parallel once the
/// implementation workflow needs it.
///
/// TWO THINGS THE IMPLEMENTER NEEDS TO SETTLE, neither of which is decided here:
///
/// 1. **"On disk" points at a different pair of verbs than it looks like.** The
///    node verbs (`DOPE_NODE_ADD` / `_UPDATE` / `_DELETE`) write the DATABASE
///    tree. The on-disk `.gmcc/` tree is reached through `DOPE_READ_REPO`,
///    `DOPE_MERGE_PLAN`, `DOPE_RESOLVE`, `DOPE_WRITE_REPO` and `DOPE_INGEST`.
///    Whether this tool means "update nodes then write the repo" or "ingest
///    from the repo" changes what it does entirely.
/// 2. **There is no batch node-update verb.** `DOPE_NODE_UPDATE` takes one
///    node, so this plural signature loops — and a partial failure leaves the
///    earlier nodes written in an append-only db. A reconciler running in
///    parallel is exactly the caller most likely to hit that.
@available(GmAgentOs 1.0, *)
public struct GmAgentDopeUpdateSessionTool: GmAgentDopeTool {
    public let name = "dope_update_session"
    public let description = "Change many session dopes on disk at once."

    public init() {}

    public func call(arguments: GmAgentDopeUpdateSessionArguments) async throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                no batch node-update verb exists (DOPE_NODE_UPDATE takes one \
                node), and whether 'on disk' means DOPE_WRITE_REPO or \
                DOPE_INGEST is undecided — see the doc comment before wiring.
                """)
    }
}
