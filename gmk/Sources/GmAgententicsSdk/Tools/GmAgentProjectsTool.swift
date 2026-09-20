// Agent tools over the project, instance and session spine.

import Foundation
import FoundationModels

@Generable
struct GmAgentProjectsSearchArguments: Sendable {
    @Guide(description: "Name or id to look for.")
    var query: String

    @Guide(description: "Only look inside this project, by uuid. Leave empty to look everywhere.")
    var projectUuid: String

    @Guide(description: GM_TOOL_GUIDE_SEARCH_LIMIT, .range(1...500))
    var limit: Int

    init(query: String, projectUuid: String = "", limit: Int = 50) {
        self.query = query
        self.projectUuid = projectUuid
        self.limit = limit
    }
}

struct GmAgentProjectsSearchTool: GmAgentProjectsTool {
    let name = "projects_search"
    let description = "Find projects, sessions, and instances by name or id."

    init() {}

    func call(arguments _: GmAgentProjectsSearchArguments) throws -> String {
        throw GmAgentToolError.notSupported(
            tool: name,
            detail: """
                CATALOG_SEARCH returns instances and sessions only — projects \
                are a filter input, never a result, and PROJECT_LIST has no \
                query. Searching all three means composing the two verbs \
                client-side.
                """
        )
    }
}

@Generable
struct GmAgentProjectsUpdateSessionArguments: Sendable {
    @Guide(description: "Which session to change, by uuid.")
    var sessionUuid: String

    @Guide(description: "Version of the session you read, so two writers cannot clobber each other.")
    var expectedVersion: Int

    @Guide(description: "New backstory for the session, or empty to leave it alone.")
    var backstory: String

    @Guide(description: "New goal for the session, or empty to leave it alone.")
    var goal: String

    @Guide(description: "Kbite codes to switch ON for this session.")
    var addKbiteCodes: [String]

    @Guide(description: "Kbite codes to switch OFF for this session.")
    var removeKbiteCodes: [String]

    init(
        sessionUuid: String,
        expectedVersion: Int,
        backstory: String = "",
        goal: String = "",
        addKbiteCodes: [String] = [],
        removeKbiteCodes: [String] = []
    ) {
        self.sessionUuid = sessionUuid
        self.expectedVersion = expectedVersion
        self.backstory = backstory
        self.goal = goal
        self.addKbiteCodes = addKbiteCodes
        self.removeKbiteCodes = removeKbiteCodes
    }
}

struct GmAgentProjectsUpdateSessionTool: GmAgentProjectsTool {
    let name = "projects_update_session"
    let description = "Change session kbites and backstory."

    init() {}

    func call(arguments _: GmAgentProjectsUpdateSessionArguments) throws -> String {
        throw GmAgentToolError.notWired(
            tool: name,
            verb: "SESSION_UPDATE + KBITE_ADD/KBITE_REMOVE"
        )
    }
}
