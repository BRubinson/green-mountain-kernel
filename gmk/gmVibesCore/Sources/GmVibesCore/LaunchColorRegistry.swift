import SwiftUI
import Observation

/// Which colour a prompt's launched pane wears, for the length of this process
/// and no longer.
///
/// THE INVARIANT THIS TYPE EXISTS TO HOLD: one RGB triple per palette entry
/// produces BOTH the `hex` the OSC 1337 escape writes into the terminal AND the
/// `color` the SwiftUI badge ring draws, so the terminal tab and the badge can
/// never disagree. Two independent tables would drift the first time somebody
/// tuned one of them.
///
/// APP-LIFETIME, held by `GMVibesServices`, because `PromptRunBar` and
/// `PromptNavRow` must read ONE store — and because `PromptEditorPane` is
/// recreated per prompt via `.id(stub.uuid)`, so pane `@State` could not hold
/// this even if it were permitted to.
///
/// IN-MEMORY, and deliberately so. A plain dictionary plus a cursor: NOT
/// `Codable`, no `UserDefaults`, no db, no save path. The no-persistence promise
/// of this slice erodes by accident the moment one of those exists, and the
/// colour is a fact about a window that is open right now.
@Observable
@MainActor
final class LaunchColorRegistry {
    /// One palette entry, in both the forms its two consumers need.
    struct LaunchColor: Equatable, Sendable {
        /// Six lowercase hex digits, no leading `#` — the form
        /// `SetColors=tab=<hex>` takes.
        let hex: String
        let color: Color
    }

    /// EIGHT, fixed. Small enough that the colours stay tellable apart at tab
    /// size, and large enough that an ordinary session never wraps.
    private static let palette: [(UInt8, UInt8, UInt8)] = [
        (0xe0, 0x6c, 0x75),
        (0xd1, 0x9a, 0x66),
        (0xe5, 0xc0, 0x7b),
        (0x98, 0xc3, 0x79),
        (0x56, 0xb6, 0xc2),
        (0x61, 0xaf, 0xef),
        (0xc6, 0x78, 0xdd),
        (0xff, 0x79, 0xc6),
    ]

    private(set) var assignments: [String: LaunchColor] = [:]

    /// ROUND-ROBIN with a wrapping cursor — NEVER hash-of-uuid, which collides
    /// silently and gives two live panes the same colour with no way to notice.
    /// The wrap is documented rather than avoided: the 9th live launch
    /// deterministically reuses colour 1, which is reuse you can reason about.
    private var cursor = 0

    /// The colour for this prompt, assigning one on first use.
    ///
    /// RE-PRESSING PLAY ON A PROMPT KEEPS ITS EXISTING COLOUR. A prompt's
    /// identity survives a relaunch, and burning a palette slot per press would
    /// exhaust eight colours inside one session of ordinary use.
    @discardableResult
    func assign(promptUuid: String) -> LaunchColor {
        if let existing = assignments[promptUuid] { return existing }
        let (r, g, b) = Self.palette[cursor % Self.palette.count]
        cursor = (cursor + 1) % Self.palette.count
        let assigned = LaunchColor(
            hex: String(format: "%02x%02x%02x", Int(r), Int(g), Int(b)),
            color: Color(.sRGB,
                         red: Double(r) / 255.0,
                         green: Double(g) / 255.0,
                         blue: Double(b) / 255.0,
                         opacity: 1))
        assignments[promptUuid] = assigned
        return assigned
    }

    /// The colour this prompt already has, or nil — a READ that assigns
    /// nothing, so a list row rendering a thousand prompts consumes no slots.
    func color(for promptUuid: String) -> LaunchColor? {
        assignments[promptUuid]
    }

    func clear(promptUuid: String) {
        assignments[promptUuid] = nil
    }
}
