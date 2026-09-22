import Foundation
import GRDB
import XCTest

/// The composed reads, driven end to end over the wire.
///
/// `SchemaEnrollmentTests` proves each composite's request COMPILES; nothing
/// there proves it decodes the right rows into the right properties. These
/// cases write a real ref set through the daemon and read it back, so a
/// composite that loses its children, mis-keys an association or drops an
/// annotation fails here with the missing content named.
final class ComposedReadTests: KernelBackedTestCase {

    /// A booted identity spine plus the code it was minted under. Every verb
    /// that re-sends the context blocks has to re-send the SAME codes: the
    /// ensure chain keys on code, so a different code with the same uuid is a
    /// second project and collides on the primary key.
    private struct Fixture {
        let code: String
        let repoPath: String
        let context: ContextEnsureResponse

        var project: ProjectContext {
            ProjectContext(
                gitRepoName: code,
                code: code,
                name: code,
                gmfsRelativeStoragePath: "projects/\(code)",
                uuid: context.projectUuid
            )
        }

        var instance: InstanceContext {
            InstanceContext(
                code: "\(code)_1",
                name: code,
                absoluteFileSystemPath: repoPath,
                gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1",
                uuid: context.instanceUuid
            )
        }

        var session: SessionContext {
            SessionContext(
                code: "main",
                name: "main",
                gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1/sessions/main",
                uuid: context.sessionUuid
            )
        }
    }

    /// Project + instance + session, uniquely coded so cases cannot collide
    /// whatever order they run in.
    private func makeFixture(_ label: String) throws -> Fixture {
        let id = String(UUID().uuidString.prefix(8)).lowercased()
        let code = "t_\(label)_\(id)"
        let repo = env.root.appendingPathComponent("repos/\(code)", isDirectory: true)
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)

        let context = try env.send(
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
                    gmfsRelativeStoragePath: "projects/\(code)/instances/\(code)_1/sessions/main"
                )
            ),
            ContextEnsureResponse.self
        )
        return Fixture(code: code, repoPath: repo.path, context: context)
    }

    private func makePrompt(_ sessionUuid: String, _ name: String) throws -> PromptRow {
        try env.send(
            .promptCreate,
            PromptCreateRequest(sessionUuid: sessionUuid, name: name),
            PromptRow.self
        )
    }

    /// One `file_change` row for the booted fixture, the FK a briefing's third
    /// ref class needs.
    private func makeFileChange(
        _ fixture: Fixture,
        promptUuid: String
    ) throws -> FileChangeAddResponse {
        try env.send(
            .fileChangeAdd,
            FileChangeAdd(
                project: fixture.project,
                instance: fixture.instance,
                session: fixture.session,
                promptUuid: promptUuid,
                relativePath: "Sources/Touched.swift",
                changeKind: .edit,
                ranges: [ChangeRange(lineStart: 1, lineEnd: 4)],
                origin: FileChangeOrigin.manual
            ),
            FileChangeAddResponse.self
        )
    }

    /// A real `kbite_resource_file` uuid: both ref families FK onto that table,
    /// so neither can be exercised with a fabricated uuid. Opens a maw under the
    /// run root, writes one chewed artifact naming one raw file, and digests.
    private func makeKbiteFileUuid(_ label: String) throws -> String {
        let kbite = try makeDigestedKbite(label)
        let resource = try XCTUnwrap(kbite.resources.first, "digest wrote no resource")
        return try XCTUnwrap(resource.files.first, "digest wrote no file row").uuid
    }

    /// The same fixture, handed back whole for the cases that read the resource
    /// listing itself rather than borrowing one file uuid out of it.
    private func makeDigestedKbite(
        _ label: String,
        files: [String] = ["notes.md"]
    ) throws -> KbiteGetResponse {
        let code = "tk_\(label)_\(String(UUID().uuidString.prefix(6)).lowercased())"
        let maw = env.root
            .appendingPathComponent("kbites", isDirectory: true)
            .appendingPathComponent("open", isDirectory: true)
            .appendingPathComponent(code, isDirectory: true)
        _ = try env.send(
            .kbiteMawOpen,
            KbiteMawOpenRequest(kbiteName: code, mawPath: maw.path),
            KbiteMawOpenResponse.self
        )

        // The parser resolves the `File` cell as a path under
        // {axis1}/{axis2}/{resourceName}/, so the raw file has to sit there.
        let axis = maw.appendingPathComponent("primary/documentation", isDirectory: true)
        let sources = axis.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        for name in files {
            try "the note body"
                .write(
                    to: sources.appendingPathComponent(name),
                    atomically: true,
                    encoding: .utf8
                )
        }
        // The File cell is a real path and the header is canonical: a grouped
        // row or a backticked name leaves the file index silently empty.
        let rows = files.map { "| \($0) | md | a note |" }.joined(separator: "\n")
        try """
        # Chewed: demo

        ## 1. Contents Overview

        | File | Type | Description |
        |------|------|-------------|
        \(rows)

        ## 4. Keywords

        notes
        """
        .write(
            to: axis.appendingPathComponent("demo_chewed.md"),
            atomically: true,
            encoding: .utf8
        )

        let digest = try env.send(
            .kbiteDigest,
            KbiteDigestRequest(code: code, kbiteOpenPath: maw.path),
            KbiteDigestResponse.self
        )
        XCTAssertEqual(digest.fileCount, files.count, "the chewed artifact named \(files.count) files")

        return try env.send(.kbiteGet, KbiteGetRequest(code: code), KbiteGetResponse.self)
    }

    /// One ref of each kind, in the order the package's three prefetches carry
    /// them. Returns the last response, whose version is what COMPLETE expects.
    private func addOneRefOfEachKind(
        packageUuid: String,
        kbiteFileUuid: String
    ) throws -> CarePackageResponse {
        _ = try env.send(
            .carePackageRefAdd,
            CarePackageRefAddRequest(
                packageUuid: packageUuid,
                kind: .dope,
                dopeCode: "agentics.care_package.clarified_intent",
                note: "the intent column"
            ),
            CarePackageResponse.self
        )
        _ = try env.send(
            .carePackageRefAdd,
            CarePackageRefAddRequest(
                packageUuid: packageUuid,
                kind: .kbite,
                kbiteFileUuid: kbiteFileUuid
            ),
            CarePackageResponse.self
        )
        return try env.send(
            .carePackageRefAdd,
            CarePackageRefAddRequest(
                packageUuid: packageUuid,
                kind: .exploration,
                curatedTitle: "the composed read",
                curatedBody: "a curated copy, carried by value",
                filePath: "Sources/Persistence/Composites/AgenticsComposites.swift"
            ),
            CarePackageResponse.self
        )
    }

    // MARK: - AgentBriefingWithRefs

    /// Three `including(all:)` prefetches on one root, read back in seq order.
    ///
    /// The failure this catches is a prefetch that decodes EMPTY: the request
    /// compiles either way, and only a written-then-read ref set tells the two
    /// apart. Two dope refs, so the seq ordering is an assertion rather than a
    /// coincidence.
    func testBriefingComposesItsThreeRefClasses() throws {
        let fixture = try makeFixture("brief")
        let prompt = try makePrompt(fixture.context.sessionUuid, "briefing fixture")

        let change = try makeFileChange(fixture, promptUuid: prompt.uuid)
        let kbiteFileUuid = try makeKbiteFileUuid("brief")

        let opened = try env.send(
            .briefingOpen,
            BriefingOpenRequest(promptUuid: prompt.uuid, briefingForStep: "initial"),
            BriefingRowResponse.self
        )
        XCTAssertTrue(opened.created)

        _ = try env.send(
            .briefingComplete,
            BriefingCompleteRequest(
                briefingUuid: opened.briefing.uuid,
                expectedVersion: opened.briefing.version,
                dopeRefs: ["agentics.agent_briefing.status", "agentics.care_package.status"],
                kbiteRefs: [kbiteFileUuid],
                fileChangeRefs: [change.fileChangeUuid]
            ),
            BriefingRowResponse.self
        )

        let read =
            try env.send(
                .briefingGet,
                BriefingGetRequest(briefingUuid: opened.briefing.uuid),
                BriefingGetResponse.self
            )
            .briefing

        XCTAssertEqual(read.status, "ready")
        XCTAssertEqual(
            read.dopeRefs.map(\.dopeCode),
            ["agentics.agent_briefing.status", "agentics.care_package.status"],
            "dope children decoded empty or out of seq order"
        )
        XCTAssertEqual(read.dopeRefs.map(\.seq), [0, 1])
        XCTAssertEqual(
            read.kbiteRefs.map(\.kbiteResourceFileUuid),
            [kbiteFileUuid],
            "kbite children decoded empty"
        )
        XCTAssertEqual(
            read.fileChangeRefs.map(\.fileChangeUuid),
            [change.fileChangeUuid],
            "file-change children decoded empty"
        )
    }

    // MARK: - CarePackageWithRefs

    /// The same prefetch shape over a different root, with the third class
    /// being a curated COPY rather than an FK onto another machine's table.
    func testCarePackageComposesItsThreeRefClasses() throws {
        let fixture = try makeFixture("pkg")
        let prompt = try makePrompt(fixture.context.sessionUuid, "care package fixture")
        let kbiteFileUuid = try makeKbiteFileUuid("pkg")

        let summary =
            try env.send(
                .clarifyOpen,
                ClarifyOpenRequest(promptUuid: prompt.uuid),
                ClarifySummaryResponse.self
            )
            .summary

        let opened = try env.send(
            .carePackageOpen,
            CarePackageOpenRequest(summaryUuid: summary.uuid),
            CarePackageResponse.self
        )
        XCTAssertTrue(opened.created)

        let afterRefs = try addOneRefOfEachKind(
            packageUuid: opened.package.uuid,
            kbiteFileUuid: kbiteFileUuid
        )

        _ = try env.send(
            .carePackageComplete,
            CarePackageCompleteRequest(
                packageUuid: opened.package.uuid,
                expectedVersion: afterRefs.package.version,
                clarifiedIntent: "read the three ref classes back through one composite"
            ),
            CarePackageResponse.self
        )

        let package =
            try env.send(
                .carePackageGet,
                CarePackageGetRequest(promptUuid: prompt.uuid),
                CarePackageResponse.self
            )
            .package

        XCTAssertEqual(package.status, "ready")
        XCTAssertEqual(
            package.dopeRefs.map(\.dopeCode),
            ["agentics.care_package.clarified_intent"],
            "dope children decoded empty"
        )
        XCTAssertEqual(
            package.kbiteRefs.map(\.kbiteResourceFileUuid),
            [kbiteFileUuid],
            "kbite children decoded empty"
        )
        XCTAssertEqual(
            package.explorationRefs.map(\.curatedTitle),
            ["the composed read"],
            "exploration children decoded empty"
        )
        XCTAssertEqual(
            package.explorationRefs.first?.curatedBody,
            "a curated copy, carried by value"
        )
    }

    // MARK: - SessionSummary

    /// The annotated scalar: `lastActivityAt` is computed by the request, not
    /// stored, so an annotation that loses its `forKey` decodes as absent and
    /// the whole row fails rather than quietly reading a column.
    func testSessionListCarriesItsActivityAnnotation() throws {
        let fixture = try makeFixture("slist")

        let sessions =
            try env.send(
                .sessionList,
                SessionListRequest(instanceUuid: fixture.context.instanceUuid),
                SessionListResponse.self
            )
            .sessions

        let session = try XCTUnwrap(
            sessions.first { $0.uuid == fixture.context.sessionUuid },
            "SESSION_LIST lost the session it was just given"
        )
        XCTAssertEqual(session.instanceUuid, fixture.context.instanceUuid)
        XCTAssertEqual(session.code, "main")
        XCTAssertFalse(session.lastActivityAt.isEmpty, "the activity annotation decoded empty")
        XCTAssertGreaterThanOrEqual(
            session.lastActivityAt,
            session.createdAt,
            "last activity precedes creation — the annotation read the wrong column"
        )
    }

    // MARK: - DiagramWithOwner

    /// The LEFT JOIN annotation: INSTANCE is not a tier, so a SESSION-tier
    /// diagram reaches its instance through session and a PROJECT-tier one
    /// reports nil. An INNER join here would drop the project row entirely.
    func testDiagramGetDerivesInstanceOnlyThroughSession() throws {
        let fixture = try makeFixture("diag")

        let sessionDiagram = try env.send(
            .diagramInit,
            DiagramInitRequest(
                sessionUuid: fixture.context.sessionUuid,
                code: "d_session_tier",
                name: "session tier"
            ),
            DiagramResponse.self
        )
        XCTAssertEqual(sessionDiagram.diagram.tier, DiagramTier.session.rawValue)

        let projectDiagram = try env.send(
            .diagramInit,
            DiagramInitRequest(
                projectUuid: fixture.context.projectUuid,
                code: "d_project_tier",
                name: "project tier"
            ),
            DiagramResponse.self
        )
        XCTAssertEqual(projectDiagram.diagram.tier, DiagramTier.project.rawValue)

        let sessionTree =
            try env.send(
                .diagramGet,
                DiagramGetRequest(diagramUuid: sessionDiagram.diagram.uuid),
                DiagramGetResponse.self
            )
            .tree
        XCTAssertEqual(
            sessionTree.instanceUuid,
            fixture.context.instanceUuid,
            "a SESSION-tier diagram must derive its instance through the session"
        )

        let projectTree =
            try env.send(
                .diagramGet,
                DiagramGetRequest(diagramUuid: projectDiagram.diagram.uuid),
                DiagramGetResponse.self
            )
            .tree
        XCTAssertNil(
            projectTree.instanceUuid,
            "a PROJECT-tier diagram has no session, so no instance"
        )
        XCTAssertEqual(projectTree.projectUuid, fixture.context.projectUuid)
    }

    /// building → answering, on the summary version the question write left.
    private func sealClarification(promptUuid: String, summaryUuid: String) throws {
        let current = try env.send(
            .clarifyGet,
            ClarifyGetRequest(promptUuid: promptUuid),
            ClarifyGetResponse.self
        )
        _ = try env.send(
            .clarifySeal,
            ClarifySealRequest(summaryUuid: summaryUuid, expectedVersion: current.summary.version),
            ClarifySummaryResponse.self
        )
    }

    // MARK: - ClarificationQuestionWithOptions

    /// The option prefetch plus the selection that rides beside it.
    ///
    /// `options` and `selectedOptionUuids` reach the row by different paths —
    /// one prefetch, one answer junction — so a composite that mis-keys either
    /// still answers the other. Two options make the seq ordering an assertion,
    /// and selecting the SECOND makes the selection one too.
    func testClarifyGetComposesQuestionOptionsAndSelection() throws {
        let fixture = try makeFixture("clarq")
        let prompt = try makePrompt(fixture.context.sessionUuid, "clarify fixture")

        let opened = try env.send(
            .clarifyOpen,
            ClarifyOpenRequest(promptUuid: prompt.uuid),
            ClarifySummaryResponse.self
        )
        XCTAssertTrue(opened.created)

        let written = try env.send(
            .clarifyQuestionAdd,
            ClarifyQuestionAddRequest(
                summaryUuid: opened.summary.uuid,
                question: "which shape does the read return?",
                options: ["option alpha", "option beta"]
            ),
            ClarifyQuestionRowResponse.self
        )
        XCTAssertEqual(
            written.question.options.map(\.body),
            ["option alpha", "option beta"],
            "the option children decoded empty or out of seq order at write"
        )
        let chosen = try XCTUnwrap(written.question.options.last, "the question kept no options")

        try sealClarification(promptUuid: prompt.uuid, summaryUuid: opened.summary.uuid)

        _ = try env.send(
            .clarifyAnswer,
            ClarifyAnswerRequest(
                questionUuid: written.question.uuid,
                expectedVersion: written.question.version,
                selectedOptionUuids: [chosen.uuid]
            ),
            ClarifyQuestionRowResponse.self
        )

        let read = try env.send(
            .clarifyGet,
            ClarifyGetRequest(promptUuid: prompt.uuid),
            ClarifyGetResponse.self
        )
        let question = try XCTUnwrap(
            read.questions.first { $0.uuid == written.question.uuid },
            "CLARIFY_GET lost the question it was just given"
        )

        XCTAssertEqual(
            question.options.map(\.body),
            ["option alpha", "option beta"],
            "the option children decoded empty or out of seq order"
        )
        XCTAssertEqual(question.options.map(\.seq), [1, 2])
        XCTAssertEqual(
            question.selectedOptionUuids,
            [chosen.uuid],
            "the answer junction decoded empty or selected the wrong option"
        )
    }

    // MARK: - ArchPersistenceChangeWithFields

    /// One persistence change with its two field children, in seq order.
    ///
    /// The change row is reachable on its own, so a field prefetch that decodes
    /// empty leaves the read looking healthy. Two fields written in order make
    /// both the presence and the ordering assertions rather than coincidences.
    func testArchitectureGetComposesPersistenceChangeFields() throws {
        let fixture = try makeFixture("arch")
        let prompt = try makePrompt(fixture.context.sessionUuid, "architecture fixture")

        let opened = try env.send(
            .archOpen,
            ArchOpenRequest(promptUuid: prompt.uuid),
            ArchSummaryResponse.self
        )
        XCTAssertTrue(opened.created)

        let change = try env.send(
            .archPersistAdd,
            ArchPersistAddRequest(
                summaryUuid: opened.summary.uuid,
                className: "KbiteResourceFileHead",
                filePath: "Sources/Persistence/Composites/KbitesComposites.swift",
                reasonBrief: "project the content column out of the listing"
            ),
            ArchPersistAddResponse.self
        )

        for name in ["has_content", "resource_file_name"] {
            _ = try env.send(
                .archFieldAdd,
                ArchFieldAddRequest(
                    persistenceChangeUuid: change.change.uuid,
                    fieldName: name,
                    dataType: "TEXT",
                    changeReason: "the composed read needs it",
                    changePurpose: "decoded by the projection",
                    nullable: false
                ),
                ArchFieldAddResponse.self
            )
        }

        let read = try env.send(
            .archGet,
            ArchGetRequest(promptUuid: prompt.uuid),
            ArchGetResponse.self
        )
        let persistence = try XCTUnwrap(
            read.persistenceChanges.first { $0.uuid == change.change.uuid },
            "ARCH_GET lost the persistence change it was just given"
        )

        XCTAssertEqual(persistence.className, "KbiteResourceFileHead")
        XCTAssertEqual(
            persistence.fields.map(\.fieldName),
            ["has_content", "resource_file_name"],
            "the field children decoded empty or out of seq order"
        )
        XCTAssertEqual(persistence.fields.map(\.seq), [1, 2])
    }

    // MARK: - KbiteResourceWithFiles

    /// The projected child: heads in the listing, content only on the file get.
    ///
    /// `hasContent` is computed by the association's select, so a projection
    /// that lost its `forKey` fails to decode and one that read the wrong
    /// expression reports false for a file that has a body. The trace proves
    /// the ~115 MB column is named nowhere but inside that test.
    func testKbiteResourceListProjectsHeadsAndFileGetCarriesContent() throws {
        let kbite = try makeDigestedKbite("res")
        let resource = try XCTUnwrap(kbite.resources.first, "digest wrote no resource")
        let head = try XCTUnwrap(resource.files.first, "the file children decoded empty")

        XCTAssertEqual(resource.files.count, 1)
        XCTAssertEqual(head.resourceFileName, "notes.md")
        XCTAssertTrue(head.hasContent, "the digested file has a body, so the projection must say so")

        let file =
            try env.send(
                .kbiteFileGet,
                KbiteFileGetRequest(fileUuid: head.uuid),
                KbiteFileGetResponse.self
            )
            .file
        XCTAssertEqual(file.uuid, head.uuid)
        XCTAssertEqual(file.kbiteResourceUuid, resource.uuid)
        XCTAssertEqual(
            file.resourceFileContent,
            "the note body",
            "KBITE_FILE_GET is the only door to the content column"
        )

        try assertResourceContentIsOnlyProbed()
    }

    /// Both statements of the resource composite, captured off a live fetch.
    ///
    /// `including(all:)` plans its children in a SECOND statement that no
    /// prepared request exposes, so the only public door to that SQL is a
    /// trace over a fetch that has parent rows to prefetch for.
    private func assertResourceContentIsOnlyProbed() throws {
        var statements: [String] = []
        try env.readOnlyDatabase()
            .read { db in
                db.trace { event in
                    if case .statement(let statement) = event { statements.append(statement.sql) }
                }
                _ = try KbiteResourceWithFiles.request().fetchAll(db)
            }

        let main = try XCTUnwrap(
            statements.first { $0.contains("FROM \"kbite_resource\"") },
            "the composite ran no statement over kbite_resource: \(statements)"
        )
        XCTAssertFalse(
            main.contains("resource_file_content"),
            "the content column reached the main statement: \(main)"
        )

        let prefetch = try XCTUnwrap(
            statements.first { $0.contains("FROM \"kbite_resource_file\"") },
            "the prefetch statement never ran: \(statements)"
        )
        let unquoted = prefetch.replacingOccurrences(of: "\"", with: "")
        XCTAssertEqual(
            unquoted.components(separatedBy: "resource_file_content").count - 1,
            1,
            "the content column is named more than once in the child select: \(prefetch)"
        )
        XCTAssertTrue(
            unquoted.contains("resource_file_content IS NOT NULL"),
            "the child select reads the content column instead of probing it: \(prefetch)"
        )
    }

    // MARK: - ReviewSummaryWithFindings

    /// The finding prefetch, its ordering, and the window partition over it.
    ///
    /// A mis-keyed prefetch decodes EMPTY and REVIEW_GET still answers with a
    /// healthy-looking summary, so the children have to be read back. Three
    /// findings — one unranked, one inside the default window, one outside —
    /// make the ordering and the full/stub split assertions rather than
    /// coincidences.
    func testReviewGetComposesFindingsInRankOrder() throws {
        let fixture = try makeFixture("rev")
        let prompt = try makePrompt(fixture.context.sessionUuid, "review fixture")

        let opened = try env.send(
            .reviewOpen,
            ReviewOpenRequest(promptUuid: prompt.uuid),
            ReviewSummaryResponse.self
        )
        XCTAssertTrue(opened.created)

        let titles = ["the kept finding", "the ignored finding", "the unranked finding"]
        let written = try titles.map { title in
            try env.send(
                .reviewFindingAdd,
                ReviewFindingAddRequest(
                    summaryUuid: opened.summary.uuid,
                    kind: .regressionRisk,
                    title: title,
                    body: "written by the composed read",
                    agentName: "composed"
                ),
                ReviewFindingRowResponse.self
            )
            .finding
        }

        _ = try env.send(
            .reviewRank,
            ReviewRankRequest(
                summaryUuid: opened.summary.uuid,
                ratings: [
                    FindingRating(findingUuid: written[0].uuid, rating: 40),
                    FindingRating(findingUuid: written[1].uuid, rating: 500),
                ]
            ),
            ReviewRankResponse.self
        )

        let read = try env.send(
            .reviewGet,
            ReviewGetRequest(promptUuid: prompt.uuid),
            ReviewGetResponse.self
        )

        XCTAssertEqual(
            read.findings.map(\.title),
            ["the unranked finding", "the kept finding"],
            "the finding children decoded empty, or unranked-first ordering was lost"
        )
        XCTAssertEqual(read.findings.map(\.findingRating), [nil, 40])
        XCTAssertEqual(
            read.findingStubs.map(\.title),
            ["the ignored finding"],
            "the window partition kept a finding it should have stubbed"
        )
        XCTAssertEqual(read.findingStubs.map(\.findingRating), [500])
    }

    // MARK: - FileChangeWithRanges

    /// The range prefetch under a LIMIT, read back through FILE_CHANGE_LIST.
    ///
    /// The listing orders newest first and limits, so the prefetch's children
    /// have to belong to the limited parent set rather than the whole table.
    /// Three ranges on the newest change make the insertion ordering an
    /// assertion, and the older change on the same path proves the limit.
    func testFileChangeListCarriesOnlyTheNewestChangeRanges() throws {
        let fixture = try makeFixture("fcl")
        let prompt = try makePrompt(fixture.context.sessionUuid, "file change fixture")

        _ = try addFileChange(fixture, promptUuid: prompt.uuid, path: "Sources/First.swift", ranges: [(1, 4)])
        _ = try addFileChange(fixture, promptUuid: prompt.uuid, path: "Sources/Other.swift", ranges: [(7, 9)])
        let newest = try addFileChange(
            fixture,
            promptUuid: prompt.uuid,
            path: "Sources/First.swift",
            ranges: [(30, 33), (10, 12), (20, 22)]
        )

        let changes =
            try env.send(
                .fileChangeList,
                FileChangeListRequest(sessionUuid: fixture.context.sessionUuid, limit: 1),
                FileChangeListResponse.self
            )
            .changes

        XCTAssertEqual(changes.count, 1, "the limit reached the parent rows, not the prefetched children")
        let change = try XCTUnwrap(changes.first)
        XCTAssertEqual(change.uuid, newest.fileChangeUuid, "FILE_CHANGE_LIST returned the wrong newest row")
        XCTAssertEqual(change.relativePath, "Sources/First.swift", "the joined path annotation decoded wrong")
        XCTAssertEqual(
            change.ranges.map { [$0.lineStart, $0.lineEnd] },
            [[30, 33], [10, 12], [20, 22]],
            "the range children decoded empty, out of insertion order, or belong to another change"
        )
    }

    /// One `file_change` at a path with the ranges the case names.
    private func addFileChange(
        _ fixture: Fixture,
        promptUuid: String,
        path: String,
        ranges: [(Int, Int)]
    ) throws -> FileChangeAddResponse {
        try env.send(
            .fileChangeAdd,
            FileChangeAdd(
                project: fixture.project,
                instance: fixture.instance,
                session: fixture.session,
                promptUuid: promptUuid,
                relativePath: path,
                changeKind: .edit,
                ranges: ranges.map { ChangeRange(lineStart: $0.0, lineEnd: $0.1) },
                origin: FileChangeOrigin.manual
            ),
            FileChangeAddResponse.self
        )
    }

    // MARK: - DopeCogWithElements

    /// The cog's element prefetch, read back through DOPE_COG_GET.
    ///
    /// The elements are ordered by `sort_order` then `code`, so writing the
    /// second element with the LOWER sort order makes the ordering an
    /// assertion rather than insertion order showing through.
    func testDopeCogGetComposesItsElementsInSortOrder() throws {
        let fixture = try makeFixture("cog")

        let scope =
            try env.send(
                .dopeInit,
                DopeInitRequest(
                    sessionUuid: fixture.context.sessionUuid,
                    code: "cog_scope",
                    name: "cog scope"
                ),
                DopeScopeResponse.self
            )
            .scope

        let cog = try env.send(
            .dopeCogAdd,
            DopeCogAddRequest(scopeUuid: scope.uuid, code: "shape", name: "the shape"),
            DopeCogResponse.self
        )

        for (code, sortOrder) in [("second_hull", 2), ("first_hull", 1)] {
            _ = try env.send(
                .dopeCogElementAdd,
                DopeCogElementAddRequest(
                    cogUuid: cog.cog.uuid,
                    elementType: DopeCogElementType.hull.rawValue,
                    code: code,
                    name: code,
                    sortOrder: sortOrder,
                    primaryPath: "Sources/\(code)"
                ),
                DopeCogElementResponse.self
            )
        }

        let cogs =
            try env.send(
                .dopeCogGet,
                DopeCogGetRequest(scopeUuid: scope.uuid, code: "shape"),
                DopeCogGetResponse.self
            )
            .cogs

        let read = try XCTUnwrap(cogs.first { $0.uuid == cog.cog.uuid }, "DOPE_COG_GET lost the cog it minted")
        XCTAssertEqual(
            read.elements.map(\.code),
            ["first_hull", "second_hull"],
            "the element children decoded empty or out of sort order"
        )
    }

    // MARK: - Statement budgets

    /// What each composed read costs in SELECT statements, and that the cost
    /// does not move when a second child row is written.
    ///
    /// The count is taken on the test-side READ-ONLY handle by issuing the
    /// SAME request the repository issues, so what is proven is the request,
    /// not the kernel serving the verb: the kernel is another process. Each
    /// read is measured at one child and at two, because a budget alone
    /// passes a prefetch that degraded into a per-child query.
    func testComposedReadsHoldTheirStatementBudgets() throws {
        try assertBriefingBudget()
        try assertCarePackageBudget()
        try assertClarifyQuestionBudget()
        try assertArchitectureBudget()
        try assertKbiteResourceBudget()
        try assertSessionBudget()
    }

    /// The SELECTs one fetch issues, measured on a warmed connection.
    ///
    /// The fetch runs twice on the same connection: GRDB introspects a table's
    /// schema the first time it meets it, and those `sqlite_master` reads would
    /// otherwise land on whichever measurement ran first and break the very
    /// comparison this exists for.
    private func selectStatements(_ fetch: (Database) throws -> Void) throws -> [String] {
        var captured: [String] = []
        var capturing = false
        try env.readOnlyDatabase()
            .read { db in
                db.trace { event in
                    guard capturing, case .statement(let statement) = event else { return }
                    let sql = statement.sql.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard sql.uppercased().hasPrefix("SELECT"),
                        !sql.contains("sqlite_master"),
                        !sql.contains("sqlite_schema")
                    else { return }
                    captured.append(sql)
                }
                try fetch(db)
                capturing = true
                try fetch(db)
            }
        return captured
    }

    /// Under budget with one child, and the same count with two.
    private func assertBudget(
        _ read: String,
        withOneChild: Int,
        withTwoChildren: Int,
        budget: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertLessThanOrEqual(
            withOneChild,
            budget,
            "\(read) costs \(withOneChild) statements, over its budget of \(budget)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            withOneChild,
            withTwoChildren,
            "\(read) grew \(withOneChild) → \(withTwoChildren) on a second child: "
                + "a prefetch degraded into a per-child query",
            file: file,
            line: line
        )
    }

    /// One briefing, completed with the ref set the budget is measured over.
    private func completedBriefing(
        promptUuid: String,
        dopeRefs: [String],
        kbiteFileUuid: String,
        fileChangeUuid: String
    ) throws -> String {
        // "initial" is the only step the kernel knows, so a second briefing
        // needs a second prompt rather than a second step.
        let opened = try env.send(
            .briefingOpen,
            BriefingOpenRequest(promptUuid: promptUuid, briefingForStep: "initial"),
            BriefingRowResponse.self
        )
        _ = try env.send(
            .briefingComplete,
            BriefingCompleteRequest(
                briefingUuid: opened.briefing.uuid,
                expectedVersion: opened.briefing.version,
                dopeRefs: dopeRefs,
                kbiteRefs: [kbiteFileUuid],
                fileChangeRefs: [fileChangeUuid]
            ),
            BriefingRowResponse.self
        )
        return opened.briefing.uuid
    }

    /// BRIEFING_GET: one root and three prefetches, four statements whatever
    /// the ref count. The read it replaced ran three queries per briefing.
    private func assertBriefingBudget() throws {
        let fixture = try makeFixture("bbud")
        let kbiteFileUuid = try makeKbiteFileUuid("bbud")
        let first = try makePrompt(fixture.context.sessionUuid, "briefing budget one")
        let second = try makePrompt(fixture.context.sessionUuid, "briefing budget two")
        let firstChange = try makeFileChange(fixture, promptUuid: first.uuid)
        let secondChange = try makeFileChange(fixture, promptUuid: second.uuid)

        let one = try completedBriefing(
            promptUuid: first.uuid,
            dopeRefs: ["agentics.agent_briefing.status"],
            kbiteFileUuid: kbiteFileUuid,
            fileChangeUuid: firstChange.fileChangeUuid
        )
        let two = try completedBriefing(
            promptUuid: second.uuid,
            dopeRefs: ["agentics.agent_briefing.status", "agentics.care_package.status"],
            kbiteFileUuid: kbiteFileUuid,
            fileChangeUuid: secondChange.fileChangeUuid
        )

        let counts = try [one, two]
            .map { uuid -> Int in
                try selectStatements { db in
                    let briefings =
                        try AgentBriefingWithRefs.request()
                        .filter(AgentBriefingRecord.Columns.uuid == uuid)
                        .order(
                            AgentBriefingRecord.Columns.briefingForStep,
                            AgentBriefingRecord.Columns.createdAt
                        )
                        .fetchAll(db)
                    XCTAssertFalse(
                        briefings.isEmpty,
                        "the briefing request matched no row: a prefetch GRDB skips is not a budget"
                    )
                }
                .count
            }
        assertBudget(
            "BRIEFING_GET",
            withOneChild: counts[0],
            withTwoChildren: counts[1],
            budget: 4
        )
    }

    /// CARE_PACKAGE_GET: ONE request, four statements — a root and its three
    /// ref classes. The plan's "4 → 1" counts requests, not statements; the
    /// win is that neither number moves with the ref count.
    private func assertCarePackageBudget() throws {
        let fixture = try makeFixture("pbud")
        let prompt = try makePrompt(fixture.context.sessionUuid, "care package budget")
        let kbiteFileUuid = try makeKbiteFileUuid("pbud")

        let summary =
            try env.send(
                .clarifyOpen,
                ClarifyOpenRequest(promptUuid: prompt.uuid),
                ClarifySummaryResponse.self
            )
            .summary
        let opened = try env.send(
            .carePackageOpen,
            CarePackageOpenRequest(summaryUuid: summary.uuid),
            CarePackageResponse.self
        )
        let packageUuid = opened.package.uuid
        _ = try addOneRefOfEachKind(packageUuid: packageUuid, kbiteFileUuid: kbiteFileUuid)

        let read: (Database) throws -> Void = { db in
            let composed =
                try CarePackageWithRefs.request()
                .filter(CarePackageRecord.Columns.uuid == packageUuid)
                .fetchOne(db)
            XCTAssertNotNil(
                composed,
                "the care package request matched no row: a prefetch GRDB skips is not a budget"
            )
        }
        let withOne = try selectStatements(read).count
        _ = try env.send(
            .carePackageRefAdd,
            CarePackageRefAddRequest(
                packageUuid: packageUuid,
                kind: .dope,
                dopeCode: "agentics.care_package.status",
                note: "the second dope child"
            ),
            CarePackageResponse.self
        )
        let withTwo = try selectStatements(read).count
        assertBudget(
            "CARE_PACKAGE_GET",
            withOneChild: withOne,
            withTwoChildren: withTwo,
            budget: 4
        )
    }

    /// CLARIFY_GET questions: the composite's two statements plus one batched
    /// pass over the answer junction, grouped in memory. Three whatever the
    /// question and option counts.
    private func assertClarifyQuestionBudget() throws {
        let fixture = try makeFixture("qbud")
        let prompt = try makePrompt(fixture.context.sessionUuid, "clarify budget")
        let opened = try env.send(
            .clarifyOpen,
            ClarifyOpenRequest(promptUuid: prompt.uuid),
            ClarifySummaryResponse.self
        )
        let summaryUuid = opened.summary.uuid
        _ = try env.send(
            .clarifyQuestionAdd,
            ClarifyQuestionAddRequest(
                summaryUuid: summaryUuid,
                question: "one option?",
                options: ["only"]
            ),
            ClarifyQuestionRowResponse.self
        )

        let read: (Database) throws -> Void = { db in
            let questions =
                try ClarificationQuestionWithOptions.request()
                .filter(
                    UserClarificationQuestionRecord.Columns.clarificationSummaryUuid == summaryUuid
                )
                .fetchAll(db)
            XCTAssertFalse(
                questions.isEmpty,
                "the question request matched no row: a prefetch GRDB skips is not a budget"
            )
            _ =
                try UserClarificationAnswerRecord
                .filter(
                    questions.map(\.questionRow.uuid)
                        .contains(UserClarificationAnswerRecord.Columns.questionUuid)
                )
                .order(Column("id"))
                .fetchAll(db)
        }
        let withOne = try selectStatements(read).count
        _ = try env.send(
            .clarifyQuestionAdd,
            ClarifyQuestionAddRequest(
                summaryUuid: summaryUuid,
                question: "two options?",
                options: ["alpha", "beta"]
            ),
            ClarifyQuestionRowResponse.self
        )
        let withTwo = try selectStatements(read).count
        assertBudget(
            "CLARIFY_GET questions",
            withOneChild: withOne,
            withTwoChildren: withTwo,
            budget: 3
        )
    }

    /// ARCH_GET persistence changes: the changes and their fields, two
    /// statements whatever the field count.
    private func assertArchitectureBudget() throws {
        let fixture = try makeFixture("abud")
        let prompt = try makePrompt(fixture.context.sessionUuid, "architecture budget")
        let opened = try env.send(
            .archOpen,
            ArchOpenRequest(promptUuid: prompt.uuid),
            ArchSummaryResponse.self
        )
        let summaryUuid = opened.summary.uuid
        let change = try env.send(
            .archPersistAdd,
            ArchPersistAddRequest(
                summaryUuid: summaryUuid,
                className: "BudgetRecord",
                filePath: "Sources/Persistence/Entities/BudgetRecord.swift",
                reasonBrief: "one change, measured at one field and at two"
            ),
            ArchPersistAddResponse.self
        )
        try addArchField(changeUuid: change.change.uuid, named: "first_field")

        let read: (Database) throws -> Void = { db in
            let changes =
                try ArchPersistenceChangeWithFields.request()
                .filter(
                    ArchitecturePersistenceChangeRecord.Columns.architectureSummaryUuid
                        == summaryUuid
                )
                .fetchAll(db)
            XCTAssertFalse(
                changes.isEmpty,
                "the persistence change request matched no row: a prefetch GRDB skips is not a budget"
            )
        }
        let withOne = try selectStatements(read).count
        try addArchField(changeUuid: change.change.uuid, named: "second_field")
        let withTwo = try selectStatements(read).count
        assertBudget(
            "ARCH_GET persistence changes",
            withOneChild: withOne,
            withTwoChildren: withTwo,
            budget: 2
        )
    }

    private func addArchField(changeUuid: String, named: String) throws {
        _ = try env.send(
            .archFieldAdd,
            ArchFieldAddRequest(
                persistenceChangeUuid: changeUuid,
                fieldName: named,
                dataType: "TEXT",
                changeReason: "the budget needs a child",
                changePurpose: "decoded by the prefetch",
                nullable: false
            ),
            ArchFieldAddResponse.self
        )
    }

    /// KBITE_GET resources: the resources and their projected file heads, two
    /// statements whatever the file count.
    private func assertKbiteResourceBudget() throws {
        let one = try makeDigestedKbite("kbud1")
        let two = try makeDigestedKbite("kbud2", files: ["notes.md", "other.md"])
        XCTAssertEqual(
            two.resources.first?.files.count,
            2,
            "the two-file fixture digested one file, so the comparison proves nothing"
        )

        let counts = try [one, two]
            .map { kbite -> Int in
                let kbiteUuid = kbite.kbite.uuid
                return try selectStatements { db in
                    let resources =
                        try KbiteResourceWithFiles.request()
                        .filter(Column("kbite_uuid") == kbiteUuid)
                        .order(Column("resource_name"))
                        .fetchAll(db)
                    XCTAssertFalse(
                        resources.isEmpty,
                        "the resource request matched no row: a prefetch GRDB skips is not a budget"
                    )
                }
                .count
            }
        assertBudget(
            "KBITE_GET resources",
            withOneChild: counts[0],
            withTwoChildren: counts[1],
            budget: 2
        )
    }

    /// SESSION_GET's session row: ONE request, two statements — the row and
    /// its activation registry. The plan's "2 → 1" counts requests.
    private func assertSessionBudget() throws {
        let fixture = try makeFixture("sbud")
        let sessionUuid = fixture.context.sessionUuid
        let first = try makePrompt(sessionUuid, "session budget one")
        let second = try makePrompt(sessionUuid, "session budget two")
        try claimActivation(sessionUuid: sessionUuid, promptUuid: first.uuid, clientKey: "t_c8_one")

        let read: (Database) throws -> Void = { db in
            _ = try SessionWithActivations.request().withUuid(sessionUuid).fetchOne(db)
        }
        let withOne = try selectStatements(read).count
        try claimActivation(sessionUuid: sessionUuid, promptUuid: second.uuid, clientKey: "t_c8_two")
        let withTwo = try selectStatements(read).count

        let activations = try env.readOnlyDatabase()
            .read { db in
                try SessionWithActivations.request()
                    .withUuid(sessionUuid)
                    .fetchOne(db)?
                    .activations.count ?? 0
            }
        XCTAssertEqual(
            activations,
            2,
            "the fixture holds \(activations) claims, so the second measurement is not a second child"
        )
        assertBudget(
            "SESSION_GET session row",
            withOneChild: withOne,
            withTwoChildren: withTwo,
            budget: 2
        )
    }

    /// One activation claim. The key is not a `claude:pid:start` triple, so
    /// the liveness sweep treats it as alive and leaves it in place.
    private func claimActivation(
        sessionUuid: String,
        promptUuid: String,
        clientKey: String
    ) throws {
        let session =
            try env.send(
                .sessionGet,
                SessionGetRequest(sessionUuid: sessionUuid),
                SessionGetResponse.self
            )
            .session
        _ = try env.send(
            .sessionUpdate,
            SessionUpdateRequest(
                sessionUuid: sessionUuid,
                expectedVersion: session.version,
                activePromptUuid: promptUuid,
                clientKey: clientKey
            ),
            SessionRow.self
        )
    }
}
