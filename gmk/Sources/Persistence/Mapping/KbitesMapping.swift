// db → wire for the kbite composites and records.
//
// This is the only place a persistence type and a wire Row meet. Wire Rows
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension KbiteRecord {
    /// Converts the record to its wire representation.
    ///
    /// - Returns: The wire row for this kbite.
    func dto() -> KbiteRow {
        KbiteRow(
            uuid: uuid,
            version: version,
            code: code,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

extension KbiteResourceWithFiles {
    /// Converts the resource and its files to their wire representation.
    ///
    /// `resourceTrust` is narrowed from Int64 to the wire's Int.
    ///
    /// - Returns: The wire row for this resource with its files.
    func dto() -> KbiteResourceRow {
        KbiteResourceRow(
            uuid: resource.uuid,
            kbiteUuid: resource.kbiteUuid,
            resourceName: resource.resourceName,
            resourceSummary: resource.resourceSummary,
            resourceType: resource.resourceType,
            resourceTrust: Int(resource.resourceTrust),
            files: files.map { $0.dto() }
        )
    }
}

extension KbiteResourceFileHead {
    /// Converts the file header to its wire stub form.
    ///
    /// - Returns: The wire stub for this resource file.
    func dto() -> KbiteResourceFileStub {
        KbiteResourceFileStub(
            uuid: uuid,
            resourceFileName: resourceFileName,
            resourceFileSummary: resourceFileSummary,
            hasContent: hasContent
        )
    }
}

extension KbiteResourceFileRecord {
    /// Converts the record to its wire row form with full content.
    ///
    /// The full-content shape, reached only by KBITE_FILE_GET. Listing paths
    /// go through `KbiteResourceFileHead` instead.
    ///
    /// - Returns: The wire row for this resource file.
    func dto() -> KbiteResourceFileRow {
        KbiteResourceFileRow(
            uuid: uuid,
            kbiteResourceUuid: kbiteResourceUuid,
            resourceFileName: resourceFileName,
            resourceFileSummary: resourceFileSummary,
            resourceFileContent: resourceFileContent,
            createdAt: createdAt
        )
    }
}
