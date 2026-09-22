// db → wire for the kbite composites and records.
//
// This is the only place a persistence type and a wire Row meet. Wire Rows
// carry no GRDB conformance and no custom decoder; a record hands one over
// through `dto()` and nothing else.

import Foundation

extension KbiteRecord {
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
    /// `resourceTrust` narrows Int64 to the wire's Int.
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
    /// The full-content shape, reached only by KBITE_FILE_GET. Listing paths
    /// go through `KbiteResourceFileHead` instead.
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
