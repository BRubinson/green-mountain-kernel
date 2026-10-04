#if canImport(SwiftUI)
import SwiftUI

// Renders parsed MarkdownBlocks as real SwiftUI layout: sized headings, indented
// lists, fenced code in a monospaced filled block, bordered blockquotes, and pipe
// tables in a Grid. Inline emphasis / links / code-spans within a block are handled
// by AttributedString's inline markdown parsing.
struct MarkdownBlocksView: View {
    let blocks: [MarkdownBlock]
    /// Non-nil scales every block font off this size instead of the
    /// semantic .body/.title ramp.
    ///
    /// Diagram text surfaces MUST pass their
    /// persisted font_size through here: the semantic fonts are absolute
    /// and silently override any outer .font() modifier, which is exactly
    /// how the old inline renderer's working font_size column died in the
    /// first block-renderer port.
    let baseFontSize: Double?

    /// Creates a view that renders parsed markdown blocks.
    /// - Parameters:
    ///   - blocks: The parsed markdown blocks to render.
    ///   - baseFontSize: Optional base font size to scale all text, or nil for semantic fonts.
    init(_ blocks: [MarkdownBlock], baseFontSize: Double? = nil) {
        self.blocks = blocks
        self.baseFontSize = baseFontSize
    }

    /// Creates a view that parses and renders markdown source.
    /// - Parameters:
    ///   - source: The markdown source string to parse and render.
    ///   - baseFontSize: Optional base font size to scale all text, or nil for semantic fonts.
    init(source: String, baseFontSize: Double? = nil) {
        self.blocks = MarkdownDocument.parse(source)
        self.baseFontSize = baseFontSize
    }

    /// Calculates a font scaled from the base size or returns a fallback.
    /// - Parameters:
    ///   - factor: The scaling factor to apply to the base font size.
    ///   - fallback: The font to use if no base font size is set.
    ///   - monospaced: Whether to use monospaced design if scaling; ignored for fallback.
    /// - Returns: A scaled font or the fallback font.
    private func scaled(
        _ factor: Double,
        fallback: Font,
        monospaced: Bool = false
    ) -> Font {
        guard let base = baseFontSize else { return fallback }
        return .system(
            size: base * factor,
            design: monospaced ? .monospaced : .default
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                view(for: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Builds the SwiftUI view for a single markdown block.
    /// - Parameter block: The markdown block to render.
    /// - Returns: The SwiftUI view for this block.
    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level <= 2 ? 6 : 2)

        case .paragraph(let text):
            inline(text)
                .font(scaled(1, fallback: .body))
                .textSelection(.enabled)

        case .bulletList(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•").foregroundStyle(.secondary)
                        inline(item).font(scaled(1, fallback: .body))
                    }
                }
            }
            .padding(.leading, 6)

        case .orderedList(let start, let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { idx, item in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(start + idx).").foregroundStyle(.secondary).monospacedDigit()
                        inline(item).font(scaled(1, fallback: .body))
                    }
                }
            }
            .padding(.leading, 6)

        case .codeBlock(let language, let code):
            VStack(alignment: .leading, spacing: 4) {
                if let language, !language.isEmpty {
                    Text(language)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }
                Text(code)
                    .font(
                        scaled(
                            0.95,
                            fallback: .system(.callout, design: .monospaced),
                            monospaced: true
                        )
                    )
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
            }

        case .blockquote(let lines):
            HStack(spacing: 8) {
                Rectangle().fill(.tertiary).frame(width: 3)
                inline(lines.joined(separator: "\n"))
                    .font(scaled(1, fallback: .body))
                    .foregroundStyle(.secondary)
            }

        case .table(let headers, let rows):
            tableView(headers: headers, rows: rows)

        case .rule:
            Divider()
        }
    }

    /// Builds a table view from headers and rows.
    /// - Parameters:
    ///   - headers: The table header strings.
    ///   - rows: The table rows, each as a list of cell strings.
    /// - Returns: The SwiftUI table view.
    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    inline(h)
                        .font(
                            baseFontSize.map {
                                .system(size: $0 * 0.95, weight: .semibold)
                            } ?? .callout.weight(.semibold)
                        )
                }
            }
            Divider()
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, cell in
                        inline(cell).font(scaled(0.95, fallback: .callout))
                    }
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.25), in: .rect(cornerRadius: 8))
    }

    /// Converts markdown text with inline formatting (bold, italic, links, code).
    /// - Parameter text: The markdown text to convert.
    /// - Returns: A Text view with inline markdown parsed and rendered.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    /// Returns the font for a heading at the given level.
    /// - Parameter level: The heading level (1-6 or higher).
    /// - Returns: The scaled or semantic font for this heading level.
    private func headingFont(_ level: Int) -> Font {
        if let base = baseFontSize {
            let factor: Double
            switch level {
            case 1: factor = 1.7
            case 2: factor = 1.45
            case 3: factor = 1.25
            case 4: factor = 1.1
            default: factor = 1.0
            }
            return .system(size: base * factor)
        }
        switch level {
        case 1: return .title
        case 2: return .title2
        case 3: return .title3
        case 4: return .headline
        default: return .subheadline
        }
    }
}
#endif
