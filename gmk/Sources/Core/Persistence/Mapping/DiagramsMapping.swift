// The one place a diagram persistence type and a wire DTO meet. Rows.swift
// types gain no GRDB conformance and no custom decoding; the translation lives
// here, as `dto()`.

import Foundation

extension DiagramWithOwner {
    /// Converts a diagram record to a wire DTO.
    ///
    /// The derived instance is injected, and `visibility` is passed explicitly
    /// rather than relying on DiagramRow's default initializer.
    ///
    /// - Returns: The wire row representation of the diagram.
    func dto() -> DiagramRow {
        DiagramRow(
            uuid: diagram.uuid,
            version: diagram.version,
            tier: diagram.tier,
            projectUuid: diagram.projectUuid,
            instanceUuid: instanceUuid,
            sessionUuid: diagram.sessionUuid,
            promptUuid: diagram.promptUuid,
            code: diagram.code,
            name: diagram.name,
            description: diagram.description,
            gmccDiagramPath: diagram.gmccDiagramPath,
            dopeScopeCode: diagram.dopeScopeCode,
            revision: diagram.revision,
            createdAt: diagram.createdAt,
            updatedAt: diagram.updatedAt,
            visibility: diagram.visibility
        )
    }
}

extension DiagramElementRecord {
    /// Converts a diagram element record to a tree node.
    ///
    /// The payload and children are provided by the caller. The hydrator
    /// determines which subtype row belongs to this element and how the flat row
    /// set folds into a tree structure.
    ///
    /// - Parameters:
    ///   - payload: The diagram element payload for this node.
    ///   - children: The child nodes in the tree.
    /// - Returns: The tree node representation of this element.
    func node(payload: DiagramElementPayload, children: [DiagramElementNode]) -> DiagramElementNode {
        DiagramElementNode(
            identity: DopeNodeIdentity(
                uuid: uuid,
                version: version,
                createdAt: createdAt,
                updatedAt: updatedAt
            ),
            base: DiagramElementBase(
                code: code,
                name: name,
                description: description,
                sortOrder: Int(sortOrder),
                centerX: centerX,
                centerY: centerY,
                elementZ: elementZ,
                scale: scale
            ),
            payload: payload,
            children: children
        )
    }
}

extension DiagramStrokeVertexRecord {
    /// Converts a stroke vertex record to a wire vertex.
    ///
    /// - Returns: The wire vertex representation with x, y, and pressure values.
    func vertex() -> DiagramVertex {
        DiagramVertex(x: x, y: y, pressure: pressure)
    }
}

extension DiagramShapeVertexRecord {
    /// Converts a shape vertex record to a wire vertex.
    ///
    /// Shape vertices do not include pressure information.
    ///
    /// - Returns: The wire vertex representation with x and y values.
    func vertex() -> DiagramVertex {
        DiagramVertex(x: x, y: y, pressure: nil)
    }
}

extension DiagramDrawingLayerRecord {
    /// Converts a drawing layer record to a diagram element payload.
    ///
    /// - Returns: The diagram element payload wrapping the drawing layer data.
    func payload() -> DiagramElementPayload {
        .drawingLayer(
            DrawingLayerPayload(opacity: opacity, visible: visible, locked: locked)
        )
    }
}

extension DiagramDrawingStrokeRecord {
    /// Converts a stroke record to a diagram element payload.
    ///
    /// Uses the packed vertex blob if present, otherwise uses the vertex rows
    /// provided by the caller. The write path never leaves both populated.
    ///
    /// - Parameter vertexRows: The vertex rows to use if no packed blob exists.
    /// - Returns: The diagram element payload wrapping the stroke data.
    /// - Throws: Any error from unpacking the vertex blob.
    func payload(vertexRows: [DiagramVertex]) throws -> DiagramElementPayload {
        let packed: [DiagramVertex]?
        if let blob = packedVertices, let count = vertexCount {
            packed = try DiagramStrokeCodec.unpack(blob, count: Int(count))
        } else {
            packed = nil
        }
        return .drawingStroke(
            DrawingStrokePayload(
                tool: DiagramStrokeTool(rawValue: tool) ?? .pencil,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                vertices: packed ?? vertexRows
            )
        )
    }
}

extension DiagramDrawingShapeRecord {
    /// Converts a shape record to a diagram element payload.
    ///
    /// - Parameter vertexRows: The vertex rows that define the shape's geometry.
    /// - Returns: The diagram element payload wrapping the shape data.
    /// - Throws: `StoreError.corruptState` when the shape kind is unknown.
    func payload(vertexRows: [DiagramVertex]) throws -> DiagramElementPayload {
        guard let kind = DiagramShapeKind(rawValue: shapeKind) else {
            throw StoreError.corruptState(
                entity: Self.databaseTableName,
                detail: "unknown shape_kind '\(shapeKind)'"
            )
        }
        return .drawingShape(
            DrawingShapePayload(
                shapeKind: kind,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                fillColor: fillColor,
                cornerRadius: cornerRadius,
                vertices: vertexRows
            )
        )
    }
}

extension DiagramDrawingTextRecord {
    /// Converts a text record to a diagram element payload.
    ///
    /// - Returns: The diagram element payload wrapping the text data.
    func payload() -> DiagramElementPayload {
        .drawingText(
            DrawingTextPayload(
                markdown: markdown,
                width: width,
                height: height,
                fontSize: fontSize,
                textColor: textColor,
                backgroundColor: backgroundColor
            )
        )
    }
}

extension DiagramConnectorRecord {
    /// Converts a connector record to a diagram element payload.
    ///
    /// - Returns: The diagram element payload wrapping the connector data.
    func payload() -> DiagramElementPayload {
        .connector(
            ConnectorPayload(
                targetElementUuid: targetElementUuid,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                lineStyle: DiagramConnectorLineStyle(rawValue: lineStyle) ?? .solid,
                headKind: DiagramConnectorHead(rawValue: headKind) ?? .arrow,
                routingKind: DiagramConnectorRouting(rawValue: routingKind) ?? .orthogonalStep,
                tailKind: DiagramConnectorHead(rawValue: tailKind) ?? .none,
                label: label
            )
        )
    }
}

extension DiagramUmlNodeRecord {
    /// Converts a UML node record to a diagram element payload.
    ///
    /// - Returns: The diagram element payload wrapping the UML node data.
    /// - Throws: `StoreError.corruptState` when the node kind is unknown.
    func payload() throws -> DiagramElementPayload {
        guard let kind = DiagramNodeKind(rawValue: nodeKind) else {
            throw StoreError.corruptState(
                entity: Self.databaseTableName,
                detail: "unknown node_kind '\(nodeKind)'"
            )
        }
        return .umlNode(
            UmlNodePayload(
                nodeKind: kind,
                width: width,
                height: height,
                markdown: markdown,
                fontSize: fontSize,
                textColor: textColor,
                strokeColor: strokeColor,
                strokeWidth: strokeWidth,
                fillColor: fillColor
            )
        )
    }
}

extension DiagramDopeScopePersistenceLayerRecord {
    /// Converts a dope scope persistence layer record to a diagram element payload.
    ///
    /// - Returns: The diagram element payload wrapping the layer data.
    func payload() -> DiagramElementPayload {
        .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: dopeScopeCode))
    }
}

extension DiagramDopeEntityRecord {
    /// Converts a dope entity record to a diagram element payload.
    ///
    /// - Returns: The diagram element payload wrapping the entity data.
    func payload() -> DiagramElementPayload {
        .dopeEntity(DopeEntityPayload(entityCode: entityCode))
    }
}
