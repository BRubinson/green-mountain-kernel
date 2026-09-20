import Foundation

/// The verb registry in machine-readable form: every MessageType the daemon
/// serves, which pen tool covers it, and whether it is a read or a write.
///
/// It lives in the kit so a front-end can print it with no Store and no
/// socket, answering even when the daemon is down. It classifies; it does not
/// authorize, and nothing consults it to refuse a caller.
enum VerbLedger {

    /// ONE ROW PER INVOCATION SPELLING, not per MessageType. A verb with aliases
    /// emits one row each, all carrying the same message type, role and pen
    /// tool — which is what lets the guard match on a flat list and still see
    /// every spelling.
    struct VerbRow: Encodable, Sendable {
        let messageType: String
        let gm: String
        let cdeTool: String?
        /// record | read
        let role: String
        /// Is this a write?
        let write: Bool
        /// False for the canonical spelling, true for an alias of it.
        let alias: Bool
        /// The canonical spelling this row belongs to (== `gm` when canonical).
        let canonicalGm: String
    }

    struct Payload: Encodable, Sendable {
        let verbs: [VerbRow]
        /// invocation -> pen tool, for every write that HAS one, aliases
        /// included.
        let cdeReplacements: [String: String]
        /// The four pen tools the workflow's methodology reserves for the
        /// primary — guidance, never a refusal.
        let primaryPenTools: [String]
    }

    static func build(writesOnly: Bool = false) -> Payload {
        var rows: [VerbRow] = []
        var replacements: [String: String] = [:]
        for spec in VerbRegistry.all {
            let role: String
            let isWrite: Bool
            switch spec.role {
            case .record:
                role = "record"
                isWrite = true
            case .read:
                role = "read"
                isWrite = false
            }
            for (index, invocation) in spec.gmInvocations.enumerated() {
                if isWrite, let pen = spec.cdeTool { replacements[invocation] = pen }
                guard !writesOnly || isWrite else { continue }
                rows.append(
                    VerbRow(
                        messageType: spec.messageType.rawValue,
                        gm: invocation,
                        cdeTool: spec.cdeTool,
                        role: role,
                        write: isWrite,
                        alias: index > 0,
                        canonicalGm: spec.gmInvocation
                    )
                )
            }
        }
        return Payload(
            verbs: rows.sorted { $0.gm < $1.gm },
            cdeReplacements: replacements,
            primaryPenTools: VerbRegistry.primaryPenTools.sorted()
        )
    }
}
