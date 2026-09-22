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

    /// Every `diagram` read starts here: the LEFT JOIN onto session, with the
    /// instance annotated onto the root row under the composite's own key.
    static func request() -> QueryInterfaceRequest<Self> {
        let session = TableAlias<SessionRecord>()
        return
            DiagramRecord
            .joining(optional: DiagramRecord.session.aliased(session))
            .annotated(with: session[SessionRecord.Columns.instanceUuid].forKey("instanceUuid"))
            .asRequest(of: Self.self)
    }
}
