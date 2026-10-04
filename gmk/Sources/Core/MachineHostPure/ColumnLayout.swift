import CoreGraphics
import Foundation

/// Weighted column arithmetic: a strip's columns share the visible width in proportion to their weights.
enum ColumnLayout {
    /// The narrowest a column may be resized to, in points.
    static let defaultMinWidth: CGFloat = 100

    /// The column frames for `weights` tiled left to right across `visible`.
    ///
    /// Column edges are rounded to whole points relative to the left edge, and the last column ends exactly
    /// on the right edge, so the widths sum to the visible width with no gap or overlap.
    ///
    /// - Parameters:
    ///   - weights: The column weights, left to right; each must be positive.
    ///   - visible: The display's visible frame.
    /// - Returns: One full-height frame per weight, or an empty array when `weights` is empty.
    static func frames(weights: [Double], visible: CGRect) -> [CGRect] {
        guard !weights.isEmpty else { return [] }
        let total = weights.reduce(0, +)
        var edges: [CGFloat] = [0]
        var running = 0.0
        for weight in weights.dropLast() {
            running += weight
            edges.append((visible.width * CGFloat(running / total)).rounded())
        }
        edges.append(visible.width)
        return weights.indices.map { index in
            CGRect(
                x: visible.minX + edges[index],
                y: visible.minY,
                width: edges[index + 1] - edges[index],
                height: visible.height
            )
        }
    }

    /// The weight a new column is appended with: the mean of the existing weights.
    ///
    /// - Parameter existing: The strip's current weights.
    /// - Returns: The mean, or 1.0 when the strip is empty.
    static func appendWeight(existing: [Double]) -> Double {
        existing.isEmpty ? 1.0 : existing.reduce(0, +) / Double(existing.count)
    }

    /// The weights after the user dragged an edge of column `index` so the column now spans `observed`.
    ///
    /// The edge that moved the farther decides the trade: a left edge trades with the left neighbour, a right
    /// edge with the right one. A drag of an outer edge, which has no neighbour, changes nothing.
    ///
    /// - Parameters:
    ///   - weights: The current weights.
    ///   - index: The resized column.
    ///   - observed: The column's new frame.
    ///   - visible: The strip's visible frame.
    ///   - minWidth: The narrowest either affected column may become.
    /// - Returns: The new weights, with `Σw` unchanged.
    static func redistribute(
        weights: [Double],
        index: Int,
        observed: CGRect,
        visible: CGRect,
        minWidth: CGFloat = defaultMinWidth
    ) -> [Double] {
        guard weights.indices.contains(index), visible.width > 0 else { return weights }
        let current = frames(weights: weights, visible: visible)[index]
        let leftEdgeMoved = abs(observed.minX - current.minX) > abs(observed.maxX - current.maxX)
        let neighbour = leftEdgeMoved ? index - 1 : index + 1
        guard weights.indices.contains(neighbour) else { return weights }
        return trade(
            weights: weights,
            index: index,
            neighbour: neighbour,
            deltaPoints: observed.width - current.width,
            visibleWidth: visible.width,
            minWidth: minWidth
        )
    }

    /// The weights after widening column `index` by `deltaPoints`, taken from one neighbour.
    ///
    /// The right neighbour gives or takes the width; the last column trades with its left neighbour. Both
    /// columns are clamped to `minWidth`, and a strip of one column is unchanged.
    ///
    /// - Parameters:
    ///   - weights: The current weights.
    ///   - index: The column to resize.
    ///   - deltaPoints: Points to add; negative narrows the column.
    ///   - visibleWidth: The width of the strip's visible frame.
    ///   - minWidth: The narrowest either affected column may become.
    /// - Returns: The new weights, with `Σw` unchanged.
    static func resizeStep(
        weights: [Double],
        index: Int,
        deltaPoints: CGFloat,
        visibleWidth: CGFloat,
        minWidth: CGFloat = defaultMinWidth
    ) -> [Double] {
        guard weights.indices.contains(index), weights.count > 1 else { return weights }
        return trade(
            weights: weights,
            index: index,
            neighbour: index + 1 < weights.count ? index + 1 : index - 1,
            deltaPoints: deltaPoints,
            visibleWidth: visibleWidth,
            minWidth: minWidth
        )
    }

    /// The weights after column `index` takes `deltaPoints` from column `neighbour`.
    ///
    /// Both columns are clamped to `minWidth`.
    ///
    /// - Parameters:
    ///   - weights: The current weights.
    ///   - index: The column to resize.
    ///   - neighbour: The column that gives or takes the width.
    ///   - deltaPoints: Points to add to `index`; negative narrows it.
    ///   - visibleWidth: The width of the strip's visible frame.
    ///   - minWidth: The narrowest either column may become.
    /// - Returns: The new weights, with `Σw` unchanged.
    private static func trade(
        weights: [Double],
        index: Int,
        neighbour: Int,
        deltaPoints: CGFloat,
        visibleWidth: CGFloat,
        minWidth: CGFloat
    ) -> [Double] {
        guard visibleWidth > 0 else { return weights }
        let pointsPerWeight = Double(visibleWidth) / weights.reduce(0, +)
        let own = weights[index] * pointsPerWeight
        let pair = own + weights[neighbour] * pointsPerWeight
        guard pair >= 2 * Double(minWidth) else { return weights }
        let newOwn = min(max(own + Double(deltaPoints), Double(minWidth)), pair - Double(minWidth))
        var result = weights
        result[index] = newOwn / pointsPerWeight
        result[neighbour] = (pair - newOwn) / pointsPerWeight
        return result
    }

    /// The focus index after moving `delta` columns, clamped to the strip with no wrap.
    ///
    /// - Parameters:
    ///   - from: The focused index, or nil when nothing is focused.
    ///   - delta: Columns to move; negative is left.
    ///   - count: The number of columns.
    /// - Returns: The new index, or nil when the strip is empty.
    static func focusIndex(from: Int?, delta: Int, count: Int) -> Int? {
        guard count > 0 else { return nil }
        guard let from else { return 0 }
        return min(max(from + delta, 0), count - 1)
    }

    /// The order after swapping the element at `index` with the one `delta` places away.
    ///
    /// The target is clamped to the ends with no wrap.
    ///
    /// - Parameters:
    ///   - order: The elements, left to right.
    ///   - index: The element to move.
    ///   - delta: Places to move; negative is left.
    /// - Returns: The new order and the moved element's new index; the input when the move is clamped away.
    static func slide<T>(order: [T], index: Int, delta: Int) -> ([T], Int) {
        guard order.indices.contains(index) else { return (order, index) }
        let target = min(max(index + delta, 0), order.count - 1)
        guard target != index else { return (order, index) }
        var result = order
        result.swapAt(index, target)
        return (result, target)
    }

    /// The share of a neighbour's width a dragged window must travel from its slot to take its place.
    static let reorderShare: CGFloat = 1.0 / 3.0

    /// The adjacent column a window displaced `displacement` points from its slot swaps with, if any.
    ///
    /// Passing a neighbour takes `reorderShare` of its width. Passing back the neighbour last swapped with
    /// takes its whole width: the window sits `1 - reorderShare` of it past the new slot when the swap fires,
    /// so the return needs a further `reorderShare`, and no hover can thrash whatever the widths.
    ///
    /// - Parameters:
    ///   - slots: The column frames, left to right, in the current order.
    ///   - index: The dragged column.
    ///   - displacement: How far the dragged window's left edge sits from its slot; positive is right.
    ///   - returning: The column the dragged window last swapped with, or nil.
    /// - Returns: `index - 1` or `index + 1`, or nil when the dragged column keeps its place.
    static func reorderTarget(slots: [CGRect], index: Int, displacement: CGFloat, returning: Int?) -> Int? {
        guard slots.indices.contains(index) else { return nil }
        for neighbour in [index + 1, index - 1] where slots.indices.contains(neighbour) {
            let share = neighbour == returning ? 1 : reorderShare
            let toward = neighbour > index ? displacement : -displacement
            if toward >= share * slots[neighbour].width { return neighbour }
        }
        return nil
    }

    /// The weights with the column at `index` removed and the rest renormalized.
    ///
    /// - Parameters:
    ///   - weights: The current weights.
    ///   - index: The column to remove.
    /// - Returns: The remaining weights, renormalized.
    static func remove(weights: [Double], at index: Int) -> [Double] {
        guard weights.indices.contains(index) else { return renormalize(weights) }
        var result = weights
        result.remove(at: index)
        return renormalize(result)
    }

    /// The weights scaled so their mean is 1, which keeps ratios and stops drift.
    ///
    /// - Parameter weights: The weights to scale.
    /// - Returns: The scaled weights, or the input when it is empty or sums to zero.
    static func renormalize(_ weights: [Double]) -> [Double] {
        let total = weights.reduce(0, +)
        guard !weights.isEmpty, total > 0 else { return weights }
        let scale = Double(weights.count) / total
        return weights.map { $0 * scale }
    }
}
