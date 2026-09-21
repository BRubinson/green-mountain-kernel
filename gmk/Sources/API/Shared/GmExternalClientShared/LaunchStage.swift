/// The progress a kernel-driven launch of an external application reports back to its caller.
enum LaunchStage: Sendable {
    case preparing
    case startingApp
    case connecting
    case openingWindow
}
