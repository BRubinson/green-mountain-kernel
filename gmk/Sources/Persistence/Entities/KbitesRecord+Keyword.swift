import Foundation
import GRDB

/// Read-side mirror of the `keyword` table.
///
/// Columns map via convertFromSnakeCase.
struct KeywordRecord: BaseRecordFields, TableRecord {
    static let databaseTableName = "keyword"
    var uuid: String
    var version: Int64
    var createdAt: String
    var updatedAt: String
    var keyword: String

    enum Columns: String, ColumnExpression {
        case uuid
        case version
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case keyword
    }
}
