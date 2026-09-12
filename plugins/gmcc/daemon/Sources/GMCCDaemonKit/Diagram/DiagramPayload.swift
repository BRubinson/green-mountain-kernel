import Foundation

/// The load-bearing tagged union: ONE type drives the wire codec, store
/// persistence, containment validation, and the exhaustive-switch render
/// protocol. `DopeNodeFields`' flat-optional union is deliberately NOT
/// extended, and no clear* flags exist anywhere on this surface — an update
/// carrying a payload REPLACES the subtype row (and vertex set) wholesale,
/// so the typed-nil SET-dictionary idiom (the 6ffbda9 bug class) is
/// structurally impossible here.
///
/// Encoding: `{"kind": "<element_type raw>", "fields": {...}}`. `kind` and
/// `fields` are single-word keys — fixed points of the snake_case strategies
/// (the Envelope.swift hazard); each case struct's own camelCase keys go
/// through the shared strategy normally.
public enum DiagramElementPayload: Codable, Hashable, Sendable {
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
    public var elementType: DiagramElementType {
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(String.self, forKey: .kind)
        guard let type = DiagramElementType(rawValue: kind) else {
            throw DecodingError.dataCorruptedError(
                forKey: .kind, in: c,
                debugDescription: "unknown diagram element payload kind '\(kind)'")
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

    public func encode(to encoder: Encoder) throws {
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
/// whole element is one value. Persisted as full BaseEntity rows (user
/// decision); written as whole-set replacement, so vertex row uuids are not
/// stable across edits (vertices are not elements).
/// Coordinates are ELEMENT-LOCAL (relative to the element's center).
public struct DiagramVertex: Codable, Hashable, Sendable {
    public let x: Double
    public let y: Double
    public let pressure: Double?

    public init(x: Double, y: Double, pressure: Double? = nil) {
        self.x = x
        self.y = y
        self.pressure = pressure
    }

    private enum CodingKeys: String, CodingKey { case x, y, pressure }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        x = try c.decode(Double.self, forKey: .x)
        y = try c.decode(Double.self, forKey: .y)
        pressure = try c.decodeIfPresent(Double.self, forKey: .pressure)
    }
}

/// Missing keys decode to the schema defaults (a hand-authored --content
/// JSON should not have to spell every column), so each payload struct
/// hand-writes its decode with decodeIfPresent + default.

public struct DrawingLayerPayload: Codable, Hashable, Sendable {
    public let opacity: Double
    public let visible: Bool
    public let locked: Bool

    public init(opacity: Double = 1, visible: Bool = true, locked: Bool = false) {
        self.opacity = opacity
        self.visible = visible
        self.locked = locked
    }

    private enum CodingKeys: String, CodingKey { case opacity, visible, locked }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? 1
        visible = try c.decodeIfPresent(Bool.self, forKey: .visible) ?? true
        locked = try c.decodeIfPresent(Bool.self, forKey: .locked) ?? false
    }
}

public struct DrawingStrokePayload: Codable, Hashable, Sendable {
    public let tool: DiagramStrokeTool
    public let strokeColor: String
    public let strokeWidth: Double
    public let vertices: [DiagramVertex]

    public init(
        tool: DiagramStrokeTool = .pencil, strokeColor: String = "#1a1a1a",
        strokeWidth: Double = 2, vertices: [DiagramVertex] = []
    ) {
        self.tool = tool
        self.strokeColor = strokeColor
        self.strokeWidth = strokeWidth
        self.vertices = vertices
    }

    private enum CodingKeys: String, CodingKey {
        case tool, strokeColor, strokeWidth, vertices
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decodeIfPresent(DiagramStrokeTool.self, forKey: .tool) ?? .pencil
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor) ?? "#1a1a1a"
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        vertices = try c.decodeIfPresent([DiagramVertex].self, forKey: .vertices) ?? []
    }
}

public struct DrawingShapePayload: Codable, Hashable, Sendable {
    public let shapeKind: DiagramShapeKind
    public let strokeColor: String
    public let strokeWidth: Double
    public let fillColor: String?
    public let cornerRadius: Double?
    public let vertices: [DiagramVertex]

    public init(
        shapeKind: DiagramShapeKind, strokeColor: String = "#1a1a1a",
        strokeWidth: Double = 2, fillColor: String? = nil,
        cornerRadius: Double? = nil, vertices: [DiagramVertex] = []
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

    public init(from decoder: Decoder) throws {
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
/// The only bounded element in the family that is NOT vertex-derived: shapes
/// take their frame from the bounding box of their vertices, but wrapping
/// markdown needs a layout width up front, and re-deriving one from a vertex
/// extent on every render would be both slower and circular (the wrapped
/// height depends on the width). So the size is explicit — and it lives on
/// this subtype, not on diagram_element, so no other type is affected and
/// the tree-composing `scale` still applies on top of it.
public struct DrawingTextPayload: Codable, Hashable, Sendable {
    public let markdown: String
    public let width: Double
    public let height: Double
    public let fontSize: Double
    public let textColor: String
    public let backgroundColor: String?

    public init(
        markdown: String = "", width: Double = 180, height: Double = 60,
        fontSize: Double = 13, textColor: String = "#1a1a1a",
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

    public init(from decoder: Decoder) throws {
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
public enum DiagramConnectorLineStyle: String, Codable, Hashable, CaseIterable, Sendable {
    case solid
    case dashed
}

/// Connector head style. Widened at wire v23 for UML semantics — `dot` IS
/// the filled-circle variant and stays legal forever (pre-v23 rows carry
/// it); `circle` is the OPEN (stroked) ring. New cases ride the v23 bump:
/// the envelope handshake fences them from pre-v23 decoders, for which an
/// unknown rawValue is dataCorrupted, not a skippable field.
public enum DiagramConnectorHead: String, Codable, Hashable, CaseIterable, Sendable {
    case none
    case arrow
    case dot
    case openArrow = "open_arrow"
    case diamond
    case circle
    case cross
}

/// Connector routing style (v23). Every case selects among geometry that
/// already existed: `orthogonalStep` is the router's polyline (the ONLY
/// pre-v23 renderer, hence the decode default), `straight` is the 2-point
/// chord, `curved` is the legacy cubic promoted from routing-declined
/// fallback to a first-class choice. DiagramEdgeRouter internals are not a
/// function of this enum.
public enum DiagramConnectorRouting: String, Codable, Hashable, CaseIterable, Sendable {
    case orthogonalStep = "orthogonal_step"
    case straight
    case curved
}

/// A hand-drawn connection from the element it is parented under to a PEER
/// of that element.
///
/// The subsystem's first element-to-element reference. `targetElementUuid`
/// is optional on purpose at every layer: the column is `ON DELETE SET
/// NULL`, because CASCADE on a subtype table would delete this row and leave
/// its `diagram_element` row with no subtype at all — corruptState on every
/// later read of the whole diagram. A deleted target instead degrades to a
/// renderable ghost, the same tolerance the dope code bindings have.
///
/// In a batch, a connector may name its target by `targetClientRef` on the
/// mutation instead — temp-id resolution is a batch concern a payload is
/// structurally blind to, exactly as with `parentClientRef`.
public struct ConnectorPayload: Codable, Hashable, Sendable {
    public let targetElementUuid: String?
    public let strokeColor: String
    public let strokeWidth: Double
    public let lineStyle: DiagramConnectorLineStyle
    public let headKind: DiagramConnectorHead
    public let routingKind: DiagramConnectorRouting
    public let tailKind: DiagramConnectorHead
    public let label: String

    public init(
        targetElementUuid: String? = nil, strokeColor: String = "#1a1a1a",
        strokeWidth: Double = 2, lineStyle: DiagramConnectorLineStyle = .solid,
        headKind: DiagramConnectorHead = .arrow,
        routingKind: DiagramConnectorRouting = .orthogonalStep,
        tailKind: DiagramConnectorHead = .none, label: String = ""
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

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        targetElementUuid = try c.decodeIfPresent(String.self, forKey: .targetElementUuid)
        strokeColor = try c.decodeIfPresent(String.self, forKey: .strokeColor) ?? "#1a1a1a"
        strokeWidth = try c.decodeIfPresent(Double.self, forKey: .strokeWidth) ?? 2
        lineStyle = try c.decodeIfPresent(
            DiagramConnectorLineStyle.self, forKey: .lineStyle) ?? .solid
        headKind = try c.decodeIfPresent(
            DiagramConnectorHead.self, forKey: .headKind) ?? .arrow
        // Defaults reproduce the pre-v23 look: the router's polyline was the
        // only renderer, and no connector had a tail decoration.
        routingKind = try c.decodeIfPresent(
            DiagramConnectorRouting.self, forKey: .routingKind) ?? .orthogonalStep
        tailKind = try c.decodeIfPresent(
            DiagramConnectorHead.self, forKey: .tailKind) ?? .none
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
    }
}

/// A UML node: one element type for the whole shape vocabulary (see
/// DiagramNodeKind), an explicit frame (the drawing_text doctrine — markdown
/// wrapping needs a known width, and the kit never measures text), and a
/// block-markdown interior rendered by the kit's own renderer so rendering
/// and every host draw the same thing. Chrome fields are nil-means-theme-
/// default so an unstyled node is legible in both schemes.
public struct UmlNodePayload: Codable, Hashable, Sendable {
    public let nodeKind: DiagramNodeKind
    public let width: Double
    public let height: Double
    public let markdown: String
    public let fontSize: Double?
    public let textColor: String?
    public let strokeColor: String?
    public let strokeWidth: Double?
    public let fillColor: String?

    public init(
        nodeKind: DiagramNodeKind, width: Double = 160, height: Double = 90,
        markdown: String = "", fontSize: Double? = nil, textColor: String? = nil,
        strokeColor: String? = nil, strokeWidth: Double? = nil,
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

    public init(from decoder: Decoder) throws {
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

/// fk-by-code binding to a dope scope. Resolution runs at READ time through
/// the diagram row's own session/prompt context (the dopeGet ladder), never
/// at write time — a dangling code is a legal, renderable ghost state.
public struct DopeScopePersistenceLayerPayload: Codable, Hashable, Sendable {
    public let dopeScopeCode: String

    public init(dopeScopeCode: String) {
        self.dopeScopeCode = dopeScopeCode
    }
}

/// fk-by-code binding to a dope domain entity — 2-segment `domain.entity`
/// (DopeCode.parseEntityRef-validated on write; existence NOT checked).
public struct DopeEntityPayload: Codable, Hashable, Sendable {
    public let entityCode: String

    public init(entityCode: String) {
        self.entityCode = entityCode
    }
}

/// Tri-state field write for nullable columns: absent = leave alone,
/// `{"op": "set", "value": …}` = write, `{"op": "clear"}` = NULL. The typed
/// replacement for dope's clear* flag pairs; one use site this pass
/// (diagram.gmcc_diagram_path), available to future surfaces.
public enum FieldPatch<T: Codable & Hashable & Sendable>: Codable, Hashable, Sendable {
    case set(T)
    case clear

    private enum CodingKeys: String, CodingKey { case op, value }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let op = try c.decode(String.self, forKey: .op)
        switch op {
        case "set":
            self = .set(try c.decode(T.self, forKey: .value))
        case "clear":
            self = .clear
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .op, in: c, debugDescription: "unknown field patch op '\(op)'")
        }
    }

    public func encode(to encoder: Encoder) throws {
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
