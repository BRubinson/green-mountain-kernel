import Foundation

// MARK: - Byte-budgeted paging (the cde server's page vocabulary)

/// Where a byte-mode page sits in the whole record. Every cde read that was
/// asked for `page_bytes` carries one of these; a read that was not carries
/// nil and is the historical response, byte for byte.
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

    init(name: String, returned: Int, total: Int) {
        self.name = name
        self.returned = returned
        self.total = total
    }
}

/// One character window of a long text. The reader concatenates windows of
/// the same region in `offset` order; a text that fits arrives as one window
/// with offset 0 and `returnedChars == totalChars`.
struct CdeTextWindow: Codable, Hashable, Sendable {
    let region: String
    let text: String
    /// Character offset of `text` inside the whole blob (Swift `Character`
    /// units, so a grapheme is never split).
    let offset: Int
    let returnedChars: Int
    let totalChars: Int

    init(region: String, text: String, offset: Int, returnedChars: Int, totalChars: Int) {
        self.region = region
        self.text = text
        self.offset = offset
        self.returnedChars = returnedChars
        self.totalChars = totalChars
    }
}

/// The parsed form of the opaque cursor string. Only the string crosses the
/// wire; this is what a repository validates on the way in.
struct CdePageCursor: Hashable, Sendable {
    let region: String
    let position: Int

    init(region: String, position: Int) {
        self.region = region
        self.position = position
    }

    /// `"<region>:<position>"`, split on the LAST colon because a region name
    /// may itself carry one (`overview:<uuid>`).
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

/// THE ONE BYTE-BUDGET FILLER. A repository charges its fixed parts, then
/// offers each region in the read's fill order; the pager takes as much of
/// each as fits the budget — measured with the SAME encoder the result guard
/// measures with — and records the cursor where it stopped. At least one
/// unit lands per page (a row or a text slice) so a page always advances;
/// regions before the cursor's are skipped and regions after an exhausted
/// one report returned 0, both with their true totals; a cursor naming an
/// unoffered region or a position past its end is `badCursor`.
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
    /// Set when the cursor named a region; cleared when that region is
    /// offered. Still set at `page` time means the cursor was bad.
    private var cursorRegionSeen = false

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

    /// Charge the parts that ride on every page (stubs, questions, staleness).
    mutating func charge<T: Encodable>(_ fixed: T) {
        remaining -= size(fixed)
    }

    // MARK: Row regions

    /// Offer a row region; returns the rows that land on this page.
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

    /// Size-trim rows a repository fetched itself, WITHOUT reporting or setting
    /// a cursor — pair with `external(_:returned:total:next:)`.
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

    /// Report a SQL-paged region. `next` is the position to resume at (a row
    /// id or an offset), nil when the region is finished.
    mutating func external(_ name: String, returned: Int, total: Int, next: Int?) {
        if cursor?.region == name { cursorRegionSeen = true; reachedCursorRegion = true }
        report(name, returned: returned, total: total)
        if let next { stop(at: CdePageCursor(region: name, position: next)) }
    }

    // MARK: Text regions

    /// Offer a text region; returns the window that lands on this page, or
    /// nil when none of it does. An EMPTY blob is still a region (0 of 0).
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

    func page() throws -> CdePage {
        if let cursor, !cursorRegionSeen {
            throw CdePagerError.badCursor(cursor.wireString)
        }
        return CdePage(pageBytes: pageBytes, nextCursor: next?.wireString, regions: regions)
    }

    // MARK: Internals

    /// Gate a region: nil = nothing of it lands on this page (already
    /// reported); otherwise the position to start from.
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

    private mutating func stop(at cursor: CdePageCursor) {
        exhausted = true
        next = cursor
    }

    private mutating func report(_ name: String, returned: Int, total: Int) {
        regions.append(CdePageRegion(name: name, returned: returned, total: total))
    }

    private func size<T: Encodable>(_ value: T) -> Int {
        (try? encoder.encode(AnyEncodable(value)).count) ?? 0
    }
}
