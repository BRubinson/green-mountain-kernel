// One fully-assembled instruction body, compiled once and handed over as a single string.

import Foundation

/// The compiled instruction for one session profile.
///
/// A profile's instruction is fixed for the life of the session and assembled once,
/// never varying. This ensures the framework's key-value cache, which is keyed on
/// instruction body, is not discarded across the session.
struct AgentGmkInstruction: Sendable, Hashable {

    let text: String

    /// Creates an instruction with the given text.
    ///
    /// - Parameter text: The instruction body text.
    init(_ text: String) {
        self.text = text
    }
}
