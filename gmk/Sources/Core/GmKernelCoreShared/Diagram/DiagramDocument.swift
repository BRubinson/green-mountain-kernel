import Foundation

/// The committed-file form of one PUBLIC diagram at
/// `{instance_root}/.gmcc/diagrams/{code}.diagram.doped.json`.
///
/// Uuid-free by construction: elements identified by CODE; containment is JSON
/// nesting; connector targets are root→target slash-joined CODE PATHS (codes
/// sibling-unique only). Unresolvable paths degrade to ghost (nil target).
/// `version` = diagram revision; TIER not persisted (write gating keeps
/// constant).
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

        /// Creates a diagram element document.
        ///
        /// - Parameters:
        ///   - code: The element's unique code.
        ///   - name: The element's display name.
        ///   - description: The element's description.
        ///   - sortOrder: The sort order among siblings.
        ///   - centerX: The X coordinate of the element's center.
        ///   - centerY: The Y coordinate of the element's center.
        ///   - elementZ: The Z-order (depth) of the element.
        ///   - scale: The scale factor of the element.
        ///   - payload: The element's type-specific payload.
        ///   - targetCodePath: For connectors, the code path to the target element.
        ///   - children: The child elements; empty by default.
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

        /// Decodes an element document from JSON.
        ///
        /// - Parameter decoder: The decoder to read from.
        /// - Throws: Any decoding error.
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

    /// Creates a diagram document.
    ///
    /// - Parameters:
    ///   - version: The diagram's revision at write time.
    ///   - code: The diagram's code.
    ///   - name: The diagram's display name.
    ///   - description: The diagram's description.
    ///   - dopeScopeCode: The dope scope code bound to the diagram; nil if none.
    ///   - elements: The root-level diagram elements.
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

    /// Builds the file name for a diagram document.
    ///
    /// - Parameter code: The diagram code.
    /// - Returns: The file name with code and standard suffix.
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

    /// Encodes a diagram document to JSON data.
    ///
    /// - Parameter document: The diagram document to encode.
    /// - Returns: The encoded JSON data with a trailing newline.
    /// - Throws: Any encoding error.
    static func encode(_ document: DiagramDocument) throws -> Data {
        var data = try encoder.encode(document)
        data.append(0x0A)
        return data
    }

    /// Decodes a diagram document from JSON data.
    ///
    /// - Parameter data: The JSON data to decode.
    /// - Returns: The decoded diagram document.
    /// - Throws: Any decoding error.
    static func decode(_ data: Data) throws -> DiagramDocument {
        try decoder.decode(DiagramDocument.self, from: data)
    }

    /// Extracts the revision stamp from encoded diagram data.
    ///
    /// Used by the write-repo files-ahead gate; mirrors
    /// `DopeRepoSandbox.peekRevision`.
    ///
    /// - Parameter data: The encoded diagram data.
    /// - Returns: The diagram revision, or nil if decoding fails.
    static func peekVersion(_ data: Data) -> Int64? {
        (try? decode(data))?.version
    }

    // MARK: - Projection (db tree → document)

    /// Converts a diagram tree to a document form suitable for serialization.
    ///
    /// A pure operation with no database or filesystem access. Connector targets
    /// are translated to code paths from the tree's UUID index; unreachable
    /// targets serialize as nil.
    ///
    /// - Parameters:
    ///   - tree: The diagram tree to convert.
    ///   - dopeScopeCode: The dope scope code to associate; nil if not bound.
    /// - Returns: The diagram document.
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
