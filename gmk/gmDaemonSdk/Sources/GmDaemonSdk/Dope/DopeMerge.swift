import Foundation
import CryptoKit

/// Per-element three-way reconciliation between the repo files and the db.
///
/// THE RULE, as specified: during a session the db is the working source of
/// truth and dumps to the repo. The files become the INPUT only at a
/// boundary — a new session, a new branch, or a git merge. At that boundary
/// resolution is per-element rather than whole-tree:
///
///   * files win unconditionally for anything this session never touched;
///   * an element edited here that ALSO moved on disk is a real conflict and
///     must be chosen, not guessed.
///
/// The three sides:
///
///   base   `dope_element_provenance.synced_content_hash` — the content hash
///          recorded the last time this element came FROM a file. Keyed by
///          dot-path, never uuid: ingest re-mints every child uuid, so a
///          uuid-keyed base would not survive the operation it informs.
///   ours   the current db tree.
///   theirs the current on-disk tree.
///
/// This type is PURE — it decides, and it builds a merged bundle. It never
/// touches the db or the filesystem, which is what makes the rule testable
/// without a repo or a daemon.
public enum DopeMerge {

    /// What should happen to one dot-path.
    public enum Decision: String, Codable, Hashable, Sendable {
        /// Present on disk, untouched here (or identical) — take the file.
        case takeTheirs
        /// Edited here, unchanged on disk since the base — keep the db.
        case keepOurs
        /// Edited here AND changed on disk since the base. Needs a choice.
        case conflict
        /// Only in the db, never synced, not on disk — a local addition.
        case keepOursLocalAddition
        /// On disk and gone from the db, but we deleted it here.
        case deletedHere
    }

    public struct Outcome: Hashable, Sendable {
        public let dotPath: String
        public let kind: String
        public let decision: Decision
    }

    /// One element's identity as the merge sees it: what it is called, and
    /// what it currently contains.
    public struct Element: Hashable, Sendable {
        public let dotPath: String
        public let kind: String
        public let contentHash: String

        public init(dotPath: String, kind: String, contentHash: String) {
            self.dotPath = dotPath
            self.kind = kind
            self.contentHash = contentHash
        }
    }

    /// The stored base for one dot-path.
    public struct Base: Hashable, Sendable {
        public let syncedContentHash: String?
        public let locallyModified: Bool

        public init(syncedContentHash: String?, locallyModified: Bool) {
            self.syncedContentHash = syncedContentHash
            self.locallyModified = locallyModified
        }
    }

    /// Decide every dot-path in the union of both sides.
    ///
    /// Deliberately total: a path present on either side gets an outcome, so
    /// nothing is silently dropped by being absent from one tree.
    public static func plan(
        ours: [Element], theirs: [Element], base: [String: Base]
    ) -> [Outcome] {
        var oursByPath = [String: Element]()
        for element in ours { oursByPath[element.dotPath] = element }
        var theirsByPath = [String: Element]()
        for element in theirs { theirsByPath[element.dotPath] = element }

        var paths = Set(oursByPath.keys)
        paths.formUnion(theirsByPath.keys)

        return paths.sorted().map { path in
            let mine = oursByPath[path]
            let yours = theirsByPath[path]
            let known = base[path]
            let dirty = known?.locallyModified ?? false
            let kind = mine?.kind ?? yours?.kind ?? "unknown"

            switch (mine, yours) {
            case (.some, .some(let theirElement)):
                guard dirty else {
                    // Never touched here — the file is authoritative, even
                    // when it differs.
                    return Outcome(dotPath: path, kind: kind, decision: .takeTheirs)
                }
                // Edited here. Did the file move too, relative to the base we
                // last read? A missing base means we have no evidence it
                // did not, so treat it as a conflict rather than guessing.
                guard let baseHash = known?.syncedContentHash else {
                    return Outcome(dotPath: path, kind: kind, decision: .conflict)
                }
                return Outcome(dotPath: path, kind: kind,
                               decision: theirElement.contentHash == baseHash
                                   ? .keepOurs : .conflict)

            case (.some, .none):
                // Only in the db. Something we added locally, or something
                // the incoming tree deleted.
                if known?.syncedContentHash != nil {
                    // It came from a file before and the file is now gone.
                    // A local edit against an upstream delete is a conflict;
                    // otherwise the delete wins.
                    return Outcome(dotPath: path, kind: kind,
                                   decision: dirty ? .conflict : .takeTheirs)
                }
                return Outcome(dotPath: path, kind: kind, decision: .keepOursLocalAddition)

            case (.none, .some):
                // On disk, absent here. If we had it and it is gone from the
                // db, we deleted it; that only survives if we are dirty.
                if known != nil, dirty {
                    return Outcome(dotPath: path, kind: kind, decision: .deletedHere)
                }
                return Outcome(dotPath: path, kind: kind, decision: .takeTheirs)

            case (.none, .none):
                return Outcome(dotPath: path, kind: kind, decision: .takeTheirs)
            }
        }
    }

    /// The unresolved conflicts in a plan, in dot-path order.
    public static func conflicts(in plan: [Outcome]) -> [Outcome] {
        plan.filter { $0.decision == .conflict }
    }

    // MARK: - Element extraction

    /// Flattens a document bundle into the dot-path addressed elements the
    /// merge reasons about. The dot-path forms are the same ones dope refs
    /// already use, so a conflict names something a person can actually go
    /// and look at.
    public static func elements(of bundle: DopeDocumentBundle) -> [Element] {
        var out: [Element] = []
        for domain in bundle.domainFiles.sorted(by: { $0.body.code < $1.body.code }) {
            let d = domain.body.code
            out.append(Element(dotPath: d, kind: "persistence",
                               contentHash: hash(domain.body)))
            for entity in domain.entities.sorted(by: { $0.body.code < $1.body.code }) {
                out.append(Element(dotPath: "\(d).\(entity.body.code)", kind: "entity",
                                   contentHash: hash(entity)))
                for property in entity.properties.sorted(by: { $0.body.code < $1.body.code }) {
                    out.append(Element(
                        dotPath: "\(d).\(entity.body.code).\(property.body.code)",
                        kind: "property", contentHash: hash(property)))
                }
            }
            for en in domain.enums.sorted(by: { $0.body.code < $1.body.code }) {
                out.append(Element(dotPath: "\(d).enums.\(en.body.code)", kind: "enum",
                                   contentHash: hash(en)))
                for option in en.options.sorted(by: { $0.body.code < $1.body.code }) {
                    out.append(Element(
                        dotPath: "\(d).enums.\(en.body.code).\(option.body.code)",
                        kind: "option", contentHash: hash(option)))
                }
            }
        }
        return out
    }

    /// Content hash of any document node. Uses the file codec so the hash is
    /// computed over exactly the bytes that would be written — the encoder is
    /// `.sortedKeys`, so this is stable across runs.
    public static func hash<T: Encodable>(_ value: T) -> String {
        guard let data = try? DopeDocumentCodec.encoder.encode(value) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
