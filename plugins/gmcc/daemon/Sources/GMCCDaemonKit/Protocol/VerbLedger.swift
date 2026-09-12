import Foundation

/// The verb registry in machine-readable form: every MessageType the daemon
/// serves, which pen tool covers it, and whether it is a read or a write.
///
/// HOISTED TO THE KIT so any front-end can print it without a Store and
/// without a socket — `gmcc_hook verbs` is the reader, and it answers even
/// when the daemon is down.
///
/// It classifies; it does not authorize. Nothing consults this to refuse a
/// caller.
public enum VerbLedger {

    /// ONE ROW PER INVOCATION SPELLING, not per MessageType. A verb with aliases
    /// emits one row each, all carrying the same message type, role and pen
    /// tool — which is what lets the guard match on a flat list and still see
    /// every spelling.
    public struct VerbRow: Encodable, Sendable {
        public let messageType: String
        public let gm: String
        public let penTool: String?
        /// record | read
        public let role: String
        /// Is this a write?
        public let write: Bool
        /// False for the canonical spelling, true for an alias of it.
        public let alias: Bool
        /// The canonical spelling this row belongs to (== `gm` when canonical).
        public let canonicalGm: String
    }

    public struct Payload: Encodable, Sendable {
        public let verbs: [VerbRow]
        /// invocation -> pen tool, for every write that HAS one, aliases
        /// included.
        public let penReplacements: [String: String]
        /// The four pen tools the workflow's methodology reserves for the
        /// primary — guidance, never a refusal.
        public let primaryPenTools: [String]
    }

    public static func build(writesOnly: Bool = false) -> Payload {
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
                if isWrite, let pen = spec.penTool { replacements[invocation] = pen }
                guard !writesOnly || isWrite else { continue }
                rows.append(VerbRow(
                    messageType: spec.messageType.rawValue,
                    gm: invocation,
                    penTool: spec.penTool,
                    role: role,
                    write: isWrite,
                    alias: index > 0,
                    canonicalGm: spec.gmInvocation))
            }
        }
        return Payload(
            verbs: rows.sorted { $0.gm < $1.gm },
            penReplacements: replacements,
            primaryPenTools: VerbRegistry.primaryPenTools.sorted())
    }
}
