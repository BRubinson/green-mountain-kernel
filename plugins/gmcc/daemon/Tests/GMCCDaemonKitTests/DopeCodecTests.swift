import XCTest
@testable import GMCCDaemonKit

final class DopeCodecTests: XCTestCase {

    // MARK: - Fixture

    private func makeTree() -> DopeScopeTree {
        func identity(_ n: Int) -> DopeNodeIdentity {
            DopeNodeIdentity(uuid: "uuid-\(n)", version: Int64(n),
                             createdAt: "2026-09-05T00:00:00Z",
                             updatedAt: "2026-09-05T00:00:00Z")
        }
        let statusEnum = DopeEnumNode(
            identity: identity(10),
            body: DopeEnumBody(code: "status", name: "Status", description: "Lifecycle",
                               sortOrder: 0, repoRepresentativeFile: "Sources/Status.swift"),
            options: [
                DopeOptionNode(identity: identity(11),
                               body: DopeOptionBody(code: "active", name: "Active",
                                                    description: "", sortOrder: 0)),
                DopeOptionNode(identity: identity(12),
                               body: DopeOptionBody(code: "done", name: "Done",
                                                    description: "", sortOrder: 1)),
            ])
        let user = DopeEntityNode(
            identity: identity(20),
            body: DopeEntityBody(code: "user", name: "User", entityType: "MODEL",
                                 description: "", sortOrder: 0,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [
                DopePropertyNode(identity: identity(21),
                                 body: DopePropertyBody(
                                    code: "id", name: "Id", description: "", sortOrder: 0,
                                    dataType: "uuid", nullable: false, isUnique: true,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: nil, relationshipTargetRef: nil,
                                    baseOriginRef: nil)),
                DopePropertyNode(identity: identity(22),
                                 body: DopePropertyBody(
                                    code: "state", name: "State", description: "", sortOrder: 1,
                                    dataType: "enum", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: "core.enums.status", relationshipTargetRef: nil,
                                    baseOriginRef: nil)),
            ])
        let post = DopeEntityNode(
            identity: identity(30),
            body: DopeEntityBody(code: "post", name: "Post", entityType: "MODEL",
                                 description: "", sortOrder: 1,
                                 repoRepresentativeFile: nil,
                                 baseComposableRef: "core.base_entity"),
            properties: [
                DopePropertyNode(identity: identity(31),
                                 body: DopePropertyBody(
                                    code: "author", name: "Author", description: "", sortOrder: 0,
                                    dataType: "relationship", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: nil, relationshipTargetRef: "core.user.id",
                                    baseOriginRef: nil)),
                DopePropertyNode(identity: identity(32),
                                 body: DopePropertyBody(
                                    code: "title", name: "Title", description: "", sortOrder: 1,
                                    dataType: "text", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: 200,
                                    enumRef: nil, relationshipTargetRef: nil,
                                    baseOriginRef: nil)),
                // Materialized from the base — covers base_origin_ref in the
                // round-trip / determinism / no-uuid tests.
                DopePropertyNode(identity: identity(33),
                                 body: DopePropertyBody(
                                    code: "created_at", name: "Created At", description: "",
                                    sortOrder: 2,
                                    dataType: "datetime", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: nil, relationshipTargetRef: nil,
                                    baseOriginRef: "core.base_entity.created_at")),
            ])
        let baseEntity = DopeEntityNode(
            identity: identity(40),
            body: DopeEntityBody(code: "base_entity", name: "Base Entity",
                                 entityType: "BASE_COMPOSABLE",
                                 description: "", sortOrder: 2,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [
                DopePropertyNode(identity: identity(41),
                                 body: DopePropertyBody(
                                    code: "created_at", name: "Created At", description: "",
                                    sortOrder: 0,
                                    dataType: "datetime", nullable: false, isUnique: false,
                                    autoIncrement: nil, textCharLimit: nil,
                                    enumRef: nil, relationshipTargetRef: nil,
                                    baseOriginRef: nil)),
            ])
        let core = DopePersistenceNode(
            identity: identity(2),
            body: DopePersistenceBody(code: "core", name: "Core", description: "", sortOrder: 0),
            entities: [user, post, baseEntity], enums: [statusEnum])
        return DopeScopeTree(
            identity: identity(1),
            body: DopeScopeBody(code: "gmcc", name: "GMCC", description: "The model"),
            sessionUuid: "sess-1", promptUuid: nil,
            scopeType: "SESSION_BASE", revision: 3, domains: [core])
    }

    // MARK: - Parity + determinism

    func testDocumentRoundTripIsIdentity() throws {
        let bundle = DopeProjection.documents(from: makeTree())
        let mainData = try DopeDocumentCodec.encoder.encode(bundle.main)
        let decodedMain = try DopeDocumentCodec.decoder.decode(DopeScopeDocument.self, from: mainData)
        XCTAssertEqual(decodedMain, bundle.main)

        for file in bundle.domainFiles {
            let data = try DopeDocumentCodec.encoder.encode(file)
            let decoded = try DopeDocumentCodec.decoder.decode(DopePersistenceFileDocument.self, from: data)
            XCTAssertEqual(decoded, file)
        }
    }

    func testEncodingIsByteDeterministic() throws {
        let bundle = DopeProjection.documents(from: makeTree())
        let a = try DopeDocumentCodec.encoder.encode(bundle.domainFiles[0])
        let b = try DopeDocumentCodec.encoder.encode(bundle.domainFiles[0])
        XCTAssertEqual(a, b)
    }

    /// The uuid ban is structural: no document type has anywhere to put one.
    /// Belt-and-braces: the encoded bytes must not contain the fixture uuids
    /// or a "uuid" key at all.
    func testNoUuidAppearsInAnyDocument() throws {
        let bundle = DopeProjection.documents(from: makeTree())
        var blobs = [try DopeDocumentCodec.encoder.encode(bundle.main)]
        blobs += try bundle.domainFiles.map { try DopeDocumentCodec.encoder.encode($0) }
        for blob in blobs {
            let text = String(decoding: blob, as: UTF8.self)
            XCTAssertFalse(text.contains("uuid-"), "row uuid leaked into a document")
            // Key position only — `"data_type" : "uuid"` is a legal VALUE.
            XCTAssertFalse(text.contains("\"uuid\" :"), "a uuid key leaked into a document")
        }
    }

    /// Wire node flattening: identity + body share one flat JSON object and
    /// the snake_case round trip preserves everything (the CodingKeys
    /// single-word constraint this file exists to guard).
    func testWireTreeRoundTripUnderWireCodec() throws {
        let tree = makeTree()
        let data = try WireCodec.encoder.encode(tree)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"sort_order\""), "snake_case strategy not applied")
        XCTAssertFalse(text.contains("\"body\""), "body wrapper leaked — flattening broken")
        XCTAssertFalse(text.contains("\"identity\""), "identity wrapper leaked — flattening broken")
        let decoded = try WireCodec.decoder.decode(DopeScopeTree.self, from: data)
        XCTAssertEqual(decoded, tree)
    }

    // MARK: - Validator

    func testValidatorAcceptsTheFixture() throws {
        try DopeValidator.validate(makeTree())
    }

    func testValidatorCollectsEveryError() throws {
        var bundle = DopeProjection.documents(from: makeTree())
        // Break several things at once: bad code, dangling enum ref, version
        // mismatch, wrong map path.
        let badProperty = DopePropertyDocument(body: DopePropertyBody(
            code: "BadCode", name: "x", description: "", sortOrder: 0,
            dataType: "enum", nullable: true, isUnique: false,
            autoIncrement: nil, textCharLimit: nil,
            enumRef: "core.enums.missing", relationshipTargetRef: nil, baseOriginRef: nil))
        let entity = DopeEntityDocument(
            body: DopeEntityBody(code: "extra", name: "Extra", entityType: "MODEL",
                                 description: "", sortOrder: 9,
                                 repoRepresentativeFile: nil, baseComposableRef: nil),
            properties: [badProperty])
        let broken = DopePersistenceFileDocument(
            version: bundle.main.version + 1,   // mismatch
            body: bundle.domainFiles[0].body,
            entities: bundle.domainFiles[0].entities + [entity],
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(
            main: DopeScopeDocument(
                version: bundle.main.version,
                scope: bundle.main.scope,
                persistence: ["core": "../escape.doped.json"]),
            domainFiles: [broken])

        do {
            try DopeValidator.validate(bundle)
            XCTFail("expected BundleError")
        } catch let error as DopeValidator.BundleError {
            XCTAssertGreaterThanOrEqual(error.errors.count, 4,
                                        "expected aggregated errors, got: \(error.errors)")
        }
    }

    func testValidatorRejectsReservedEntityCodeAndChainRefs() throws {
        let tree = makeTree()
        var bundle = DopeProjection.documents(from: tree)
        let enumsEntity = DopeEntityDocument(
            body: DopeEntityBody(code: "enums", name: "Enums", entityType: "MODEL",
                                 description: "", sortOrder: 5, repoRepresentativeFile: nil,
                                 baseComposableRef: nil),
            properties: [])
        let chain = DopePropertyDocument(body: DopePropertyBody(
            code: "chain", name: "Chain", description: "", sortOrder: 7,
            dataType: "relationship", nullable: true, isUnique: false,
            autoIncrement: nil, textCharLimit: nil,
            enumRef: nil, relationshipTargetRef: "core.post.author", baseOriginRef: nil))   // author is a relationship
        let user = bundle.domainFiles[0].entities[0]
        let patchedUser = DopeEntityDocument(body: user.body,
                                             properties: user.properties + [chain])
        let file = DopePersistenceFileDocument(
            version: bundle.main.version,
            body: bundle.domainFiles[0].body,
            entities: [patchedUser, bundle.domainFiles[0].entities[1], enumsEntity],
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(main: bundle.main, domainFiles: [file])

        do {
            try DopeValidator.validate(bundle)
            XCTFail("expected BundleError")
        } catch let error as DopeValidator.BundleError {
            XCTAssertTrue(error.errors.contains { $0.contains("reserved") },
                          "missing reserved-code error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("itself a relationship") },
                          "missing chain-ref error: \(error.errors)")
        }
    }

    func testCodeValidation() throws {
        try DopeCode.validateCode("valid_code_1", field: "code")
        for bad in ["", "Upper", "1lead", "trail_", "dou__ble", "has-dash", "has.dot",
                    String(repeating: "a", count: 65)] {
            XCTAssertThrowsError(try DopeCode.validateCode(bad, field: "code"),
                                 "'\(bad)' should be rejected")
        }
    }

    func testRefParsing() throws {
        XCTAssertEqual(try DopeCode.parseRef("core.user.id", field: "ref"),
                       .property(domain: "core", entity: "user", property: "id"))
        XCTAssertEqual(try DopeCode.parseRef("core.enums.status", field: "ref"),
                       .enumType(domain: "core", enumCode: "status"))
        for bad in ["core.user", "core.user.id.extra", "core..id", "Core.user.id"] {
            XCTAssertThrowsError(try DopeCode.parseRef(bad, field: "ref"))
        }
    }

    func testEntityRefParsing() throws {
        XCTAssertEqual(try DopeCode.parseEntityRef("core.user", field: "ref"),
                       .entity(domain: "core", entity: "user"))
        for bad in ["core", "core.user.id", "core.", "Core.user", "core.enums"] {
            XCTAssertThrowsError(try DopeCode.parseEntityRef(bad, field: "ref"),
                                 "'\(bad)' should be rejected")
        }
        // The sibling-function decision preserves the strict 3-segment guard:
        // a truncated property ref must stay an error in parseRef.
        XCTAssertThrowsError(try DopeCode.parseRef("core.user", field: "ref"))
    }

    // MARK: - Base composable validation

    private func entityDoc(
        _ code: String, type: String = "MODEL", sortOrder: Int = 0,
        base: String? = nil
    ) -> DopeEntityDocument {
        DopeEntityDocument(
            body: DopeEntityBody(code: code, name: code, entityType: type,
                                 description: "", sortOrder: sortOrder,
                                 repoRepresentativeFile: nil, baseComposableRef: base),
            properties: [])
    }

    func testValidatorRejectsBadBaseRefs() throws {
        var bundle = DopeProjection.documents(from: makeTree())
        let broken = [
            entityDoc("dangling", sortOrder: 10, base: "core.missing"),        // unresolvable
            entityDoc("wrong_target", sortOrder: 11, base: "core.user"),       // targets a MODEL
            entityDoc("selfie", sortOrder: 12, base: "core.selfie"),           // self-ref
            entityDoc("threeseg", sortOrder: 13, base: "core.user.id"),        // 3-segment
            entityDoc("cyc_a", type: "BASE_COMPOSABLE", sortOrder: 14, base: "core.cyc_b"),
            entityDoc("cyc_b", type: "BASE_COMPOSABLE", sortOrder: 15, base: "core.cyc_a"),
        ]
        let file = DopePersistenceFileDocument(
            version: bundle.main.version,
            body: bundle.domainFiles[0].body,
            entities: bundle.domainFiles[0].entities + broken,
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(main: bundle.main, domainFiles: [file])

        do {
            try DopeValidator.validate(bundle)
            XCTFail("expected BundleError")
        } catch let error as DopeValidator.BundleError {
            XCTAssertTrue(error.errors.contains { $0.contains("does not resolve") },
                          "missing unresolvable-ref error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("only a BASE_COMPOSABLE") },
                          "missing target-type error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("composes itself") },
                          "missing self-ref error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("must be domain.entity") },
                          "missing 2-segment parse error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("base_composable cycle") },
                          "missing cycle error: \(error.errors)")
        }
    }

    private func propertyDoc(
        _ code: String, dataType: String = "text", origin: String? = nil
    ) -> DopePropertyDocument {
        DopePropertyDocument(body: DopePropertyBody(
            code: code, name: code, description: "", sortOrder: 0,
            dataType: dataType, nullable: true, isUnique: false,
            autoIncrement: nil, textCharLimit: nil,
            enumRef: nil, relationshipTargetRef: nil, baseOriginRef: origin))
    }

    func testValidatorRejectsBadBaseOriginRefs() throws {
        var bundle = DopeProjection.documents(from: makeTree())
        let cases = [
            DopeEntityDocument(
                body: DopeEntityBody(code: "no_chain", name: "x", entityType: "MODEL",
                                     description: "", sortOrder: 20,
                                     repoRepresentativeFile: nil, baseComposableRef: nil),
                // Entity composes nothing → chain-reach failure.
                properties: [propertyDoc("a", dataType: "datetime",
                                         origin: "core.base_entity.created_at")]),
            DopeEntityDocument(
                body: DopeEntityBody(code: "bad_refs", name: "x", entityType: "MODEL",
                                     description: "", sortOrder: 21,
                                     repoRepresentativeFile: nil,
                                     baseComposableRef: "core.base_entity"),
                properties: [
                    propertyDoc("b", origin: "core.base_entity"),               // 2-segment
                    propertyDoc("c", origin: "core.base_entity.missing"),       // unresolvable
                    propertyDoc("d", origin: "core.user.id"),                   // origin on a MODEL
                    propertyDoc("e", origin: "core.base_entity.created_at"),    // data_type mismatch (text vs datetime)
                ]),
        ]
        let file = DopePersistenceFileDocument(
            version: bundle.main.version,
            body: bundle.domainFiles[0].body,
            entities: bundle.domainFiles[0].entities + cases,
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(main: bundle.main, domainFiles: [file])

        do {
            try DopeValidator.validate(bundle)
            XCTFail("expected BundleError")
        } catch let error as DopeValidator.BundleError {
            XCTAssertTrue(error.errors.contains { $0.contains("does not compose") },
                          "missing chain-reach error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("must be domain.entity.property") },
                          "missing parse error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("does not resolve") },
                          "missing unresolvable error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("not a BASE_COMPOSABLE") },
                          "missing origin-type error: \(error.errors)")
            XCTAssertTrue(error.errors.contains { $0.contains("differs from the origin's") },
                          "missing data_type error: \(error.errors)")
        }
    }

    func testValidatorAcceptsBaseOriginThroughAChain() throws {
        var bundle = DopeProjection.documents(from: makeTree())
        let chain = [
            entityDoc("m_one", type: "BASE_COMPOSABLE", sortOrder: 20, base: "core.m_two"),
            DopeEntityDocument(
                body: DopeEntityBody(code: "m_two", name: "m_two",
                                     entityType: "BASE_COMPOSABLE",
                                     description: "", sortOrder: 21,
                                     repoRepresentativeFile: nil, baseComposableRef: nil),
                properties: [propertyDoc("stamp", dataType: "datetime")]),
            DopeEntityDocument(
                body: DopeEntityBody(code: "leaf", name: "leaf", entityType: "MODEL",
                                     description: "", sortOrder: 22,
                                     repoRepresentativeFile: nil,
                                     baseComposableRef: "core.m_one"),
                // Reaches m_two through m_one.
                properties: [propertyDoc("stamp", dataType: "datetime",
                                         origin: "core.m_two.stamp")]),
        ]
        let file = DopePersistenceFileDocument(
            version: bundle.main.version,
            body: bundle.domainFiles[0].body,
            entities: bundle.domainFiles[0].entities + chain,
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(main: bundle.main, domainFiles: [file])
        try DopeValidator.validate(bundle)
    }

    func testValidatorAcceptsBaseChain() throws {
        var bundle = DopeProjection.documents(from: makeTree())
        let chain = [
            entityDoc("b_one", type: "BASE_COMPOSABLE", sortOrder: 10, base: "core.b_two"),
            entityDoc("b_two", type: "BASE_COMPOSABLE", sortOrder: 11, base: "core.b_three"),
            entityDoc("b_three", type: "BASE_COMPOSABLE", sortOrder: 12),
        ]
        let file = DopePersistenceFileDocument(
            version: bundle.main.version,
            body: bundle.domainFiles[0].body,
            entities: bundle.domainFiles[0].entities + chain,
            enums: bundle.domainFiles[0].enums)
        bundle = DopeDocumentBundle(main: bundle.main, domainFiles: [file])
        try DopeValidator.validate(bundle)
    }
}
