#if canImport(SwiftUI)
import SwiftUI

// Renders parsed MarkdownBlocks as real SwiftUI layout: sized headings, indented
// lists, fenced code in a monospaced filled block, bordered blockquotes, and pipe
// tables in a Grid. Inline emphasis / links / code-spans within a block are handled
// by AttributedString's inline markdown parsing.
public struct MarkdownBlocksView: View {
    public let blocks: [MarkdownBlock]
    /// Non-nil scales every block font off this size instead of the
    /// semantic .body/.title ramp. Diagram text surfaces MUST pass their
    /// persisted font_size through here: the semantic fonts are absolute
    /// and silently override any outer .font() modifier, which is exactly
    /// how the old inline renderer's working font_size column died in the
    /// first block-renderer port.
    public let baseFontSize: Double?

    public init(_ blocks: [MarkdownBlock], baseFontSize: Double? = nil) {
        self.blocks = blocks
        self.baseFontSize = baseFontSize
    }
    public init(source: String, baseFontSize: Double? = nil) {
        self.blocks = MarkdownDocument.parse(source)
        self.baseFontSize = baseFontSize
    }

    private func scaled(_ factor: Double, monospaced: Bool = false,
                        fallback: Font) -> Font {
        guard let base = baseFontSize else { return fallback }
        return .system(size: base * factor,
                       design: monospaced ? .monospaced : .default)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(blocks) { block in
                view(for: block)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

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
                    .font(scaled(0.95, monospaced: true,
                                 fallback: .system(.callout, design: .monospaced)))
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

    @ViewBuilder
    private func tableView(headers: [String], rows: [[String]]) -> some View {
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                ForEach(Array(headers.enumerated()), id: \.offset) { _, h in
                    inline(h).font(baseFontSize.map {
                        .system(size: $0 * 0.95, weight: .semibold)
                    } ?? .callout.weight(.semibold))
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

    // Inline markdown (bold/italic/links/code-spans) for the text within a block.
    private func inline(_ text: String) -> Text {
        if let attributed = try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) {
            return Text(attributed)
        }
        return Text(text)
    }

    private func headingFont(_ level: Int) -> Font {
        if let base = baseFontSize {
            let factor: Double
            switch level {
            case 1:  factor = 1.7
            case 2:  factor = 1.45
            case 3:  factor = 1.25
            case 4:  factor = 1.1
            default: factor = 1.0
            }
            return .system(size: base * factor)
        }
        switch level {
        case 1:  return .title
        case 2:  return .title2
        case 3:  return .title3
        case 4:  return .headline
        default: return .subheadline
        }
    }
}
#endif
