import CoreGraphics
import Foundation

/// The identity of one observed process: its pid and launch date.
struct ProcessKey: Hashable, Sendable {
    /// The process id.
    let pid: Int32
    /// The launch date, which disambiguates a reused pid.
    let launchedAt: Date
}

/// The mirrored values of one window.
struct MirrorWindow: Equatable, Sendable {
    /// The workspace the window is assigned to, or nil when floating or unassigned.
    var workspaceCode: String?
    /// The column index in its strip, or nil when floating.
    var columnIndex: Int?
    /// The column weight.
    var weight: Double
    /// True when the window never tiles.
    var floating: Bool
    /// The current frame, when known.
    var frame: CGRect?
    /// The pre-park frame while the window is parked.
    var prePark: CGRect?
    /// The window title; a title-only change is not written.
    var title: String?
}

/// The mirrored values of one process.
struct MirrorProcess: Equatable, Sendable {
    /// The bundle identifier, when the process has one.
    var bundleId: String?
    /// The human-readable name.
    var name: String
    /// False once the process has terminated.
    var running: Bool
}

/// Everything the mirror holds, as the shell last saw it.
struct MirrorImage: Equatable, Sendable {
    /// The mirrored windows.
    var windows: [WindowKey: MirrorWindow] = [:]
    /// The mirrored processes.
    var processes: [ProcessKey: MirrorProcess] = [:]

    /// The image after `delta` is written over it.
    ///
    /// A writer keeps this, not the image it diffed against, as its last flushed image, so sub-threshold
    /// drift accumulates until it crosses the threshold and is written.
    ///
    /// - Parameter delta: A delta produced against this image.
    /// - Returns: The image the mirror now holds.
    func applying(_ delta: MirrorDelta) -> MirrorImage {
        var result = self
        result.windows.merge(delta.windowUpserts) { _, new in new }
        result.processes.merge(delta.processUpserts) { _, new in new }
        delta.windowRetirements.forEach { result.windows[$0] = nil }
        delta.processRetirements.forEach { result.processes[$0] = nil }
        return result
    }
}

/// The minimal write that brings the mirror from one image to the next.
struct MirrorDelta: Equatable, Sendable {
    /// Windows to insert or update, with their new values.
    var windowUpserts: [WindowKey: MirrorWindow] = [:]
    /// Windows to soft-delete.
    var windowRetirements: Set<WindowKey> = []
    /// Processes to insert or update, with their new values.
    var processUpserts: [ProcessKey: MirrorProcess] = [:]
    /// Processes to soft-delete.
    var processRetirements: Set<ProcessKey> = []

    /// True when there is nothing to write, so the caller skips the flush.
    var isEmpty: Bool {
        windowUpserts.isEmpty && windowRetirements.isEmpty && processUpserts.isEmpty && processRetirements.isEmpty
    }
}

/// Diffs two mirror images into the minimal debounced write.
///
/// The delta is pure; the shell maps it to the store's batch type.
enum MirrorProjection {
    /// The frame difference, in points, under which a frame is unchanged.
    static let frameTolerance: CGFloat = 2

    /// The writes that bring the mirror from `last` to `current`.
    ///
    /// A frame or pre-park change under `frameTolerance` is no change and a title-only change is not
    /// written. A process that disappears is retired together with every window it owned.
    ///
    /// - Parameters:
    ///   - last: The image the mirror holds.
    ///   - current: The image the shell sees now.
    /// - Returns: The delta; empty when nothing material changed.
    static func diff(last: MirrorImage, current: MirrorImage) -> MirrorDelta {
        var delta = MirrorDelta()
        for (key, process) in current.processes where last.processes[key] != process {
            delta.processUpserts[key] = process
        }
        delta.processRetirements = Set(last.processes.keys).subtracting(current.processes.keys)
        for (key, window) in current.windows {
            guard let previous = last.windows[key] else {
                delta.windowUpserts[key] = window
                continue
            }
            if materiallyDiffers(previous, window) { delta.windowUpserts[key] = window }
        }
        delta.windowRetirements = Set(last.windows.keys).subtracting(current.windows.keys)
        for key in last.windows.keys where delta.processRetirements.contains(processKey(of: key)) {
            delta.windowRetirements.insert(key)
            delta.windowUpserts[key] = nil
        }
        return delta
    }

    /// True when two window values differ in anything the mirror writes.
    ///
    /// - Parameters:
    ///   - lhs: The mirrored value.
    ///   - rhs: The current value.
    /// - Returns: Whether the difference is material.
    private static func materiallyDiffers(_ lhs: MirrorWindow, _ rhs: MirrorWindow) -> Bool {
        lhs.workspaceCode != rhs.workspaceCode
            || lhs.columnIndex != rhs.columnIndex
            || lhs.weight != rhs.weight
            || lhs.floating != rhs.floating
            || !framesMatch(lhs.frame, rhs.frame)
            || !framesMatch(lhs.prePark, rhs.prePark)
    }

    /// True when both frames are absent, or both are present and every edge is within `frameTolerance`.
    ///
    /// - Parameters:
    ///   - lhs: One frame.
    ///   - rhs: The other frame.
    /// - Returns: Whether the frames are the same for mirroring.
    static func framesMatch(_ lhs: CGRect?, _ rhs: CGRect?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return true
        case let (lhs?, rhs?):
            return abs(lhs.minX - rhs.minX) < frameTolerance && abs(lhs.minY - rhs.minY) < frameTolerance
                && abs(lhs.width - rhs.width) < frameTolerance && abs(lhs.height - rhs.height) < frameTolerance
        default: return false
        }
    }

    /// The mirrored value of every window the reducer tracks.
    ///
    /// - Parameter state: The reducer state.
    /// - Returns: One value per tiled or floating window.
    static func windows(of state: WMState) -> [WindowKey: MirrorWindow] {
        var result: [WindowKey: MirrorWindow] = [:]
        for strip in state.workspaces.values {
            for (index, column) in strip.columns.enumerated() {
                result[column.window] = MirrorWindow(
                    workspaceCode: strip.code,
                    columnIndex: index,
                    weight: column.weight,
                    floating: false,
                    frame: state.frames[column.window],
                    prePark: state.parked[column.window],
                    title: state.titles[column.window]
                )
            }
        }
        for key in state.floating {
            result[key] = MirrorWindow(
                workspaceCode: nil,
                columnIndex: nil,
                weight: 1,
                floating: true,
                frame: state.frames[key],
                prePark: state.parked[key],
                title: state.titles[key]
            )
        }
        return result
    }

    /// The process that owns `window`.
    ///
    /// - Parameter window: A window key.
    /// - Returns: Its owning process key.
    private static func processKey(of window: WindowKey) -> ProcessKey {
        ProcessKey(pid: window.pid, launchedAt: window.launchedAt)
    }
}
