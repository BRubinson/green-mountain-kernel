import CoreGraphics
import Foundation

/// A mirrored window row as read back at launch: its identity and any pre-park frame.
struct MirrorWindowSnapshot: Equatable, Sendable {
    /// The owning process id recorded in the mirror.
    let pid: Int32
    /// The owning process's launch date recorded in the mirror.
    let launchedAt: Date
    /// The window's CoreGraphics id.
    let cgWindowId: UInt32
    /// The frame the window had before it was parked, or nil when it was not parked.
    let prePark: CGRect?

    /// The window key the row describes.
    var key: WindowKey { WindowKey(pid: pid, launchedAt: launchedAt, cgWindowId: cgWindowId) }
}

/// Returns windows a previous run left parked to view.
///
/// The mirror supplies the pre-park frame when it knows the window. Geometry comes first, so a window
/// parked in the moments before a crash, or with an empty database, is still found and returned to view.
enum CrashRecovery {
    /// The moves that bring every hidden observed window back on screen.
    ///
    /// A hidden window whose mirror row matches on pid, launch date and window id returns to its pre-park
    /// frame when that frame is still on a connected display. Any other hidden window keeps its size, clamped
    /// to fit, centred in the main display's visible frame. Windows that are not hidden are never moved.
    ///
    /// - Parameters:
    ///   - observed: Every window observed at launch.
    ///   - displays: Every connected display.
    ///   - mirror: The mirrored window rows of the previous run.
    /// - Returns: One `(window, frame)` move per hidden window, in `observed` order.
    static func plan(
        observed: [ObservedWindow],
        displays: [DisplayGeom],
        mirror: [MirrorWindowSnapshot]
    ) -> [(WindowKey, CGRect)] {
        guard let main = displays.first(where: \.isMain) ?? displays.first else { return [] }
        let prePark = Dictionary(
            mirror.compactMap { row in row.prePark.map { (row.key, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
        return observed.compactMap { window in
            guard ParkGeometry.isParked(frame: window.frame, displays: displays) else { return nil }
            if let frame = prePark[window.key], !ParkGeometry.isParked(frame: frame, displays: displays) {
                return (window.key, frame)
            }
            return (window.key, centred(size: window.frame.size, in: main.visibleFrame))
        }
    }

    /// A rectangle of `size`, clamped to fit, centred in `container`.
    ///
    /// - Parameters:
    ///   - size: The desired size.
    ///   - container: The rectangle to centre in.
    /// - Returns: The centred rectangle.
    static func centred(size: CGSize, in container: CGRect) -> CGRect {
        let width = min(size.width, container.width)
        let height = min(size.height, container.height)
        return CGRect(
            x: container.midX - width / 2,
            y: container.midY - height / 2,
            width: width,
            height: height
        )
    }
}
