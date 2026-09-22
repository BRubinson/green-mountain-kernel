import Foundation
import GmDaemonSdk

/// The eagle subsystem's entry point, reached as `gm_kernel eagle [args...]`.
///
/// This is the seam the kernel dispatches into; the subsystem itself is not yet
/// built, so every invocation reports that and exits cleanly.
public enum GmEagle {
    /// The library's own identity line, carrying the protocol it was built against.
    public static var banner: String {
        "gm_eagle (protocol v\(GmWireProtocol.version))"
    }

    /// Runs the subsystem with the arguments that followed `eagle` on the
    /// command line and returns the process exit status.
    public static func run(_ arguments: [String]) -> Int32 {
        switch arguments.first {
        case "--help", "-h", "help", nil:
            FileHandle.standardOutput.write(Data((usage + "\n").utf8))
            return 0
        case "--version", "version":
            FileHandle.standardOutput.write(Data((banner + "\n").utf8))
            return 0
        default:
            FileHandle.standardError.write(Data((usage + "\n").utf8))
            return 2
        }
    }

    private static var usage: String {
        """
        \(banner)

        USAGE
          gm_kernel eagle [--version | --help]

        No eagle subcommand is implemented yet.
        """
    }
}
