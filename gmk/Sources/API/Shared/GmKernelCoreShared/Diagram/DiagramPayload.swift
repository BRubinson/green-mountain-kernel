import Foundation

/// The load-bearing tagged union: ONE type drives the wire codec, store
/// persistence, containment validation, and the exhaustive-switch render
/// protocol.
///
/// No clear* flags — payload updates replace the subtype row wholesale. Encoding
/// is `{"kind": "<element_type raw>", "fields": {...}}`; `kind` and `fields`
/// are snake_case fixed points.
enum DiagramElementPayload: Codable, Hashable, Sendable {
    case drawingLayer(DrawingLayerPayload)
    case drawingStroke(DrawingStrokePayload)
    case drawingShape(DrawingShapePayload)
    case drawingText(DrawingTextPayload)
    case connector(ConnectorPayload)
    case umlNode(UmlNodePayload)
    case dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload)
    case dopeEntity(DopeEntityPayload)

    /// The tag IS the element type — payload/element_type agreement is
    /// definitional on add and validated on update (type morphing refused).
    var elementType: DiagramElementType {
        switch self {
        case .drawingLayer: return .drawingLayer
        case .drawingStroke: return .drawingStroke
        case .drawingShape: return .drawingShape
        case .drawingText: return .drawingText
        case .connector: return .connector
        case .umlNode: return .umlNode
        case .dopeScopePersistenceLayer: return .dopeScopePersistenceLayer
        case .dopeEntity: return .dopeEntity
        }
    }

    private enum CodingKeys: String, CodingKey { case kind, fields }

    /// Decodes a diagram element from its wire representation.
    ///
    /// The `kind` field determines which payload type to decode from `fields`.
    /// - Parameter decoder: The decoder to read the element from.
    /// - Throws: `DecodingError.dataCorruptedError` when `kind` is not a valid element type.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        guard let type = DiagramElementType(rawValue: kind) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind,
                in: c,
                debugDescription: "unknown diagram element payload kind '\(kind)'"
            )
        }
        switch type {
        case .drawingLayer:
            self = .drawingLayer(try c.decode(DrawingLayerPayload.self, forKey: .fields))
        case .drawingStroke:
            self = .drawingStroke(try c.decode(DrawingStrokePayload.self, forKey: .fields))
        case .drawingShape:
            self = .drawingShape(try c.decode(DrawingShapePayload.self, forKey: .fields))
        case .drawingText:
            self = .drawingText(try c.decode(DrawingTextPayload.self, forKey: .fields))
        case .connector:
            self = .connector(try c.decode(ConnectorPayload.self, forKey: .fields))
        case .umlNode:
            self = .umlNode(try c.decode(UmlNodePayload.self, forKey: .fields))
        case .dopeScopePersistenceLayer:
            self = .dopeScopePersistenceLayer(try c.decode(DopeScopePersistenceLayerPayload.self, forKey: .fields))
        case .dopeEntity:
            self = .dopeEntity(try c.decode(DopeEntityPayload.self, forKey: .fields))
        }
    }

    /// Encodes a diagram element to its wire representation.
    ///
    /// Writes the element's type to the `kind` field and its payload to `fields`.
    /// - Parameter encoder: The encoder to write the element to.
    /// - Throws: Any error from the encoder during the write.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(elementType.rawValue, forKey: .kind)
        switch self {
        case .drawingLayer(let p): try c.encode(p, forKey: .fields)
        case .drawingStroke(let p): try c.encode(p, forKey: .fields)
        case .drawingShape(let p): try c.encode(p, forKey: .fields)
        case .drawingText(let p): try c.encode(p, forKey: .fields)
        case .connector(let p): try c.encode(p, forKey: .fields)
        case .umlNode(let p): try c.encode(p, forKey: .fields)
        case .dopeScopePersistenceLayer(let p): try c.encode(p, forKey: .fields)
        case .dopeEntity(let p): try c.encode(p, forKey: .fields)
        }
    }
}

/// One stroke/shape vertex as it rides the wire — INSIDE the payload, so the
/// whole element is one value.
///
/// Persisted as full BaseEntity rows (user decision); written as whole-set
/// replacement, so vertex row uuids are not stable across edits (vertices are
/// not elements). Coordinates are ELEMENT-LOCAL (relative to the element's
/// center).
struct DiagramVertex: Codable, Hashable, Sendable {
    let x: Double
    let y: Double
    let pressure: Double?

    /// Creates a vertex at element-local coordinates with optional pressure.
    /// - Parameters:
    ///   - x: The x-coordinate relative to the element's center.
    ///   - y: The y-coordinate relative to the element's center.
    ///   - pressure: The pressure value for the vertex, or nil if not specified.
    init(x: Double, y: Double, pressure: Double? = nil) {
        self.x = x
        self.y = y
        self.pressure = pressure
    }

    private enum CodingKeys: String, CodingKey { case x, y, pressure }

    /// Decodes a vertex from its wire representation.
    /// - Parameter decoder: The decoder to read the vertex from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure)
    }
}

/// Missing keys decode to the schema defaults (a hand-authored --content
/// JSON should not have to spell every column), so each payload struct
/// hand-writes its decode with decodeIfPresent + default.

struct DrawingLayerPayload: Codable, Hashable, Sendable {
    let opacity: Double
    let visible: Bool
    let locked: Bool

    /// Creates a drawing layer with the specified properties.
    /// - Parameters:
    ///   - opacity: The layer opacity from 0 (transparent) to 1 (opaque); defaults to 1.
    ///   - visible: Whether the layer is visible; defaults to true.
    ///   - locked: Whether the layer is locked; defaults to false.
    init(opacity: Double = 1, visible: Bool = true, locked: Bool = false) {
        self.opacity = opacity
        self.visible = visible
        self.locked = locked
    }

    private enum CodingKeys: String, CodingKey { case opacity, visible, locked }

    /// Decodes a drawing layer from its wire representation.
    ///
    /// Missing keys are decoded to their schema defaults.
    /// - Parameter decoder: The decoder to read the layer from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

struct DrawingStrokePayload: Codable, Hashable, Sendable {
    let tool: DiagramStrokeTool
    let strokeColor: String
    let strokeWidth: Double
    let vertices: [DiagramVertex]

    /// Creates a drawing stroke with the specified properties.
    /// - Parameters:
    ///   - tool: The drawing tool; defaults to `.pencil`.
    ///   - strokeColor: The stroke color as a hex string; defaults to "#1a1a1a".
    ///   - strokeWidth: The stroke width in points; defaults to 2.
    ///   - vertices: The list of vertices; defaults to an empty list.
    init(
        tool: DiagramStrokeTool = .pencil,
        strokeColor: String = "#1a1a1a",
        strokeWidth: Double = 2,
        vertices: [DiagramVertex] = []
    ) {
        self.tool = tool
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.vertices = vertices
    }

    private enum CodingKeys: String, CodingKey {
        case tool, strokeColor, strokeWidth, vertices
    }

    /// Decodes a drawing stroke from its wire representation.
    ///
    /// Missing keys are decoded to their schema defaults.
    /// - Parameter decoder: The decoder to read the stroke from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decodeIfPresent(DiagramStrokeTool.self, forKey: .tool) ?? .pencil
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor) ?? "#1a1a1a"
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        vertices = try c.decodeIfPresent([DiagramVertex].self, forKey: .vertices) ?? []
    }
}

struct DrawingShapePayload: Codable, Hashable, Sendable {
    let shapeKind: DiagramShapeKind
    let strokeColor: String
    let strokeWidth: Double
    let fillColor: String?
    let cornerRadius: Double?
    let vertices: [DiagramVertex]

    /// Creates a drawing shape with the specified properties.
    /// - Parameters:
    ///   - shapeKind: The shape type.
    ///   - strokeColor: The stroke color as a hex string; defaults to "#1a1a1a".
    ///   - strokeWidth: The stroke width in points; defaults to 2.
    ///   - fillColor: The fill color as a hex string, or nil for no fill.
    ///   - cornerRadius: The corner radius in points, or nil for sharp corners.
    ///   - vertices: The list of vertices; defaults to an empty list.
    init(
        shapeKind: DiagramShapeKind,
        strokeColor: String = "#1a1a1a",
        strokeWidth: Double = 2,
        fillColor: String? = nil,
        cornerRadius: Double? = nil,
        vertices: [DiagramVertex] = []
    ) {
        self.shapeKind = shapeKind
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
        self.cornerRadius = cornerRadius
        self.vertices = vertices
    }

    private enum CodingKeys: String, CodingKey {
        case shapeKind, strokeColor, strokeWidth, fillColor, cornerRadius, vertices
    }

    /// Decodes a drawing shape from its wire representation.
    ///
    /// Missing keys are decoded to their schema defaults.
    /// - Parameter decoder: The decoder to read the shape from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shapeKind = try c.decode(DiagramShapeKind.self, forKey: .shapeKind)
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor) ?? "#1a1a1a"
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        fillColor = try c.decodeIfPresent(String.self, forKey: .fillColor)
        cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius)
        vertices = try c.decodeIfPresent([DiagramVertex].self, forKey: .vertices) ?? []
    }
}

/// A resizable markdown text box.
///
/// The only bounded element in the family that is NOT vertex-derived:
/// wrapping markdown needs a layout width up front, and deriving one from a
/// vertex extent is circular, since the wrapped height depends on the width.
/// The size lives on this subtype rather than on diagram_element, so no other
/// type is affected and the tree-composing `scale` still applies on top.
struct DrawingTextPayload: Codable, Hashable, Sendable {
    let markdown: String
    let width: Double
    let height: Double
    let fontSize: Double
    let textColor: String
    let backgroundColor: String?

    /// Creates a drawing text with the specified properties.
    /// - Parameters:
    ///   - markdown: The text content as markdown; defaults to an empty string.
    ///   - width: The width in points; defaults to 180.
    ///   - height: The height in points; defaults to 60.
    ///   - fontSize: The font size in points; defaults to 13.
    ///   - textColor: The text color as a hex string; defaults to "#1a1a1a".
    ///   - backgroundColor: The background color as a hex string, or nil for transparent.
    init(
        markdown: String = "",
        width: Double = 180,
        height: Double = 60,
        fontSize: Double = 13,
        textColor: String = "#1a1a1a",
        backgroundColor: String? = nil
    ) {
        self.markdown = markdown
        self.width = width
        self.height = height
        self.fontSize = fontSize
        self.textColor = textColor
        self.backgroundColor = backgroundColor
    }

    private enum CodingKeys: String, CodingKey {
        case markdown, width, height, fontSize, textColor, backgroundColor
    }

    /// Decodes a drawing text from its wire representation.
    ///
    /// Missing keys are decoded to their schema defaults.
    /// - Parameter decoder: The decoder to read the text from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        markdown = try c.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 180
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 60
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? 13
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor) ?? "#1a1a1a"
        backgroundColor = try c.decodeIfPresent(String.self, forKey: .backgroundColor)
    }
}

/// Connector line style.
enum DiagramConnectorLineStyle: String, Codable, Hashable, CaseIterable, Sendable {
    case solid
    case dashed
}

/// Connector head style.
///
/// Widened at wire v23 for UML semantics — `dot` IS the filled-circle variant
/// and stays legal forever (pre-v23 rows carry it); `circle` is the OPEN
/// (stroked) ring. New cases ride the v23 bump: the envelope handshake fences
/// them from pre-v23 decoders, for which an unknown rawValue is dataCorrupted,
/// not a skippable field.
enum DiagramConnectorHead: String, Codable, Hashable, CaseIterable, Sendable {
    case none
    case arrow
    case dot
    case openArrow = "open_arrow"
    case diamond
    case circle
    case cross
}

/// Connector routing style (v23).
///
/// Every case selects among geometry that already existed: `orthogonalStep`
/// is the router's polyline (the ONLY pre-v23 renderer, hence the decode
/// default), `straight` is the 2-point chord, `curved` is the legacy cubic
/// promoted from routing-declined fallback to a first-class choice.
/// DiagramEdgeRouter internals are not a function of this enum.
enum DiagramConnectorRouting: String, Codable, Hashable, CaseIterable, Sendable {
    case orthogonalStep = "orthogonal_step"
    case straight
    case curved
}

/// A hand-drawn connection from the element it is parented under to a PEER
/// of that element.
///
/// `targetElementUuid` is optional at every layer; its column uses `ON DELETE
/// SET NULL` to prevent CASCADE corruption. A deleted target becomes a ghost.
/// In batch operations, use `targetClientRef` instead; temp-id resolution is
/// a batch concern the payload is blind to.
struct ConnectorPayload: Codable, Hashable, Sendable {
    let targetElementUuid: String?
    let strokeColor: String
    let strokeWidth: Double
    let lineStyle: DiagramConnectorLineStyle
    let headKind: DiagramConnectorHead
    let routingKind: DiagramConnectorRouting
    let tailKind: DiagramConnectorHead
    let label: String

    /// Creates a connector line with the specified properties.
    /// - Parameters:
    ///   - targetElementUuid: The UUID of the target element, or nil for a ghost state.
    ///   - strokeColor: The stroke color as a hex string; defaults to "#1a1a1a".
    ///   - strokeWidth: The stroke width in points; defaults to 2.
    ///   - lineStyle: The line style; defaults to `.solid`.
    ///   - headKind: The line head style; defaults to `.arrow`.
    ///   - routingKind: The routing style; defaults to `.orthogonalStep`.
    ///   - tailKind: The line tail style; defaults to `.none`.
    ///   - label: The connector label text; defaults to an empty string.
    init(
        targetElementUuid: String? = nil,
        strokeColor: String = "#1a1a1a",
        strokeWidth: Double = 2,
        lineStyle: DiagramConnectorLineStyle = .solid,
        headKind: DiagramConnectorHead = .arrow,
        routingKind: DiagramConnectorRouting = .orthogonalStep,
        tailKind: DiagramConnectorHead = .none,
        label: String = ""
    ) {
        self.targetElementUuid = targetElementUuid
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.lineStyle = lineStyle
        self.headKind = headKind
        self.routingKind = routingKind
        self.tailKind = tailKind
        self.label = label
    }

    private enum CodingKeys: String, CodingKey {
        case targetElementUuid, strokeColor, strokeWidth, lineStyle, headKind,
            routingKind, tailKind, label
    }

    /// Decodes a connector from its wire representation.
    ///
    /// Missing keys are decoded to their schema defaults.
    /// - Parameter decoder: The decoder to read the connector from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetElementUuid = try c.decodeIfPresent(String.self, forKey: .targetElementUuid)
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor) ?? "#1a1a1a"
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        lineStyle =
            try c.decodeIfPresent(
                DiagramConnectorLineStyle.self,
                forKey: .lineStyle
            ) ?? .solid
        headKind =
            try c.decodeIfPresent(
                DiagramConnectorHead.self,
                forKey: .headKind
            ) ?? .arrow
        // Defaults reproduce the pre-v23 look: the router's polyline was the
        // only renderer, and no connector had a tail decoration.
        routingKind =
            try c.decodeIfPresent(
                DiagramConnectorRouting.self,
                forKey: .routingKind
            ) ?? .orthogonalStep
        tailKind =
            try c.decodeIfPresent(
                DiagramConnectorHead.self,
                forKey: .tailKind
            ) ?? .none
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// A UML node: one element type for the whole shape vocabulary (see
/// DiagramNodeKind), an explicit frame (the drawing_text doctrine — markdown
/// wrapping needs a known width, and the kit never measures text), and a
/// block-markdown interior rendered by the kit's own renderer so rendering
/// and every host draw the same thing.
///
/// Chrome fields are nil-means-theme-default so an unstyled node is legible
/// in both schemes.
struct UmlNodePayload: Codable, Hashable, Sendable {
    let nodeKind: DiagramNodeKind
    let width: Double
    let height: Double
    let markdown: String
    let fontSize: Double?
    let textColor: String?
    let strokeColor: String?
    let strokeWidth: Double?
    let fillColor: String?

    /// Creates a UML node with the specified properties.
    /// - Parameters:
    ///   - nodeKind: The node type.
    ///   - width: The node width in points; defaults to 160.
    ///   - height: The node height in points; defaults to 90.
    ///   - markdown: The node content as block markdown; defaults to an empty string.
    ///   - fontSize: The font size, or nil to use the theme default.
    ///   - textColor: The text color as a hex string, or nil for the theme default.
    ///   - strokeColor: The stroke color as a hex string, or nil for the theme default.
    ///   - strokeWidth: The stroke width in points, or nil for the theme default.
    ///   - fillColor: The fill color as a hex string, or nil for the theme default.
    init(
        nodeKind: DiagramNodeKind,
        width: Double = 160,
        height: Double = 90,
        markdown: String = "",
        fontSize: Double? = nil,
        textColor: String? = nil,
        strokeColor: String? = nil,
        strokeWidth: Double? = nil,
        fillColor: String? = nil
    ) {
        self.nodeKind = nodeKind
        self.width = width
        self.height = height
        self.markdown = markdown
        self.fontSize = fontSize
        self.textColor = textColor
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.fillColor = fillColor
    }

    private enum CodingKeys: String, CodingKey {
        case nodeKind, width, height, markdown, fontSize, textColor,
            strokeColor, strokeWidth, fillColor
    }

    /// Decodes a UML node from its wire representation.
    ///
    /// Missing keys are decoded to their schema defaults or nil for theme defaults.
    /// - Parameter decoder: The decoder to read the node from.
    /// - Throws: Any error from the decoder during the read.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        nodeKind = try c.decode(DiagramNodeKind.self, forKey: .nodeKind)
        width = try c.decodeIfPresent(Double.self, forKey: .width) ?? 160
        height = try c.decodeIfPresent(Double.self, forKey: .height) ?? 90
        markdown = try c.decodeIfPresent(String.self, forKey: .markdown) ?? ""
        fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize)
        textColor = try c.decodeIfPresent(String.self, forKey: .textColor)
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor)
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth)
        fillColor = try c.decodeIfPresent(String.self, forKey: .fillColor)
    }
}

/// fk-by-code binding to a dope scope.
///
/// Resolution runs at READ time through the diagram row's own session/prompt
/// context (the dopeGet ladder), never at write time — a dangling code is a
/// legal, renderable ghost state.
struct DopeScopePersistenceLayerPayload: Codable, Hashable, Sendable {
    let dopeScopeCode: String

    /// Creates a dope scope persistence layer binding.
    /// - Parameter dopeScopeCode: The code identifying the dope scope.
    init(dopeScopeCode: String) {
        self.dopeScopeCode = dopeScopeCode
    }
}

/// fk-by-code binding to a dope domain entity — 2-segment `domain.entity`
/// (DopeCode.parseEntityRef-validated on write; existence NOT checked).
struct DopeEntityPayload: Codable, Hashable, Sendable {
    let entityCode: String

    /// Creates a dope entity binding.
    /// - Parameter entityCode: The code identifying the dope entity in the format `domain.entity`.
    init(entityCode: String) {
        self.entityCode = entityCode
    }
}

/// Tri-state field write for nullable columns: absent = leave alone,
/// `{"op": "set", "value": …}` = write, `{"op": "clear"}` = NULL.
///
/// The typed replacement for dope's clear* flag pairs; one use site this pass
/// (diagram.gmcc_diagram_path), available to future surfaces.
enum FieldPatch<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    case set(T)
    case clear

    private enum CodingKeys: String, CodingKey { case op, value }

    /// Decodes a field patch from its wire representation.
    ///
    /// The `op` field determines whether to set a new value or clear the field to NULL.
    /// - Parameter decoder: The decoder to read the field patch from.
    /// - Throws: `DecodingError.dataCorruptedError` when `op` is not "set" or "clear".
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(String.self, forKey: .op)
        switch op {
        case "set":
            self = .set(try c.decode(T.self, forKey: .value))
        case "clear":
            self = .clear
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .op,
                in: c,
                debugDescription: "unknown field patch op '\(op)'"
            )
        }
    }

    /// Encodes a field patch to its wire representation.
    ///
    /// Writes "set" with the value, or "clear" without a value.
    /// - Parameter encoder: The encoder to write the field patch to.
    /// - Throws: Any error from the encoder during the write.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .set(let value):
            try c.encode("set", forKey: .op)
            try c.encode(value, forKey: .value)
        case .clear:
            try c.encode("clear", forKey: .op)
        }
    }
}
