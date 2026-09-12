import Foundation
import FoundationModels
import GmDaemonSdk

// The projects family: find things above a prompt, and edit a session.

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentProjectsSearchArguments: Sendable {
    @Guide(description: "Name or id to look for.")
    public var query: String

    @Guide(description: "Only look inside this project, by uuid. Leave empty to look everywhere.")
    public var projectUuid: String

    @Guide(description: "How many hits to return, 1 to 500.", .range(1...500))
    public var limit: Int

    public init(query: String, projectUuid: String = "", limit: Int = 50) {
        self.query = query
        self.projectUuid = projectUuid
        self.limit = limit
    }
}

/// Find projects, sessions, and instances by name or id.
///
/// PARTIALLY BACKED, and the missing third is the one named first in the tool's
/// own description. `CATALOG_SEARCH` returns instances and sessions; it accepts
/// `projectUuid` only as a FILTER, and never returns a project. The only verb
/// that yields projects is `PROJECT_LIST`, which takes no query at all.
///
/// So a real implementation is a composition — catalog-search for instances and
/// sessions, plus a client-side filter over the full project list — and it must
/// be built that way rather than implying the daemon searches all three. This
/// throws instead of quietly returning two of the three kinds, because a caller
/// that asked for projects and got none would reasonably conclude none matched.
@available(GmAgentOs 1.0, *)
public struct GmAgentProjectsSearchTool: GmAgentProjectsTool {
    public let name = "projects_search"
    public let description = "Find projects, sessions, and instances by name or id."

    public init() {}

    public func call(arguments: GmAgentProjectsSearchArguments) async throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                CATALOG_SEARCH returns instances and sessions only — projects \
                are a filter input, never a result, and PROJECT_LIST has no \
                query. Searching all three means composing the two verbs \
                client-side.
                """)
    }
}

@available(GmAgentOs 1.0, *)
@Generable
public struct GmAgentProjectsUpdateSessionArguments: Sendable {
    @Guide(description: "Which session to change, by uuid.")
    public var sessionUuid: String

    @Guide(description: "Version of the session you read, so two writers cannot clobber each other.")
    public var expectedVersion: Int

    @Guide(description: "New backstory for the session, or empty to leave it alone.")
    public var backstory: String

    @Guide(description: "New goal for the session, or empty to leave it alone.")
    public var goal: String

    @Guide(description: "Kbite codes to switch ON for this session.")
    public var addKbiteCodes: [String]

    @Guide(description: "Kbite codes to switch OFF for this session.")
    public var removeKbiteCodes: [String]

    public init(
        sessionUuid: String, expectedVersion: Int, backstory: String = "",
        goal: String = "", addKbiteCodes: [String] = [], removeKbiteCodes: [String] = []
    ) {
        self.sessionUuid = sessionUuid
        self.expectedVersion = expectedVersion
        self.backstory = backstory
        self.goal = goal
        self.addKbiteCodes = addKbiteCodes
        self.removeKbiteCodes = removeKbiteCodes
    }
}

/// Change session kbites and backstory.
///
/// THIS IS THREE VERBS BEHIND ONE TOOL, and the partial-failure story has to be
/// decided before it is wired rather than discovered after. `SESSION_UPDATE`
/// carries backstory and goal and takes an `expected_version`; kbite
/// registration is `KBITE_ADD` and `KBITE_REMOVE` against a scope, and they do
/// not share that version. A call that updates the backstory and then fails
/// half way through the kbite changes leaves the session genuinely half-edited,
/// in a db that is never wiped.
///
/// The honest options are to order the writes so the survivable one goes last,
/// or to split this back into two tools. It is left as one tool because that is
/// what was asked for, with the hazard written down rather than hidden.
@available(GmAgentOs 1.0, *)
public struct GmAgentProjectsUpdateSessionTool: GmAgentProjectsTool {
    public let name = "projects_update_session"
    public let description = "Change session kbites and backstory."

    public init() {}

    public func call(arguments: GmAgentProjectsUpdateSessionArguments) async throws -> String {
        throw GmAgentToolError.notWired(
            tool: name, verb: "SESSION_UPDATE + KBITE_ADD/KBITE_REMOVE")
    }
}
