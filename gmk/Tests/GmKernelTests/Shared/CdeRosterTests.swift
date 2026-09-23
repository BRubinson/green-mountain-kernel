import Foundation
import XCTest

// MARK: - The roster as a value (no kernel)

/// `CdeToolRoster` is a generated build artifact, so nothing about it is held
/// by the compiler.
///
/// These are the assertions that keep it honest: that the reflected roster is
/// structurally sound, and that it agrees with the verb registry it is a
/// projection of.
final class CdeRosterTests: XCTestCase {

    /// Ops whose work the pen folds itself, so they carry no VerbSpec.
    private static let compositeOps: Set<String> = ["cde_init.run"]

    // MARK: Structural

    func testTheRosterDecodesWithoutDuplicateNames() {
        XCTAssertEqual(
            CdeToolRoster.specs.count,
            CdeToolRoster.names.count,
            "two roster entries share a tool name"
        )
    }

    func testEveryToolNameIsSnakeCaseAndCdePrefixed() {
        for spec in CdeToolRoster.specs {
            // A refusal is named for the family it refuses, not for the cde
            // namespace it is not part of.
            if !spec.refuses {
                XCTAssertTrue(spec.name.hasPrefix("cde_"), "'\(spec.name)' is not in the cde namespace")
            }
            XCTAssertEqual(spec.name, spec.name.lowercased(), "'\(spec.name)' is not snake_case")
            XCTAssertNil(spec.name.rangeOfCharacter(from: CharacterSet(charactersIn: " -.")))
            for op in spec.ops {
                XCTAssertEqual(op.op, op.op.lowercased(), "\(spec.name).\(op.op) is not snake_case")
            }
        }
    }

    func testARefusalCarriesNoOpsAndAnAnsweringToolCarriesSome() {
        for spec in CdeToolRoster.specs {
            if spec.refuses {
                XCTAssertTrue(spec.ops.isEmpty, "refusal '\(spec.name)' declares ops")
            } else {
                XCTAssertFalse(spec.ops.isEmpty, "'\(spec.name)' answers nothing")
            }
        }
    }

    func testPinnedIsDrawnFromTheRoster() {
        XCTAssertTrue(CdeToolRoster.pinned.isSubset(of: CdeToolRoster.names))
        for name in CdeToolRoster.pinned {
            XCTAssertEqual(CdeToolRoster.spec(named: name)?.alwaysLoad, true)
        }
    }

    func testTheQualifiedNameIsTheHarnessPluginNamespace() {
        XCTAssertEqual(CdeToolSpec.qualifiedName("cde_prompt"), "mcp__plugin_gmcc_cde__cde_prompt")
    }

    func testTheInitializeSheetFitsItsBudget() {
        XCTAssertLessThanOrEqual(CdeSheet.instructions.utf8.count, 2_048)
    }

    // MARK: Parity with the verb registry

    func testEveryOpVerbHasAVerbSpec() {
        for spec in CdeToolRoster.specs {
            for op in spec.ops where !Self.compositeOps.contains("\(spec.name).\(op.op)") {
                for verb in op.verbs {
                    XCTAssertNotNil(
                        VerbRegistry.spec(for: verb),
                        "\(spec.name).\(op.op) sends \(verb.rawValue), which the registry does not declare"
                    )
                }
            }
        }
    }

    func testPerOpIsWriteMatchesTheVerbRole() {
        for spec in CdeToolRoster.specs {
            for op in spec.ops where !Self.compositeOps.contains("\(spec.name).\(op.op)") {
                let records = op.verbs.contains { verb in
                    guard case .record = VerbRegistry.spec(for: verb)?.role else { return false }
                    return true
                }
                XCTAssertEqual(op.isWrite, records, "\(spec.name).\(op.op) disagrees with its verbs' role")
            }
        }
    }

    func testCdePromptRecordsNothingBeyondItsOwnTwoWrites() throws {
        let allowed: Set<MessageType> = [.promptUpdateContent, .promptSetStatus]
        let spec = try XCTUnwrap(CdeToolRoster.spec(named: "cde_prompt"))
        for op in spec.ops {
            for verb in op.verbs where !allowed.contains(verb) {
                guard case .record = VerbRegistry.spec(for: verb)?.role else { continue }
                XCTFail("cde_prompt.\(op.op) reaches the write \(verb.rawValue)")
            }
        }
    }

    func testEveryDeclaredCdeToolOnAVerbIsInTheRoster() {
        for verb in VerbRegistry.all {
            guard let tool = verb.cdeTool else { continue }
            XCTAssertTrue(
                CdeToolRoster.names.contains(tool),
                "\(verb.messageType.rawValue) names pen tool '\(tool)', which the roster does not carry"
            )
        }
    }

    // MARK: Regression pins

    func testTheRosterIsFourteenToolsElevenOfThemGrantable() {
        XCTAssertEqual(CdeToolRoster.specs.count, 14)
        XCTAssertEqual(CdeToolRoster.specs.filter { !$0.refuses }.count, 11)
    }

    func testExactlyTheFiveDeclaredToolsArePinned() {
        XCTAssertEqual(
            CdeToolRoster.pinned,
            ["cde_init", "cde_prompt", "cde_rpir_search", "cde_dope", "cde_kbite"]
        )
    }

    /// A required argument on the SCHEMA is required for every op, so anything
    /// beyond the selector makes the harness refuse the calls that do not need it.
    ///
    /// Per-op required-ness is the arm's runtime answer, never the schema's.
    func testEverySchemaRequiresOnlyItsSelector() {
        for spec in CdeToolRoster.specs {
            guard case .object(let schema) = spec.schema else {
                XCTFail("\(spec.name) has no object schema")
                continue
            }
            let required: [String]
            if case .array(let entries)? = schema["required"] {
                required = entries.compactMap { value in
                    guard case .string(let key) = value else { return nil }
                    return key
                }
            } else {
                required = []
            }
            let expected: [String]
            if spec.refuses {
                expected = []
            } else {
                expected = spec.name == "cde_rpir_search" ? ["query", "scope"] : ["op"]
            }
            XCTAssertEqual(required.sorted(), expected, "\(spec.name) requires the wrong arguments")
        }
    }

    func testEveryRequiredOpArgumentIsADeclaredProperty() {
        for spec in CdeToolRoster.specs where !spec.refuses {
            guard case .object(let schema) = spec.schema,
                case .object(let properties)? = schema["properties"]
            else {
                XCTFail("\(spec.name) declares no properties")
                continue
            }
            for op in spec.ops {
                for key in op.requiredParams {
                    XCTAssertNotNil(
                        properties[key],
                        "\(spec.name).\(op.op) needs '\(key)', which the schema does not declare"
                    )
                }
            }
        }
    }

    func testEverySchemaIsANormalisedObjectWithAnOpEnum() {
        let banned = ["$ref", "$defs", "x-order", "title", "additionalProperties"]
        for spec in CdeToolRoster.specs where !spec.refuses {
            guard case .object(let schema) = spec.schema else {
                XCTFail("\(spec.name) has no object schema")
                continue
            }
            XCTAssertEqual(schema["type"], .string("object"), "\(spec.name) schema is not an object")
            for key in banned {
                XCTAssertFalse(
                    Self.schemaKeys(spec.schema).contains(key),
                    "\(spec.name) schema carries '\(key)', which Claude Code is not shown"
                )
            }
            guard case .object(let properties)? = schema["properties"] else {
                XCTFail("\(spec.name) schema declares no properties")
                continue
            }
            let selector = properties["op"] ?? properties["scope"]
            guard case .object(let discriminator)? = selector,
                case .array(let cases)? = discriminator["enum"]
            else {
                XCTFail("\(spec.name) schema has no op/scope enum")
                continue
            }
            let served = cases.compactMap { value -> String? in
                guard case .string(let text) = value else { return nil }
                return text
            }
            XCTAssertEqual(Set(served), Set(spec.ops.map(\.op)), "\(spec.name)'s served enum and its ops differ")
        }
    }

    /// Extracts all schema keywords from a JSON value tree.
    ///
    /// Recursively collects every keyword in a schema structure to detect banned ones. Property
    /// names inside a `properties` map are argument names, not keywords (e.g., a tool with a
    /// `title` argument).
    ///
    /// - Parameters:
    ///   - value: The JSON value to traverse.
    ///   - arePropertyNames: When true, skips collecting keys from this level (for `properties` maps).
    /// - Returns: A set of all keywords found in the tree.
    private static func schemaKeys(_ value: GmJsonValue, arePropertyNames: Bool = false) -> Set<String> {
        switch value {
        case .object(let fields):
            let own = arePropertyNames ? Set<String>() : Set(fields.keys)
            return fields.reduce(into: own) { keys, entry in
                keys.formUnion(
                    schemaKeys(entry.value, arePropertyNames: !arePropertyNames && entry.key == "properties")
                )
            }
        case .array(let values):
            return values.reduce(into: Set<String>()) { keys, element in
                keys.formUnion(schemaKeys(element))
            }
        default:
            return []
        }
    }
}

// MARK: - What the pen actually serves

/// The roster is only worth anything if the shipped binary serves it.
///
/// This runs the `gm_mcp` personality of the kernel under test over stdio and
/// compares its `tools/list` with the roster compiled into this bundle.
final class CdeRosterWireTests: KernelBackedTestCase {

    func testServedToolsListMatchesTheRoster() throws {
        let served = try servedTools()
        XCTAssertFalse(served.isEmpty, "the pen served no tools at all")

        XCTAssertEqual(Set(served.compactMap { $0["name"] as? String }), CdeToolRoster.names)

        let pinned = served.compactMap { entry -> String? in
            guard let meta = entry["_meta"] as? [String: Any],
                meta["anthropic/alwaysLoad"] as? Bool == true
            else { return nil }
            return entry["name"] as? String
        }
        XCTAssertEqual(Set(pinned), CdeToolRoster.pinned)
    }

    /// Fetches the tool list from the running pen binary via MCP.
    /// - Returns: An array of tool definitions as returned by `tools/list`.
    /// - Throws: XCTest assertion errors if the pen cannot be run or returns no result.
    private func servedTools() throws -> [[String: Any]] {
        let binary = env.root.appendingPathComponent("gm_kernel", isDirectory: false)
        try XCTSkipUnless(
            FileManager.default.isExecutableFile(atPath: binary.path),
            "no staged kernel to run as the pen"
        )

        let process = Process()
        process.executableURL = binary
        process.arguments = ["mcp"]
        var environment = ProcessInfo.processInfo.environment
        environment["GM_FS_ROOT"] = env.root.path
        process.environment = environment
        let input = Pipe()
        let output = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()

        let requests = """
            {"jsonrpc":"2.0","id":1,"method":"initialize","params":{}}
            {"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}

            """
        input.fileHandleForWriting.write(Data(requests.utf8))
        try input.fileHandleForWriting.close()
        // Drain before waiting: the listing is far larger than a pipe buffer.
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let transcript = String(bytes: data, encoding: .utf8) ?? ""
        for line in transcript.split(separator: "\n") {
            guard let message = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                message["id"] as? Int == 2,
                let result = message["result"] as? [String: Any],
                let tools = result["tools"] as? [[String: Any]]
            else { continue }
            return tools
        }
        XCTFail("the pen answered no tools/list result")
        return []
    }
}

// MARK: - The rank ops, end to end

/// The two ranking ops take their batch as `"<finding-uuid>:<0-999>"` strings.
///
/// Nothing but a real call proves the served arm parses the shape the schema
/// declares: a mismatch there is a tool that is advertised and cannot be used.
final class CdeRankWireTests: KernelBackedTestCase {

    private struct Seeded {
        let promptUuid: String
        let reviewSummaryUuid: String
        let reviewFindingUuid: String
        let exploreFindingUuid: String
    }

    nonisolated(unsafe) private static var seeded: Seeded?

    func testReviewRankTakesTheDeclaredStringPairs() throws {
        let fixture = try seed()
        let result = try call(
            "cde_rpir_review",
            [
                "op": .string("rank"),
                "summary_uuid": .string(fixture.reviewSummaryUuid),
                "ratings": .array([.string("\(fixture.reviewFindingUuid):100")]),
            ]
        )
        XCTAssertEqual(result["updatedCount"] as? Int, 1)
        XCTAssertEqual(result["unrankedCount"] as? Int, 0)
    }

    func testExploreRankTakesTheSameShape() throws {
        let fixture = try seed()
        let result = try call(
            "cde_rpir_explore",
            [
                "op": .string("rank"),
                "prompt_uuid": .string(fixture.promptUuid),
                "ratings": .array([.string("\(fixture.exploreFindingUuid):250")]),
            ]
        )
        XCTAssertEqual(result["updatedCount"] as? Int, 1)
    }

    func testABadRatingPairRejectsTheWholeBatch() throws {
        let fixture = try seed()
        let response = try env.send(
            .mcpCall,
            McpCallRequest(
                tool: "cde_rpir_review",
                identity: GmHarnessIdentity(),
                arguments: .object([
                    "op": .string("rank"),
                    "summary_uuid": .string(fixture.reviewSummaryUuid),
                    "ratings": .array([.string("\(fixture.reviewFindingUuid)-100")]),
                ])
            ),
            McpCallResponse.self
        )
        XCTAssertTrue(response.isError, "a malformed pair was accepted")
        XCTAssertTrue(response.text.contains("<finding-uuid>:<0-999>"), response.text)
    }

    // MARK: Harness

    /// Makes an MCP tool call and returns the result as a JSON object.
    /// - Parameters:
    ///   - tool: The tool name to call.
    ///   - arguments: The tool arguments as a dictionary of JSON values.
    /// - Returns: The call result as a JSON object.
    /// - Throws: XCTest assertion errors if the call fails or does not return an object.
    private func call(_ tool: String, _ arguments: [String: GmJsonValue]) throws -> [String: Any] {
        let response = try env.send(
            .mcpCall,
            McpCallRequest(tool: tool, identity: GmHarnessIdentity(), arguments: .object(arguments)),
            McpCallResponse.self
        )
        XCTAssertFalse(response.isError, "\(tool): \(response.text.prefix(300))")
        let object = try JSONSerialization.jsonObject(with: Data(response.text.utf8)) as? [String: Any]
        return try XCTUnwrap(object, "\(tool) did not render an object")
    }

    /// Creates a test fixture with a prompt and one review and exploration finding.
    ///
    /// Cached per process so a rank of one names every unranked row. Memoized in a static
    /// variable to avoid redundant setup across test methods.
    ///
    /// - Returns: The seeded prompt, summary, and finding uuids.
    /// - Throws: XCTest assertion errors if setup fails.
    private func seed() throws -> Seeded {
        if let seeded = Self.seeded { return seeded }
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let code = "t_rank_\(id)"
        let repo = env.root.appendingPathComponent("repos/\(code)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        let ensured = try env.send(
            .contextEnsure,
            ContextEnsureRequest(
                project: ProjectContext(
                    gitRepoName: code,
                    code: code,
                    name: code,
                    gmfsRelativeStoragePath: "projects/\(code)"
                ),
                instance: InstanceContext(
                    code: "\(code)_1",
                    name: code,
                    absoluteFileSystemPath: repo.path,
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1"
                ),
                session: SessionContext(
                    code: "main",
                    name: "main",
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1/sessions/main",
                    backstory: "",
                    goal: ""
                )
            ),
            ContextEnsureResponse.self
        )
        let prompt = try env.send(
            .promptCreate,
            PromptCreateRequest(
                sessionUuid: ensured.sessionUuid,
                name: "rank fixture",
                backstory: "",
                goal: "",
                detail: "rank"
            ),
            PromptRow.self
        )
        _ = try env.send(
            .promptStart,
            PromptStartRequest(promptUuid: prompt.uuid, variant: .bot),
            BotWorkflowResponse.self
        )
        let review = try seedReview(prompt.uuid)
        let built = Seeded(
            promptUuid: prompt.uuid,
            reviewSummaryUuid: review.summaryUuid,
            reviewFindingUuid: review.findingUuid,
            exploreFindingUuid: try seedExploration(prompt.uuid)
        )
        Self.seeded = built
        return built
    }

    /// Creates a review summary and a test finding for the given prompt.
    /// - Parameter promptUuid: The prompt uuid to create a review for.
    /// - Returns: A tuple of the review summary and finding uuids.
    /// - Throws: Store or wire errors if creation fails.
    private func seedReview(_ promptUuid: String) throws -> (summaryUuid: String, findingUuid: String) {
        let review = try env.send(
            .reviewOpen,
            ReviewOpenRequest(promptUuid: promptUuid),
            ReviewSummaryResponse.self
        )
        let finding = try env.send(
            .reviewFindingAdd,
            ReviewFindingAddRequest(
                summaryUuid: review.summary.uuid,
                kind: .other,
                title: "rank me",
                body: "the served arm must parse the declared pair",
                agentName: "reviewer"
            ),
            ReviewFindingRowResponse.self
        )
        return (review.summary.uuid, finding.finding.uuid)
    }

    /// Creates an exploration summary and a test finding for the given prompt.
    /// - Parameter promptUuid: The prompt uuid to create an exploration for.
    /// - Returns: The exploration finding uuid.
    /// - Throws: Store or wire errors if creation fails.
    private func seedExploration(_ promptUuid: String) throws -> String {
        let explore = try env.send(
            .exploreOpen,
            ExploreOpenRequest(promptUuid: promptUuid, agentType: "general", agentId: "t"),
            ExploreSummaryResponse.self
        )
        let finding = try env.send(
            .exploreFindingAdd,
            ExploreFindingAddRequest(
                summaryUuid: explore.summary.uuid,
                kind: .other,
                title: "rank me",
                body: "the served arm must parse the declared pair",
                agentName: "general"
            ),
            ExploreFindingRowResponse.self
        )
        return finding.finding.uuid
    }
}
