import Foundation

/// One Claude Code hook the plugin serves: the event it answers, the shape of
/// its `hooks.json` entry, and the body that runs when the harness fires it.
///
/// A conformer is BOTH the kernel-side handler (`HookEventHandler` dispatches
/// to it in-process) and the whole body of one generated executable under the
/// plugin's `hooks/bin/` (`main()` below). The `hooks.json` command that names
/// that executable is rendered from `event` and `binaryName`, so the manifest
/// cannot name an event this code does not handle.
protocol GmHook {

    static var event: GmHookEvent { get }

    /// The `matcher` field, or nil for events that take none.
    static var matcher: String? { get }

    static var timeout: Int? { get }

    static var isAsync: Bool { get }

    /// The hook body, returning the stdout line or nil for silence.
    ///
    /// NEVER throws and NEVER blocks: a failure path returns nil, because a
    /// hook that exits non-zero blocks the tool call it fired on.
    ///
    /// - Parameter context: The hook context with stdin, dry-run flag, and optional caller.
    /// - Returns: the line to print on stdout, or nil for silence.
    static func run(_ context: GmHookContext) -> String?
}

struct GmHookContext {

    let stdin: Data

    let dryRun: Bool

    /// nil opens a short-lived socket client, which is what the executable does.
    ///
    /// The kernel passes its own in-process caller, so a `HOOK_EVENT` served
    /// in-process does not dial the daemon it is already inside.
    let caller: (any GmVerbCaller)?
}

/// The events the plugin hooks.
///
/// Raw values are the harness's own names, so the
/// same enum is the in-process lookup for `HOOK_EVENT` and the key under which
/// the bridge writes the `hooks.json` group.
enum GmHookEvent: String, CaseIterable, Sendable {

    case preToolUse = "PreToolUse"

    case postToolUse = "PostToolUse"

    case subagentStart = "SubagentStart"

    /// THE REGISTRY.
    ///
    /// An exhaustive switch rather than a list: a case added
    /// without a handler does not compile, where an unlisted handler would
    /// be silent.
    var hook: any GmHook.Type {
        switch self {
        case .preToolUse: return PreToolUseHook.self
        case .postToolUse: return PostToolUseHook.self
        case .subagentStart: return SubagentStartHook.self
        }
    }

    /// The generated executable's name: `gm_hook_post_tool_use`.
    var binaryName: String { "gm_hook_" + Self.snakeCase(rawValue) }

    /// Convert camelCase text to snake_case.
    ///
    /// - Parameter text: The camelCase text.
    /// - Returns: The text in snake_case.
    private static func snakeCase(_ text: String) -> String {
        var out = ""
        for (index, scalar) in text.unicodeScalars.enumerated() {
            if CharacterSet.uppercaseLetters.contains(scalar), index > 0 { out.append("_") }
            out.unicodeScalars.append(scalar)
        }
        return out.lowercased()
    }
}

extension GmHook {

    static var matcher: String? { nil }

    static var timeout: Int? { nil }

    static var isAsync: Bool { false }

    static var binaryName: String { event.binaryName }

    /// The executable's entire body, shared by every generated main.
    ///
    /// The hook contract lives HERE and nowhere else: read stdin once, honour
    /// `--dry-run`, print at most one line, write nothing to stderr, exit 0.
    static func main() -> Never {
        let dryRun = CommandLine.arguments.dropFirst().contains("--dry-run")
        let context = GmHookContext(stdin: GmHookSupport.readStdin(), dryRun: dryRun, caller: nil)
        if let line = run(context) {
            FileHandle.standardOutput.write(Data((line + "\n").utf8))
        }
        exit(0)
    }
}

/// Helpers every handler shares.
enum GmHookSupport {

    /// Read all available data from standard input.
    ///
    /// - Returns: The stdin data.
    static func readStdin() -> Data {
        FileHandle.standardInput.readDataToEndOfFile()
    }

    /// Whether a shell command invokes `gm_hook` in command position.
    ///
    /// Detects invocation at line start, after `;` `&` `|` `(` `` ` `` `$(`, or
    /// after `exec` — never anywhere in the string. `grep gm_hook` is a mention
    /// and is not denied, as that would make this repository undevelopable from
    /// its own tooling. `env X=1 gm_hook` and `bash -c "gm_hook …"` are
    /// deliberate gaps: the guard stops the reach, not a determined circumvention.
    ///
    /// - Parameter command: The shell command line.
    /// - Returns: `true` if `gm_hook` is invoked in command position.
    static func invokesGmHook(_ command: String) -> Bool {
        command.range(of: denyPattern, options: .regularExpression) != nil
    }

    /// Built from the registry, longest name first, so a hook executable added
    /// tomorrow is denied the day it exists.
    private static let denyPattern: String = {
        let names = (GmHookEvent.allCases.map(\.binaryName) + ["gm_hook"])
            .sorted { $0.count > $1.count }
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        // The optional quote is the hook launcher's own spelling pasted back.
        return #"(?:^|[;&|(`]|\$\(|\bexec)\s*(?:\S*/)?(?:"# + names + #")["']?(?=\s|$)"#
    }()

    /// Format a hook response line in Claude Code's hook response shape.
    ///
    /// Keys are camelCase, so it is built with JSONSerialization rather than
    /// through WireCodec, which snake_cases everything it touches.
    ///
    /// - Parameters:
    ///   - event: The hook event.
    ///   - context: The additional context string.
    /// - Returns: A JSON-encoded response line, or `nil` if encoding fails.
    static func additionalContextLine(event: GmHookEvent, _ context: String) -> String? {
        let response: [String: Any] = [
            "hookSpecificOutput": [
                "hookEventName": event.rawValue,
                "additionalContext": context,
            ]
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: response) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Encode a value to JSON using WireCodec snake_case encoding.
    ///
    /// DTOs carry no CodingKeys, so only the shared snake_case strategy keeps
    /// this output matching the wire keys that skills and bot docs grep for.
    ///
    /// - Parameter value: The encodable value.
    /// - Returns: The pretty-printed JSON string, or `nil` if encoding fails.
    static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        // WireCodec, not a bare JSONEncoder: DTOs carry no CodingKeys, so only
        // the shared snake_case strategy keeps this output matching the wire
        // keys that skills and bot docs grep for.
        guard let data = try? WireCodec.prettyEncoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Run a body function with a verb caller, managing a socket client if needed.
    ///
    /// Opens a short-lived socket client only when one was not supplied, and
    /// closes only what it opened. Maps no error onto exit code (hooks have none
    /// to map). The kernel's in-process caller prevents a deadlock from opening
    /// a `DaemonClient` that would connect the kernel to itself.
    ///
    /// - Parameters:
    ///   - caller: An optional verb caller, or `nil` to open a socket client.
    ///   - body: The function to run with the caller.
    /// - Returns: The result of calling `body`.
    /// - Throws: Any error from the body function.
    static func withKitClient<T>(
        _ caller: (any GmVerbCaller)?,
        _ body: (any GmVerbCaller) throws -> T
    ) throws -> T {
        if let caller { return try body(caller) }
        let client = DaemonClient()
        defer { client.close() }
        return try body(client)
    }
}
