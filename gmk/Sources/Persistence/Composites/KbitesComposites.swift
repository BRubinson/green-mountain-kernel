// Composite read shapes over the kbite tables.
//
// A composite is a decode target for one request: its properties are Records,
// arrays of Records, or annotated scalars, and it owns the request that fills
// it. Wire mapping lives in Mapping/, never here.

import Foundation
import GRDB

/// PROJECTION record: a decoder for a select-projected `kbite_resource_file`
/// row, not a table mirror, so it is not enrolled in RecordSchemaTests.
///
/// `hasContent` decodes the projected `has_content` expression, which keeps
/// `resource_file_content` — ~115 MB, the largest thing in the schema — out of
/// every listing result set.
struct KbiteResourceFileHead: FetchableRecord, Decodable, SnakeCaseDecoded {
    var uuid: String
    var resourceFileName: String
    var resourceFileSummary: String
    var hasContent: Bool
}

/// One `kbite_resource` row with its files projected down to heads.
///
/// `resource` names no association, so GRDB decodes it from the base row
/// through `KbiteResourceRecord.init(row:)`. `files` matches the association's
/// `forKey`, and its element type — not the association's destination record —
/// decides how the prefetched rows decode.
struct KbiteResourceWithFiles: FetchableRecord, Decodable {
    var resource: KbiteResourceRecord
    var files: [KbiteResourceFileHead]

    static func request() -> QueryInterfaceRequest<Self> {
        KbiteResourceRecord
            .including(
                all: KbiteResourceRecord.files
                    .select(
                        Column("uuid"),
                        Column("resource_file_name"),
                        Column("resource_file_summary"),
                        (Column("resource_file_content") != nil).forKey("has_content")
                    )
                    .order(Column("resource_file_name"))
            )
            .asRequest(of: Self.self)
    }
}
