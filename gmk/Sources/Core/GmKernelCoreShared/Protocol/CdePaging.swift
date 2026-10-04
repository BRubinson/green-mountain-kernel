import Foundation

// MARK: - Byte-budgeted paging (the cde server's page vocabulary)

/// Where a byte-mode page sits in the whole record.
///
/// Every cde read asked for `page_bytes` carries one of these; a read that was
/// not carries nil and is the historical response, byte for byte.
struct CdePage: Codable, Hashable, Sendable {
    /// The budget that was applied, after clamping.
    let pageBytes: Int
    /// nil on the last page; otherwise the opaque `"<region>:<position>"` to
    /// pass back as `page_cursor`, never constructed by hand.
    let nextCursor: String?
    /// Every pageable region of this read, IN FILL ORDER, whether or not any
    /// of it landed on this page — so an empty region on the page is
    /// distinguishable from an empty region in the record.
    let regions: [CdePageRegion]

    /// Creates a page with the given byte budget, optional next cursor, and regions.
    /// - Parameters:
    ///   - pageBytes: The budget applied after clamping.
    ///   - nextCursor: The opaque cursor to resume at, or nil on the last page.
    ///   - regions: The pageable regions in fill order, by their counts on this page.
    init(pageBytes: Int, nextCursor: String?, regions: [CdePageRegion]) {
        self.pageBytes = pageBytes
        self.nextCursor = nextCursor
        self.regions = regions
    }
}

/// One pageable region: a row array, or one long text delivered as windows.
struct CdePageRegion: Codable, Hashable, Sendable {
    let name: String
    /// Rows (or characters, for a text region) delivered on THIS page.
    let returned: Int
    /// The region's full size in the record.
    let total: Int

    /// Creates a page region with the given name and counts.
    /// - Parameters:
    ///   - name: The region identifier.
    ///   - returned: Rows or characters delivered on this page.
    ///   - total: The region's full size in the record.
    init(name: String, returned: Int, total: Int) {
        self.name = name
        self.returned = returned
        self.total = total
    }
}

/// One character window of a long text.
///
/// The reader concatenates windows of the same region in `offset` order; a
/// text that fits arrives as one window with offset 0 and `returnedChars ==
/// totalChars`.
struct CdeTextWindow: Codable, Hashable, Sendable {
    let region: String
    let text: String
    /// Character offset of `text` inside the whole blob (Swift `Character`
    /// units, so a grapheme is never split).
    let offset: Int
    let returnedChars: Int
    let totalChars: Int

    /// Creates a text window for the given region and slice.
    /// - Parameters:
    ///   - region: The region identifier.
    ///   - text: The slice of the blob on this page.
    ///   - offset: Character offset of `text` inside the whole blob.
    ///   - returnedChars: Character count of this window.
    ///   - totalChars: Total character count of the whole blob.
    init(region: String, text: String, offset: Int, returnedChars: Int, totalChars: Int) {
        self.region = region
        self.text = text
        self.offset = offset
        self.returnedChars = returnedChars
        self.totalChars = totalChars
    }
}

/// The parsed form of the opaque cursor string.
///
/// Only the string crosses the wire; this is what a repository validates on
/// the way in.
struct CdePageCursor: Hashable, Sendable {
    let region: String
    let position: Int

    /// Creates a cursor at the given region and position.
    /// - Parameters:
    ///   - region: The region identifier.
    ///   - position: The resumption point (row id or character offset).
    init(region: String, position: Int) {
        self.region = region
        self.position = position
    }

    /// Creates a cursor by parsing an opaque wire string.
    ///
    /// The format is `"<region>:<position>"`, split on the LAST colon because
    /// a region name may itself carry one (`overview:<uuid>`). Returns nil if
    /// the string is invalid, region is empty, or position is negative.
    /// - Parameter wire: The opaque cursor string from a prior read.
    init?(_ wire: String) {
        guard let colon = wire.lastIndex(of: ":") else { return nil }
        let region = String(wire[wire.startIndex..<colon])
        let digits = wire[wire.index(after: colon)...]
        guard !region.isEmpty, let position = Int(digits), position >= 0 else { return nil }
        self.region = region
        self.position = position
    }

    var wireString: String { "\(region):\(position)" }
}

enum CdePagerError: Error, CustomStringConvertible, Equatable {
    case badCursor(String)

    var description: String {
        switch self {
        case .badCursor(let cursor):
            return "page_cursor '\(cursor)' is not a page.next_cursor this read produced"
        }
    }
}

/// THE ONE BYTE-BUDGET FILLER.
///
/// Offers each region in fill order; takes what fits the budget (measured with
/// the SAME encoder as the result) and records the cursor where it stopped. At
/// least one unit lands per page so a page always advances; regions before the
/// cursor are skipped and regions after an exhausted one report returned 0,
/// both with their true totals; a cursor naming an unoffered region or
/// position past its end is `badCursor`.
struct CdePager {
    static let minimumTextSlice = 512
    static let textStep = 512
    static let minimumPageBytes = 4_096

    let pageBytes: Int
    private let encoder = CdeResultBudget.encoder()
    private var remaining: Int
    private var regions: [CdePageRegion] = []
    private let cursor: CdePageCursor?
    private var reachedCursorRegion: Bool
    private var exhausted = false
    private var next: CdePageCursor?
    /// Set when the cursor named a region; cleared when that region is offered.
    ///
    /// Still set at `page` time means the cursor was bad.
    private var cursorRegionSeen = false

    /// Creates a pager with the given byte budget and optional resume cursor.
    /// - Parameters:
    ///   - pageBytes: The budget cap; clamped to the valid range.
    ///   - cursor: An opaque cursor from a prior read, or nil to start fresh.
    /// - Throws: `CdePagerError.badCursor` if the cursor string is malformed.
    init(pageBytes: Int, cursor: String?) throws {
        let clamped = min(max(pageBytes, Self.minimumPageBytes), CdeResultBudget.maxBytes)
        self.pageBytes = clamped
        self.remaining = clamped
        if let cursor {
            guard let parsed = CdePageCursor(cursor) else { throw CdePagerError.badCursor(cursor) }
            self.cursor = parsed
            self.reachedCursorRegion = false
        } else {
            self.cursor = nil
            self.reachedCursorRegion = true
        }
    }

    /// The parsed cursor, for regions the repository pages in SQL itself.
    var startPosition: CdePageCursor? { cursor }

    /// Budget still unspent, for a SQL-paged region deciding how much to fetch.
    var budgetRemaining: Int { remaining }

    // MARK: Fixed parts

    /// Charges the budget for parts that ride on every page.
    /// - Parameter fixed: The stubs, questions, or staleness value to measure.
    mutating func charge<T: Encodable>(_ fixed: T) {
        remaining -= size(fixed)
    }

    // MARK: Row regions

    /// Offers a row region and returns the rows that fit on this page.
    /// - Parameters:
    ///   - name: The region identifier.
    ///   - all: All rows in the region from the repository.
    /// - Returns: The rows that fit within the remaining budget.
    /// - Throws: `CdePagerError.badCursor` if a cursor names this region incorrectly.
    mutating func rows<Row: Encodable>(_ name: String, _ all: [Row]) throws -> [Row] {
        guard let start = try begin(name, total: all.count) else { return [] }
        var taken: [Row] = []
        var index = start
        while index < all.count {
            let cost = size(all[index]) + 2
            if cost > remaining, !taken.isEmpty {
                stop(at: CdePageCursor(region: name, position: index))
                break
            }
            remaining -= cost
            taken.append(all[index])
            index += 1
        }
        report(name, returned: taken.count, total: all.count)
        return taken
    }

    /// Trims rows to fit the budget without reporting or setting a cursor.
    ///
    /// Use with `external(_:returned:total:next:)` for repository-paged regions.
    /// - Parameter rows: All rows fetched by the repository.
    /// - Returns: The rows that fit within the remaining budget.
    mutating func take<Row: Encodable>(_ rows: [Row]) -> [Row] {
        var taken: [Row] = []
        for row in rows {
            let cost = size(row) + 2
            if cost > remaining, !taken.isEmpty { break }
            remaining -= cost
            taken.append(row)
        }
        return taken
    }

    /// Reports a repository-paged region's counts and resume position.
    /// - Parameters:
    ///   - name: The region identifier.
    ///   - returned: Rows or characters on this page.
    ///   - total: The region's full size in the record.
    ///   - next: Position to resume at (row id or offset), or nil if finished.
    mutating func external(_ name: String, returned: Int, total: Int, next: Int?) {
        if cursor?.region == name { cursorRegionSeen = true; reachedCursorRegion = true }
        report(name, returned: returned, total: total)
        if let next { stop(at: CdePageCursor(region: name, position: next)) }
    }

    // MARK: Text regions

    /// Offers a text region and returns the window that fits on this page.
    ///
    /// An empty blob is still a region (0 of 0). At least one slice lands per
    /// page so a page always advances.
    /// - Parameters:
    ///   - name: The region identifier.
    ///   - blob: The entire text from the repository.
    /// - Returns: The text window on this page, or nil if none fits.
    /// - Throws: `CdePagerError.badCursor` if a cursor names this region incorrectly.
    mutating func text(_ name: String, _ blob: String) throws -> CdeTextWindow? {
        let total = blob.count
        guard let offset = try begin(name, total: total) else { return nil }
        guard total > 0 else {
            report(name, returned: 0, total: 0)
            return nil
        }
        let startIndex = blob.index(blob.startIndex, offsetBy: offset)
        let rest = blob[startIndex...]
        var end = rest.startIndex
        var chars = 0
        // Grow in steps until the encoded slice would not fit. The first
        // slice is unconditional: a page always advances.
        while end < rest.endIndex {
            let stepEnd = rest.index(end, offsetBy: Self.textStep, limitedBy: rest.endIndex) ?? rest.endIndex
            let candidate = String(rest[rest.startIndex..<stepEnd])
            let cost = size(candidate) + 2
            if cost > remaining, chars >= Self.minimumTextSlice { break }
            end = stepEnd
            chars = candidate.count
            if cost > remaining { break }
        }
        let slice = String(rest[rest.startIndex..<end])
        remaining -= size(slice) + 2
        if end < rest.endIndex {
            stop(at: CdePageCursor(region: name, position: offset + chars))
        }
        report(name, returned: chars, total: total)
        return CdeTextWindow(region: name, text: slice, offset: offset, returnedChars: chars, totalChars: total)
    }

    // MARK: The page

    /// Assembles the page with all regions offered so far.
    /// - Returns: The complete page, with regions in offer order.
    /// - Throws: `CdePagerError.badCursor` if the cursor named a region never offered.
    func page() throws -> CdePage {
        if let cursor, !cursorRegionSeen {
            throw CdePagerError.badCursor(cursor.wireString)
        }
        return CdePage(pageBytes: pageBytes, nextCursor: next?.wireString, regions: regions)
    }

    // MARK: Internals

    /// Gates a region and returns the starting position.
    ///
    /// Returns nil if nothing of it lands on this page (already reported).
    /// - Parameters:
    ///   - name: The region identifier.
    ///   - total: The region's full size in the record.
    /// - Returns: The starting position, or nil if the region is skipped.
    /// - Throws: `CdePagerError.badCursor` if the cursor position is invalid.
    private mutating func begin(_ name: String, total: Int) throws -> Int? {
        if !reachedCursorRegion {
            guard let cursor, cursor.region == name else {
                report(name, returned: 0, total: total)
                return nil
            }
            guard cursor.position <= total else { throw CdePagerError.badCursor(cursor.wireString) }
            reachedCursorRegion = true
            cursorRegionSeen = true
            if exhausted {
                report(name, returned: 0, total: total)
                return nil
            }
            return cursor.position
        }
        if exhausted {
            report(name, returned: 0, total: total)
            return nil
        }
        return 0
    }

    /// Records the position where this page must stop.
    /// - Parameter cursor: The resumption point for the next page.
    private mutating func stop(at cursor: CdePageCursor) {
        exhausted = true
        next = cursor
    }

    /// Records a region's counts on this page.
    /// - Parameters:
    ///   - name: The region identifier.
    ///   - returned: Rows or characters on this page.
    ///   - total: The region's full size in the record.
    private mutating func report(_ name: String, returned: Int, total: Int) {
        regions.append(CdePageRegion(name: name, returned: returned, total: total))
    }

    /// Measures the encoded size of a value.
    /// - Parameter value: The value to measure.
    /// - Returns: The encoded byte count, or 0 if encoding fails.
    private func size<T: Encodable>(_ value: T) -> Int {
        (try? encoder.encode(AnyEncodable(value)).count) ?? 0
    }
}
