import Foundation

/// The kernel binary's personalities, keyed by the name it is invoked under.
///
/// THE REGISTRY. Raw values are the invoked names; `run` is an exhaustive
/// switch, so a personality without a body does not compile. The subcommand
/// spelling (`gm_kernel hook`) is the same word without the `gm_` prefix and
/// exists for discoverability — argv[0] dispatch is invisible to anyone reading
/// `--help` — and it collides with none of `gm_hook`'s own first arguments.
/// None of them writes the database: the app is the only kernel host.
enum GmPersonality: String, CaseIterable, Sendable {

    /// The pen server: JSON-RPC 2.0 over stdio, spawned per Claude session by
    /// the harness. Shipped INSIDE the plugin as `bin/gm_mcp`.
    case mcp = "gm_mcp"

    /// The shell-callable client: SessionStart provisioning, kernel lifecycle,
    /// the raw-wire passthrough. Shipped INSIDE the plugin as `bin/gm_hook`.
    case hook = "gm_hook"

    /// The plugin generator: `gm_kernel bridge [--check] <plugin-dir>`.
    case bridge = "gm_bridge"

    enum Distribution: Sendable {
        /// Compiled with the client closure and committed under `plugins/gmcc/bin`.
        case plugin
        /// Reached only as a subcommand of the built kernel.
        case buildOnly
    }

    var distribution: Distribution {
        switch self {
        case .mcp, .hook: return .plugin
        case .bridge: return .buildOnly
        }
    }

    /// `hook` for `gm_hook`.
    var subcommand: String { String(rawValue.dropFirst(Self.prefix.count)) }

    private static let prefix = "gm_"

    var summary: String {
        switch self {
        case .mcp:
            return "the pen server, JSON-RPC 2.0 over stdio; ships in the plugin's bin/"
        case .hook:
            return "the shell-callable client and raw-wire passthrough; ships in the plugin's bin/"
        case .bridge:
            return "the plugin generator: gm_kernel bridge [--check] <plugin-dir>"
        }
    }

    /// Resolve a personality from command arguments.
    ///
    /// argv[0] WINS over argv[1]: `gm_hook call BACKUP` arrives with argv[1] ==
    /// "call", so a subcommand-first rule would dispatch `call` as a personality.
    ///
    /// - Parameter arguments: The command arguments.
    /// - Returns: The personality and its argv, or `nil` if not recognized.
    static func resolve(_ arguments: [String]) -> (GmPersonality, [String])? {
        let invokedAs = URL(fileURLWithPath: arguments.first ?? "").lastPathComponent
        if let personality = GmPersonality(rawValue: invokedAs) {
            return (personality, Array(arguments.dropFirst()))
        }
        if let sub = arguments.dropFirst().first,
            let personality = GmPersonality(rawValue: prefix + sub)
        {
            return (personality, Array(arguments.dropFirst(2)))
        }
        return nil
    }

    /// Run this personality with the argv that follows it.
    ///
    /// Never returns.
    ///
    /// - Parameter argv: The command arguments for this personality.
    func run(_ argv: [String]) -> Never {
        switch self {
        case .mcp:
            MainActor.assumeIsolated { GmMcpServer.main() }
            exit(0)
        case .hook:
            HookCli.main(argv)
        case .bridge:
            GmBridgeCli.main(argv)
        }
    }

    /// The one-line call a generated standalone main makes, for `.plugin`
    /// personalities. nil for the rest: they are not compiled on their own.
    var standaloneEntry: String? {
        switch self {
        case .mcp: return "MainActor.assumeIsolated { GmMcpServer.main() }; exit(0)"
        case .hook: return "HookCli.main()"
        case .bridge: return nil
        }
    }

    /// Source folders under gmk/Sources that a `.plugin` personality needs
    /// beyond the base client closure.
    var closureFolders: [String] {
        switch self {
        case .mcp: return ["API/Clients/GmKernelCoreClient/GmMcpServer"]
        case .hook: return ["API/Clients/GmKernelCoreClient/HookCli"]
        case .bridge: return []
        }
    }

    static var usage: String {
        let rows = allCases.map { p in
            "  \(p.subcommand.padding(toLength: 10, withPad: " ", startingAt: 0)) \(p.summary). Also reached as `\(p.rawValue)`."
        }
        return """
            gm_kernel — the GM kernel binary. One Mach-O, typed personalities.

            USAGE
              gm_kernel <personality> [args...]
              <personality>                     (via the name it is invoked under)

            PERSONALITIES
            \(rows.joined(separator: "\n"))

              --version  protocol version
              --help     this text

            The invoked NAME is consulted before any argument: `gm_hook call BACKUP` has
            "call" as its first argument. No personality writes the database: the only
            writer is gm_kernel.app, which clients launch through LaunchServices when the
            socket is dead. A bare `gm_kernel` outside an app bundle exits 2 and opens nothing.

            """
    }
}
