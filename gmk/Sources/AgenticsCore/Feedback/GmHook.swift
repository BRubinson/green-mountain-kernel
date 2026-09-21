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

    /// The hook body. NEVER throws and NEVER blocks: a failure path returns
    /// nil, because a hook that exits non-zero blocks the tool call it fired on.
    ///
    /// - Returns: the line to print on stdout, or nil for silence.
    static func run(_ context: GmHookContext) -> String?
}

struct GmHookContext {

    let stdin: Data

    let dryRun: Bool

    /// nil opens a short-lived socket client, which is what the executable does.
    /// The kernel passes its own in-process caller, so a `HOOK_EVENT` served
    /// in-process does not dial the daemon it is already inside.
    let caller: (any GmVerbCaller)?
}

/// The events the plugin hooks. Raw values are the harness's own names, so the
/// same enum is the in-process lookup for `HOOK_EVENT` and the key under which
/// the bridge writes the `hooks.json` group.
enum GmHookEvent: String, CaseIterable, Sendable {

    case preToolUse = "PreToolUse"

    case postToolUse = "PostToolUse"

    case subagentStart = "SubagentStart"

    /// THE REGISTRY. An exhaustive switch rather than a list: a case added
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

    static func readStdin() -> Data {
        FileHandle.standardInput.readDataToEndOfFile()
    }

    /// Whether a shell command line invokes `gm_hook` or any generated hook
    /// executable in COMMAND POSITION — line start, after `;` `&` `|` `(` `` ` ``
    /// `$(`, or after `exec` — never anywhere in the string. `grep gm_hook` is a
    /// mention, and denying it makes this repository undevelopable from its
    /// own tooling. `env X=1 gm_hook` and `bash -c "gm_hook …"` are deliberate
    /// gaps: the guard stops the reach, not a determined circumvention.
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

    /// Claude Code's hook response shape, whose keys are camelCase — so it is
    /// built with JSONSerialization rather than through WireCodec, which
    /// snake_cases everything it touches.
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

    static func encodeJSON<T: Encodable>(_ value: T) -> String? {
        // WireCodec, not a bare JSONEncoder: DTOs carry no CodingKeys, so only
        // the shared snake_case strategy keeps this output matching the wire
        // keys that skills and bot docs grep for.
        guard let data = try? WireCodec.prettyEncoder.encode(value) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Runs `body` against a verb caller, opening a short-lived socket client
    /// only when one was not supplied, and closing only what it opened. It maps
    /// NO error onto an exit code, because a hook has none to map onto.
    ///
    /// THE INJECTED CASE IS NOT AN OPTIMISATION. When the kernel serves
    /// `HOOK_EVENT` it passes its own in-process caller; opening a `DaemonClient`
    /// there would connect the kernel to itself on the serial queue that would
    /// have to answer, which is a deadlock.
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
