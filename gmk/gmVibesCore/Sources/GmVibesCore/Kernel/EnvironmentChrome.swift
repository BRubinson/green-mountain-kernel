import AppKit
import GmDaemonSdk
import SwiftUI

/// Which environment this bundle is looking at, and how it says so.
///
/// ## Derived from the RESOLVED ROOT, never from a build flag
///
/// A `#if GM_TEST` would be a SECOND source of truth, and two sources of truth
/// can disagree. The disagreement that matters is the one where a build wearing
/// non-production chrome is actually resolving `~/gmfs` — a red bar over live
/// data, lying at the exact moment the signal matters most.
///
/// Here, "am I isolated?" and "which database am I writing?" are the SAME
/// expression. The badge cannot be wrong, because a wrong badge would require a
/// wrong root, and the baked Info.plist key is what makes the root unspoofable.
///
/// ## Inode comparison, not string comparison
///
/// `Paths.isProductionRoot` compares `(st_dev, st_ino)` of `gm.db`, because
/// `standardizedFileURL` does not resolve symlinks. A `~/prod_gmfs` symlink, an
/// APFS firmlink, or `/Users` vs `/System/Volumes/Data/Users` would each make
/// one root look like two and paint the warning chrome over production.
public enum EnvironmentKind: Sendable {
    case production
    case beta
    case test

    /// Resolve from the root this process actually opened.
    ///
    /// The declared `GMEnvironment` label is used only to tell BETA from TEST,
    /// never to decide whether we are on production — that answer comes from the
    /// filesystem. A label that could override the root would reintroduce the
    /// second source of truth this type exists to remove.
    public static var current: EnvironmentKind {
        if Paths.isProductionRoot { return .production }
        switch Paths.declaredEnvironmentName?.lowercased() {
        case "beta": return .beta
        default: return .test
        }
    }

    public var isProduction: Bool { self == .production }

    /// The single letter the menu bar and Dock carry.
    public var badge: String {
        switch self {
        case .production: return ""
        case .beta: return "B"
        case .test: return "T"
        }
    }

    public var displayName: String {
        switch self {
        case .production: return "Production"
        case .beta: return "Beta"
        case .test: return "Test"
        }
    }

    /// The banner colour. Red for test, amber for beta — distinct because
    /// mistaking beta for test is a different mistake from mistaking either for
    /// production, and a single "not prod" colour would hide that.
    public var bannerColor: Color {
        switch self {
        case .production: return .clear
        case .beta: return Color(nsColor: .systemOrange)
        case .test: return Color(nsColor: .systemRed)
        }
    }

    /// The pane's BACKGROUND tint, as a bare hex string (no leading `#`).
    /// `nil` on production — and nil means the escape is NOT EMITTED AT ALL,
    /// so a production pane's script stays byte-identical to today's.
    ///
    /// NOT `bannerColor`, and that is a decision rather than a duplication.
    /// `bannerColor` is `.systemOrange`: correct as a 22pt fill over app chrome,
    /// unreadable as the ground behind terminal text. These are two different
    /// QUANTITIES that happen to mean the same thing, not two descriptions of
    /// one quantity. Deriving one by darkening the other was considered and
    /// rejected — terminal contrast is not a linear function of a UI fill, and
    /// a derived value is one nobody can read off the file.
    ///
    /// KEEP THE TINTS DARK AND LOW-SATURATION. These values are a starting
    /// point, not a verified choice — nobody has looked at one in a real pane
    /// yet. Never `systemOrange`.
    public var paneBackgroundHex: String? {
        switch self {
        case .production: return nil
        case .beta: return "3a2410"  // dark amber
        case .test: return "3a1414"  // dark red
        }
    }
}

/// The always-visible bar a non-production window carries.
///
/// Correct AT FIRST PAINT, which is the whole requirement. `Paths.root` reads
/// the bundle key synchronously in-process, so this renders the truth on frame
/// zero — unlike the daemon's `PATHS_GET` answer, which arrives after the window
/// is already on screen and would flash production chrome first.
public struct EnvironmentBanner: View {
    private let kind: EnvironmentKind

    public init(kind: EnvironmentKind = .current) {
        self.kind = kind
    }

    public var body: some View {
        if kind.isProduction {
            EmptyView()
        } else {
            HStack(spacing: 6) {
                Text(kind.badge).font(.system(size: 10, weight: .heavy, design: .rounded))
                Text(kind.displayName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                Spacer()
                // The ROOT, spelled out. A banner saying "TEST" tells you the
                // build's intent; the path tells you what it will actually
                // write, and only the second one is checkable.
                Text(Paths.root.path)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .frame(maxWidth: .infinity)
            .background(kind.bannerColor)
            .foregroundStyle(.white)
        }
    }
}

/// Dock-tile badging.
///
/// ## The Dock tile is CONDITIONAL, and that is accepted rather than worked around
///
/// `INFOPLIST_KEY_LSUIElement = YES` means the app is menu-bar resident and has
/// NO Dock tile at all until a window opens — `WindowPresence` raises the
/// activation policy to `.regular` only while one is on screen. So a Dock badge
/// cannot be the primary signal, and this is stated here rather than left for
/// someone to discover as a bug: the ALWAYS-VISIBLE signals are the menu-bar
/// glyph and the banner above.
///
/// Call this after the activation policy changes. It is a no-op on production
/// and a no-op when there is no tile to draw on.
@MainActor
public enum EnvironmentDockBadge {

    public static func apply(kind: EnvironmentKind = .current) {
        guard !kind.isProduction else {
            NSApp.applicationIconImage = nil  // back to the bundle icon
            return
        }
        guard NSApp.activationPolicy() == .regular else { return }
        NSApp.applicationIconImage = badged(kind: kind)
    }

    /// Composite the environment letter over the app icon.
    private static func badged(kind: EnvironmentKind) -> NSImage? {
        let base = NSApp.applicationIconImage ?? NSImage(named: NSImage.applicationIconName)
        guard let base else { return nil }
        let size = NSSize(width: 512, height: 512)
        let image = NSImage(size: size)
        image.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size))

        let inset: CGFloat = 40
        let diameter: CGFloat = 300
        let circle = NSRect(
            x: size.width - diameter - inset, y: inset,
            width: diameter, height: diameter)
        NSColor(
            cgColor: kind == .beta
                ? NSColor.systemOrange.cgColor
                : NSColor.systemRed.cgColor)?.setFill()
        NSBezierPath(ovalIn: circle).fill()

        let letter = kind.badge as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 210, weight: .heavy),
            .foregroundColor: NSColor.white,
        ]
        let textSize = letter.size(withAttributes: attributes)
        letter.draw(
            at: NSPoint(
                x: circle.midX - textSize.width / 2,
                y: circle.midY - textSize.height / 2),
            withAttributes: attributes)

        image.unlockFocus()
        return image
    }
}
