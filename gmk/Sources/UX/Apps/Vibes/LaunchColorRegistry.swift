import SwiftUI
import Observation

@Observable
@MainActor
final class LaunchColorRegistry {
    struct LaunchColor: Equatable, Sendable {
        let hex: String
        let color: Color
    }

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

    private var cursor = 0

    /// Assigns or returns the launch color for a prompt.
    ///
    /// - Parameter promptUuid: The prompt's UUID.
    /// - Returns: The assigned color, cycling through the palette.
    @discardableResult
    func assign(promptUuid: String) -> LaunchColor {
        if let existing = assignments[promptUuid] { return existing }
        let (r, g, b) = Self.palette[cursor % Self.palette.count]
        cursor = (cursor + 1) % Self.palette.count
        let assigned = LaunchColor(
            hex: String(format: "%02x%02x%02x", Int(r), Int(g), Int(b)),
            color: Color(
                .sRGB,
                red: Double(r) / 255.0,
                green: Double(g) / 255.0,
                blue: Double(b) / 255.0,
                opacity: 1
            )
        )
        assignments[promptUuid] = assigned
        return assigned
    }

    /// Returns the launch color assigned to a prompt, if any.
    ///
    /// - Parameter promptUuid: The prompt's UUID.
    /// - Returns: The assigned color, or `nil` if not yet assigned.
    func color(for promptUuid: String) -> LaunchColor? {
        assignments[promptUuid]
    }

    /// Removes the launch color assignment for a prompt.
    ///
    /// - Parameter promptUuid: The prompt's UUID.
    func clear(promptUuid: String) {
        assignments[promptUuid] = nil
    }
}
