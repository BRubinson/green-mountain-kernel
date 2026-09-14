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
        // NO `outputStyles:` KEY. It is not part of the plugin manifest schema,
        // and emitting it does not degrade gracefully — Claude Code REJECTS the
        // whole manifest with "outputStyles: Invalid input", which disables the
        // entire plugin rather than just ignoring the key.
        //
        // A plugin ships output styles by PUTTING THEM IN `output-styles/`, and
        // nothing announces them in the manifest. Auto-application is the style
        // file's own business: `force-for-plugin: true` in its frontmatter is
        // what applies it whenever the plugin is enabled. See
        // GmBridgeOutputStyle.all, whose primarch style already carries it.
    )
}
