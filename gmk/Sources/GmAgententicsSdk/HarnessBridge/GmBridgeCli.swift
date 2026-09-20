import Foundation

/// The plugin generator personality: `gm_kernel bridge [--check] <plugin-dir>`.
enum GmBridgeCli {

    static func main(_ arguments: [String]) -> Never {
        var args = arguments
        var check = false
        if let i = args.firstIndex(of: "--check") {
            check = true
            args.remove(at: i)
        }
        guard args.count == 1 else { usage() }

        let target = URL(fileURLWithPath: args[0]).standardizedFileURL

        do {
            if check {
                // --check reports the whole picture; verify() would stop at the first
                // boot-critical gap and hide the rest.
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
                if fatal.isEmpty {
                    out("\nwrite would SUCCEED")
                    exit(0)
                }
                out("\nwrite would be REFUSED: \(fatal.count) boot-critical file(s) render nothing")
                exit(1)
            }
            let report = try GmBridgeWriter.write(to: target)
            out("wrote \(report.written.count) files, \(report.bytes) bytes, to \(target.path)")
            if !report.omitted.isEmpty {
                out("  \(report.omitted.count) declared but rendered nothing:")
                for path in report.omitted { out("  - \(path)") }
            }
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("gm_kernel bridge: \(error)\n".utf8))
            exit(1)
        }
    }

    private static func out(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(
            Data(
                """
                usage: gm_kernel bridge [--check] <plugin-dir>

                  --check   render everything and report, writing NOTHING.

                Without --check the target directory is rewritten from the bridge values
                by stage-and-swap, so a failure leaves the old tree intact.

                """
                .utf8
            )
        )
        exit(2)
    }
}
