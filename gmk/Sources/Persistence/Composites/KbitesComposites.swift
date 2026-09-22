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

    /// The head projection every list-shaped read of a resource's files rides,
    /// so no caller can widen it back to `resource_file_content` by accident.
    static let fileHeads =
        KbiteResourceRecord.files
        .select(
            Column("uuid"),
            Column("resource_file_name"),
            Column("resource_file_summary"),
            (Column("resource_file_content") != nil).forKey("has_content")
        )
        .order(Column("resource_file_name"))

    static func request() -> QueryInterfaceRequest<Self> {
        KbiteResourceRecord
            .including(all: Self.fileHeads)
            .asRequest(of: Self.self)
    }
}

/// One kbite with everything the export manifest names: its own keyword
/// vocabulary and its resources down to file heads.
///
/// The file heads are the point. An archive walks every file of every
/// resource, and a manifest selecting `resource_file_content` would hold the
/// largest column in the schema in memory for the whole export; the writer
/// fetches each file's content on its own, one row at a time.
struct KbiteWithResources: FetchableRecord, Decodable {
    var kbite: KbiteRecord
    var keywords: [KeywordRecord]
    var resources: [KbiteResourceWithFiles]

    static func request(code: String) -> QueryInterfaceRequest<Self> {
        KbiteRecord
            .filter(KbiteRecord.Columns.code == code)
            .including(all: KbiteRecord.keywords.order(Column("keyword")))
            .including(
                all: KbiteRecord.resources
                    .including(all: KbiteResourceWithFiles.fileHeads)
            )
            .asRequest(of: Self.self)
    }
}

/// What a kbite delete is about to take with it: its resources, the files
/// under them, and the registrations at each of the four scope tiers.
///
/// The file count reaches two tables down, which no association aggregate
/// expresses in one hop, so it stays an annotation.
struct KbiteCounts: FetchableRecord, Decodable {
    var resourceCount: Int
    var fileCount: Int
    var projectRegistrationCount: Int
    var instanceRegistrationCount: Int
    var sessionRegistrationCount: Int
    var promptRegistrationCount: Int

    /// Registrations are counted per tier and summed here: the four tables are
    /// four separate `*_active_kbite` tables, not one polymorphic one.
    var registrationCount: Int {
        projectRegistrationCount + instanceRegistrationCount
            + sessionRegistrationCount + promptRegistrationCount
    }

    private static let fileCount: SQLSelection = SQL(
        sql: """
            (SELECT COUNT(*) FROM kbite_resource_file f
              JOIN kbite_resource r ON r.uuid = f.kbite_resource_uuid
             WHERE r.kbite_uuid = kbite.uuid)
            """
    )
    .forKey("fileCount")

    static func request(kbiteUuid: String) -> QueryInterfaceRequest<Self> {
        KbiteRecord
            .all()
            .withUuid(kbiteUuid)
            .annotated(
                with: KbiteRecord.resources.unordered().count.forKey("resourceCount"),
                KbiteRecord.projectActivations.count.forKey("projectRegistrationCount"),
                KbiteRecord.instanceActivations.count.forKey("instanceRegistrationCount"),
                KbiteRecord.sessionActivations.count.forKey("sessionRegistrationCount"),
                KbiteRecord.promptActivations.count.forKey("promptRegistrationCount")
            )
            .annotated(with: [Self.fileCount])
            .asRequest(of: Self.self)
    }
}

/// The shared-vocabulary keywords tagged on one resource file.
///
/// The junction is the root because the file side of the read is already in
/// hand: only the words are missing.
enum KbiteFileKeywords {
    static func request(fileUuid: String) -> QueryInterfaceRequest<String> {
        let keyword = TableAlias<KeywordRecord>()
        return
            ResourceFileKeywordJunctionRecord
            .filter(ResourceFileKeywordJunctionRecord.Columns.fileUuid == fileUuid)
            .joining(required: ResourceFileKeywordJunctionRecord.keyword.aliased(keyword))
            .order(keyword[KeywordRecord.Columns.keyword])
            .select(keyword[KeywordRecord.Columns.keyword], as: String.self)
    }
}
