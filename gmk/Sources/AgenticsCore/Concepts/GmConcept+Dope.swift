import Foundation

/// The `dope` skill body.
///
/// Computed rather than a constant: the reference index at the bottom is built
/// from `GmBridgeResource.all`, so a dope reference declared in the bridge is
/// cited here without editing this file.
var GM_CONCEPT_DOPE: String {
    """
    # DOPE — Domain Optimized Project Essence

    DOPE is the project's model of ITSELF: scopes, persistence domains and their entities, enums and properties — the cogs describing what the repo is MADE OF rather than what it models.

    ## Two authorities, in order

    1. The committed `.gmcc/` tree is authoritative AT BOOT. Sessions boot-sync their dope scope from it. The directory keeps that name; it is a path segment, not a product name.
    2. The db is authoritative for granular edits AFTERWARD. Publish a session's changes back to disk with `dope_update_session`; that is the one door from the record to the tree.

    ## Access: Dot-Path Codes

    Dope refs are DOT-PATH CODES (`domain.entity.property`), never uuids and never file paths. A ref that resolves to neither dangles.

    - Search first — `dope_search_session` for this session's tree, `dope_search_global` to look across every project.
    - Take the codes that hit, and read only the files those codes point to.
    - Reach for dope before reading files: it is the cheaper description of the same thing.

    ## Never Do

    1. Browse to adjacent nodes or dump the tree. Search returns codes; codes are the whole interface.
    2. Write dope by hand under `.gmcc/` during a bot run. The record is db-native; the tree is what `dope_update_session` writes.

    ## Reference

    Detail lives beside this file rather than in it — read it only when it names your situation:

    \(GmBridgeResource.index(for: "dope"))
    """
}
