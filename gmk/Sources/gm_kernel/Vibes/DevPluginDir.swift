import Foundation

/// The plugin tree a non-production pane should load. Baked into the bundle at build time,
/// the way `GMFSRoot` is: the plugin directory is a property of the BITS.
///
/// IT MUST BE A REAL KEY IN `gmk/gmVibes/Info.plist`, NEVER `INFOPLIST_KEY_GMDevPluginDir`:
/// that build-setting prefix is a declared allow-list and Xcode silently drops keys it does
/// not recognise, producing a bundle with no key and a silent fall-through. `.none` degrades
/// silently, so a Beta app on another machine loads the published marketplace plugin with
/// nothing announcing the difference.
enum DevPluginDir {
    /// Three cases, not an optional: "no baked directory" and "baked directory that is not
    /// there" want opposite answers.
    ///
    /// A bundle claiming nothing must degrade silently, which is `.none`. A bundle that NAMES
    /// a directory absent from disk has lost its plugin, and answering `nil` there would let
    /// the pane quietly load the installed marketplace plugin instead. That is `.missing`,
    /// and it BLOCKS.
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
        // GUARD 3 — EXISTS ON THIS MACHINE. `$(SRCROOT)/../plugins/gmcc` resolves against the
        // machine that BUILT the bundle, so a Beta app handed to anyone else names a checkout
        // they do not have. Reported as `.missing` so the preflight rules on it.
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: raw, isDirectory: &isDir), isDir.boolValue
        else { return .missing(raw) }
        return .present(raw)
    }
}
