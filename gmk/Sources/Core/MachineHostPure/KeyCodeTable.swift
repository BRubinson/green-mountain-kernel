import Foundation

/// Carbon modifier masks, spelled as literals so the pure core never imports Carbon.
enum ModifierMask {
    /// `cmdKey`.
    static let command: UInt32 = 0x0100
    /// `shiftKey`.
    static let shift: UInt32 = 0x0200
    /// `optionKey`.
    static let option: UInt32 = 0x0800
    /// `controlKey`.
    static let control: UInt32 = 0x1000
}

/// The fixed hotkey table, its Carbon virtual key codes on the US-ANSI layout, and its legend text.
///
/// Virtual key codes name physical keys, so a binding survives an input-source switch.
enum KeyCodeTable {
    /// `kVK_LeftArrow`.
    static let leftArrow: UInt32 = 0x7B
    /// `kVK_RightArrow`.
    static let rightArrow: UInt32 = 0x7C

    /// The `kVK_*` code per lower-case name of every bound key.
    static let codes: [String: UInt32] = [
        "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04, "g": 0x05, "q": 0x0C, "w": 0x0D,
        "e": 0x0E, "r": 0x0F, "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14, "4": 0x15,
        "6": 0x16, "5": 0x17, "equal": 0x18, "9": 0x19, "7": 0x1A, "minus": 0x1B, "8": 0x1C,
        "left": leftArrow, "right": rightArrow,
    ]

    /// The display label per key code: upper-case letters, digits, `-`, `=` and arrows.
    static let labels: [UInt32: String] = Dictionary(
        uniqueKeysWithValues: codes.map { name, code in
            switch name {
            case "minus": (code, "-")
            case "equal": (code, "=")
            case "left": (code, "←")
            case "right": (code, "→")
            default: (code, name.uppercased())
            }
        }
    )

    /// Every hotkey, in legend order: show and move per workspace code, column focus, slide, then resize.
    ///
    /// Workspace chords are Option and Option-Shift with the code's own key. Column focus and slide are
    /// Control-Option and Control-Option-Shift with the arrows, which leaves Option-arrow word navigation
    /// to the frontmost app and keeps every direction off the workspace keys.
    static let bindings: [HotkeyBinding] = {
        let option = ModifierMask.option
        let optionShift = ModifierMask.option | ModifierMask.shift
        let controlOption = ModifierMask.control | ModifierMask.option
        let controlOptionShift = controlOption | ModifierMask.shift
        let step = Double(WMReducer.resizeStep)
        let codes = MachineHostPlacement.WorkspaceCodes.all
        var bindings: [HotkeyBinding] = []
        for code in codes {
            guard let key = Self.codes[code.lowercased()] else { continue }
            bindings.append(binding(key, option, .focusWorkspace, workspace: code))
        }
        for code in codes {
            guard let key = Self.codes[code.lowercased()] else { continue }
            bindings.append(binding(key, optionShift, .moveToWorkspace, workspace: code))
        }
        bindings.append(binding(leftArrow, controlOption, .focusLeft))
        bindings.append(binding(rightArrow, controlOption, .focusRight))
        bindings.append(binding(leftArrow, controlOptionShift, .slideLeft))
        bindings.append(binding(rightArrow, controlOptionShift, .slideRight))
        bindings.append(binding(Self.codes["minus"] ?? 0, option, .resizeShrink, step: step))
        bindings.append(binding(Self.codes["equal"] ?? 0, option, .resizeGrow, step: step))
        return bindings
    }()

    /// The display label for a virtual key code.
    ///
    /// - Parameter keyCode: A code from this table.
    /// - Returns: The label, or nil when the code is not in the table.
    static func label(for keyCode: UInt32) -> String? {
        labels[keyCode]
    }

    /// The modifier glyphs of a Carbon mask, in the macOS menu order.
    ///
    /// - Parameter modifiers: The Carbon modifier mask.
    /// - Returns: The glyphs, such as `⌃⌥⇧`; empty for no modifiers.
    static func glyphs(for modifiers: UInt32) -> String {
        var glyphs = ""
        if modifiers & ModifierMask.control != 0 { glyphs += "⌃" }
        if modifiers & ModifierMask.option != 0 { glyphs += "⌥" }
        if modifiers & ModifierMask.shift != 0 { glyphs += "⇧" }
        if modifiers & ModifierMask.command != 0 { glyphs += "⌘" }
        return glyphs
    }

    /// The legend text for a binding's chord: its modifier glyphs, then its key label.
    ///
    /// - Parameter binding: A binding from `bindings`.
    /// - Returns: The chord, such as `⌥⇧Q` or `⌃⌥←`.
    static func chordLabel(for binding: HotkeyBinding) -> String {
        glyphs(for: binding.modifiers) + (label(for: binding.keyCode) ?? "?")
    }

    /// The legend text for what a binding does, without its workspace code.
    ///
    /// - Parameter binding: A binding from `bindings`.
    /// - Returns: The meaning, such as `Show workspace` or `Widen column by 50 pt`.
    static func meaning(for binding: HotkeyBinding) -> String {
        let step = binding.resizeStep.map { " by \(Int($0)) pt" } ?? ""
        return switch binding.action {
        case .focusWorkspace: "Show workspace"
        case .moveToWorkspace: "Move window to workspace"
        case .focusLeft: "Focus column to the left"
        case .focusRight: "Focus column to the right"
        case .slideLeft: "Swap column left"
        case .slideRight: "Swap column right"
        case .resizeGrow: "Widen column\(step)"
        case .resizeShrink: "Narrow column\(step)"
        }
    }

    /// One table chord.
    ///
    /// - Parameters:
    ///   - keyCode: The virtual key code.
    ///   - modifiers: The Carbon modifier mask.
    ///   - action: What the chord does.
    ///   - workspace: The target workspace for the workspace actions.
    ///   - step: The resize step for the resize actions.
    /// - Returns: The binding.
    private static func binding(
        _ keyCode: UInt32,
        _ modifiers: UInt32,
        _ action: HotkeyAction,
        workspace: String? = nil,
        step: Double? = nil
    ) -> HotkeyBinding {
        HotkeyBinding(
            keyCode: keyCode,
            modifiers: modifiers,
            action: action,
            workspaceCode: workspace,
            resizeStep: step
        )
    }
}
