import Foundation

/// The containment rules for element-to-element references, as ONE pure
/// predicate both write paths call. `Store+Diagram` answers "who is this
/// element's parent" from SQL and `DiagramTreeReducer` from an in-memory
/// tree; sharing the PREDICATE is what keeps the rule from drifting between
/// them.
///
/// It is a Swift guard rather than a SQL CHECK because a CHECK cannot reference another table.
enum DiagramContainment {

    /// What a reference violated, so both implementations produce the same
    /// error text for the same violation.
    enum Violation: Equatable, Sendable {
        case targetIsSelf
        case targetIsOwnParent
        case targetNotAPeerOfParent
        case referrerHasNoParent
        case targetMissing(uuid: String)

        /// A human-readable description of this violation.
        ///
        /// - Parameters:
        ///   - role: The name of the element role being validated.
        ///   - referrer: The uuid of the element making the reference.
        ///   - target: The uuid of the target element.
        /// - Returns: An error message describing the violation.
        func message(role: String, referrer: String, target: String) -> String {
            switch self {
            case .targetIsSelf:
                return "\(role) \(referrer) cannot reference itself"
            case .targetIsOwnParent:
                return "\(role) target \(target) is the referring element's own parent — "
                    + "a connector joins its parent to a PEER of that parent, not to it"
            case .targetNotAPeerOfParent:
                return "\(role) target \(target) is not a peer of \(referrer)'s parent — "
                    + "both must share the same parent element"
            case .referrerHasNoParent:
                return "\(role) requires the referring element to have a parent"
            case .targetMissing(let uuid):
                return "\(role) target \(uuid) does not exist in this diagram"
            }
        }
    }

    /// Evaluate one reference, returning nil when it is legal.
    ///
    /// Callers resolve the parentage however they like — SQL lookups on one
    /// side, a tree walk on the other — which is the seam that lets one
    /// predicate serve both implementations. `grandparentOfReferrer` is the
    /// parent the target must also have; nil means the referrer's parent is
    /// top-level, so a legal target is top-level too.
    ///
    /// - Parameters:
    ///   - rule: The containment rule to apply.
    ///   - referrerUuid: The uuid of the element making the reference.
    ///   - parentOfReferrer: The uuid of the referrer's parent, or `nil` if top-level.
    ///   - grandparentOfReferrer: The uuid of the referrer's parent's parent, or `nil` if top-level.
    ///   - targetUuid: The uuid of the target element.
    ///   - parentOfTarget: The uuid of the target's parent, or `nil` if top-level.
    ///   - targetExists: Whether the target element exists in the diagram.
    /// - Returns: A `Violation` if the reference is illegal; `nil` if legal.
    static func validateReference(
        rule: DiagramElementRefSpec.ContainmentRule,
        referrerUuid: String,
        parentOfReferrer: String?,
        grandparentOfReferrer: String?,
        targetUuid: String,
        parentOfTarget: String?,
        targetExists: Bool
    ) -> Violation? {
        guard targetExists else { return .targetMissing(uuid: targetUuid) }
        switch rule {
        case .peerOfOwnParent:
            if targetUuid == referrerUuid { return .targetIsSelf }
            guard let parentOfReferrer else { return .referrerHasNoParent }
            if targetUuid == parentOfReferrer { return .targetIsOwnParent }
            guard parentOfTarget == grandparentOfReferrer else {
                return .targetNotAPeerOfParent
            }
            return nil
        }
    }
}
