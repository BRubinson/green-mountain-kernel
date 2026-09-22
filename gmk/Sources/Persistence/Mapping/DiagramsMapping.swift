// The one place a diagram persistence type and a wire DTO meet. Rows.swift
// types gain no GRDB conformance and no custom decoding; the translation lives
// here, as `dto()`.

import Foundation

extension DiagramWithOwner {
    /// db → wire, with the derived instance injected. `visibility` is passed
    /// explicitly rather than leaning on DiagramRow's "PRIVATE" init default.
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
            visibility: diagram.visibility,
            createdAt: diagram.createdAt,
            updatedAt: diagram.updatedAt
        )
    }
}

extension DiagramElementRecord {
    /// db → wire for one tree node. The payload and the children are handed
    /// in: which subtype row belongs to this element, and how the flat row set
    /// folds into a tree, are the hydrator's questions, not this mapping's.
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
    func vertex() -> DiagramVertex {
        DiagramVertex(x: x, y: y, pressure: pressure)
    }
}

extension DiagramShapeVertexRecord {
    /// This table carries no pressure column.
    func vertex() -> DiagramVertex {
        DiagramVertex(x: x, y: y, pressure: nil)
    }
}

extension DiagramDrawingLayerRecord {
    func payload() -> DiagramElementPayload {
        .drawingLayer(
            DrawingLayerPayload(opacity: opacity, visible: visible, locked: locked)
        )
    }
}

extension DiagramDrawingStrokeRecord {
    /// Read precedence, per the storage-strategy axis: the packed blob when
    /// present, else the vertex rows the caller supplies. The write path never
    /// leaves both populated.
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
    func payload() -> DiagramElementPayload {
        .dopeScopePersistenceLayer(DopeScopePersistenceLayerPayload(dopeScopeCode: dopeScopeCode))
    }
}

extension DiagramDopeEntityRecord {
    func payload() -> DiagramElementPayload {
        .dopeEntity(DopeEntityPayload(entityCode: entityCode))
    }
}
