import Foundation

// WHAT PATHS WOULD THIS SHELL COMMAND WRITE? A self-contained scanner over a
// Bash command line, with no knowledge of hooks, agents or Claude Code. It
// lives in Util, apart from the hook surface, because it is generic shell
// parsing that happens to have one consumer.

/// THE PATHS A BASH COMMAND NAMED — and nothing else. Each recorded form is a
/// shape whose write TARGET is stated in the command itself:
///     >  FILE   and  >>  FILE     (unquoted redirections)    tee [-a] FILE...
///     sed -i[SUFFIX] ... FILE...        perl -i... ... FILE...
///     cp / install / ln SRC... DST  →  DST
///     mv SRC... DST                 →  DST written, every SRC deleted
///     rm [-rf] FILE...              →  deleted
///     touch FILE...

/// A DOCUMENTED GAP, recording NOTHING silently: interpreter heredocs, `make`,
/// `./script.sh`, `git apply`, unbalanced quotes, and any target spelled with
/// an unexpanded `$VAR` or a glob.
///
/// Parse failures land on "record nothing": absent rows are detectable, wrong
/// rows poison the record. IT IS NOT A DIFF ENGINE — the sole git use is `git
/// status --porcelain -- <path>` that CLASSIFIES paths already named, so it
/// cannot discover paths or misattribute edits.
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

    /// Transparent wrappers: the real command is the next word.
    ///
    /// Ported from the write guard's peel loop, which faces the identical
    /// problem.
    private static let wrappers: Set<String> = ["env", "command", "nohup", "time", "exec"]

    /// Extracts paths the command writes or deletes.
    ///
    /// - Parameters:
    ///   - command: The command line to parse.
    ///   - cwd: The current working directory when the command runs.
    /// - Returns: An array of targets with their write intents; empty if parsing fails.
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

    /// Returns words with assignments and wrapper commands removed.
    ///
    /// Peel leading `NAME=value` assignments and transparent wrappers so
    /// `FOO=1 env sed -i …` reaches the same dispatch as a bare `sed -i …`.
    ///
    /// - Parameter words: The words to filter.
    /// - Returns: Words with leading assignments and wrapper names stripped.
    private static func peeled(_ words: [String]) -> [String] {
        var words = words
        while let first = words.first, isAssignment(first) || wrappers.contains(first) {
            words.removeFirst()
        }
        return words
    }

    /// True when the word is a shell variable assignment.
    ///
    /// "contains an `=`" is not the test — a `--body "rating=0"` argument
    /// contains one, and peeling on that would eat the command word.
    ///
    /// - Parameter word: The word to test.
    /// - Returns: True if the word is a valid assignment name.
    private static func isAssignment(_ word: String) -> Bool {
        guard let split = word.firstIndex(of: "=") else { return false }
        let name = word[word.startIndex..<split]
        guard let first = name.first, first == "_" || first.isLetter else { return false }
        return name.allSatisfy { $0 == "_" || $0.isLetter || $0.isNumber }
    }

    /// Returns paths the command's own arguments will write or delete.
    ///
    /// - Parameters:
    ///   - words: The command and its arguments, with assignments and wrappers removed.
    ///   - cwd: The current working directory when the command runs.
    /// - Returns: Targets extracted from the command.
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
                sources: operands.dropLast(),
                destination: destination,
                cwd: cwd
            )
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

    /// Returns non-option arguments.
    ///
    /// `--` ends option parsing; a lone `-` is stdin, never a path.
    ///
    /// - Parameter words: The words to filter.
    /// - Returns: Arguments that do not start with `-` or follow option-terminating flags.
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

    /// Returns destination paths when copying into a directory.
    ///
    /// When copying or moving into an existing directory, the actual writes are
    /// `DST/basename(SRC)`, not DST — recording the directory would file a change
    /// against a path that is not a file at all.
    ///
    /// - Parameters:
    ///   - sources: The source paths to copy or move.
    ///   - destination: The target path.
    ///   - cwd: The current working directory when the command runs.
    /// - Returns: Paths that will actually be written.
    private static func destinations(
        sources: some Collection<String>,
        destination: String,
        cwd: String
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

    /// Parses sed and perl option clusters.
    ///
    /// Both take CLUSTERS, which is where a naive parser loses the file list
    /// and reads the script as a filename. Four shapes are handled:
    /// `-e PROGRAM` (argument is next word), `-e'PROGRAM'` (argument is rest of word),
    /// `-i.bak` (suffix after the dot), and `-i ''` (BSD sed's in-place idiom).
    ///
    /// - Parameters:
    ///   - words: The command arguments to parse.
    ///   - argumentTaking: The single-character flags that consume the next word.
    /// - Returns: The flags found, positional arguments, and whether in-place edit is enabled.
    private static func scanOptions(
        _ words: [String],
        argumentTaking: Set<Character>
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

    /// Returns the final path component.
    ///
    /// - Parameter path: The path to extract from.
    /// - Returns: The basename of the path.
    private static func basename(_ path: String) -> String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    /// Returns targets resolved and deduplicated.
    ///
    /// Absolutise against the payload's cwd, drop what cannot be a real path,
    /// and collapse repeats. The unresolvable are dropped, not guessed. A word
    /// carrying `$` or a glob was never expanded by this parser. Later mentions
    /// win: `rm x` followed by `touch x` results in `x` marked as written.
    ///
    /// - Parameters:
    ///   - targets: The targets to process.
    ///   - cwd: The current working directory.
    /// - Returns: Resolved and ordered targets without duplicates.
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

    /// Returns the absolute path resolved against the cwd.
    ///
    /// A command word resolves against the cwd the tool call ran in. `cd` is
    /// not tracked across segments — a `cd sub && rm x` records `x` under the
    /// payload's cwd, which is a documented limit of a parser that does not
    /// execute the shell.
    ///
    /// - Parameters:
    ///   - path: The path to resolve, which may be relative or contain `~`.
    ///   - cwd: The current working directory.
    /// - Returns: The absolute, standardized path.
    private static func absolutePath(_ path: String, cwd: String) -> String {
        let expanded = (path as NSString).expandingTildeInPath
        return URL(
            fileURLWithPath: expanded,
            relativeTo: URL(fileURLWithPath: cwd, isDirectory: true)
        )
        .standardizedFileURL.path
    }
}

// MARK: - The command-line scanner

/// One token of a command segment.
///
/// A redirection OPERATOR is distinguished from a word because only an unquoted
/// `>` redirects — a quoted one is text, and treating it as an operator
/// manufactures a write that never happened.
enum BashToken: Equatable {
    case word(String)
    case redirect(String)
}

/// The quoting-aware segmenter behind PostToolUse Bash capture.
///
/// A command line is split into COMMAND POSITIONS: unquoted, `'…'`, `"…"`,
/// `$( … )`, and backtick states. Separators split only outside quotes. Example:
/// `git commit -m "cleanup; rm -rf x"` holds no command position after `;`.
/// HEREDOCS STOP THE SCAN at `<<`. AN UNBALANCED QUOTE RETURNS NIL: a
/// half-parsed path is wrong.
enum BashCommandScanner {
    private enum State { case unquoted, single, double, commandSub, backtick }

    /// Segments the command line by unquoted semicolons and pipes.
    ///
    /// - Parameter command: The command line to segment.
    /// - Returns: An array of token segments, or nil if parsing fails (unbalanced quotes or heredocs).
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
                    if stack[stack.count - 1] == .backtick { stack.removeLast() } else { stack.append(.backtick) }
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
                    || c == "\n"
                {
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

    /// Splits a token segment into command words and redirection targets.
    ///
    /// A redirection's operand is NOT a command argument: in `tee a.txt >
    /// log`, `log` belongs to the shell and `a.txt` to tee, and folding them
    /// together would file `log` twice and shift every positional after it.
    ///
    /// - Parameter tokens: The tokens to split.
    /// - Returns: Command words and paths from write redirections.
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

/// The path-limited classifier.
///
/// It answers ONE question about ONE path the caller already holds: did that
/// path end up created, edited or deleted? `git status --porcelain -- <path>`
/// is scoped to the single pathspec it is given, so it can neither enumerate a
/// working tree nor discover a file nobody named. That bound is the point.
enum GitPathClassifier {
    /// Returns the repo-relative path, or nil if outside the repo.
    ///
    /// Containment is checked against the booted repo root rather than any
    /// git repo: $HOME can itself be a git toplevel, and gmfs and kbite
    /// trees are repos too — foreign paths would land as junk rows.
    ///
    /// - Parameters:
    ///   - absolute: The absolute path to convert.
    ///   - repoRoot: The root of the repo.
    /// - Returns: The path relative to the repo root, or nil if outside it.
    static func repoRelative(_ absolute: String, repoRoot: String) -> String? {
        let path = URL(fileURLWithPath: absolute).standardizedFileURL.path
        let root = URL(fileURLWithPath: repoRoot).standardizedFileURL.path
        guard path.hasPrefix(root + "/") else { return nil }
        return String(path.dropFirst(root.count + 1))
    }

    /// Classifies the path change as create, edit, or delete.
    ///
    /// Returns nil when nothing happened here that is worth a row — git has no
    /// answer and there is no file, which is what a misparsed argument looks like.
    /// The nil fallthrough is a safety net: it prevents a `sed` script mistaken
    /// for a filename from reaching the database.
    ///
    /// - Parameters:
    ///   - relativePath: The repo-relative path.
    ///   - repoRoot: The root of the repo.
    ///   - declared: The write intent from the parsed command.
    /// - Returns: The kind of change, or nil if nothing actually happened.
    static func classify(
        relativePath: String,
        repoRoot: String,
        declared: BashWritePaths.Intent
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

    /// Returns the two-character git status code for the path.
    ///
    /// Returns nil when git reports nothing (clean, unknown, or not a repo).
    ///
    /// - Parameters:
    ///   - relativePath: The repo-relative path to check.
    ///   - repoRoot: The root of the repo.
    /// - Returns: The two-character status code, or nil if git has no status.
    private static func statusCode(relativePath: String, repoRoot: String) -> String? {
        guard
            let output = runGit(
                ["-C", repoRoot, "status", "--porcelain", "--", relativePath])
        else { return nil }
        guard let line = output.split(separator: "\n").first, line.count >= 2 else { return nil }
        return String(line.prefix(2))
    }

    /// Runs a git command and returns its output.
    ///
    /// - Parameter arguments: The git command arguments (including subcommand).
    /// - Returns: The command's stdout, or nil if the process fails.
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
