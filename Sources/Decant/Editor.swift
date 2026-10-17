import AppKit
import DecantCore
import SwiftUI

struct EditorMark: Equatable {
    var range: NSRange
    var color: NSColor
}

/// A request to move the caret to a line/column; `id` makes repeated jumps to the same spot fire again.
struct Jump: Equatable {
    var line: Int
    var column: Int
    var id = UUID()
}

enum EditorFont {
    static func make(family: String, size: Double) -> NSFont {
        if !family.isEmpty, let f = NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: size) { return f }
        return .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static var families: [String] {
        let names = NSFontManager.shared.availableFontNames(with: .fixedPitchFontMask) ?? []
        return Array(Set(names.compactMap { NSFont(name: $0, size: 12)?.familyName })).filter { !$0.hasPrefix(".") }.sorted()
    }
}

final class EditorTextView: NSTextView {
    var onFile: ((URL) -> Void)?

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if let onFile, let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first {
            onFile(url)
            return true
        }
        return super.performDragOperation(sender)
    }
}

/// NSTextView-backed editor: fast with large documents, line numbers, find bar, wrap toggle, syntax colours,
/// background marks (regex matches) and an error line marked in the gutter.
struct CodeEditor: NSViewRepresentable {
    @Binding var text: String
    var editable = true
    var syntax: Format = .text
    var errorLine: Int?
    var jump: Jump?
    var marks: [EditorMark] = []
    /// Answers the Find in Output command.
    var findable = false
    var onFile: ((URL) -> Void)?
    var font: NSFont
    var wrap: Bool

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> EditorContainer {
        let tv = EditorTextView(usingTextLayoutManager: false)
        tv.isRichText = false
        tv.importsGraphics = false
        tv.allowsUndo = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isAutomaticSpellingCorrectionEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.isGrammarCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: 4, height: 14)
        tv.isVerticallyResizable = true
        tv.autoresizingMask = [.width]
        tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        tv.delegate = context.coordinator

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = tv
        let ruler = LineNumberGutter(textView: tv)
        let container = EditorContainer(scroll: scroll, gutter: ruler)
        scroll.contentView.postsBoundsChangedNotifications = true
        scroll.contentView.postsFrameChangedNotifications = true

        let c = context.coordinator
        c.textView = tv
        c.ruler = ruler
        let center = NotificationCenter.default
        for name in [NSView.boundsDidChangeNotification, NSView.frameDidChangeNotification] {
            c.observers.append(center.addObserver(forName: name, object: scroll.contentView, queue: .main) { [weak tv, weak ruler] _ in
                MainActor.assumeIsolated {
                    if let tv, let scroll = tv.enclosingScrollView { tv.minSize = NSSize(width: 0, height: scroll.contentSize.height) }
                    ruler?.needsDisplay = true
                }
            })
        }
        c.observers.append(center.addObserver(forName: .outputCommand, object: nil, queue: .main) { [weak c] note in
            let isFind = note.object as? String == OutputCommand.find.rawValue
            MainActor.assumeIsolated {
                guard isFind, let c, c.parent.findable, let tv = c.textView, tv.window != nil else { return }
                tv.window?.makeFirstResponder(tv)
                let item = NSMenuItem()
                item.tag = NSTextFinder.Action.showFindInterface.rawValue
                tv.performTextFinderAction(item)
            }
        })
        return container
    }

    func updateNSView(_ container: EditorContainer, context: Context) {
        let scroll = container.scroll
        let c = context.coordinator
        let old = c.parent
        c.parent = self
        guard let tv = c.textView else { return }
        tv.isEditable = editable
        tv.onFile = onFile
        tv.minSize = NSSize(width: 0, height: scroll.contentSize.height)
        applyWrap(scroll, tv)
        if tv.string != text {
            c.updating = true
            tv.string = text
            c.updating = false
            c.highlight()
        } else if old.font != font || old.syntax != syntax || c.needsHighlight {
            c.highlight()
        } else if old.marks != marks || old.errorLine != errorLine {
            c.applyMarks()
        }
        c.ruler?.font = .monospacedDigitSystemFont(ofSize: max(9, font.pointSize - 2), weight: .regular)
        c.ruler?.errorLine = errorLine
        c.ruler?.needsDisplay = true
        if let jump, jump != c.lastJump {
            c.lastJump = jump
            DispatchQueue.main.async { c.go(to: jump) }
        }
    }

    static func dismantleNSView(_ nsView: EditorContainer, coordinator: Coordinator) {
        coordinator.observers.forEach(NotificationCenter.default.removeObserver)
    }

    private func applyWrap(_ scroll: NSScrollView, _ tv: NSTextView) {
        guard let container = tv.textContainer, container.widthTracksTextView != wrap || scroll.hasHorizontalScroller == wrap else { return }
        scroll.hasHorizontalScroller = !wrap
        tv.isHorizontallyResizable = !wrap
        container.widthTracksTextView = wrap
        if wrap {
            container.containerSize = NSSize(width: scroll.contentSize.width, height: .greatestFiniteMagnitude)
            tv.setFrameSize(NSSize(width: scroll.contentSize.width, height: tv.frame.height))
        } else {
            container.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: CodeEditor
        weak var textView: EditorTextView?
        weak var ruler: LineNumberGutter?
        var observers: [NSObjectProtocol] = []
        var updating = false
        var needsHighlight = false
        var lastJump: Jump?
        private var pending: DispatchWorkItem?

        init(_ parent: CodeEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !updating, let tv = textView else { return }
            parent.text = tv.string
            ruler?.needsDisplay = true
            // Re-colour right away for normal documents, debounced for big ones.
            pending?.cancel()
            if tv.string.utf16.count < 50_000 {
                highlight()
            } else {
                let work = DispatchWorkItem { [weak self] in self?.highlight() }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
            }
        }

        var attributes: [NSAttributedString.Key: Any] {
            let para = NSMutableParagraphStyle()
            para.lineSpacing = parent.font.pointSize * 0.3
            return [.font: parent.font, .foregroundColor: NSColor.labelColor, .paragraphStyle: para]
        }

        func highlight() {
            needsHighlight = false
            guard let tv = textView, let storage = tv.textStorage else { return }
            let base = attributes
            storage.beginEditing()
            storage.setAttributes(base, range: NSRange(location: 0, length: storage.length))
            // ponytail: re-highlights the whole document; incremental highlighting if 400 KB+ files need colour.
            if parent.syntax != .text, storage.length < 400_000 {
                var location = 0
                for span in Highlighter.spans(storage.string, format: parent.syntax) {
                    let length = span.text.utf16.count
                    if span.role != .plain {
                        storage.addAttribute(.foregroundColor, value: Palette.nsColor(for: span.role), range: NSRange(location: location, length: length))
                    }
                    location += length
                }
            }
            storage.endEditing()
            tv.typingAttributes = base
            applyMarks()
        }

        func applyMarks() {
            guard let tv = textView, let lm = tv.layoutManager else { return }
            let length = (tv.string as NSString).length
            lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: NSRange(location: 0, length: length))
            for m in parent.marks where NSMaxRange(m.range) <= length {
                lm.addTemporaryAttribute(.backgroundColor, value: m.color, forCharacterRange: m.range)
            }
            if let line = parent.errorLine, let r = lineRange(line) {
                lm.addTemporaryAttribute(.backgroundColor, value: NSColor.systemRed.withAlphaComponent(0.14), forCharacterRange: r)
            }
        }

        func lineRange(_ line: Int) -> NSRange? {
            guard let ns = textView?.string as NSString?, line >= 1 else { return nil }
            var current = 1, index = 0
            while current < line {
                let r = ns.range(of: "\n", range: NSRange(location: index, length: ns.length - index))
                guard r.location != NSNotFound else { return nil }
                index = r.location + 1
                current += 1
            }
            return ns.lineRange(for: NSRange(location: index, length: 0))
        }

        func go(to jump: Jump) {
            guard let tv = textView, let line = lineRange(jump.line) else { return }
            let location = min(line.location + max(0, jump.column - 1), NSMaxRange(line))
            tv.window?.makeFirstResponder(tv)
            tv.setSelectedRange(NSRange(location: location, length: 0))
            tv.scrollRangeToVisible(line)
            tv.showFindIndicator(for: line)
        }
    }
}

/// The scroll view with a line-number gutter on its left. (A plain view rather than NSRulerView: floating
/// rulers lose their inset when the document scrolls horizontally.)
final class EditorContainer: NSView {
    let scroll: NSScrollView
    let gutter: LineNumberGutter

    init(scroll: NSScrollView, gutter: LineNumberGutter) {
        self.scroll = scroll
        self.gutter = gutter
        super.init(frame: .zero)
        addSubview(gutter)
        addSubview(scroll)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override func layout() {
        super.layout()
        let w = gutter.width
        gutter.frame = NSRect(x: 0, y: 0, width: w, height: bounds.height)
        scroll.frame = NSRect(x: w, y: 0, width: max(0, bounds.width - w), height: bounds.height)
    }
}

/// Line numbers; the error line gets a red marker.
final class LineNumberGutter: NSView {
    weak var textView: NSTextView?
    var errorLine: Int?
    var font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    private(set) var width: CGFloat = 40
    private var counted = (length: -1, lines: 1)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("unused") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let tv = textView, let lm = tv.layoutManager, let tc = tv.textContainer else { return }
        let ns = tv.string as NSString
        if counted.length != ns.length {
            var n = 1
            ns.enumerateSubstrings(in: NSRange(location: 0, length: ns.length), options: [.byLines, .substringNotRequired]) { _, _, _, _ in n += 1 }
            counted = (ns.length, n)
        }
        let digitWidth = ("8" as NSString).size(withAttributes: [.font: font]).width
        let w = CGFloat(max(2, String(counted.lines).count)) * digitWidth + 26
        if abs(w - width) > 0.5 {
            width = w
            superview?.needsLayout = true
            return
        }

        let visible = tv.visibleRect
        let chars = lm.characterRange(forGlyphRange: lm.glyphRange(forBoundingRect: visible, in: tc), actualGlyphRange: nil)
        // ponytail: counts newlines from the top on every draw; cache line starts if huge files scroll slowly.
        var line = 1
        var index = 0
        while index < chars.location {
            let r = ns.range(of: "\n", range: NSRange(location: index, length: chars.location - index))
            guard r.location != NSNotFound else { break }
            index = r.location + 1
            line += 1
        }
        let normal: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor(Palette.gutter)]
        let error: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
        let inset = tv.textContainerInset.height

        func draw(_ n: Int, _ fragment: NSRect) {
            let y = convert(NSPoint(x: 0, y: fragment.minY + inset), from: tv).y
            let label = "\(n)" as NSString
            let isError = n == errorLine
            let size = label.size(withAttributes: normal)
            let lineHeight = min(fragment.height, font.pointSize * 2.2)
            let origin = NSPoint(x: width - size.width - 12, y: y + (lineHeight - size.height) / 2 - 1)
            if isError {
                NSColor.systemRed.setFill()
                NSBezierPath(roundedRect: NSRect(x: origin.x - 5, y: origin.y - 1, width: size.width + 10, height: size.height + 2), xRadius: 5, yRadius: 5).fill()
            }
            label.draw(at: origin, withAttributes: isError ? error : normal)
        }

        index = ns.length == 0 ? 0 : ns.lineRange(for: NSRange(location: min(chars.location, ns.length - 1), length: 0)).location
        while index < ns.length, index <= NSMaxRange(chars) {
            draw(line, lm.lineFragmentRect(forGlyphAt: lm.glyphIndexForCharacter(at: index), effectiveRange: nil))
            index = NSMaxRange(ns.lineRange(for: NSRange(location: index, length: 0)))
            line += 1
        }
        if ns.length == 0 || ns.character(at: ns.length - 1) == 10, lm.extraLineFragmentRect.height > 0 {
            draw(line, lm.extraLineFragmentRect)
        }
    }
}
