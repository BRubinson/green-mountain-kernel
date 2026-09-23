import Foundation

enum KBitePreview {
    case markdown(blocks: [MarkdownBlock], source: String)
    case text(String)
    case unavailable(String)
}

enum KBiteMarkdown {
    static let maxBytes = 512 * 1024

    /// Generates a preview of a kbite file.
    ///
    /// Returns a markdown preview if the file is a `.md` file, a text preview
    /// for other text files, or unavailable if the file is too large, unreadable,
    /// or binary.
    ///
    /// - Parameter url: The file URL to preview.
    /// - Returns: The generated preview.
    static func preview(for url: URL) -> KBitePreview {
        let fm = FileManager.default
        let attrs = (try? fm.attributesOfItem(atPath: url.path)) ?? [:]
        if let size = attrs[.size] as? NSNumber, size.intValue > maxBytes {
            return .unavailable(
                "Preview unavailable (file is \(size.intValue / 1024) KB; cap is \(maxBytes / 1024) KB)."
            )
        }

        guard let data = try? Data(contentsOf: url) else {
            return .unavailable("Could not read file.")
        }

        guard let text = String(data: data, encoding: .utf8) else {
            return .unavailable("Preview unavailable (binary or non-UTF8 file).")
        }

        if url.pathExtension.lowercased() == "md" {
            // Full block-level parse so headings / lists / code / tables render as
            // real layout (MarkdownBlocksView) rather than flattened inline text.
            return .markdown(blocks: MarkdownDocument.parse(text), source: text)
        }

        return .text(text)
    }
}
