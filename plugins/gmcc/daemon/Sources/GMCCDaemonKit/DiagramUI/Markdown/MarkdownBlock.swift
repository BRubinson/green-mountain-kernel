import Foundation

// A lightweight block-level markdown model. SwiftUI's `Text(AttributedString(markdown:))`
// PARSES block structure but FLATTENS it (headings/lists/code render as one run of
// inline text). To render "natively" — real headings, indented lists, fenced code,
// tables — we parse the document into blocks here and lay each out in SwiftUI
// (MarkdownBlocksView). Inline emphasis/links/code-spans WITHIN a block are still
// handled by AttributedString at render time.

public enum MarkdownBlock: Identifiable, Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulletList(items: [String])
    case orderedList(start: Int, items: [String])
    case codeBlock(language: String?, code: String)
    case blockquote(lines: [String])
    case table(headers: [String], rows: [[String]])
    case rule

    public var id: String {
        switch self {
        case .heading(let l, let t):     return "h\(l):\(t)"
        case .paragraph(let t):          return "p:\(t)"
        case .bulletList(let i):         return "ul:\(i.joined(separator: "\u{1}"))"
        case .orderedList(let s, let i): return "ol:\(s):\(i.joined(separator: "\u{1}"))"
        case .codeBlock(let lang, let c): return "code:\(lang ?? ""):\(c)"
        case .blockquote(let l):         return "quote:\(l.joined(separator: "\u{1}"))"
        case .table(let h, let r):       return "table:\(h.joined(separator: "\u{1}")):\(r.count)"
        case .rule:                      return "rule"
        }
    }
}

public enum MarkdownDocument {
    // Parse a markdown string into ordered blocks. Deliberately small but covers the
    // shapes architect-agent output uses: ATX headings, fenced code, bullet/ordered
    // lists, blockquotes, pipe tables, thematic breaks, and paragraphs.
    public static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        // Normalize CRLF/CR so per-line whitespace trimming (which excludes \r) and
        // line classifiers behave on files from Windows-y tooling.
        let normalized = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        var i = 0

        func flushParagraph(_ buf: inout [String]) {
            guard !buf.isEmpty else { return }
            let text = buf.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty { blocks.append(.paragraph(text)) }
            buf.removeAll()
        }

        var paragraph: [String] = []

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Fenced code block ``` … ```
            if trimmed.hasPrefix("```") {
                flushParagraph(&paragraph)
                let lang = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i]); i += 1
                }
                if i < lines.count { i += 1 } // consume closing fence (if present)
                blocks.append(.codeBlock(language: lang.isEmpty ? nil : lang,
                                         code: code.joined(separator: "\n")))
                continue
            }

            // Blank line — paragraph boundary.
            if trimmed.isEmpty {
                flushParagraph(&paragraph)
                i += 1
                continue
            }

            // Thematic break --- *** ___
            if isThematicBreak(trimmed) {
                flushParagraph(&paragraph)
                blocks.append(.rule)
                i += 1
                continue
            }

            // ATX heading # … ######
            if let h = parseHeading(trimmed) {
                flushParagraph(&paragraph)
                blocks.append(h)
                i += 1
                continue
            }

            // Pipe table: a header row followed by a |---|---| separator row.
            if trimmed.contains("|"), i + 1 < lines.count,
               isTableSeparator(lines[i + 1].trimmingCharacters(in: .whitespaces)) {
                flushParagraph(&paragraph)
                let headers = splitTableRow(trimmed)
                var rows: [[String]] = []
                i += 2
                while i < lines.count {
                    let r = lines[i].trimmingCharacters(in: .whitespaces)
                    guard r.contains("|"), !r.isEmpty else { break }
                    // Normalize each row to the header column count so cells stay
                    // aligned under their headers in the Grid.
                    var cells = splitTableRow(r)
                    if cells.count < headers.count {
                        cells += Array(repeating: "", count: headers.count - cells.count)
                    } else if cells.count > headers.count {
                        cells = Array(cells.prefix(headers.count))
                    }
                    rows.append(cells)
                    i += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            // Blockquote (one or more consecutive `>` lines).
            if trimmed.hasPrefix(">") {
                flushParagraph(&paragraph)
                var quote: [String] = []
                while i < lines.count {
                    let q = lines[i].trimmingCharacters(in: .whitespaces)
                    guard q.hasPrefix(">") else { break }
                    quote.append(String(q.dropFirst()).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.blockquote(lines: quote))
                continue
            }

            // Bullet list (-, *, +).
            if isBullet(trimmed) {
                flushParagraph(&paragraph)
                var items: [String] = []
                while i < lines.count, isBullet(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    items.append(String(t.dropFirst(1)).trimmingCharacters(in: .whitespaces))
                    i += 1
                }
                blocks.append(.bulletList(items: items))
                continue
            }

            // Ordered list (1. 2. …). Preserve the source start number rather than
            // renumbering from 1.
            if isOrdered(trimmed) {
                flushParagraph(&paragraph)
                let start = Int(trimmed.prefix(while: \.isNumber)) ?? 1
                var items: [String] = []
                while i < lines.count, isOrdered(lines[i].trimmingCharacters(in: .whitespaces)) {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    if let dot = t.firstIndex(of: ".") {
                        items.append(String(t[t.index(after: dot)...]).trimmingCharacters(in: .whitespaces))
                    }
                    i += 1
                }
                blocks.append(.orderedList(start: start, items: items))
                continue
            }

            // Otherwise accumulate into the current paragraph.
            paragraph.append(line)
            i += 1
        }
        flushParagraph(&paragraph)
        return blocks
    }

    // MARK: - Line classifiers

    private static func parseHeading(_ s: String) -> MarkdownBlock? {
        guard let level = headingLevel(of: s) else { return nil }
        // `s` arrives already left-trimmed, so the first `level` characters are the
        // `#`s; skip them (the required space is trimmed off below) to get the text.
        var idx = s.startIndex
        for _ in 0..<level { idx = s.index(after: idx) }
        let text = String(s[idx...]).trimmingCharacters(in: .whitespaces)
        return .heading(level: level, text: text)
    }

    /// The ATX heading level (1...6) for a line, or nil if it isn't a heading.
    /// Shared by the block parser and the in-editor highlighter so both agree on the
    /// exact rule: 1–6 leading `#` (after optional leading spaces) followed by a space.
    public static func headingLevel(of line: String) -> Int? {
        let s = line.drop(while: { $0 == " " })
        guard s.first == "#" else { return nil }
        var level = 0
        var idx = s.startIndex
        while idx < s.endIndex, s[idx] == "#", level < 6 {
            level += 1; idx = s.index(after: idx)
        }
        guard level > 0, idx < s.endIndex, s[idx] == " " else { return nil }
        return level
    }

    private static func isThematicBreak(_ s: String) -> Bool {
        let stripped = s.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func isBullet(_ s: String) -> Bool {
        guard s.count >= 2 else { return false }
        let first = s.first!
        return (first == "-" || first == "*" || first == "+") && s[s.index(after: s.startIndex)] == " "
    }

    private static func isOrdered(_ s: String) -> Bool {
        guard let dot = s.firstIndex(of: ".") else { return false }
        let prefix = s[s.startIndex..<dot]
        return !prefix.isEmpty && prefix.allSatisfy(\.isNumber)
            && s.index(after: dot) < s.endIndex && s[s.index(after: dot)] == " "
    }

    private static func isTableSeparator(_ s: String) -> Bool {
        guard s.contains("|"), s.contains("-") else { return false }
        // Each cell is dashes with optional leading/trailing colons.
        return splitTableRow(s).allSatisfy { cell in
            let c = cell.trimmingCharacters(in: .whitespaces)
            return !c.isEmpty && c.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func splitTableRow(_ s: String) -> [String] {
        var row = s
        if row.hasPrefix("|") { row.removeFirst() }
        if row.hasSuffix("|") { row.removeLast() }
        return row.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}
