import Foundation

/// The containment rules for element-to-element references, as ONE pure
/// predicate both write paths call.
///
/// Why this file exists: `Store+Diagram` validates against SQL lookups and
/// `DiagramTreeReducer` validates against an in-memory tree, and the two are
/// held together only by parity fixtures. A rule this fiddly — an identity
/// exclusion layered on a peer-set test — hand-written twice would drift.
/// Sharing the PREDICATE while each side keeps its own way of answering
/// "who is this element's parent" makes the contract structural instead of
/// aspirational.
///
/// It is a Swift guard rather than a SQL CHECK because it cannot be one: a
/// CHECK cannot reference another table. That is the same reason m0016's
/// diagram dope binding is a Swift guard.
public enum DiagramContainment {

    /// What a reference violated, so both implementations produce the same
    /// error text for the same violation.
    public enum Violation: Equatable, Sendable {
        case targetIsSelf
        case targetIsOwnParent
        case targetNotAPeerOfParent
        case referrerHasNoParent
        case targetMissing(uuid: String)

        public func message(role: String, referrer: String, target: String) -> String {
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

    /// Evaluate one reference. Returns nil when the reference is legal.
    ///
    /// Callers resolve the parentage however they like — SQL lookups on one
    /// side, a tree walk on the other — which is exactly the seam that lets
    /// one predicate serve both implementations.
    ///
    /// - Parameters:
    ///   - grandparentOfReferrer: the `parent_element_uuid` of the
    ///     referrer's parent, i.e. the parent the target must also have.
    ///     nil means the referrer's parent is top-level, so a legal target
    ///     is also top-level.
    public static func validateReference(
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
