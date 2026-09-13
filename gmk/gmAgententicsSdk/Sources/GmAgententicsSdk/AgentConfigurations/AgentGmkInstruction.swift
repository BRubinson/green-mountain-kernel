// One fully-assembled instruction body, compiled once and handed over as a single string.

import Foundation

/// The compiled instruction for one session profile.
///
/// This replaced `AgentPhaseInstructions`, which was a `DynamicInstructions`
/// rebuilt on every phase change. Rebuilding was the problem: the framework's
/// key-value cache is keyed on the instruction body, so a body that changes at
/// each phase throws the cache away silently. A profile's instruction is fixed
/// for the life of the session, so it is assembled once and never varies.
struct AgentGmkInstruction: Sendable, Hashable {

    let text: String

    init(_ text: String) {
        self.text = text
    }
}
