import SwiftUI

// MARK: - App-wide FocusedValues
//
// Find-in-page plumbing for cmd+F / cmd+G. The focused screen publishes these;
// AppCommands (and the menu bar) consume whichever screen currently has focus.

struct FocusCommandPaletteKey: FocusedValueKey { typealias Value = () -> Void }
struct FocusFindInPageKey: FocusedValueKey { typealias Value = () -> Void }
struct FocusFindNextKey: FocusedValueKey { typealias Value = () -> Void }
struct FocusFindPreviousKey: FocusedValueKey { typealias Value = () -> Void }

extension FocusedValues {
    var commandPalette: (() -> Void)? {
        get { self[FocusCommandPaletteKey.self] }
        set { self[FocusCommandPaletteKey.self] = newValue }
    }
    var findInPage: (() -> Void)? {
        get { self[FocusFindInPageKey.self] }
        set { self[FocusFindInPageKey.self] = newValue }
    }
    var findNext: (() -> Void)? {
        get { self[FocusFindNextKey.self] }
        set { self[FocusFindNextKey.self] = newValue }
    }
    var findPrevious: (() -> Void)? {
        get { self[FocusFindPreviousKey.self] }
        set { self[FocusFindPreviousKey.self] = newValue }
    }
}
