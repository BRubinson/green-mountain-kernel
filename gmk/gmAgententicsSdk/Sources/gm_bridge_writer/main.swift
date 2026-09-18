import Foundation
import GmAgententicsSdk

// The plugin generator: `gm_bridge_writer [--check] <plugin-dir>`.
//
// AN EXECUTABLE IN THIS PACKAGE, NOT A `gm_kernel` SUBCOMMAND, and the platform
// floor is why rather than taste. `gmAgententicsSdk` is macOS 27 with
// `unsafeFlags`; `gmKernel`, `gmDaemon` and `gmDaemonSdk` are macOS 14. SwiftPM
// checks floors at GRAPH RESOLUTION, before any `@available` scope exists, so a
// `gm_kernel bridge emit` would drag 27 into `gm_hook`, `gm_daemon` and every CI
// job. Reaching for `@available` is the plausible move that cannot work.
//
// The cost is nil: generation is a developer-machine act, like
// `rebuild_local.sh`, and never runs on a user's machine.

func usage() -> Never {
    FileHandle.standardError.write(
        Data(
            """
            usage: gm_bridge_writer [--check] <plugin-dir>

              --check   render everything and report, writing NOTHING. Use this to
                        see what would change before letting it change.

            With no --check the target directory is DELETED and rewritten from the
            bridge values in gmAgententicsSdk. The write is staged beside the target
            and swapped in, so a failure leaves the old tree intact.

            """.utf8))
    exit(2)
}

var args = Array(CommandLine.arguments.dropFirst())
var check = false
if let i = args.firstIndex(of: "--check") { check = true; args.remove(at: i) }
guard args.count == 1 else { usage() }

let target = URL(fileURLWithPath: args[0]).standardizedFileURL

do {
    if check {
        // --check REPORTS; it does not refuse. It deliberately does NOT call
        // `verify()`, because verify throws on the first boot-critical gap and
        // a check that dies at the first problem hides the other nine. The
        // whole point of this mode is to see the full picture before deciding.
        let (rendered, omitted) = GmBridgeWriter.render()
        let bytes = rendered.reduce(0) { $0 + $1.body.utf8.count }
        print("would write \(rendered.count) files, \(bytes) bytes, to \(target.path)")
        for file in rendered.sorted(by: { $0.path < $1.path }) {
            print("  + \(file.path)  (\(file.body.utf8.count) bytes)")
        }
        let fatal = Set(omitted).intersection(GmBridgeWriter.bootCritical).sorted()
        if !omitted.isEmpty {
            print("\n  \(omitted.count) declared but rendered NOTHING:")
            for path in omitted.sorted() {
                print("  - \(path)\(fatal.contains(path) ? "   <- BOOT-CRITICAL" : "")")
            }
        }
        if fatal.isEmpty {
            print("\nwrite would SUCCEED")
            exit(0)
        }
        // Non-zero so a script can gate on it, after the full report has been
        // printed rather than instead of it.
        print("\nwrite would be REFUSED: \(fatal.count) boot-critical file(s) render nothing")
        exit(1)
    }
    let report = try GmBridgeWriter.write(to: target)
    print("wrote \(report.written.count) files, \(report.bytes) bytes, to \(target.path)")
    if !report.omitted.isEmpty {
        print("  \(report.omitted.count) declared but rendered nothing:")
        for path in report.omitted { print("  - \(path)") }
    }
} catch {
    FileHandle.standardError.write(Data("gm_bridge_writer: \(error)\n".utf8))
    exit(1)
}
