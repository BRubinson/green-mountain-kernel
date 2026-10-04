import Foundation
import GRDB

/// The five dope tree tables share one soft-delete shape: BaseEntity columns
/// plus `deleted_on`.
///
/// This lets DopeRepository.fetchDopeTree build every node's DopeNodeIdentity through one generic helper instead of
/// five copies.
protocol DopeNodeRecord: BaseRecordFields {
    var createdAt: String { get }
    var updatedAt: String { get }
    var deletedOn: String? { get }
}
