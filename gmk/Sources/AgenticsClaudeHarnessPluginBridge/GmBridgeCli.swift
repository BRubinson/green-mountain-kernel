import Foundation

/// The plugin generator personality:
/// `gm_kernel bridge [--check] [--roster-out <path>] <plugin-dir>`.
enum GmBridgeCli {

    /// The roster is the one file this personality writes outside the plugin
    /// directory, so the path is checked against the repo rather than trusted.
    enum RosterOutError: Error, CustomStringConvertible {
        case notTheRoster(String)
        case notARepo(String)

        var description: String {
            switch self {
            case .notTheRoster(let path):
                return "--roster-out must name '\(CdeToolRoster.generatedPath)' in a repo, got '\(path)'"
            case .notARepo(let path):
                return """
                    --roster-out '\(path)' spells the roster's path, but the directory above \
                    it holds no gmk/gmk.xcworkspace — the roster is SOURCE and only lands in \
                    a checkout of this repo
                    """
            }
        }
    }

    static func main(_ arguments: [String]) -> Never {
        var args = arguments
        var check = false
        if let i = args.firstIndex(of: "--check") {
            check = true
            args.remove(at: i)
        }
        var rosterOut: String?
        if let i = args.firstIndex(of: "--roster-out") {
            guard i + 1 < args.count else { usage() }
            rosterOut = args[i + 1]
            args.removeSubrange(i...(i + 1))
        }
        guard args.count == 1 else { usage() }

        let target = URL(fileURLWithPath: args[0]).standardizedFileURL

        do {
            if check { try report(target: target, rosterOut: rosterOut) }
            // Resolved BEFORE the swap: a refused roster path must not cost the
            // caller a rewritten plugin tree first.
            let roster = try rosterOut.map(rosterPath)
            let report = try GmBridgeWriter.write(to: target)
            out("wrote \(report.written.count) files, \(report.bytes) bytes, to \(target.path)")
            if !report.omitted.isEmpty {
                out("  \(report.omitted.count) declared but rendered nothing:")
                for path in report.omitted { out("  - \(path)") }
            }
            if let roster {
                let specs = try GmBridgeRoster.specs()
                try GmBridgeRoster.render().write(to: roster, atomically: true, encoding: .utf8)
                out("wrote roster, \(specs.count) tools, to \(roster.path)")
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("gm_kernel bridge: \(error)\n".utf8))
            exit(1)
        }
    }

    /// `--check`: render everything, say what would land, and write nothing.
    ///
    /// It reports the whole picture where `verify()` would stop at the first
    /// boot-critical gap and hide the rest.
    private static func report(target: URL, rosterOut: String?) throws -> Never {
        let (rendered, omitted) = GmBridgeWriter.render()
        let bytes = rendered.reduce(0) { $0 + $1.body.utf8.count }
        out("would write \(rendered.count) files, \(bytes) bytes, to \(target.path)")
        for file in rendered.sorted(by: { $0.path < $1.path }) {
            out("  + \(file.path)  (\(file.body.utf8.count) bytes)")
        }
        let fatal = Set(omitted).intersection(GmBridgeWriter.bootCritical).sorted()
        if !omitted.isEmpty {
            out("\n  \(omitted.count) declared but rendered NOTHING:")
            for path in omitted.sorted() {
                out("  - \(path)\(fatal.contains(path) ? "   <- BOOT-CRITICAL" : "")")
            }
        }
        for problem in GmBridgeWriter.rosterProblems() {
            out("\nroster PROBLEM: \(problem)")
        }
        let unknown = GmBridgeWriter.unknownToolNames(in: rendered)
        if !unknown.isEmpty {
            out("\n  \(unknown.count) pen-tool name(s) cited but NOT SERVED:")
            for name in unknown { out("  ? mcp__plugin_gmcc_cde__\(name)") }
        }
        var stale = false
        if let rosterOut {
            let path = try rosterPath(rosterOut)
            let committed = (try? String(contentsOf: path, encoding: .utf8)) ?? ""
            stale = committed != (try GmBridgeRoster.render())
            out(
                stale
                    ? "\nroster STALE: \(path.path) differs from a fresh reflection of AgenticsCore/Tools"
                    : "\nroster current: \(path.path)"
            )
        }
        if fatal.isEmpty && !stale {
            out("\nwrite would SUCCEED")
            exit(0)
        }
        if !fatal.isEmpty {
            out("\nwrite would be REFUSED: \(fatal.count) boot-critical file(s) render nothing")
        }
        exit(1)
    }

    /// Where `--roster-out` may write: a repo's own generated roster, and
    /// nothing else.
    ///
    /// The path must END in the roster's repo-relative spelling EXACTLY, and
    /// what is left above it must be a checkout of this repo. Without the second
    /// half a caller could mint that tail in any directory on disk and have the
    /// roster written there, because the first half derives the repo from the
    /// very path it is checking.
    private static func rosterPath(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let suffix = "/" + CdeToolRoster.generatedPath
        guard url.path.hasSuffix(suffix) else { throw RosterOutError.notTheRoster(url.path) }
        let repo = URL(fileURLWithPath: String(url.path.dropLast(suffix.count)))
        let workspace = repo.appendingPathComponent("gmk/gmk.xcworkspace")
        guard FileManager.default.fileExists(atPath: workspace.path) else {
            throw RosterOutError.notARepo(url.path)
        }
        try Paths.assertContained(url, repoRoot: repo)
        return url
    }

    private static func out(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(
            Data(
                """
                usage: gm_kernel bridge [--check] [--roster-out <path>] <plugin-dir>

                  --check        render everything and report, writing NOTHING.
                  --roster-out   also write the cde tool roster, reflected from the
                                 @Generable tool declarations, to <path>. The path must
                                 be a repo's own CdeToolRoster.generated.swift; with
                                 --check a stale roster is reported and nothing is written.

                Without --check the target directory is rewritten from the bridge values
                by stage-and-swap, so a failure leaves the old tree intact.

                """
                .utf8
            )
        )
        exit(2)
    }
}
