import Foundation

// Hoisted VERBATIM out of Sources/gm/Commands/Hook.swift. This block is the
// parser-free half of the hook surface — payload decoding, sandbox adoption,
// write-target resolution, and the Bash command scanner — and it moved to the
// kit so both the shell client and anything else that must speak the hook
// contract share ONE implementation. Two copies of a write-path scanner drift
// apart in exactly the way that makes capture silently stop capturing.
//
// Types stay INTERNAL: HookRunner (same module) is the only caller that needs
// them, and the tests reach them through @testable import GMCCDaemonKit.

// MARK: - Dry-run reports

/// What `--dry-run` prints: the resolved roots plus the exact payloads the
/// live path would send. The flag is load-bearing rather than a convenience —
/// capture is proven through it before a hook script points at any of this.
struct HookDryRun: Encodable {
    let event: String
    let repoRoot: String
    /// The runtime this write would land in. A sandbox session whose marker
    /// was missed prints the prod root here, which is the single most
    /// valuable thing this flag can tell its reader.
    let gmccRoot: String
    let changes: [FileChangeAdd]
}

struct SubagentStartDryRun: Encodable {
    let event: String
    let gmccRoot: String
    let registration: AgentRegisterRequest?
}

private func readStdin() -> Data {
    FileHandle.standardInput.readDataToEndOfFile()
}

// MARK: - The payload

/// One Claude Code hook payload, decoded from the raw JSON on stdin.
///
/// EVERY FIELD IS OPTIONAL AND EVERY DECODE IS TOLERANT. The payload shape
/// varies by event and by tool — `tool_response` is an object for Edit and a
/// different object for Bash, and other tools return a bare string — so a
/// strict decode would throw on a sibling field and lose a change that was
/// perfectly recordable. A missing field means "not recorded", never "fail".
///
/// Keys are spelled out literally instead of going through a key strategy:
/// the top level is snake_case and `structuredPatch` inside `tool_response` is
/// camelCase, and no single strategy reads both.
/// PUBLIC ONLY WHERE A FRONT-END GENUINELY NEEDS IT. `decode` and `sessionId`
/// are exposed because SessionStart's context-ensure rides the same payload and
/// must read the conversation id out of it; everything else stays internal, so
/// the kit's hook surface cannot be reached around through its own data types.
public struct HookPayload: Equatable {
    public let sessionId: String?
    let hookEventName: String?
    let cwd: String?
    let transcriptPath: String?
    let permissionMode: String?
    let toolName: String?
    let toolUseId: String?
    let durationMs: Int?
    /// THE TRAP. The payload field is named `prompt_id` and it is Claude
    /// Code's TURN id — it has nothing to do with a gmcc prompt uuid. It
    /// carries the distinct name from the moment it is decoded, so the
    /// confusion has nowhere to start.
    let claudeTurnId: String?
    /// PRESENT for every spawned agent, ABSENT for the primary. That absence
    /// is the discriminator — there is no heuristic anywhere in this path.
    let agentId: String?
    /// A LABEL, never a role: it is the subagent_type for a plain subagent,
    /// the literal `workflow-subagent` for a bare workflow agent, and the
    /// NAME for a named teammate. Authority comes from AGENT_REGISTER.
    let agentType: String?
    let filePath: String?
    let notebookPath: String?
    let command: String?
    let structuredPatch: [StructuredPatchHunk]

    public static func decode(_ data: Data) -> HookPayload? {
        guard !data.isEmpty,
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let input = root["tool_input"] as? [String: Any] ?? [:]
        let response = root["tool_response"] as? [String: Any] ?? [:]
        return HookPayload(
            sessionId: string(root["session_id"]),
            hookEventName: string(root["hook_event_name"]),
            cwd: string(root["cwd"]),
            transcriptPath: string(root["transcript_path"]),
            permissionMode: string(root["permission_mode"]),
            toolName: string(root["tool_name"]),
            toolUseId: string(root["tool_use_id"]),
            durationMs: (root["duration_ms"] as? NSNumber)?.intValue,
            claudeTurnId: string(root["prompt_id"]),
            agentId: string(root["agent_id"]),
            agentType: string(root["agent_type"]),
            filePath: string(input["file_path"]),
            notebookPath: string(input["notebook_path"]),
            command: string(input["command"]),
            structuredPatch: hunks(response["structuredPatch"]))
    }

    /// Empty strings are absences. Claude Code omits a field it has no value
    /// for, but a shim that re-serialises a payload can turn the omission
    /// into `""`, and an empty session_id must not look like a conversation.
    private static func string(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        return text
    }

    /// structuredPatch, decoded through the plain-JSON path its camelCase
    /// keys need. A malformed or absent patch is no ranges, never a failure.
    private static func hunks(_ value: Any?) -> [StructuredPatchHunk] {
        guard let array = value as? [Any],
              let data = try? JSONSerialization.data(withJSONObject: array),
              let decoded = try? JSONDecoder().decode([StructuredPatchHunk].self, from: data)
        else { return [] }
        return decoded
    }
}

// MARK: - The sandbox marker

/// Adopt a snapshot's runtime when the hook fires inside one.
///
/// WITHOUT THIS A SANDBOX SESSION'S HOOKS WRITE THE PROD DB. Sandbox sessions
/// used to be told which runtime they were in by an inherited GMCC_ROOT; a
/// hook that reads no inherited env has to find that out for itself, and the
/// marker on disk is the thing that knows. This is the hazard that removing
/// env inheritance creates, closed at the same time.
///
/// The parse matches gmcc_session_startup.sh's: the marker is read as DATA,
/// never sourced — a file that lives in a repo must not get shell execution
/// out of a hook. The walk starts at the payload's cwd and climbs, so a tool
/// call made in a subdirectory of the snapshot finds the marker at its root.
enum SandboxMarker {
    static let fileName = ".gmcc_sandbox"

    /// No-op when GMCC_ROOT is already set: an explicit runtime always wins,
    /// and a sandbox launcher sets it before any client ever runs.
    static func adopt(startingAt directory: String) {
        let env = ProcessInfo.processInfo.environment
        guard env["GMCC_ROOT"].map({ $0.isEmpty }) ?? true else { return }
        guard let roots = find(startingAt: directory) else { return }
        if let root = roots.gmccRoot { setenv("GMCC_ROOT", root, 1) }
        if let ckfs = roots.ckfsRoot { setenv("GMCC_CKFS_ROOT", ckfs, 1) }
    }

    struct Roots: Equatable {
        let gmccRoot: String?
        let ckfsRoot: String?
    }

    /// The nearest marker at or above `directory`, parsed. nil when there is
    /// none — the ordinary case, since almost every repo is not a snapshot.
    static func find(startingAt directory: String) -> Roots? {
        var url = URL(fileURLWithPath: directory, isDirectory: true).standardizedFileURL
        while url.path != "/" {
            let marker = url.appendingPathComponent(fileName)
            if let text = try? String(contentsOf: marker, encoding: .utf8) {
                return parse(text)
            }
            url = url.deletingLastPathComponent()
        }
        return nil
    }

    /// `export NAME="value"` lines, first wins — the same shape the sandbox
    /// snapshot writes and the same two names it writes.
    static func parse(_ text: String) -> Roots {
        func value(_ name: String) -> String? {
            let prefix = "export \(name)=\""
            for line in text.split(separator: "\n") {
                let line = line.trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix(prefix), line.hasSuffix("\"") else { continue }
                let value = String(line.dropFirst(prefix.count).dropLast())
                return value.isEmpty ? nil : value
            }
            return nil
        }
        return Roots(gmccRoot: value("GMCC_ROOT"), ckfsRoot: value("GMCC_CKFS_ROOT"))
    }
}

// MARK: - What a tool call wrote

/// One recordable change: a repo-relative path, the kind it landed as, and
/// how honestly it was derived.
struct HookWriteTarget: Equatable {
    let relativePath: String
    let changeKind: ChangeKind
    /// `hook` for an exact payload-named path, `command` for one inferred
    /// from a Bash command line. The distinction is kept all the way to the
    /// column so an inference is never indistinguishable from an exact row.
    let origin: String
    let ranges: [ChangeRange]
}

enum HookWriteTargets {
    /// THE TOOL ALLOWLIST. Only these four tools produce rows, by name.
    ///
    /// A permissive rule — "any payload carrying a file_path" — would record
    /// a change for a tool that only READ the file, and a wrong row is worse
    /// than a missing one: an absent row is detectable at a gate and a wrong
    /// one poisons the record the workflow machine reasons from. The hook
    /// manifest's matcher decides what fires; this decides what counts.
    /// Can this payload name a write AT ALL, without asking git?
    ///
    /// Mirrors `resolve`'s tool allowlist using only work that costs no
    /// subprocess: a declared path is a field read, and the Bash allowlist is
    /// pure string scanning over the command line. A `true` here is not a
    /// promise that a row lands — git may still classify the path away — it
    /// only means the expensive path is worth entering.
    static func mayHaveTargets(payload: HookPayload) -> Bool {
        switch payload.toolName {
        case "Edit", "Write", "NotebookEdit":
            return (payload.filePath ?? payload.notebookPath) != nil
        case "Bash":
            guard let command = payload.command, let cwd = payload.cwd else { return false }
            return !BashWritePaths.extract(command: command, cwd: cwd).isEmpty
        default:
            return false
        }
    }

    static func resolve(payload: HookPayload, repoRoot: String) -> [HookWriteTarget] {
        switch payload.toolName {
        case "Edit", "Write", "NotebookEdit":
            return declaredPath(payload: payload, repoRoot: repoRoot)
        case "Bash":
            return commandPaths(payload: payload, repoRoot: repoRoot)
        default:
            return []
        }
    }

    /// The exact case: the tool NAMED its file and the payload carries the
    /// hunks it wrote, so both the path and the line ranges are facts rather
    /// than inferences.
    private static func declaredPath(
        payload: HookPayload, repoRoot: String
    ) -> [HookWriteTarget] {
        guard let absolute = payload.filePath ?? payload.notebookPath,
              let relativePath = GitPathClassifier.repoRelative(absolute, repoRoot: repoRoot)
        else { return [] }
        // Edit and NotebookEdit cannot bring a file into existence, so their
        // kind is settled without asking git. Write can, and git is the only
        // thing that knows whether this path is new.
        let changeKind: ChangeKind = payload.toolName == "Write"
            ? GitPathClassifier.classify(
                relativePath: relativePath, repoRoot: repoRoot, declared: .write) ?? .create
            : .edit
        return [HookWriteTarget(
            relativePath: relativePath,
            changeKind: changeKind,
            origin: FileChangeOrigin.hook,
            ranges: StructuredPatchExpander.expand(payload.structuredPatch))]
    }

    /// The inferred case: paths the command NAMED, classified by git. No
    /// ranges — a command line says nothing about line numbers, and a
    /// fabricated range would be worse than none.
    private static func commandPaths(
        payload: HookPayload, repoRoot: String
    ) -> [HookWriteTarget] {
        guard let command = payload.command, let cwd = payload.cwd else { return [] }
        return BashWritePaths.extract(command: command, cwd: cwd).compactMap { target in
            guard let relativePath = GitPathClassifier.repoRelative(
                    target.path, repoRoot: repoRoot),
                  let changeKind = GitPathClassifier.classify(
                    relativePath: relativePath, repoRoot: repoRoot, declared: target.intent)
            else { return nil }
            return HookWriteTarget(
                relativePath: relativePath,
                changeKind: changeKind,
                origin: FileChangeOrigin.command,
                ranges: [])
        }
    }
}

// MARK: - The Bash write allowlist

/// THE PATHS A BASH COMMAND NAMED — and nothing else.
///
/// WHAT THIS IS. A named allowlist over the command line. Each recorded form
/// below is a shape whose write TARGET is stated in the command itself:
///
///     >  FILE   and  >>  FILE     (unquoted redirections)
///     tee [-a] FILE...
///     sed -i[SUFFIX] ... FILE...        perl -i... ... FILE...
///     cp / install / ln SRC... DST  →  DST
///     mv SRC... DST                 →  DST written, every SRC deleted
///     rm [-rf] FILE...              →  deleted
///     touch FILE...
///
/// WHAT IT RECORDS NOTHING FOR, AS A DOCUMENTED GAP: every interpreter
/// heredoc (`python - <<EOF`), `make`, `./script.sh`, `git apply`, unbalanced
/// quotes, and any target spelled with an unexpanded `$VAR` or a glob. Those
/// produce ZERO rows, silently. This is a known-incomplete capture surface,
/// and it is named here rather than discovered at the first gate that blocks.
///
/// IT IS NOT A DIFF ENGINE. It holds no baseline, no cursor, no lock and no
/// compare-and-swap, and it has nothing to advance. Its one use of git is a
/// PATH-LIMITED `git status --porcelain -- <path>` that CLASSIFIES a path the
/// command already named. It CANNOT DISCOVER A PATH. The next reader's first
/// instinct will be that the delta engine came back through git; it did not,
/// and this is the paragraph that says so.
///
/// IT THEREFORE CANNOT MISATTRIBUTE, which is the whole reason this mechanism
/// was chosen. The designs it beat derived a write WINDOW from the payload's
/// `duration_ms` and intersected it with a git listing; under the parallel
/// fan-out this system runs by default, another agent's edit lands inside that
/// window and is attributed to this command's agent. An absent row is
/// detectable at a gate; a wrong row is not, and it poisons the record.
///
/// The segmenting rules are ported from the PreToolUse write guard's proven
/// scanner: quoting is tracked, separators split only outside quotes, and
/// every failure mode of the parse lands on "record nothing".
enum BashWritePaths {
    struct Target: Equatable {
        let path: String
        let intent: Intent
    }

    /// What the COMMAND meant to do with a path. git has the last word on the
    /// kind; this is what it falls back to when git has nothing to say.
    enum Intent: Equatable {
        case write
        case delete
    }

    /// A single command line cannot legitimately name more paths than this.
    /// file_change is append-only history, so a pathological command (a
    /// generated `rm` list) would be permanent.
    static let maxTargets = 100

    /// Transparent wrappers: the real command is the next word. Ported from
    /// the write guard's peel loop, which faces the identical problem.
    private static let wrappers: Set<String> = ["env", "command", "nohup", "time", "exec"]

    static func extract(command: String, cwd: String) -> [Target] {
        guard let segments = BashCommandScanner.segments(command) else { return [] }
        var targets: [Target] = []
        for segment in segments {
            let (words, redirections) = BashCommandScanner.split(segment)
            // Redirections are scanned for EVERY segment, whatever the
            // command is: `>` is the shell's write, not the program's.
            for path in redirections { targets.append(Target(path: path, intent: .write)) }
            targets += commandTargets(peeled(words), cwd: cwd)
        }
        return resolve(targets, cwd: cwd)
    }

    /// Peel leading `NAME=value` assignments and transparent wrappers so
    /// `FOO=1 env sed -i …` reaches the same dispatch as a bare `sed -i …`.
    private static func peeled(_ words: [String]) -> [String] {
        var words = words
        while let first = words.first, isAssignment(first) || wrappers.contains(first) {
            words.removeFirst()
        }
        return words
    }

    /// THE ASSIGNMENT TEST LOOKS AT ONE WORD. "contains an `=`" is not the
    /// test — a `--body "rating=0"` argument contains one, and peeling on
    /// that would eat the command word.
    private static func isAssignment(_ word: String) -> Bool {
        guard let split = word.firstIndex(of: "=") else { return false }
        let name = word[word.startIndex..<split]
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    private static func commandTargets(_ words: [String], cwd: String) -> [Target] {
        guard let command = words.first.map(basename) else { return [] }
        let rest = Array(words.dropFirst())
        switch command {
        case "tee":
            // Every non-option argument is written. -a/-i are the only flags
            // tee takes that matter, and both are argument-less.
            return operands(rest).map { Target(path: $0, intent: .write) }
        case "sed":
            // `-e`/`-f` supply the script; `-l` takes a line length. Without
            // one of the script options the FIRST positional is the script,
            // which is the rule sed itself uses.
            let parsed = scanOptions(rest, argumentTaking: ["e", "f", "l"])
            guard parsed.inPlace else { return [] }
            let scriptSupplied = parsed.flags.contains("e") || parsed.flags.contains("f")
            let files = scriptSupplied ? parsed.positionals : Array(parsed.positionals.dropFirst())
            return files.map { Target(path: $0, intent: .write) }
        case "perl":
            // `-e`/`-E` carry the program; everything positional after the
            // options is a file.
            let parsed = scanOptions(rest, argumentTaking: ["e", "E"])
            guard parsed.inPlace else { return [] }
            return parsed.positionals.map { Target(path: $0, intent: .write) }
        case "cp", "install", "ln":
            // The DESTINATION is what changes; the sources are read.
            let operands = operands(rest)
            guard operands.count >= 2, let destination = operands.last else { return [] }
            return destinations(
                sources: operands.dropLast(), destination: destination, cwd: cwd)
                .map { Target(path: $0, intent: .write) }
        case "mv":
            let operands = operands(rest)
            guard operands.count >= 2, let destination = operands.last else { return [] }
            let sources = Array(operands.dropLast())
            return destinations(sources: sources, destination: destination, cwd: cwd)
                    .map { Target(path: $0, intent: .write) }
                + sources.map { Target(path: $0, intent: .delete) }
        case "rm":
            return operands(rest).map { Target(path: $0, intent: .delete) }
        case "touch":
            return operands(rest).map { Target(path: $0, intent: .write) }
        default:
            // EVERYTHING ELSE IS THE GAP. `make`, `./build.sh`, `git apply`
            // and every interpreter heredoc record nothing, by construction.
            return []
        }
    }

    /// Non-option arguments. `--` ends option parsing; a lone `-` is stdin,
    /// never a path.
    private static func operands(_ words: [String]) -> [String] {
        var out: [String] = []
        var optionsEnded = false
        for word in words {
            if !optionsEnded {
                if word == "--" { optionsEnded = true; continue }
                if word == "-" { continue }
                if word.hasPrefix("-") { continue }
            }
            out.append(word)
        }
        return out
    }

    /// A copy or move INTO AN EXISTING DIRECTORY writes `DST/basename(SRC)`,
    /// not DST — recording the directory would file a change against a path
    /// that is not a file at all.
    private static func destinations(
        sources: some Collection<String>, destination: String, cwd: String
    ) -> [String] {
        // Resolved against the payload's cwd before the question is asked —
        // the hook process's own working directory is somebody else's.
        let absolute = absolutePath(destination, cwd: cwd)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: absolute, isDirectory: &isDirectory),
              isDirectory.boolValue
        else { return [destination] }
        return sources.map {
            URL(fileURLWithPath: absolute, isDirectory: true)
                .appendingPathComponent(basename($0)).path
        }
    }

    /// What one option walk learned: the short flags that were set, whether
    /// in-place editing was among them, and the positional words left over.
    private struct ParsedOptions {
        let flags: Set<Character>
        let positionals: [String]
        var inPlace: Bool { flags.contains("i") }
    }

    /// The sed/perl option walk. Both tools take CLUSTERS, and a cluster is
    /// where a naive parser loses the file list: in `perl -pi -e 's/a/b/'` the
    /// `-e` pulls the program out of the next word, while in `perl -pe
    /// 's/a/b/'` the very same argument is pulled by an `e` sitting at the end
    /// of a cluster. Miss that and the script is read as a filename.
    ///
    /// Three shapes, all handled here:
    ///   - `-e PROGRAM`   the argument is the next word
    ///   - `-e'PROGRAM'`  the argument is the rest of this word
    ///   - `-i.bak`       everything from the `.` is a SUFFIX, not more flags
    ///
    /// Plus one platform idiom that is not a cluster at all: BSD sed spells
    /// in-place `-i ''`, so a bare `-i` followed by an EMPTY word consumes
    /// that word as the suffix it is.
    private static func scanOptions(
        _ words: [String], argumentTaking: Set<Character>
    ) -> ParsedOptions {
        var flags: Set<Character> = []
        var positionals: [String] = []
        var index = 0
        var optionsEnded = false
        while index < words.count {
            let word = words[index]
            if optionsEnded {
                positionals.append(word)
                index += 1
                continue
            }
            if word == "--" { optionsEnded = true; index += 1; continue }
            guard word.hasPrefix("-"), word.count > 1 else {
                positionals.append(word)
                index += 1
                continue
            }
            if word.hasPrefix("--") {
                if word.hasPrefix("--in-place") { flags.insert("i") }
                if word == "--expression" || word == "--file" {
                    flags.insert(word == "--file" ? "f" : "e")
                    index += 2
                    continue
                }
                if word.hasPrefix("--expression=") { flags.insert("e") }
                if word.hasPrefix("--file=") { flags.insert("f") }
                index += 1
                continue
            }
            if word == "-i", index + 1 < words.count, words[index + 1].isEmpty {
                flags.insert("i")
                index += 2
                continue
            }
            let body = Array(word.dropFirst())
            var consumesNext = false
            for (position, character) in body.enumerated() {
                if character == "." { break }
                flags.insert(character)
                if argumentTaking.contains(character) {
                    // Whatever follows in this word IS the argument; if there
                    // is nothing left, the next word is.
                    consumesNext = position == body.count - 1
                    break
                }
            }
            index += consumesNext ? 2 : 1
        }
        return ParsedOptions(flags: flags, positionals: positionals.filter { !$0.isEmpty })
    }

    private static func basename(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Absolutise against the payload's cwd, drop what cannot be a real path,
    /// and collapse repeats.
    ///
    /// THE UNRESOLVABLE ARE DROPPED, NOT GUESSED. A word carrying `$` or a
    /// glob was never expanded by this parser, and `/dev/null` is not a file
    /// anyone wants a history row for. Later mentions win: `rm x` then
    /// `touch x` in one command line ends with x written, and that ordering
    /// is what the row should say.
    private static func resolve(_ targets: [Target], cwd: String) -> [Target] {
        var order: [String] = []
        var intents: [String: Intent] = [:]
        for target in targets {
            guard !target.path.isEmpty,
                  !target.path.contains("$"),
                  !target.path.contains("*"),
                  !target.path.contains("?")
            else { continue }
            let absolute = absolutePath(target.path, cwd: cwd)
            guard !absolute.hasPrefix("/dev/"), !absolute.hasPrefix("/proc/") else { continue }
            if intents[absolute] == nil { order.append(absolute) }
            intents[absolute] = target.intent
        }
        return order.prefix(maxTargets).map { Target(path: $0, intent: intents[$0]!) }
    }

    /// A command word resolves against the cwd the TOOL CALL ran in. `cd` is
    /// not tracked across segments — a `cd sub && rm x` records `x` under the
    /// payload's cwd, which is a documented limit of a parser that does not
    /// execute the shell.
    private static func absolutePath(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(
            fileURLWithPath: expanded,
            relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)
        ).standardizedFileURL.path
    }
}

// MARK: - The command-line scanner

/// One token of a command segment. A redirection OPERATOR is distinguished
/// from a word because only an unquoted `>` redirects — a quoted one is text,
/// and treating it as an operator manufactures a write that never happened.
enum BashToken: Equatable {
    case word(String)
    case redirect(String)
}

/// The quoting-aware segmenter behind PostToolUse Bash capture.
///
/// A command line is split into COMMAND POSITIONS. The scanner walks it once
/// carrying a context stack:
///
///     U  top-level unquoted     S  inside '…'     D  inside "…"
///     C  inside $( … )          B  inside ` … `
///
/// Separators split only in U/C/B. Inside D, `$(` and a backtick still open a
/// real command position; everything else is literal. Inside S nothing is
/// special at all. This matters because `git commit -m "cleanup; rm -rf x"`
/// contains no command position after the `;` — splitting there would invent
/// a deletion out of a commit message.
///
/// HEREDOCS STOP THE SCAN at an unquoted `<<`, deliberately: a heredoc body is
/// data whose lines are indistinguishable from commands without parsing the
/// shell. Everything before the `<<` is still scanned.
///
/// AN UNBALANCED QUOTE RETURNS NIL — the whole command records nothing. The
/// scanner cannot know where the intended word boundaries were, and a
/// half-parsed path is a wrong path.
enum BashCommandScanner {
    private enum State { case unquoted, single, double, commandSub, backtick }

    static func segments(_ command: String) -> [[BashToken]]? {
        let chars = Array(command)
        var segments: [[BashToken]] = []
        var tokens: [BashToken] = []
        var current = ""
        var hasCurrent = false
        var stack: [State] = [.unquoted]

        func flushWord() {
            guard hasCurrent else { return }
            tokens.append(.word(current))
            current = ""
            hasCurrent = false
        }
        func breakSegment() {
            flushWord()
            if !tokens.isEmpty { segments.append(tokens); tokens = [] }
        }
        func append(_ character: Character) {
            current.append(character)
            hasCurrent = true
        }

        var index = 0
        scan: while index < chars.count {
            let c = chars[index]
            let next = index + 1 < chars.count ? chars[index + 1] : nil
            switch stack[stack.count - 1] {
            case .single:
                if c == "'" { stack.removeLast() } else { append(c) }
                index += 1

            case .double:
                if c == "\\", let next {
                    // Only these four are escapable inside double quotes;
                    // every other backslash is a literal backslash.
                    if "$`\"\\".contains(next) { append(next) } else { append(c); append(next) }
                    index += 2
                    continue
                }
                if c == "\"" { stack.removeLast(); index += 1; continue }
                if c == "$", next == "(" {
                    breakSegment(); stack.append(.commandSub); index += 2; continue
                }
                if c == "`" { breakSegment(); stack.append(.backtick); index += 1; continue }
                append(c == "\n" ? " " : c)
                index += 1

            case .unquoted, .commandSub, .backtick:
                if c == "\\", let next {
                    // Escaped: it joins the word and can never be read as an
                    // operator, which is what `\>` means.
                    append(next)
                    index += 2
                    continue
                }
                if c == "'" { hasCurrent = true; stack.append(.single); index += 1; continue }
                if c == "\"" { hasCurrent = true; stack.append(.double); index += 1; continue }
                if c == "`" {
                    if stack[stack.count - 1] == .backtick { stack.removeLast() }
                    else { stack.append(.backtick) }
                    breakSegment()
                    index += 1
                    continue
                }
                if c == "$", next == "(" {
                    breakSegment(); stack.append(.commandSub); index += 2; continue
                }
                if c == ")" {
                    if stack[stack.count - 1] == .commandSub { stack.removeLast() }
                    breakSegment()
                    index += 1
                    continue
                }
                if c == "<", next == "<" { breakSegment(); break scan }
                if c == ">" {
                    // A leading fd (`2>`, `1>>`) belongs to the operator. Left
                    // in the word list it would look like a path named `2`.
                    if hasCurrent, !current.isEmpty, current.allSatisfy(\.isNumber) {
                        current = ""
                        hasCurrent = false
                    }
                    flushWord()
                    tokens.append(.redirect(next == ">" ? ">>" : ">"))
                    index += next == ">" ? 2 : 1
                    continue
                }
                if c == "<" {
                    if hasCurrent, !current.isEmpty, current.allSatisfy(\.isNumber) {
                        current = ""
                        hasCurrent = false
                    }
                    flushWord()
                    tokens.append(.redirect("<"))
                    index += 1
                    continue
                }
                if c == ";" || c == "&" || c == "|" || c == "(" || c == "{" || c == "}"
                    || c == "\n" {
                    breakSegment()
                    index += 1
                    continue
                }
                if c == " " || c == "\t" { flushWord(); index += 1; continue }
                append(c)
                index += 1
            }
        }
        // Anything but a closed, top-level context means the parse lost
        // track: an unterminated quote or an unclosed substitution. Both
        // record nothing.
        guard stack.count == 1, stack[0] == .unquoted else { return nil }
        breakSegment()
        return segments
    }

    /// Split one segment into the command's own words and the paths its
    /// redirections write.
    ///
    /// A redirection's operand is NOT a command argument: in `tee a.txt >
    /// log`, `log` belongs to the shell and `a.txt` to tee, and folding them
    /// together would file `log` twice and shift every positional after it.
    static func split(_ tokens: [BashToken]) -> (words: [String], redirections: [String]) {
        var words: [String] = []
        var redirections: [String] = []
        var index = 0
        while index < tokens.count {
            switch tokens[index] {
            case .word(let word):
                words.append(word)
                index += 1
            case .redirect(let op):
                if index + 1 < tokens.count, case .word(let target) = tokens[index + 1] {
                    // `<` reads; only the writing operators contribute.
                    if op != "<" { redirections.append(target) }
                    index += 2
                } else {
                    index += 1
                }
            }
        }
        return (words, redirections)
    }
}

// MARK: - Kind, confirmed by git

/// The path-limited classifier. It answers ONE question about ONE path the
/// caller already holds: did that path end up created, edited or deleted?
///
/// `git status --porcelain -- <path>` is scoped to the single pathspec it is
/// given, so it can neither enumerate a working tree nor discover a file
/// nobody named. That bound is the point.
enum GitPathClassifier {
    /// Repo-relative, or nil when the path is not inside this repo at all.
    ///
    /// Containment is checked against the BOOTED repo root rather than "some
    /// git repo": $HOME can itself be a git toplevel, and the ckfs and kbite
    /// trees are repos too — foreign paths would land as junk rows in an
    /// append-only db.
    static func repoRelative(_ absolute: String, repoRoot: String) -> String? {
        let path = URL(fileURLWithPath: absolute).standardizedFileURL.path
        let root = URL(fileURLWithPath: repoRoot).standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    /// nil means "nothing happened here that is worth a row": git has no
    /// answer and there is no file, which is what a misparsed argument looks
    /// like. THAT FALLTHROUGH IS A SAFETY NET, not an accident — it is why a
    /// `sed` script mistaken for a filename cannot reach the db.
    static func classify(
        relativePath: String, repoRoot: String, declared: BashWritePaths.Intent
    ) -> ChangeKind? {
        if let code = statusCode(relativePath: relativePath, repoRoot: repoRoot) {
            if code.contains("?") { return .create }
            if code.contains("D") { return .delete }
            if code.contains("A") { return .create }
            if code.contains("M") { return .edit }
        }
        let absolute = URL(fileURLWithPath: repoRoot, isDirectory: true)
            .appendingPathComponent(relativePath).path
        if FileManager.default.fileExists(atPath: absolute) { return .edit }
        return declared == .delete ? .delete : nil
    }

    /// The two status columns of the first reported line, or nil when git
    /// reports nothing (clean, unknown, or not a repo).
    private static func statusCode(relativePath: String, repoRoot: String) -> String? {
        guard let output = runGit(
            ["-C", repoRoot, "status", "--porcelain", "--", relativePath])
        else { return nil }
        guard let line = output.split(separator: "\n").first, line.count >= 2 else { return nil }
        return String(line.prefix(2))
    }

    private static func runGit(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(data: data, encoding: .utf8)
        return (text?.isEmpty ?? true) ? nil : text
    }
}
