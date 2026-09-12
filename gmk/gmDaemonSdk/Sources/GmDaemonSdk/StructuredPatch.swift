import Foundation

/// One hunk of a PostToolUse `tool_response.structuredPatch`.
///
/// Decoded with a PLAIN JSONDecoder, never the wire codec: these keys come
/// from Claude Code's payload in camelCase, and running them through
/// `convertFromSnakeCase` would silently nil every one of them.
public struct StructuredPatchHunk: Codable, Hashable, Sendable {
    public let oldStart: Int
    public let oldLines: Int
    public let newStart: Int
    public let newLines: Int
    public let lines: [String]

    public init(oldStart: Int, oldLines: Int, newStart: Int, newLines: Int, lines: [String]) {
        self.oldStart = oldStart
        self.oldLines = oldLines
        self.newStart = newStart
        self.newLines = newLines
        self.lines = lines
    }
}

/// structuredPatch → `file_change_range` rows. Exact line numbers off the
/// payload, no diffing and no filesystem read.
///
/// The mapping is deliberately NEW-side: an edit is recorded where it landed,
/// so a later reader lines a range up against the file as it now is. A hunk
/// that deletes every line it touches reports `newLines: 0`, and a zero-height
/// range would be unreadable — hence the `max(newLines, 1)` floor, which puts
/// the deletion on the line it collapsed into.
public enum StructuredPatchExpander {
    /// Applied at the source as well as in `FileChangeRepository`, which is
    /// the actual guarantee: expanding here keeps a megabyte of generated-file
    /// rewrite off the socket in the first place.
    public static let maxHunks = FileChangeLimits.maxRangesPerChange
    public static let maxHunkBodyCharacters = FileChangeLimits.maxChangedContentCharacters

    public static func expand(_ hunks: [StructuredPatchHunk]) -> [ChangeRange] {
        hunks.prefix(maxHunks).map { hunk in
            ChangeRange(
                lineStart: hunk.newStart,
                lineEnd: hunk.newStart + max(hunk.newLines, 1) - 1,
                changedContent: String(hunk.lines.joined(separator: "\n")
                    .prefix(maxHunkBodyCharacters)))
        }
    }
}

/// The size budget on recorded ranges, declared once and enforced where the
/// rows are written. A structuredPatch for a regenerated file can carry
/// thousands of hunks and megabytes of body; file_change is append-only
/// history, so an uncapped expansion is permanent.
public enum FileChangeLimits {
    public static let maxRangesPerChange = 100
    public static let maxChangedContentCharacters = 4000
}
