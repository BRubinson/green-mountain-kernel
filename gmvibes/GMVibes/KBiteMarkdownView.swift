import SwiftUI
import GMCCDaemonKit

struct KBiteMarkdownView: View {
    let url: URL
    var showOpenInWindow: Bool = true
    // When set + active, the body renders as highlighted plain text (find-in-page)
    // instead of block markdown.
    var findQuery: SearchQuery = SearchQuery("")

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(url.lastPathComponent)
                        .font(.headline)
                    Text(url.path)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
                Spacer()
                if showOpenInWindow {
                    Button {
                        openWindow(value: WindowSeed(.kbiteFile(url)))
                    } label: {
                        Label("Open in Window", systemImage: "macwindow.badge.plus")
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch KBiteMarkdown.preview(for: url) {
        case .markdown(let blocks, let source):
            if findQuery.isActive {
                // While searching, show highlighted plain text.
                HighlightedText(source: source, query: findQuery, activeLocalOccurrence: nil)
            } else {
                MarkdownBlocksView(blocks)
            }
        case .text(let raw):
            if findQuery.isActive {
                HighlightedText(source: raw, query: findQuery, activeLocalOccurrence: nil)
            } else {
                Text(raw)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
            }
        case .unavailable(let message):
            VStack(alignment: .leading, spacing: 8) {
                Label(message, systemImage: "doc.questionmark")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
