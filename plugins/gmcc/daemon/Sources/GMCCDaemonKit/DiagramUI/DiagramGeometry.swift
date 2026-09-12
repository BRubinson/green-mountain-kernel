import CoreGraphics
import Foundation

/// Drag arithmetic the kit owns so no host ever writes it. SwiftUI-free.
public enum DiagramDrag {
    /// The element_update that moves `node` by a DIAGRAM-space delta.
    ///
    /// Bundles the trap: `centerX/centerY` are PARENT-space pre-multiplied
    /// by the parent's accumulated scale, so the divisor is the PARENT scale
    /// (`resolved.accumulatedScale / node.base.scale`) — never the element's
    /// own accumulated scale. A card with its own scale inside a scaled
    /// scope would drift under the cursor otherwise. Scale is 1 throughout
    /// v1 scaffolds, but the division is written for the general case.
    public static func moveMutation(node: DiagramElementNode,
                                    resolved: ResolvedElement,
                                    by diagramDelta: CGSize) -> DiagramMutation {
        let parentScale = node.base.scale > 0
            ? resolved.accumulatedScale / node.base.scale : 1
        let divisor = parentScale > 0 ? parentScale : 1
        return .elementUpdate(DiagramElementUpdate(
            elementUuid: node.identity.uuid,
            expectedVersion: node.identity.version,
            centerX: node.base.centerX + diagramDelta.width / divisor,
            centerY: node.base.centerY + diagramDelta.height / divisor))
    }
}
