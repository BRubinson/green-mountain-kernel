import Foundation

/// The workstation placement rules: the fixed workspace codes, a display set's identity,
/// the seed placement of a new workstation, and the refusals that keep every display occupied.
enum MachineHostPlacement {
    /// The global workspace codes, one per hotkey.
    enum WorkspaceCodes {
        /// The 21 codes in table order, which is both the grid order and the active hand-off order.
        static let all: [String] = [
            "1", "2", "3", "4", "5", "6", "7", "8", "9",
            "Q", "W", "E", "R", "T", "Y",
            "A", "S", "D", "F", "G", "H",
        ]
    }

    /// One connected display as the seed rule sees it.
    struct SeedDisplay: Hashable, Sendable {
        /// The display's stable identity within the machine.
        let stableKey: String
        /// Whether this is the machine's built-in panel.
        let isBuiltin: Bool
        /// The left edge of the display's frame in global coordinates.
        let originX: Double
    }

    /// The placement a new workstation starts with, keyed by display stable key.
    struct SeedPlan: Hashable, Sendable {
        /// Each display's fixed grid column; 0 is the seed display.
        let positions: [String: Int]
        /// The display each workspace code sits on.
        let placement: [String: String]
        /// The one visible code on each display.
        let active: [String: String]

        /// The plan for no displays at all.
        static let empty = SeedPlan(positions: [:], placement: [:], active: [:])
    }

    /// A recorded workstation's placement, keyed by display stable key.
    struct StoredLayout: Hashable, Sendable {
        /// The display each workspace code sits on.
        let placement: [String: String]
        /// The visible code on each display.
        let active: [String: String]
    }

    /// The layout a connected display set should show now, keyed by display stable key.
    struct TargetLayout: Hashable, Sendable {
        /// The set's identity, as `displaySetKey` spells it.
        let displaySetKey: String
        /// The display each workspace code sits on.
        let placement: [String: String]
        /// The visible code on each display.
        let active: [String: String]
        /// True when no workstation is recorded for the set, so `placement` and `active` are its seed.
        let isNew: Bool
    }

    /// Picks the layout for a connected display set: its recorded workstation's, else its seed.
    ///
    /// - Parameters:
    ///   - readings: The connected displays, in any order.
    ///   - known: The recorded workstations' layouts, by display-set key.
    /// - Returns: The layout, the same for every permutation of `readings`, or nil when no display is connected.
    static func targetLayout(readings: [SeedDisplay], known: [String: StoredLayout]) -> TargetLayout? {
        guard !readings.isEmpty else { return nil }
        let key = displaySetKey(readings.map(\.stableKey))
        if let stored = known[key] {
            return TargetLayout(displaySetKey: key, placement: stored.placement, active: stored.active, isNew: false)
        }
        let seed = seedPlan(readings)
        return TargetLayout(displaySetKey: key, placement: seed.placement, active: seed.active, isNew: true)
    }

    /// Derives a workstation's identity from the stable keys of its connected displays.
    /// - Parameter stableKeys: The connected displays' stable keys, in any order.
    /// - Returns: The keys sorted and joined with ",", identical for every ordering of the input.
    static func displaySetKey(_ stableKeys: [String]) -> String {
        stableKeys.sorted().joined(separator: ",")
    }

    /// Computes the starting positions, placement and active codes for a newly seen display set.
    ///
    /// Position 0 is the built-in display when one is present, otherwise the leftmost; the rest
    /// run left to right with ties broken by stable key. Every code starts on position 0 with "1"
    /// active; each further display takes the next code counting down from "H" as its only and
    /// active code. The first 21 displays each get a code; any display after that gets none.
    /// - Parameter displays: The connected displays, in any order.
    /// - Returns: The seed plan, the same for every permutation of `displays`, and empty when it is.
    static func seedPlan(_ displays: [SeedDisplay]) -> SeedPlan {
        let leftToRight = displays.sorted { ($0.originX, $0.stableKey) < ($1.originX, $1.stableKey) }
        guard let seed = leftToRight.first(where: \.isBuiltin) ?? leftToRight.first else { return .empty }
        let ordered = [seed] + leftToRight.filter { $0.stableKey != seed.stableKey }
        let codes = WorkspaceCodes.all
        var positions: [String: Int] = [:]
        var placement = Dictionary(uniqueKeysWithValues: codes.map { ($0, seed.stableKey) })
        var active = [seed.stableKey: codes[0]]
        for (position, display) in ordered.enumerated() {
            positions[display.stableKey] = position
            guard position > 0, position < codes.count else { continue }
            let code = codes[codes.count - position]
            placement[code] = display.stableKey
            active[display.stableKey] = code
        }
        return SeedPlan(positions: positions, placement: placement, active: active)
    }

    /// Checks whether moving a workspace code between displays of one workstation is allowed.
    /// - Parameters:
    ///   - code: The workspace code being moved.
    ///   - from: The display the code sits on now.
    ///   - to: The display the code would move to.
    ///   - placement: The workstation's current placement, code to display.
    ///   - members: The displays that belong to the workstation.
    /// - Returns: The refusal, or nil when the move is allowed.
    static func placementRefusal(
        code: String,
        from: String,
        to: String,
        placement: [String: String],
        members: Set<String>
    ) -> MachineHostError? {
        guard WorkspaceCodes.all.contains(code) else { return .unknownWorkspaceCode(code) }
        guard members.contains(to) else { return .displayNotInWorkstation(display: to) }
        guard from != to else { return nil }
        let othersOnSource = placement.contains { $0.key != code && $0.value == from }
        return othersOnSource ? nil : .wouldStrandDisplay(code: code, display: from)
    }

    /// Picks the code that becomes active on a display when its active code leaves it.
    /// - Parameters:
    ///   - code: The code leaving the display.
    ///   - display: The display the code is leaving.
    ///   - placement: The workstation's placement before the move, code to display.
    /// - Returns: The first remaining code on `display` in table order, or nil when none remains.
    static func activeHandOff(leaving code: String, from display: String, placement: [String: String]) -> String? {
        WorkspaceCodes.all.first { $0 != code && placement[$0] == display }
    }
}
