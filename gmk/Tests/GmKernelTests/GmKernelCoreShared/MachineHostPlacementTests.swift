import Foundation
import XCTest

/// Workspace codes, display-set identity, seed placement, move refusals and the active hand-off.
final class MachineHostPlacementTests: XCTestCase {
    private typealias Placement = MachineHostPlacement
    private typealias Display = MachineHostPlacement.SeedDisplay

    /// An external display to the left of the built-in panel.
    private let leftExternal = Display(stableKey: "ext-left", isBuiltin: false, originX: -1920)
    /// The built-in panel, deliberately not the leftmost display.
    private let builtin = Display(stableKey: "builtin", isBuiltin: true, originX: 0)
    /// An external display to the right of the built-in panel.
    private let rightExternal = Display(stableKey: "ext-right", isBuiltin: false, originX: 1512)

    func testCodesAreTheTwentyOneInTableOrder() {
        XCTAssertEqual(
            Placement.WorkspaceCodes.all,
            ["1", "2", "3", "4", "5", "6", "7", "8", "9", "Q", "W", "E", "R", "T", "Y", "A", "S", "D", "F", "G", "H"]
        )
        XCTAssertEqual(Placement.WorkspaceCodes.all.count, 21)
        XCTAssertEqual(Placement.WorkspaceCodes.all.last, "H")
    }

    func testDisplaySetKeyIgnoresInputOrder() {
        XCTAssertEqual(Placement.displaySetKey(["b", "c", "a"]), "a,b,c")
        XCTAssertEqual(Placement.displaySetKey(["c", "a", "b"]), Placement.displaySetKey(["a", "b", "c"]))
    }

    func testSeedPutsTheBuiltinFirstEvenWhenItIsNotLeftmost() {
        let plan = Placement.seedPlan([rightExternal, leftExternal, builtin])
        XCTAssertEqual(plan.positions, ["builtin": 0, "ext-left": 1, "ext-right": 2])
        XCTAssertEqual(plan.placement.values.filter { $0 == "builtin" }.count, 19)
        XCTAssertEqual(plan.active, ["builtin": "1", "ext-left": "H", "ext-right": "G"])
        XCTAssertEqual(plan.placement["H"], "ext-left")
        XCTAssertEqual(plan.placement["G"], "ext-right")
        XCTAssertEqual(Set(plan.placement.keys), Set(Placement.WorkspaceCodes.all))
        XCTAssertEqual(plan.placement.count, 21)
    }

    func testSeedWithoutABuiltinStartsAtTheLeftmost() {
        let middle = Display(stableKey: "middle", isBuiltin: false, originX: 0)
        let plan = Placement.seedPlan([rightExternal, middle, leftExternal])
        XCTAssertEqual(plan.positions, ["ext-left": 0, "middle": 1, "ext-right": 2])
        XCTAssertEqual(plan.active["ext-left"], "1")
    }

    func testSeedWithOneDisplayPutsEveryCodeOnIt() {
        let plan = Placement.seedPlan([builtin])
        XCTAssertEqual(plan.positions, ["builtin": 0])
        XCTAssertEqual(plan.placement.count, 21)
        XCTAssertTrue(plan.placement.values.allSatisfy { $0 == "builtin" })
        XCTAssertEqual(plan.active, ["builtin": "1"])
    }

    func testSeedIsDeterministicUnderPermutation() {
        let tied = Display(stableKey: "ext-tied", isBuiltin: false, originX: 1512)
        let inputs = [builtin, leftExternal, rightExternal, tied]
        let expected = Placement.seedPlan(inputs)
        for permutation in permutations(of: inputs) {
            XCTAssertEqual(Placement.seedPlan(permutation), expected)
        }
    }

    func testSeedOfNoDisplaysIsEmpty() {
        XCTAssertEqual(Placement.seedPlan([]), Placement.SeedPlan.empty)
    }

    func testRefusesMovingTheLastCodeOffADisplay() {
        let plan = Placement.seedPlan([builtin, rightExternal])
        let refusal = Placement.placementRefusal(
            code: "H",
            from: "ext-right",
            to: "builtin",
            placement: plan.placement,
            members: ["builtin", "ext-right"]
        )
        XCTAssertEqual(refusal, .wouldStrandDisplay(code: "H", display: "ext-right"))
    }

    func testRefusesATargetOutsideTheWorkstation() {
        let plan = Placement.seedPlan([builtin, rightExternal])
        let refusal = Placement.placementRefusal(
            code: "1",
            from: "builtin",
            to: "elsewhere",
            placement: plan.placement,
            members: ["builtin", "ext-right"]
        )
        XCTAssertEqual(refusal, .displayNotInWorkstation(display: "elsewhere"))
    }

    func testRefusesAnUnknownCode() {
        let plan = Placement.seedPlan([builtin, rightExternal])
        let refusal = Placement.placementRefusal(
            code: "Z",
            from: "builtin",
            to: "ext-right",
            placement: plan.placement,
            members: ["builtin", "ext-right"]
        )
        XCTAssertEqual(refusal, .unknownWorkspaceCode("Z"))
    }

    func testAcceptsAMoveThatLeavesTheSourceOccupied() {
        let plan = Placement.seedPlan([builtin, rightExternal])
        let refusal = Placement.placementRefusal(
            code: "1",
            from: "builtin",
            to: "ext-right",
            placement: plan.placement,
            members: ["builtin", "ext-right"]
        )
        XCTAssertNil(refusal)
    }

    func testHandOffPicksTheFirstRemainingCodeInTableOrder() {
        let plan = Placement.seedPlan([builtin, rightExternal])
        XCTAssertEqual(Placement.activeHandOff(leaving: "1", from: "builtin", placement: plan.placement), "2")
        XCTAssertEqual(Placement.activeHandOff(leaving: "5", from: "builtin", placement: plan.placement), "1")
        XCTAssertNil(Placement.activeHandOff(leaving: "H", from: "ext-right", placement: plan.placement))
    }

    func testEverySeededDisplayHasACodeAndExactlyOneActive() {
        let inputs = [builtin, leftExternal, rightExternal]
        for count in 1...inputs.count {
            let displays = Array(inputs.prefix(count))
            let plan = Placement.seedPlan(displays)
            for display in displays {
                let codes = plan.placement.filter { $0.value == display.stableKey }.map(\.key)
                XCTAssertFalse(codes.isEmpty, display.stableKey)
                let active = plan.active[display.stableKey]
                XCTAssertNotNil(active, display.stableKey)
                XCTAssertTrue(active.map(codes.contains) ?? false, display.stableKey)
            }
            XCTAssertEqual(plan.active.count, displays.count)
        }
    }

    func testTwentyOneDisplaysEachGetExactlyOneCodeAndItIsActive() {
        let displays = (0..<21).map { Display(stableKey: "d\($0)", isBuiltin: $0 == 0, originX: Double($0) * 1000) }
        let plan = Placement.seedPlan(displays)
        XCTAssertEqual(plan.active.count, 21)
        for display in displays {
            let codes = plan.placement.filter { $0.value == display.stableKey }.map(\.key)
            XCTAssertEqual(codes.count, 1, display.stableKey)
            XCTAssertEqual(plan.active[display.stableKey], codes.first, display.stableKey)
        }
        XCTAssertEqual(Set(plan.active.values), Set(Placement.WorkspaceCodes.all))
    }

    func testDisplaysAfterTheTwentyFirstGetNoCode() {
        let displays = (0..<22).map { Display(stableKey: "d\($0)", isBuiltin: false, originX: Double($0) * 1000) }
        let plan = Placement.seedPlan(displays)
        XCTAssertEqual(plan.active.count, 21)
        XCTAssertNil(plan.active["d21"])
        XCTAssertFalse(plan.placement.values.contains("d21"))
    }

    func testTargetLayoutOfAKnownSetIsItsStoredLayout() {
        let stored = Placement.StoredLayout(placement: ["1": "builtin", "H": "ext-right"], active: ["builtin": "2"])
        let key = Placement.displaySetKey(["builtin", "ext-right"])
        let layout = Placement.targetLayout(readings: [rightExternal, builtin], known: [key: stored])
        XCTAssertEqual(layout?.displaySetKey, key)
        XCTAssertEqual(layout?.placement, stored.placement)
        XCTAssertEqual(layout?.active, stored.active)
        XCTAssertEqual(layout?.isNew, false)
    }

    func testTargetLayoutOfAnUnknownSetIsItsSeed() {
        let other = Placement.StoredLayout(placement: ["1": "builtin"], active: ["builtin": "1"])
        let readings = [rightExternal, builtin]
        let layout = Placement.targetLayout(readings: readings, known: ["builtin": other])
        let seed = Placement.seedPlan(readings)
        XCTAssertEqual(layout?.placement, seed.placement)
        XCTAssertEqual(layout?.active, seed.active)
        XCTAssertEqual(layout?.isNew, true)
    }

    func testTargetLayoutOfNoDisplaysIsNil() {
        XCTAssertNil(Placement.targetLayout(readings: [], known: [:]))
    }

    func testTargetLayoutIgnoresReadingOrder() {
        let inputs = [builtin, leftExternal, rightExternal]
        let expected = Placement.targetLayout(readings: inputs, known: [:])
        for permutation in permutations(of: inputs) {
            XCTAssertEqual(Placement.targetLayout(readings: permutation, known: [:]), expected)
        }
    }

    /// Every ordering of the given displays.
    /// - Parameter items: The displays to permute.
    /// - Returns: All `items.count!` orderings.
    private func permutations(of items: [Display]) -> [[Display]] {
        guard let head = items.first else { return [[]] }
        return permutations(of: Array(items.dropFirst()))
            .flatMap { rest in
                (0...rest.count)
                    .map { index in
                        var ordering = rest
                        ordering.insert(head, at: index)
                        return ordering
                    }
            }
    }
}
