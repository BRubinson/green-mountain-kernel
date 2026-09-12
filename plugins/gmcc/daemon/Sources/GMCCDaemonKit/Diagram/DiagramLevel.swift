import Foundation

// The DIAGRAM tree has exactly two levels (diagram, element), and unlike
// dope they never travel on the wire — the tagged DiagramElementPayload and
// mutation kinds discriminate everything. There is deliberately NO level
// registry: the element-axis registry below (DiagramElementTypeSpec) is the
// single truth for subtype persistence and containment.

/// diagram.tier values — the chain-non-null ownership ladder.
///
/// INSTANCE was removed by m0021. It existed to give a diagram a repo
/// checkout to anchor a path against; screenshots now materialize under CKFS
/// storage, which every remaining tier carries, so the rung had nothing left
/// to do. A session or prompt diagram still reaches an instance transitively
/// via session -> instance wherever one is genuinely needed.
public enum DiagramTier: String, Codable, Hashable, CaseIterable, Sendable {
    case project = "PROJECT"
    case session = "SESSION"
    case prompt = "PROMPT"
}

/// diagram.visibility values — an AXIS beside the tier ladder, never a rung
/// on it (m0024). PRIVATE lives in the db only; PUBLIC additionally
/// serializes into the repo's committed .gmcc tree via DIAGRAM_WRITE_REPO.
/// PUBLIC is legal ONLY on SESSION-tier rows — the same
/// session→instance-root gate DOPE_WRITE_REPO uses — enforced by a Swift
/// store guard, not a CHECK (the rule crosses tables).
public enum DiagramVisibility: String, Codable, Hashable, CaseIterable, Sendable {
    case `private` = "PRIVATE"
    case `public` = "PUBLIC"
}

/// diagram_element.element_type values. Raw values are the db discriminators
/// AND the wire payload tags — one string, three layers.
///
/// Since m0021 the db carries NO CHECK on this column: validity is this
/// enum plus DiagramElementTypeSpec, enforced on both write paths and thrown
/// on at read (`fetchElementInfo`). Adding a type is one case here, one
/// registry entry below, and one subtype table — never a migration. That is
/// the standard DopeCogElement.swift:11-19 set for cogs, applied to the
/// family it was written about.
public enum DiagramElementType: String, Codable, Hashable, CaseIterable, Sendable {
    case drawingLayer = "drawing_layer"
    case drawingStroke = "drawing_stroke"
    case drawingShape = "drawing_shape"
    case drawingText = "drawing_text"
    case connector = "connector"
    case umlNode = "uml_node"
    case dopeScopePersistenceLayer = "dope_scope_persistence_layer"
    case dopeEntity = "dope_entity"

    /// Auto-mint prefix for elements added without a code (hand-naming
    /// hundreds of freedraw strokes would be hostile).
    public var codePrefix: String {
        switch self {
        case .drawingLayer: return "layer"
        case .drawingStroke: return "stroke"
        case .drawingShape: return "shape"
        case .drawingText: return "text"
        case .connector: return "connector"
        case .umlNode: return "node"
        case .dopeScopePersistenceLayer: return "scope"
        case .dopeEntity: return "entity"
        }
    }

    /// Default display name for elements added without one.
    public var defaultName: String {
        switch self {
        case .drawingLayer: return "Layer 1"
        case .drawingStroke: return "Stroke"
        case .drawingShape: return "Shape"
        case .drawingText: return "Text"
        case .connector: return "Connector"
        case .umlNode: return "Node"
        case .dopeScopePersistenceLayer: return "Dope Scope Persistence Layer"
        case .dopeEntity: return "Dope Entity"
        }
    }
}

/// Where an element type's geometry lives.
///
/// Strokes pack to a blob because a freedraw stroke is hundreds of points
/// and a row-per-vertex costs ~250B of BaseEntity scaffolding per 24B of
/// coordinate. Low-cardinality shapes keep vertex rows, where the row form
/// is queryable and the overhead is irrelevant. Both representations coexist
/// permanently; this is the axis that picks between them.
public enum DiagramVertexStorage: Sendable, Hashable {
    /// No geometry beyond the element's own center/scale.
    case none
    /// One row per vertex in `table`, joined by `parentColumn`.
    case rows(table: String, parentColumn: String)
    /// Packed little-endian (f32 x, f32 y, u8 pressure) triples in a blob
    /// column, with the vertex rows as the fallback read when it is NULL.
    case packedBlob(column: String, countColumn: String,
                    fallback: (table: String, parentColumn: String))

    /// The vertex table this storage reads from, if any — the fallback for
    /// `.packedBlob`, the table itself for `.rows`.
    public var vertexTable: String? {
        switch self {
        case .none: return nil
        case .rows(let table, _): return table
        case .packedBlob(_, _, let fallback): return fallback.table
        }
    }

    public var vertexParentColumn: String? {
        switch self {
        case .none: return nil
        case .rows(_, let column): return column
        case .packedBlob(_, _, let fallback): return fallback.parentColumn
        }
    }

    public static func == (lhs: DiagramVertexStorage, rhs: DiagramVertexStorage) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none): return true
        case (.rows(let lt, let lc), .rows(let rt, let rc)): return lt == rt && lc == rc
        case (.packedBlob(let lc, let ln, let lf), .packedBlob(let rc, let rn, let rf)):
            return lc == rc && ln == rn && lf == rf
        default: return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        switch self {
        case .none: hasher.combine(0)
        case .rows(let t, let c): hasher.combine(1); hasher.combine(t); hasher.combine(c)
        case .packedBlob(let c, let n, let f):
            hasher.combine(2); hasher.combine(c); hasher.combine(n)
            hasher.combine(f.table); hasher.combine(f.parentColumn)
        }
    }
}

/// When an element gets its frame during resolution.
///
/// `.deferred` types are positioned in a second pass, after every
/// `.immediate` element already has a frame in the uuid-keyed index —
/// because they are defined in terms of OTHER elements' geometry, which does
/// not exist yet during the main walk. Connector is the first such type; the
/// pass is general so it is not the last.
public enum DiagramResolutionPhase: Sendable, Hashable {
    case immediate
    case deferred
}

/// diagram_drawing_shape.shape_kind values.
public enum DiagramShapeKind: String, Codable, Hashable, CaseIterable, Sendable {
    case rectangle
    case ellipse
    case line
    case arrow
    case polygon
}

/// diagram_drawing_stroke.tool values.
public enum DiagramStrokeTool: String, Codable, Hashable, CaseIterable, Sendable {
    case pencil
    case marker
    case highlighter
}

/// diagram_uml_node.node_kind values — the UML vocabulary, ONE element type
/// with a kind column (the drawing_shape/shape_kind precedent, and xyflow's
/// node-types-are-data model). Reshaping a node is an ordinary wholesale
/// payload update; a type-per-shape design would make it delete+recreate,
/// ghosting every incoming connector.
public enum DiagramNodeKind: String, Codable, Hashable, CaseIterable, Sendable {
    case dbCylinder = "db_cylinder"
    case roundedRect = "rounded_rect"
    case triangle
    case rhombus
    case diamond
    case circle
}

/// A typed reference from one element to ANOTHER element, declared once in
/// the registry and validated generically by both write paths.
///
/// This is the first thing in the diagram subsystem that is not parent
/// containment. Every other element relationship is either
/// `parent_element_uuid` (validated purely by type membership) or a
/// ghost-tolerant CODE lookup into the external dope tree.
public struct DiagramElementRefSpec: Sendable, Hashable {
    /// Names the reference in errors: "connector target ...".
    public let role: String
    /// The subtype-table column holding the referenced element's uuid.
    public let column: String
    public let rule: ContainmentRule

    public enum ContainmentRule: Sendable, Hashable {
        /// The target must be a PEER OF THE REFERRER'S OWN PARENT — it
        /// shares the referrer's grandparent — and may be neither the
        /// referrer's parent nor the referrer itself.
        ///
        /// A connector is rendered as a child of the element it connects
        /// FROM, so "connects to a sibling" means a sibling of that parent,
        /// not a sibling of the connector. The other reading would let a
        /// connector under entity A target only other children of A, which
        /// is never what anyone draws.
        case peerOfOwnParent
    }

    public init(role: String, column: String, rule: ContainmentRule) {
        self.role = role
        self.column = column
        self.rule = rule
    }
}

/// The element-axis registry: subtype table, vertex storage, legal parents,
/// element references, resolution phase, routing participation,
/// binding-ness — the single truth consumed by store dispatch, containment
/// validation, hydration, the resolver, and the CLI's help text.
public struct DiagramElementTypeSpec: Sendable {
    public let type: DiagramElementType
    public let subtypeTable: String
    /// Where this type's geometry lives. `.rows` is the classic vertex
    /// table; `.packedBlob` packs to a blob and falls back to those rows.
    public let vertexStorage: DiagramVertexStorage
    /// nil = a top-level type (parent_element_uuid must be NULL). Since
    /// m0021 there is NO schema CHECK behind this — the registry IS the
    /// rule, enforced by both write paths.
    public let allowedParentTypes: Set<DiagramElementType>?
    /// Whether this type binds into the dope tree by code.
    public let isDopeBinding: Bool
    /// Typed references this type makes to OTHER elements, beyond parent
    /// containment. Empty for every type except connector.
    public let elementRefs: [DiagramElementRefSpec]
    /// Immediate placement, or a second pass against completed frames.
    public let resolution: DiagramResolutionPhase
    /// Whether this type's frame becomes an obstacle the edge router steers
    /// around. Structural content (entity cards, shapes, text) blocks;
    /// freehand ink and layers deliberately do not, so edges cross drawings
    /// by design and a dense stroke corpus never chokes the router.
    public let participatesInRouting: Bool

    /// Non-nil only for vertex-bearing types — derived from `vertexStorage`
    /// so call sites that only care about the table keep working.
    public var vertexTable: String? { vertexStorage.vertexTable }
    /// The subtype-table FK column the vertex table uses.
    public var vertexParentColumn: String? { vertexStorage.vertexParentColumn }

    public static let all: [DiagramElementType: DiagramElementTypeSpec] = {
        let specs: [DiagramElementTypeSpec] = [
            DiagramElementTypeSpec(
                type: .drawingLayer, subtypeTable: "diagram_drawing_layer",
                vertexStorage: .none,
                allowedParentTypes: nil, isDopeBinding: false,
                elementRefs: [], resolution: .immediate,
                participatesInRouting: false),
            DiagramElementTypeSpec(
                type: .drawingStroke, subtypeTable: "diagram_drawing_stroke",
                vertexStorage: .packedBlob(
                    column: "packed_vertices", countColumn: "vertex_count",
                    fallback: (table: "diagram_stroke_vertex",
                               parentColumn: "stroke_element_uuid")),
                allowedParentTypes: [.drawingLayer], isDopeBinding: false,
                elementRefs: [], resolution: .immediate,
                // Ink is not an obstacle: you draw over and around a canvas
                // freely, and a dense stroke corpus would swamp the router.
                participatesInRouting: false),
            DiagramElementTypeSpec(
                type: .drawingShape, subtypeTable: "diagram_drawing_shape",
                vertexStorage: .rows(table: "diagram_shape_vertex",
                                     parentColumn: "shape_element_uuid"),
                allowedParentTypes: [.drawingLayer], isDopeBinding: false,
                elementRefs: [], resolution: .immediate,
                participatesInRouting: true),
            DiagramElementTypeSpec(
                type: .drawingText, subtypeTable: "diagram_drawing_text",
                // Explicit width/height on the subtype row, NOT a vertex
                // extent: markdown wrapping needs a known layout width.
                vertexStorage: .none,
                allowedParentTypes: [.drawingLayer], isDopeBinding: false,
                elementRefs: [], resolution: .immediate,
                participatesInRouting: true),
            DiagramElementTypeSpec(
                type: .umlNode, subtypeTable: "diagram_uml_node",
                // Explicit width/height on the subtype row, like drawing_text:
                // markdown wrapping needs a known layout width, and the kit
                // never measures text (hosts may auto-fit and write back).
                vertexStorage: .none,
                allowedParentTypes: [.drawingLayer], isDopeBinding: false,
                elementRefs: [], resolution: .immediate,
                // Structural content: edges route around nodes.
                participatesInRouting: true),
            DiagramElementTypeSpec(
                type: .connector, subtypeTable: "diagram_connector",
                vertexStorage: .none,
                // Rendered as a child of the element it connects FROM.
                // umlNode joined in m0024 — without it nodes could not
                // source an edge at all.
                allowedParentTypes: [.dopeEntity, .drawingShape, .drawingText,
                                     .umlNode],
                isDopeBinding: false,
                elementRefs: [DiagramElementRefSpec(
                    role: "target", column: "target_element_uuid",
                    rule: .peerOfOwnParent)],
                // Defined in terms of another element's frame, so it cannot
                // be placed until every immediate element has one.
                resolution: .deferred,
                // A connector is a route, not an obstacle to other routes.
                participatesInRouting: false),
            DiagramElementTypeSpec(
                type: .dopeScopePersistenceLayer, subtypeTable: "diagram_dope_scope_persistence_layer",
                vertexStorage: .none,
                allowedParentTypes: nil, isDopeBinding: true,
                elementRefs: [], resolution: .immediate,
                participatesInRouting: false),
            DiagramElementTypeSpec(
                type: .dopeEntity, subtypeTable: "diagram_dope_entity",
                vertexStorage: .none,
                allowedParentTypes: [.dopeScopePersistenceLayer], isDopeBinding: true,
                elementRefs: [], resolution: .immediate,
                participatesInRouting: true),
        ]
        return Dictionary(uniqueKeysWithValues: specs.map { ($0.type, $0) })
    }()

    /// Every type whose frame the edge router must steer around.
    public static var routingParticipants: Set<DiagramElementType> {
        Set(all.values.filter(\.participatesInRouting).map(\.type))
    }

    public static func spec(for type: DiagramElementType) -> DiagramElementTypeSpec {
        // Total over DiagramElementType by construction.
        all[type]!
    }
}
