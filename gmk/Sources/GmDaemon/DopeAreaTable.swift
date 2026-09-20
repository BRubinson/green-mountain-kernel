import Foundation

/// Where each dope area's `content_revision` actually lives.
///
/// This mapping is in the PERSISTENCE layer, not on the `DopeArea` enum in the
/// SDK, because a table name is not part of the concept "sub-loadable area of a
/// dope scope" — it is part of how this database happens to store one. The
/// enum moved to the base layer with the rest of the domain; its schema
/// binding stayed here.
extension DopeArea {
    /// The table whose rows carry this area's content_revision.
    var table: String {
        switch self {
        case .persistence: return "dope_persistence"
        case .cogs: return "dope_cog"
        }
    }
}
