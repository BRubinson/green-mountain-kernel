import AppKit
import CoreGraphics
import Foundation

/// One connected display, as the store input and as the reducer's geometry.
struct DisplayReading: Sendable {
    /// The row to upsert on `stableKey`.
    let input: DisplayInput
    /// The geometry the reducer lays out against.
    let geom: DisplayGeom
}

/// Enumerates connected displays with keys that survive a replug.
///
/// The key is the CoreGraphics display UUID; the `NSScreen` index and the `CGDirectDisplayID` both change
/// across replugs and are never identity.
@MainActor
enum DisplayIdentity {
    /// Every connected display, the menu-bar display first.
    ///
    /// Two panels can report the same CoreGraphics UUID; the first keeps it and each later one is suffixed
    /// with `#<cgDisplayId>`, so no two readings share a stable key.
    ///
    /// - Returns: One reading per screen; a screen without a display id or UUID is skipped.
    static func current() -> [DisplayReading] {
        var seen: Set<String> = []
        return NSScreen.screens.enumerated()
            .compactMap { index, screen in reading(screen, isMain: index == 0, seen: &seen) }
    }

    /// The primary display's frame height, which anchors the accessibility-to-Cocoa flip.
    ///
    /// - Returns: The height, or zero when no screen is connected.
    static func primaryHeight() -> CGFloat {
        NSScreen.screens.first?.frame.height ?? 0
    }

    /// The reading for one screen.
    ///
    /// - Parameters:
    ///   - screen: The screen.
    ///   - isMain: True for the screen that carries the menu bar.
    ///   - seen: The stable keys already handed out; this reading's key is added.
    /// - Returns: The reading, or nil when the screen has no display id or UUID.
    private static func reading(_ screen: NSScreen, isMain: Bool, seen: inout Set<String>) -> DisplayReading? {
        let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        guard let cgId = number.map({ CGDirectDisplayID($0.uint32Value) }),
            let uuid = CGDisplayCreateUUIDFromDisplayID(cgId)?.takeRetainedValue(),
            let reported = CFUUIDCreateString(nil, uuid) as String?
        else { return nil }
        let key = seen.contains(reported) ? "\(reported)#\(cgId)" : reported
        seen.insert(key)
        let frame = screen.frame
        let visible = screen.visibleFrame
        let mode = CGDisplayCopyDisplayMode(cgId)
        let physical = CGDisplayScreenSize(cgId)
        let input = DisplayInput(
            stableKey: key,
            name: screen.localizedName,
            isBuiltin: CGDisplayIsBuiltin(cgId) != 0,
            cgDisplayId: Int64(cgId),
            frameX: frame.minX,
            frameY: frame.minY,
            frameWidth: frame.width,
            frameHeight: frame.height,
            visibleX: visible.minX,
            visibleY: visible.minY,
            visibleWidth: visible.width,
            visibleHeight: visible.height,
            pixelWidth: mode.map { Int64($0.pixelWidth) },
            pixelHeight: mode.map { Int64($0.pixelHeight) },
            backingScale: Double(screen.backingScaleFactor),
            physicalWidthMm: positive(Double(physical.width)),
            physicalHeightMm: positive(Double(physical.height)),
            refreshHz: refreshRate(mode, screen: screen)
        )
        return DisplayReading(
            input: input,
            geom: DisplayGeom(key: key, frame: frame, visibleFrame: visible, isMain: isMain)
        )
    }

    /// The display's refresh rate: the mode's, else the screen's maximum frame rate.
    ///
    /// - Parameters:
    ///   - mode: The display's current mode, when CoreGraphics returns one.
    ///   - screen: The screen, whose maximum frame rate stands in when the mode reports zero.
    /// - Returns: The rate in hertz, or nil when neither source reports one.
    private static func refreshRate(_ mode: CGDisplayMode?, screen: NSScreen) -> Double? {
        positive(mode?.refreshRate ?? 0) ?? positive(Double(screen.maximumFramesPerSecond))
    }

    /// The value when it is greater than zero; EDID reports zero for what it does not know.
    ///
    /// - Parameter value: A measured value.
    /// - Returns: The value, or nil when it is zero or negative.
    private static func positive(_ value: Double) -> Double? {
        value > 0 ? value : nil
    }
}
