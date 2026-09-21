import Foundation

/// The committed-file form of one PUBLIC diagram —
/// `{instance_root}/.gmcc/diagrams/{code}.diagram.doped.json`.
/// Uuid-free BY CONSTRUCTION: elements are identified by CODE, containment is
/// JSON nesting, and a connector's target is a root→target slash-joined CODE
/// PATH, since element codes are only sibling-unique. An unresolvable path
/// degrades to a ghost (nil target), never an error. `version` is the
/// diagram's revision; the TIER is not persisted, because write gating
/// already makes it constant.
struct DiagramDocument: Codable, Hashable, Sendable {
    struct ElementDoc: Codable, Hashable, Sendable {
        let code: String
        let name: String
        let description: String
        let sortOrder: Int
        let centerX: Double
        let centerY: Double
        let elementZ: Double
        let scale: Double
        /// The wire payload, with a connector's `targetElementUuid` nil'd —
        /// the uuid never reaches the file; `targetCodePath` replaces it.
        let payload: DiagramElementPayload
        let targetCodePath: String?
        let children: [ElementDoc]

        init(
            code: String,
            name: String,
            description: String,
            sortOrder: Int,
            centerX: Double,
            centerY: Double,
            elementZ: Double,
            scale: Double,
            payload: DiagramElementPayload,
            targetCodePath: String? = nil,
            children: [ElementDoc] = []
        ) {
            self.code = code
            self.name = name
            self.description = description
            self.sortOrder = sortOrder
            self.centerX = centerX
            self.centerY = centerY
            self.elementZ = elementZ
            self.scale = scale
            self.payload = payload
            self.targetCodePath = targetCodePath
            self.children = children
        }

        private enum CodingKeys: String, CodingKey {
            case code, name, description, sortOrder, centerX, centerY,
                elementZ, scale, payload, targetCodePath, children
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            code = try c.decode(String.self, forKey: .code)
            name = try c.decodeIfPresent(String.self, forKey: .name) ?? code
            description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
            sortOrder = try c.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
            centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? 0
            centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? 0
            elementZ = try c.decodeIfPresent(Double.self, forKey: .elementZ) ?? 0
            scale = try c.decodeIfPresent(Double.self, forKey: .scale) ?? 1
            payload = try c.decode(DiagramElementPayload.self, forKey: .payload)
            targetCodePath = try c.decodeIfPresent(String.self, forKey: .targetCodePath)
            children = try c.decodeIfPresent([ElementDoc].self, forKey: .children) ?? []
        }
    }

    /// The diagram's revision at write time — the ingest gate's left side.
    let version: Int64
    let code: String
    let name: String
    let description: String
    let dopeScopeCode: String?
    let elements: [ElementDoc]

    init(
        version: Int64,
        code: String,
        name: String,
        description: String,
        dopeScopeCode: String?,
        elements: [ElementDoc]
    ) {
        self.version = version
        self.code = code
        self.name = name
        self.description = description
        self.dopeScopeCode = dopeScopeCode
        self.elements = elements
    }
}

enum DiagramDocumentCodec {
    static let fileSuffix = ".diagram.doped.json"

    static func fileName(code: String) -> String {
        "\(code)\(fileSuffix)"
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    static func encode(_ document: DiagramDocument) throws -> Data {
        var data = try encoder.encode(document)
        data.append(0x0A)
        return data
    }

    static func decode(_ data: Data) throws -> DiagramDocument {
        try decoder.decode(DiagramDocument.self, from: data)
    }

    /// Just the `version` stamp, for the write-repo files-ahead gate —
    /// mirrors DopeRepoSandbox.peekRevision.
    static func peekVersion(_ data: Data) -> Int64? {
        (try? decode(data))?.version
    }

    // MARK: - Projection (db tree → document)

    /// Pure: no db, no fs. Connector target uuids are translated to code
    /// paths against the tree's own uuid index; a target uuid that no
    /// longer resolves inside the tree serializes as no target (the ghost
    /// travels as a ghost).
    static func document(
        from tree: DiagramTree,
        dopeScopeCode: String?
    ) -> DiagramDocument {
        var pathByUuid: [String: String] = [:]
        func index(_ node: DiagramElementNode, prefix: String) {
            let path = prefix.isEmpty ? node.base.code : "\(prefix)/\(node.base.code)"
            pathByUuid[node.identity.uuid] = path
            for child in node.children { index(child, prefix: path) }
        }
        for element in tree.elements { index(element, prefix: "") }

        func doc(_ node: DiagramElementNode) -> ElementDocBuild {
            var payload = node.payload
            var targetCodePath: String?
            if case .connector(let p) = payload {
                targetCodePath = p.targetElementUuid.flatMap { pathByUuid[$0] }
                payload = .connector(
                    ConnectorPayload(
                        targetElementUuid: nil,
                        strokeColor: p.strokeColor,
                        strokeWidth: p.strokeWidth,
                        lineStyle: p.lineStyle,
                        headKind: p.headKind,
                        routingKind: p.routingKind,
                        tailKind: p.tailKind,
                        label: p.label
                    )
                )
            }
            return ElementDocBuild(
                doc: DiagramDocument.ElementDoc(
                    code: node.base.code,
                    name: node.base.name,
                    description: node.base.description,
                    sortOrder: node.base.sortOrder,
                    centerX: node.base.centerX,
                    centerY: node.base.centerY,
                    elementZ: node.base.elementZ,
                    scale: node.base.scale,
                    payload: payload,
                    targetCodePath: targetCodePath,
                    children: node.children.map { doc($0).doc }
                )
            )
        }

        return DiagramDocument(
            version: tree.revision,
            code: tree.code,
            name: tree.name,
            description: tree.description,
            dopeScopeCode: dopeScopeCode,
            elements: tree.elements.map { doc($0).doc }
        )
    }

    private struct ElementDocBuild {
        let doc: DiagramDocument.ElementDoc
    }
}
