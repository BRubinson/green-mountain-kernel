import SwiftUI
import AppKit

// A code-editor-style editable markdown field for the prompt editor's
// Backstory/Goal/Detail sections, backed by a single NSTextView (TextKit 1) inside an
// NSScrollView with an NSRulerView line-number gutter.
//
// Why AppKit: the field must behave like a NORMAL text view — ⌘A selects the whole
// section, selection spans lines, and the selection stays visible (greyed) when focus
// leaves — AND keep a precise, wrap-aware line-number gutter (one number per logical
// line, aligned to its first wrapped row). Those are native NSTextView/TextKit
// behaviors; SwiftUI exposes neither cross-line selection persistence nor per-line
// layout geometry.
//
// The NSScrollView hosts the text view (so width-tracking / wrapping work the standard
// way) but does NOT scroll: scrollers are off and the view is sized exactly to its
// content via `sizeThatFits`, so the host's outer SwiftUI ScrollView scrolls the page.
//
// The public contract stays a plain `Binding<String>`: header styling (purplish,
// level-scaled font, `#` markers kept) is re-derived into the text storage on every edit
// and never persisted. Wrapping is display-only — the model keeps one logical line per
// "\n" — so the host's persistence / undo / autosave (keyed on the String) are untouched.
struct MarkdownSourceEditor: NSViewRepresentable {
    @Binding var text: String
    var minHeight: CGFloat
    // Find-in-page: when this field is the active find segment, select the active match
    // so it's visible inside the editor.
    var query: SearchQuery = SearchQuery("")
    var activeOccurrence: Int? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.verticalScrollElasticity = .none
        scrollView.horizontalScrollElasticity = .none
        scrollView.autohidesScrollers = true

        // Explicit TextKit 1 stack so `layoutManager` geometry (gutter + height) is
        // available (modern NSTextView defaults to TextKit 2, where it's nil).
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = MarkdownHeaderStyle.editorInsetH
        layoutManager.addTextContainer(textContainer)

        let textView = NSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.drawsBackground = false
        textView.textColor = MarkdownHeaderStyle.nsBodyColor
        textView.font = MarkdownHeaderStyle.nsFont(forLevel: nil)
        textView.textContainerInset = NSSize(width: 0, height: MarkdownHeaderStyle.editorInsetV)
        textView.typingAttributes = [
            .font: MarkdownHeaderStyle.nsFont(forLevel: nil),
            .foregroundColor: MarkdownHeaderStyle.nsBodyColor,
        ] as [NSAttributedString.Key: Any]

        scrollView.documentView = textView

        let ruler = LineNumberRuler(scrollView: scrollView, textView: textView)
        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true

        context.coordinator.textView = textView
        context.coordinator.ruler = ruler
        context.coordinator.setText(text)
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.parent = self
        if context.coordinator.textView?.string != text {
            context.coordinator.setText(text, preservingSelection: true)
        }
        context.coordinator.applyFind(query: query, activeOccurrence: activeOccurrence)
    }

    // Self-size: lay the text out at the proposed content width and report the used
    // height, so the editor grows to fit inside the host's vertical ScrollView.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView scrollView: NSScrollView,
                      context: Context) -> CGSize? {
        let width = proposal.width ?? scrollView.bounds.width
        guard width > 0 else { return nil }
        let h = context.coordinator.height(forWidth: width)
        return CGSize(width: width, height: max(minHeight, h))
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownSourceEditor
        weak var textView: NSTextView?
        weak var ruler: LineNumberRuler?
        private var lastFindKey: String?

        // Detached TextKit stack used ONLY for height measurement. Mirrors the live
        // stack's container padding so `usedRect` matches the displayed layout, but is
        // never shown — so probing it at arbitrary widths can't corrupt the on-screen
        // text view (the previous approach resized the live view, collapsing it to a
        // 1-glyph column).
        private let measuringStorage = NSTextStorage()
        private let measuringLayout = NSLayoutManager()
        private let measuringContainer = NSTextContainer(
            size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))

        init(_ parent: MarkdownSourceEditor) {
            self.parent = parent
            super.init()
            measuringStorage.addLayoutManager(measuringLayout)
            measuringLayout.addTextContainer(measuringContainer)
            measuringContainer.lineFragmentPadding = MarkdownHeaderStyle.editorInsetH
            measuringContainer.widthTracksTextView = false
        }

        // MARK: Text + styling

        func setText(_ string: String, preservingSelection: Bool = false) {
            guard let tv = textView else { return }
            let sel = tv.selectedRange()
            tv.string = string
            restyle()
            if preservingSelection {
                let len = (tv.string as NSString).length
                let loc = min(sel.location, len)
                tv.setSelectedRange(NSRange(location: loc, length: min(sel.length, len - loc)))
            }
            updateRuler()
        }

        // One whole-line font + color run per logical line (heading → level font + purple;
        // body → body font + adaptive label color). Idempotent; re-run on every edit so
        // styling tracks typed "#"s. Does not touch the selection.
        func restyle() {
            guard let ts = textView?.textStorage else { return }
            Self.applyStyling(to: ts)
        }

        // Styling is factored out so the detached measuring text storage (see
        // `height(forWidth:)`) can be styled identically to the live one — per-line
        // heading fonts change line heights, so the measurement must match the display.
        static func applyStyling(to ts: NSTextStorage) {
            let nsString = ts.string as NSString
            let len = nsString.length
            ts.beginEditing()
            var idx = 0
            while idx < len {
                let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
                var contentRange = lineRange
                while contentRange.length > 0 {
                    let c = nsString.character(at: contentRange.location + contentRange.length - 1)
                    if c == 10 || c == 13 { contentRange.length -= 1 } else { break }
                }
                let level = MarkdownHeaderStyle.headingLevel(of: nsString.substring(with: contentRange))
                ts.addAttribute(.font, value: MarkdownHeaderStyle.nsFont(forLevel: level), range: lineRange)
                ts.addAttribute(.foregroundColor,
                                value: level != nil ? MarkdownHeaderStyle.nsHeaderColor : MarkdownHeaderStyle.nsBodyColor,
                                range: lineRange)
                idx = NSMaxRange(lineRange)
            }
            ts.endEditing()
        }

        func updateRuler() {
            guard let tv = textView, let ruler else { return }
            let lineCount = max(1, (tv.string as NSString).components(separatedBy: "\n").count)
            let digits = max(2, String(lineCount).count)
            ruler.ruleThickness = CGFloat(digits) * 8 + 16
            ruler.needsDisplay = true
        }

        // Lay the text out at a given total width and return the height it needs.
        // Measures on the DETACHED stack so it never touches the live text view's
        // geometry — the on-screen width is driven solely by the scroll view's tiling
        // (`widthTracksTextView` + `autoresizingMask = [.width]`).
        func height(forWidth width: CGFloat) -> CGFloat {
            guard let tv = textView else { return parent.minHeight }
            let rulerThickness = ruler?.ruleThickness ?? 0
            // Matches the live container width (scroll view width − ruler), so the
            // measured height tracks the displayed layout.
            let contentWidth = max(20, width - rulerThickness)
            let s = tv.string
            if measuringStorage.string != s {
                measuringStorage.replaceCharacters(
                    in: NSRange(location: 0, length: measuringStorage.length), with: s)
            }
            Self.applyStyling(to: measuringStorage)
            measuringContainer.size = NSSize(width: contentWidth, height: CGFloat.greatestFiniteMagnitude)
            measuringLayout.ensureLayout(for: measuringContainer)
            return measuringLayout.usedRect(for: measuringContainer).height
                + tv.textContainerInset.height * 2
        }

        // MARK: Delegate

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            restyle()
            updateRuler()
            if parent.text != tv.string { parent.text = tv.string }
            lastFindKey = nil
            tv.enclosingScrollView?.invalidateIntrinsicContentSize()
        }

        // Select the active find match so it's visible (mirrors the old selectActiveMatch).
        // Keyed on (literal, occurrence) so it only re-applies when the target changes.
        func applyFind(query: SearchQuery, activeOccurrence: Int?) {
            guard let tv = textView else { return }
            guard query.isActive, let occ = activeOccurrence else { lastFindKey = nil; return }
            let key = "\(query.literal)#\(occ)"
            guard key != lastFindKey else { return }
            let s = tv.string
            let ranges = query.ranges(in: s)
            guard ranges.indices.contains(occ) else { return }
            lastFindKey = key
            let ns = NSRange(ranges[occ], in: s)
            tv.setSelectedRange(ns)
            tv.scrollRangeToVisible(ns)
        }
    }
}

// MARK: - Line-number gutter (NSRulerView)

// Draws one right-aligned number per LOGICAL line at that line's first visual (wrapped)
// row, using the text view's TextKit line-fragment geometry, so numbers stay aligned
// even when lines soft-wrap. A trailing empty line (text ends in "\n") is numbered via
// the layout manager's extra line fragment.
final class LineNumberRuler: NSRulerView {
    init(scrollView: NSScrollView, textView: NSTextView) {
        super.init(scrollView: scrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 32
    }

    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let tv = clientView as? NSTextView,
              let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let nsString = tv.string as NSString
        let len = nsString.length
        let inset = tv.textContainerInset.height
        let relativeY = convert(NSPoint.zero, from: tv).y
        let attrs: [NSAttributedString.Key: Any] = [
            .font: MarkdownHeaderStyle.nsFont(forLevel: nil),
            .foregroundColor: NSColor.tertiaryLabelColor,
        ]

        func drawNumber(_ n: Int, fragMinY: CGFloat) {
            let str = "\(n)" as NSString
            let size = str.size(withAttributes: attrs)
            str.draw(at: NSPoint(x: ruleThickness - size.width - 6, y: fragMinY + relativeY + inset),
                     withAttributes: attrs)
        }

        var idx = 0
        var line = 1
        while idx < len {
            let lineRange = nsString.lineRange(for: NSRange(location: idx, length: 0))
            let glyphRange = lm.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
            let frag = lm.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            drawNumber(line, fragMinY: frag.minY)
            line += 1
            idx = NSMaxRange(lineRange)
        }
        if len == 0 {
            drawNumber(1, fragMinY: 0)
        } else if nsString.character(at: len - 1) == 10 || nsString.character(at: len - 1) == 13 {
            let extra = lm.extraLineFragmentRect
            drawNumber(line, fragMinY: extra.height > 0 ? extra.minY : lm.usedRect(for: tc).height)
        }
    }
}
