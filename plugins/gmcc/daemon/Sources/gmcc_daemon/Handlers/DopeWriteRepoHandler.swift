import Foundation
import GMCCDaemonKit

/// DOPE_WRITE_REPO — db → files via the sandbox's staged atomic swap;
/// refuses when the files are ahead of the db unless forced.
enum DopeWriteRepoHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeWriteRepoRequest.self, from: line)
        return try okResult(.dopeWriteRepo, head, try store.dopeWriteRepo(request))
    }
}
