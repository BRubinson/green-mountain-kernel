import CoreGraphics
import Foundation

/// Drag arithmetic the kit owns so no host ever writes it.
///
/// SwiftUI-free.
enum DiagramDrag {
    /// Computes a mutation to move the element in diagram space.
    ///
    /// The element_update that moves `node` by a diagram-space delta. Bundles
    /// the trap: `centerX/centerY` are parent-space pre-multiplied by the
    /// parent's accumulated scale, so the divisor is the parent scale
    /// (`resolved.accumulatedScale / node.base.scale`) — never the element's
    /// own accumulated scale. A card with its own scale inside a scaled
    /// scope would drift under the cursor otherwise. Scale is 1 throughout
    /// v1 scaffolds, but the division is written for the general case.
    ///
    /// - Parameters:
    ///   - node: The element node to move.
    ///   - resolved: The resolved element with accumulated scale.
    ///   - diagramDelta: The movement delta in diagram space.
    /// - Returns: The element update mutation.
    static func moveMutation(
        node: DiagramElementNode,
        resolved: ResolvedElement,
        by diagramDelta: CGSize
    ) -> DiagramMutation {
        let parentScale =
            node.base.scale > 0
            ? resolved.accumulatedScale / node.base.scale : 1
        let divisor = parentScale > 0 ? parentScale : 1
        return .elementUpdate(
            DiagramElementUpdate(
                elementUuid: node.identity.uuid,
                expectedVersion: node.identity.version,
                centerX: node.base.centerX + diagramDelta.width / divisor,
                centerY: node.base.centerY + diagramDelta.height / divisor
            )
        )
    }
}
