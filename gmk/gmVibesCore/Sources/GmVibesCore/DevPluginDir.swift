import Foundation

/// The plugin tree a non-production pane should load, or `nil`.
///
/// Baked into the bundle at build time, exactly the way `GMFSRoot` is —
/// the plugin directory is a property of the BITS, the same kind of fact as
/// the root, so it rides the mechanism this repo already won the argument
/// for rather than a new one.
///
/// *** IT MUST BE A REAL KEY IN `gmk/gmVibes/Info.plist`, NEVER
/// `INFOPLIST_KEY_GMDevPluginDir`. *** That build-setting prefix is a
/// DECLARED ALLOW-LIST and Xcode SILENTLY DROPS keys it does not recognise,
/// producing a bundle with no key and a silent fall-through. That trap is
/// documented as verified-empirically against `GMFSRoot` in Info.plist
/// itself, and it would repeat here verbatim.
///
/// CONSEQUENCE OF `.none`, STATED SO IT IS NOT DISCOVERED: a colleague's Beta
/// app silently loads the PUBLISHED marketplace plugin while the developer's
/// loads the working tree, and nothing announces the difference. That is the
/// concrete form of the accepted cost that a beta session is no longer
/// self-contained. The preflight on `PromptRunBar` is what makes the
/// developer's own stale case loud; `.none` only prevents a hard startup
/// failure for someone else.
///
/// PLACEMENT: `gmVibesCore`, NOT `Paths`. `Paths` is the zero-dependency base
/// shared by `gm_hook`, `gm_daemon` and `gm_mcp`, none of which will ever read
/// a plugin directory.
enum DevPluginDir {
    /// WHY THIS IS THREE CASES AND NOT AN OPTIONAL. Collapsing "no baked
    /// directory" and "baked directory that is not there" into one `nil`
    /// makes ONE PREDICATE SERVE TWO POPULATIONS, and they want opposite
    /// answers:
    ///
    /// - A bundle with no baked directory at all (Release, and any build whose
    ///   `$(GM_DEV_PLUGIN_DIR)` expanded empty) must degrade SILENTLY. That is
    ///   `.none`, and it is the case the colleague's-machine reasoning above is
    ///   about: nothing is claimed, so nothing is missing.
    /// - A bundle that NAMES a directory which is not on disk is a different
    ///   fact: this tree lost its plugin — deleted, moved, on a branch that
    ///   predates it, or a generation killed between the writer's two renames.
    ///   Answering `nil` there disabled nothing and emitted no `--plugin-dir`,
    ///   so the pane quietly loaded the INSTALLED marketplace plugin — the exact
    ///   silent fallback the preflight was grafted in to prevent. That is
    ///   `.missing`, and it BLOCKS.
    enum Resolution: Equatable {
        /// No baked directory. Silent, no flag, no block.
        case none
        /// A baked directory that does not exist (or is not a directory).
        case missing(String)
        /// A baked directory that is on disk. Proceed to the manifest checks.
        case present(String)
    }

    static var current: Resolution {
        // GUARD 1 — present.
        guard let raw = Bundle.main.object(forInfoDictionaryKey: "GMDevPluginDir") as? String
        else { return .none }
        // GUARD 2 — NON-EMPTY. The plist is shared across configurations, so
        // under Debug and Release `$(GM_DEV_PLUGIN_DIR)` expands to the EMPTY
        // STRING: the key EXISTS with no value. `Paths.swift:77` guards
        // `!baked.isEmpty` for exactly this and must be mirrored here.
        guard !raw.isEmpty else { return .none }
        // GUARD 3 — EXISTS ON THIS MACHINE. `$(SRCROOT)/../plugins/gmcc`
        // resolves against the machine that BUILT the bundle, so a Beta app
        // handed to anyone else names a checkout they do not have. That case
        // must not hard-fail at startup with the pane already open — but it is
        // NOT the same case as a developer's own tree losing its plugin, and
        // this guard used to answer both with `nil`. It now reports the
        // distinction and lets the preflight rule on it; see `Resolution`.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: raw, isDirectory: &isDir), isDir.boolValue
        else { return .missing(raw) }
        return .present(raw)
    }
}
