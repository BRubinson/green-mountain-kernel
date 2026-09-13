import SwiftUI

// MARK: - App-wide FocusedValues
//
// Find-in-page plumbing for cmd+F / cmd+G. The focused screen publishes these;
// AppCommands (and the menu bar) consume whichever screen currently has focus.

public struct FocusCommandPaletteKey: FocusedValueKey { public typealias Value = () -> Void }
public struct FocusFindInPageKey: FocusedValueKey { public typealias Value = () -> Void }
public struct FocusFindNextKey: FocusedValueKey { public typealias Value = () -> Void }
public struct FocusFindPreviousKey: FocusedValueKey { public typealias Value = () -> Void }

extension FocusedValues {
    public var commandPalette: (() -> Void)? {
        get { self[FocusCommandPaletteKey.self] }
        set { self[FocusCommandPaletteKey.self] = newValue }
    }
    public var findInPage: (() -> Void)? {
        get { self[FocusFindInPageKey.self] }
        set { self[FocusFindInPageKey.self] = newValue }
    }
    public var findNext: (() -> Void)? {
        get { self[FocusFindNextKey.self] }
        set { self[FocusFindNextKey.self] = newValue }
    }
    public var findPrevious: (() -> Void)? {
        get { self[FocusFindPreviousKey.self] }
        set { self[FocusFindPreviousKey.self] = newValue }
    }
}
