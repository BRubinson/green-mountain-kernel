import Foundation
import GMCCDaemonKit

/// EXPLORE_FINDING_ADD — insert a finding (rating optional; NULL = unranked work-in-progress).
enum ExploreFindingAddHandler {
    static func handle(line: Data, head: EnvelopeHead, store: Store) throws -> HandlerResult {
        let request = try decodePayload(ExploreFindingAddRequest.self, from: line)
        return try okResult(.exploreFindingAdd, head, try store.exploreFindingAdd(request))
    }
}
