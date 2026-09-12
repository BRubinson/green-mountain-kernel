import Foundation
import GMCCDaemonKit

/// DOPE_READ_REPO — parse + validate {instance_root}/.gmcc; never
/// writes. Filesystem access runs OUTSIDE any db lock (see Store+DopeRepo).
enum DopeReadRepoHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(DopeReadRepoRequest.self, from: line)
        return try okResult(.dopeReadRepo, head, try store.dopeReadRepo(request))
    }
}
