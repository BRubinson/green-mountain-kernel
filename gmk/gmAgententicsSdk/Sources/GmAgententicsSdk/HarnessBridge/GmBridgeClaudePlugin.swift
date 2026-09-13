import Foundation
import GmDaemonSdk

extension GmBridgeClaudePlugin {

    public static let current = File(
        name: "gmcc",
        version: GmVersion.current,
        description: """
            Green Mountain Coding Collection — a harness integration for the \
            Green Mountain Kernel, bringing integrated, opinionated coding \
            practices.
            """
    )
}
