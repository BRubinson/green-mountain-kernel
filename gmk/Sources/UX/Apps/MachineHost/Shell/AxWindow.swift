import ApplicationServices
import CoreGraphics
import Foundation

/// The CoreGraphics window id behind an accessibility window element.
///
/// Private API with no public equivalent.
///
/// - Parameters:
///   - element: A window element.
///   - windowId: Receives the window id on success.
/// - Returns: `.success`, or the accessibility error the owning app answered with.
@_silgen_name("_AXUIElementGetWindow")
func _AXUIElementGetWindow(_ element: AXUIElement, _ windowId: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Low-level accessibility reads and writes on one window element.
///
/// Every call blocks on the owning app for up to its messaging timeout, so these run only on that app's
/// `AxAppThread`. A failed or timed-out call answers nil or false; nothing throws up the stack.
enum AxWindow {
    /// The attribute some apps expose to animate accessibility-driven frame changes.
    private static let enhancedUserInterface = "AXEnhancedUserInterface"
    /// The attribute that reports a window in native fullscreen.
    private static let fullScreen = "AXFullScreen"

    /// The CoreGraphics id of `element`.
    ///
    /// - Parameter element: A window element.
    /// - Returns: The window id, or nil when the app did not answer.
    static func windowId(_ element: AXUIElement) -> UInt32? {
        var id = CGWindowID(0)
        guard _AXUIElementGetWindow(element, &id) == .success, id != 0 else { return nil }
        return id
    }

    /// The frame of `element` in accessibility coordinates (top-left origin).
    ///
    /// - Parameter element: A window element.
    /// - Returns: The frame, or nil when the app did not answer.
    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let origin = point(element, kAXPositionAttribute as CFString),
            let size = size(element, kAXSizeAttribute as CFString)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    /// Moves and sizes `element` to `rect`, given in accessibility coordinates.
    ///
    /// Size is written before and after the position so a window that cannot grow past a display edge
    /// still lands at its full size. Enhanced user interface is off for the write, then restored.
    ///
    /// - Parameters:
    ///   - element: A window element.
    ///   - rect: The target frame in accessibility coordinates.
    ///   - app: The owning application element.
    /// - Returns: True when the position write was accepted.
    @discardableResult
    static func setFrame(_ element: AXUIElement, _ rect: CGRect, app: AXUIElement) -> Bool {
        withEnhancedUserInterfaceOff(app) { writeFrame(element, rect) }
    }

    /// Moves and sizes `element` to `rect`, size before and after the position, with no attribute toggle.
    ///
    /// - Parameters:
    ///   - element: A window element.
    ///   - rect: The target frame in accessibility coordinates.
    /// - Returns: True when the position write was accepted.
    @discardableResult
    static func writeFrame(_ element: AXUIElement, _ rect: CGRect) -> Bool {
        setSize(element, rect.size)
        let moved = setPoint(element, rect.origin)
        setSize(element, rect.size)
        return moved
    }

    /// Runs `body` with enhanced user interface off on `app`, restoring it afterwards when it was on.
    ///
    /// - Parameters:
    ///   - app: The application element.
    ///   - body: The frame writes.
    /// - Returns: What `body` returns.
    @discardableResult
    static func withEnhancedUserInterfaceOff<Result>(_ app: AXUIElement, _ body: () -> Result) -> Result {
        let enhanced = bool(app, enhancedUserInterface as CFString)
        if enhanced { AXUIElementSetAttributeValue(app, enhancedUserInterface as CFString, kCFBooleanFalse) }
        defer { if enhanced { AXUIElementSetAttributeValue(app, enhancedUserInterface as CFString, kCFBooleanTrue) } }
        return body()
    }

    /// Makes `element` its app's main window and raises it.
    ///
    /// - Parameter element: A window element.
    /// - Returns: True when the raise was accepted.
    @discardableResult
    static func raise(_ element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXMainAttribute as CFString, kCFBooleanTrue)
        return AXUIElementPerformAction(element, kAXRaiseAction as CFString) == .success
    }

    /// The `AXRole` of `element`.
    ///
    /// - Parameter element: An element.
    /// - Returns: The role, or nil when the app did not answer.
    static func role(_ element: AXUIElement) -> String? {
        string(element, kAXRoleAttribute as CFString)
    }

    /// The `AXSubrole` of `element`.
    ///
    /// - Parameter element: An element.
    /// - Returns: The subrole, or nil when the app did not answer.
    static func subrole(_ element: AXUIElement) -> String? {
        string(element, kAXSubroleAttribute as CFString)
    }

    /// The `AXTitle` of `element`.
    ///
    /// - Parameter element: An element.
    /// - Returns: The title, or nil when the app did not answer.
    static func title(_ element: AXUIElement) -> String? {
        string(element, kAXTitleAttribute as CFString)
    }

    /// True when `element` is minimized; false when it is not or the app did not answer.
    ///
    /// - Parameter element: A window element.
    /// - Returns: The `AXMinimized` value.
    static func isMinimized(_ element: AXUIElement) -> Bool {
        bool(element, kAXMinimizedAttribute as CFString)
    }

    /// True when `element` is in native fullscreen; false when it is not or the app did not answer.
    ///
    /// - Parameter element: A window element.
    /// - Returns: The `AXFullScreen` value.
    static func isFullscreen(_ element: AXUIElement) -> Bool {
        bool(element, fullScreen as CFString)
    }

    /// The windows `app` reports.
    ///
    /// An app that has no windows attribute answers empty; a timeout or any other error is no answer.
    ///
    /// - Parameter app: An application element.
    /// - Returns: The window elements, or nil when the app did not answer.
    static func windows(of app: AXUIElement) -> [AXUIElement]? {
        var value: CFTypeRef?
        switch AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) {
        case .success:
            return value as? [AXUIElement]
        case .noValue, .attributeUnsupported:
            return []
        default:
            return nil
        }
    }

    /// The focused window of `app`.
    ///
    /// - Parameter app: An application element.
    /// - Returns: The focused window, or nil when there is none or the app did not answer.
    static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
            let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        return (value as! AXUIElement)  // swiftlint:disable:this force_cast
    }

    /// A string attribute of `element`.
    ///
    /// - Parameters:
    ///   - element: An element.
    ///   - attribute: The attribute name.
    /// - Returns: The value, or nil when absent or unanswered.
    private static func string(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return nil }
        return value as? String
    }

    /// A boolean attribute of `element`.
    ///
    /// - Parameters:
    ///   - element: An element.
    ///   - attribute: The attribute name.
    /// - Returns: The value, or false when absent or unanswered.
    private static func bool(_ element: AXUIElement, _ attribute: CFString) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// A point attribute of `element`.
    ///
    /// - Parameters:
    ///   - element: An element.
    ///   - attribute: The attribute name.
    /// - Returns: The point, or nil when absent or unanswered.
    private static func point(_ element: AXUIElement, _ attribute: CFString) -> CGPoint? {
        guard let value = axValue(element, attribute) else { return nil }
        var point = CGPoint.zero
        return AXValueGetValue(value, .cgPoint, &point) ? point : nil
    }

    /// A size attribute of `element`.
    ///
    /// - Parameters:
    ///   - element: An element.
    ///   - attribute: The attribute name.
    /// - Returns: The size, or nil when absent or unanswered.
    private static func size(_ element: AXUIElement, _ attribute: CFString) -> CGSize? {
        guard let value = axValue(element, attribute) else { return nil }
        var size = CGSize.zero
        return AXValueGetValue(value, .cgSize, &size) ? size : nil
    }

    /// An `AXValue` attribute of `element`.
    ///
    /// - Parameters:
    ///   - element: An element.
    ///   - attribute: The attribute name.
    /// - Returns: The value, or nil when absent, unanswered or of another type.
    private static func axValue(_ element: AXUIElement, _ attribute: CFString) -> AXValue? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &value) == .success,
            let value, CFGetTypeID(value) == AXValueGetTypeID()
        else { return nil }
        return (value as! AXValue)  // swiftlint:disable:this force_cast
    }

    /// Writes the position of `element`.
    ///
    /// - Parameters:
    ///   - element: A window element.
    ///   - origin: The top-left corner in accessibility coordinates.
    /// - Returns: True when the app accepted the write.
    @discardableResult
    private static func setPoint(_ element: AXUIElement, _ origin: CGPoint) -> Bool {
        var origin = origin
        guard let value = AXValueCreate(.cgPoint, &origin) else { return false }
        return AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, value) == .success
    }

    /// Writes the size of `element`.
    ///
    /// - Parameters:
    ///   - element: A window element.
    ///   - size: The size in points.
    /// - Returns: True when the app accepted the write.
    @discardableResult
    private static func setSize(_ element: AXUIElement, _ size: CGSize) -> Bool {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return false }
        return AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, value) == .success
    }
}
