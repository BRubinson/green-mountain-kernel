// Composite read shapes over the diagram tables: a root Record plus the
// joined Records and annotated scalars one read needs. Decode-only, like the
// Entities they compose, and never a write path.

import Foundation
import GRDB

/// A diagram row with its instance, which is derived rather than stored.
///
/// INSTANCE is not an ownership tier, so a SESSION-tier diagram reaches its
/// instance through the session and a PROJECT-tier diagram reports nil.
struct DiagramWithOwner: FetchableRecord, Decodable {
    var diagram: DiagramRecord
    var instanceUuid: String?

    /// Builds a request for diagrams with their instance uuid annotated.
    ///
    /// Every diagram read starts here, performing a LEFT JOIN onto session and annotating
    /// the instance uuid onto the root row under the composite's own key.
    ///
    /// - Returns: A request that fetches DiagramWithOwner rows.
    static func request() -> QueryInterfaceRequest<Self> {
        let session = TableAlias<SessionRecord>()
        return
            DiagramRecord
            .joining(optional: DiagramRecord.session.aliased(session))
            .annotated(with: session[SessionRecord.Columns.instanceUuid].forKey("instanceUuid"))
            .asRequest(of: Self.self)
    }
}

/// The identity chain a diagram owner's uuid resolves to.
///
/// A session reaches project through its instance, and a prompt through its
/// session's.
struct DiagramOwnerChain: FetchableRecord, Decodable {
    var sessionUuid: String
    var instanceUuid: String
    var projectUuid: String

    /// Builds a request for the owner chain of a session.
    /// - Parameter uuid: The session uuid.
    /// - Returns: A request that fetches the DiagramOwnerChain for the session.
    static func forSession(_ uuid: String) -> QueryInterfaceRequest<Self> {
        let instance = TableAlias<InstanceRecord>()
        return
            SessionRecord
            .all()
            .withUuid(uuid)
            .joining(required: SessionRecord.instance.aliased(instance))
            .select(
                SessionRecord.Columns.uuid.forKey("sessionUuid"),
                SessionRecord.Columns.instanceUuid.forKey("instanceUuid"),
                instance[InstanceRecord.Columns.projectUuid].forKey("projectUuid")
            )
            .asRequest(of: Self.self)
    }

    /// Builds a request for the owner chain of a prompt.
    /// - Parameter uuid: The prompt uuid.
    /// - Returns: A request that fetches the DiagramOwnerChain for the prompt.
    static func forPrompt(_ uuid: String) -> QueryInterfaceRequest<Self> {
        let session = TableAlias<SessionRecord>()
        let instance = TableAlias<InstanceRecord>()
        return
            PromptRecord
            .all()
            .withUuid(uuid)
            .joining(
                required: PromptRecord.session.aliased(session)
                    .joining(required: SessionRecord.instance.aliased(instance))
            )
            .select(
                session[SessionRecord.Columns.uuid].forKey("sessionUuid"),
                session[SessionRecord.Columns.instanceUuid].forKey("instanceUuid"),
                instance[InstanceRecord.Columns.projectUuid].forKey("projectUuid")
            )
            .asRequest(of: Self.self)
    }
}
