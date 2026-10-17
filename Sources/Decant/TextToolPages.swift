import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import DecantCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Diff

struct DiffPage: View {
    @Environment(Store.self) private var store
    @AppStorage("diffUnified") private var unified = false
    @AppStorage("diffIgnoreWhitespace") private var ignoreWhitespace = false
    @AppStorage("diffIgnoreCase") private var ignoreCase = false
    @AppStorage("diffCollapse") private var collapse = true
    @State private var rows: [Diff.Row] = []

    private struct Key: Equatable { var a, b: String; var ws, cs: Bool }

    var body: some View {
        @Bindable var store = store
        let doc = store[doc: .diff]
        let added = rows.filter { $0.kind == .added || $0.kind == .changed }.count
        let removed = rows.filter { $0.kind == .removed || $0.kind == .changed }.count
        let empty = doc.input.isEmpty && doc.aux.isEmpty
        ToolPage(tool: .diff, status: empty ? nil : added + removed == 0 ? Status(text: "Identical") : Status(text: "+\(added) −\(removed)", tone: .neutral),
                 meta: empty ? ["Line diff with word-level highlights"] : ["\(rows.filter { $0.kind == .changed }.count) changed", "\(rows.filter { $0.kind == .added }.count) added", "\(rows.filter { $0.kind == .removed }.count) removed"]) {
            OptionSegments(selection: $unified, options: [("Side by Side", false), ("Unified", true)])
            OptionToggle(title: "Ignore whitespace", isOn: $ignoreWhitespace)
            OptionToggle(title: "Ignore case", isOn: $ignoreCase)
            OptionToggle(title: "Collapse unchanged", isOn: $collapse)
            CapsuleButton(title: "Swap", systemImage: "arrow.left.arrow.right") {
                store[doc: .diff] = Doc(input: doc.aux, aux: doc.input)
            }
        } content: {
            GeometryReader { g in
                VStack(spacing: 14) {
                    HStack(spacing: 14) {
                        EditorPane(title: "Original", text: $store[doc: .diff].input, placeholder: "Paste the original text.")
                        EditorPane(title: "Changed", text: $store[doc: .diff].aux, placeholder: "Paste the changed text.")
                    }
                    .frame(height: max(160, g.size.height * 0.36))
                    Pane("Differences") {
                        if empty {
                            Text("Paste two texts to compare them.").foregroundStyle(Palette.text4).frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            DiffView(rows: rows, unified: unified, collapse: collapse)
                        }
                    } accessory: {
                        if !empty {
                            HStack(spacing: 10) {
                                Text("+\(added)").foregroundStyle(Palette.added)
                                Text("−\(removed)").foregroundStyle(Palette.removed)
                            }
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .padding(.trailing, 10)
                        }
                    }
                }
            }
        }
        .task(id: Key(a: doc.input, b: doc.aux, ws: ignoreWhitespace, cs: ignoreCase)) {
            let (a, b, ws, cs) = (doc.input, doc.aux, ignoreWhitespace, ignoreCase)
            rows = await Task.detached { Diff.rows(a, b, ignoreWhitespace: ws, ignoreCase: cs) }.value
        }
    }
}

struct DiffView: View {
    let rows: [Diff.Row]
    var unified = false
    var collapse = true
    @State private var expanded: Set<Int> = []
    @AppStorage("fontSize") private var fontSize = 13.0

    struct Line: Hashable {
        var kind: Diff.Kind
        var old: Diff.Line?
        var new: Diff.Line?
    }

    private enum Item: Hashable { case line(Int), fold(Int, Int) }

    /// Unified lines: every change block lists its removed lines, then its added ones.
    private var lines: [Line] {
        guard unified else { return rows.map { Line(kind: $0.kind, old: $0.left, new: $0.right) } }
        var out: [Line] = [], dels: [Line] = [], adds: [Line] = []
        func flush() { out += dels + adds; dels = []; adds = [] }
        for r in rows {
            if r.kind == .same {
                flush()
                out.append(Line(kind: .same, old: r.left, new: r.right))
            } else {
                if let l = r.left { dels.append(Line(kind: .removed, old: l, new: nil)) }
                if let n = r.right { adds.append(Line(kind: .added, old: nil, new: n)) }
            }
        }
        flush()
        return out
    }

    /// Long unchanged runs fold down to three lines of context on each side.
    private func items(_ lines: [Line]) -> [Item] {
        guard collapse, lines.contains(where: { $0.kind != .same }) else { return lines.indices.map(Item.line) }
        var out: [Item] = []
        var i = 0
        while i < lines.count {
            guard lines[i].kind == .same else { out.append(.line(i)); i += 1; continue }
            var j = i
            while j < lines.count, lines[j].kind == .same { j += 1 }
            let lead = i == 0 ? 0 : 3, trail = j == lines.count ? 0 : 3
            if j - i > lead + trail + 2, !expanded.contains(i) {
                out += (i..<i + lead).map(Item.line)
                out.append(.fold(i, j - i - lead - trail))
                out += (j - trail..<j).map(Item.line)
            } else {
                out += (i..<j).map(Item.line)
            }
            i = j
        }
        return out
    }

    var body: some View {
        let lines = lines
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items(lines), id: \.self) { item in
                    switch item {
                    case .line(let i): unified ? AnyView(unifiedRow(lines[i])) : AnyView(splitRow(lines[i]))
                    case .fold(let key, let count):
                        Button { expanded.insert(key) } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.up.and.down")
                                Text("\(count) unchanged lines")
                            }
                            .font(.system(size: 11.5, weight: .medium))
                            .foregroundStyle(Palette.text3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 26)
                            .background(Palette.accentTint.opacity(0.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 6)
        }
        .font(.system(size: fontSize - 0.5, design: .monospaced))
    }

    private func splitRow(_ line: Line) -> some View {
        HStack(alignment: .top, spacing: 0) {
            half(line.old, side: .removed, kind: line.kind)
            Rectangle().fill(Palette.cardSeparator).frame(width: 1)
            half(line.new, side: .added, kind: line.kind)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func half(_ l: Diff.Line?, side: Diff.Kind, kind: Diff.Kind) -> some View {
        let changed = kind != .same
        let tint = side == .removed ? Palette.removed : Palette.added
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(l.map { "\($0.number)" } ?? "")
                .foregroundStyle(Palette.gutter)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, 6)
            Text(l != nil && changed ? (side == .removed ? "−" : "+") : " ")
                .foregroundStyle(tint)
                .frame(width: 14)
            Text(l.map { attributed($0, tint: tint) } ?? AttributedString(""))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 10)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(l == nil ? (changed ? Palette.cardFoot : .clear) : changed ? tint.opacity(0.10) : .clear)
    }

    private func unifiedRow(_ line: Line) -> some View {
        let tint = line.kind == .removed ? Palette.removed : Palette.added
        let l = line.new ?? line.old
        return HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(line.old.map { "\($0.number)" } ?? "").frame(width: 44, alignment: .trailing)
            Text(line.new.map { "\($0.number)" } ?? "").frame(width: 44, alignment: .trailing).padding(.trailing, 6)
            Text(line.kind == .same ? " " : line.kind == .removed ? "−" : "+").foregroundStyle(tint).frame(width: 14)
            Text(l.map { attributed($0, tint: tint) } ?? AttributedString(""))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(Palette.gutter)
        .padding(.vertical, 2)
        .background(line.kind == .same ? Color.clear : tint.opacity(0.10))
    }

    private func attributed(_ line: Diff.Line, tint: Color) -> AttributedString {
        line.segments.reduce(into: AttributedString()) { out, s in
            var part = AttributedString(s.text)
            part.foregroundColor = .primary
            if s.emphasized { part.backgroundColor = tint.opacity(0.32) }
            out += part
        }
    }
}

// MARK: - Regex

struct RegexPage: View {
    @Environment(Store.self) private var store
    @AppStorage("rxIgnoreCase") private var ignoreCase = false
    @AppStorage("rxMultiline") private var multiline = true
    @AppStorage("rxDotAll") private var dotAll = false
    @AppStorage("rxExtended") private var extended = false

    private static let groupColors: [NSColor] = [.systemOrange, .systemGreen, .systemPurple, .systemPink, .systemTeal, .systemYellow]

    var body: some View {
        @Bindable var store = store
        let doc = store[doc: .regex]
        let (regex, error) = compile(doc.aux)
        let matches = regex.map { Array($0.matches(in: doc.input, range: NSRange(location: 0, length: (doc.input as NSString).length)).prefix(5000)) } ?? []
        let names = RegexGroups.names(doc.aux)
        ToolPage(tool: .regex, status: error.map(Status.error) ?? (doc.aux.isEmpty ? nil : Status(text: matches.count == 1 ? "1 match" : "\(matches.count) matches", tone: matches.isEmpty ? .neutral : .ok)),
                 meta: ["\(regex?.numberOfCaptureGroups ?? 0) groups", "ICU syntax"]) {
            HStack(spacing: 4) {
                Text("/").foregroundStyle(Palette.text4)
                TextField("Pattern, e.g. (?<year>\\d{4})-(\\d{2})", text: $store[doc: .regex].aux)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, design: .monospaced))
                    .frame(width: 360)
                Text("/" + flags).foregroundStyle(Palette.text4).font(.system(size: 13.5, design: .monospaced))
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .glassCapsule()
            OptionToggle(title: "Ignore case", isOn: $ignoreCase)
            OptionToggle(title: "^$ per line", isOn: $multiline)
            OptionToggle(title: ". matches newline", isOn: $dotAll)
            OptionToggle(title: "Extended", isOn: $extended)
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Test String", text: $store[doc: .regex].input,
                           placeholder: "Paste text to test the pattern against. Matches and capture groups are highlighted.",
                           marks: marks(matches), footer: error.map { AnyView(ErrorBar(message: $0)) })
                Pane("Matches") {
                    if matches.isEmpty {
                        Text(doc.aux.isEmpty ? "Type a pattern above." : "No matches.").foregroundStyle(Palette.text4).frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(matches.prefix(500).enumerated()), id: \.offset) { i, m in
                                    matchRow(i, m, text: doc.input as NSString, names: names)
                                    Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                                }
                            }
                        }
                    }
                } accessory: {
                    if !matches.isEmpty {
                        IconButton(systemImage: "doc.on.doc", help: "Copy All Matches") {
                            Output.copy(matches.map { (doc.input as NSString).substring(with: $0.range) }.joined(separator: "\n"))
                        }
                    }
                }
                .frame(width: 340)
            }
        }
    }

    private var flags: String {
        (ignoreCase ? "i" : "") + (multiline ? "m" : "") + (dotAll ? "s" : "") + (extended ? "x" : "")
    }

    private func compile(_ pattern: String) -> (NSRegularExpression?, String?) {
        guard !pattern.isEmpty else { return (nil, nil) }
        var o: NSRegularExpression.Options = []
        if ignoreCase { o.insert(.caseInsensitive) }
        if multiline { o.insert(.anchorsMatchLines) }
        if dotAll { o.insert(.dotMatchesLineSeparators) }
        if extended { o.insert(.allowCommentsAndWhitespace) }
        do { return (try NSRegularExpression(pattern: pattern, options: o), nil) } catch {
            return (nil, (error as NSError).userInfo["NSInvalidValue"].map { "Invalid pattern: \($0)" } ?? "Invalid pattern")
        }
    }

    private func marks(_ matches: [NSTextCheckingResult]) -> [EditorMark] {
        matches.flatMap { m in
            [EditorMark(range: m.range, color: NSColor.controlAccentColor.withAlphaComponent(0.22))]
                + (1..<max(m.numberOfRanges, 1)).compactMap { g in
                    let r = m.range(at: g)
                    return r.location == NSNotFound ? nil : EditorMark(range: r, color: Self.groupColors[(g - 1) % Self.groupColors.count].withAlphaComponent(0.35))
                }
        }
    }

    private func matchRow(_ i: Int, _ m: NSTextCheckingResult, text: NSString, names: [Int: String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Match \(i + 1)").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(m.range.location)–\(NSMaxRange(m.range))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.text4)
            }
            Text(text.substring(with: m.range).isEmpty ? "(empty)" : text.substring(with: m.range))
                .font(.system(size: 12.5, design: .monospaced))
                .textSelection(.enabled)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 5))
            ForEach(1..<max(m.numberOfRanges, 1), id: \.self) { g in
                let r = m.range(at: g)
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle().fill(Color(nsColor: Self.groupColors[(g - 1) % Self.groupColors.count])).frame(width: 7, height: 7)
                    Text(names[g].map { "\(g) \($0)" } ?? "\(g)").foregroundStyle(Palette.text3).frame(minWidth: 24, alignment: .leading)
                    Text(r.location == NSNotFound ? "–" : text.substring(with: r))
                        .font(.system(size: 12.5, design: .monospaced))
                        .textSelection(.enabled)
                }
                .font(.system(size: 12))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

// MARK: - Counter

struct CounterPage: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let s = TextStats(store[doc: .counter].input)
        ToolPage(tool: .counter, meta: ["\(s.words) words", "\(s.characters) characters", "\(s.lines) lines"]) {
            EmptyView()
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Text", text: $store[doc: .counter].input, placeholder: "Type or paste text to count characters, words and lines.")
                Pane("Counts") {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 12) {
                            tile("Characters", s.characters)
                            tile("Without whitespace", s.nonWhitespace)
                            tile("Words", s.words)
                            tile("Lines", s.lines)
                            tile("Sentences", s.sentences)
                            tile("Paragraphs", s.paragraphs)
                            tile("UTF-8 bytes", s.bytes)
                            tile("UTF-16 units", s.utf16)
                            tile("Reading time", s.readingTime)
                        }
                        .padding(16)
                    }
                }
                .frame(width: 360)
            }
        }
    }

    private func tile(_ label: String, _ value: some CustomStringConvertible) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value is Int ? (value as! Int).formatted() : value.description)
                .font(.system(size: 26, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Palette.cardFoot, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Markdown

struct MarkdownPage: View {
    @Environment(Store.self) private var store
    @AppStorage("markdownHTML") private var showHTML = false

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .markdown].input
        let html = Markdown.html(input)
        let stats = TextStats(input)
        ToolPage(tool: .markdown, status: input.isEmpty ? nil : Status(text: "Rendered"), meta: input.isEmpty ? ["CommonMark with GitHub tables"] : ["\(stats.words) words", stats.readingTime + " read"]) {
            OptionSegments(selection: $showHTML, options: [("Preview", false), ("HTML", true)])
            CapsuleButton(title: "Copy HTML", systemImage: "doc.on.doc") { Output.copy(html) }
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Markdown", text: $store[doc: .markdown].input,
                           placeholder: "Write or paste Markdown. CommonMark with GitHub tables and strikethrough.")
                if showHTML {
                    EditorPane(title: "HTML", text: .constant(html), editable: false, output: true, primary: true, fileExtension: "html")
                } else {
                    Pane("Preview") {
                        MarkdownWebView(html: html)
                    } accessory: {
                        IconButton(systemImage: "square.and.arrow.down", help: "Save HTML…") {
                            Output.save(Data(MarkdownWebView.page(html).utf8), name: "Preview.html")
                        }
                        IconButton(systemImage: "doc.on.doc", help: "Copy HTML (⇧⌘C)") { Output.copy(html) }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .outputCommand)) { note in
                        if note.object as? String == OutputCommand.copy.rawValue { Output.copy(html) }
                        if note.object as? String == OutputCommand.save.rawValue { Output.save(Data(MarkdownWebView.page(html).utf8), name: "Preview.html") }
                    }
                }
            }
        }
    }
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String

    static func page(_ body: String) -> String {
        """
        <!doctype html><html><head><meta charset="utf-8"><style>
        :root { color-scheme: light dark; }
        body { font: 14px/1.6 -apple-system, system-ui; margin: 0; padding: 22px 28px; max-width: 780px; color: #1d1f24; background: transparent; }
        @media (prefers-color-scheme: dark) { body { color: #e6e7ea; } a { color: #86b8ff; } code, pre { background: rgba(255,255,255,.07) !important; } th, td { border-color: #3a3d44 !important; } blockquote { border-color: #4a4e57 !important; color: #a4a9b3 !important; } hr { border-color: #3a3d44 !important; } }
        h1, h2, h3 { line-height: 1.25; margin: 1.3em 0 .5em; } h1 { font-size: 1.9em; } h2 { font-size: 1.45em; } h1:first-child, h2:first-child { margin-top: 0; }
        code { font: 12.5px ui-monospace, SFMono-Regular, Menlo, monospace; background: rgba(0,0,0,.05); padding: .15em .35em; border-radius: 5px; }
        pre { background: rgba(0,0,0,.045); padding: 14px 16px; border-radius: 10px; overflow: auto; } pre code { background: none !important; padding: 0; }
        blockquote { margin: 0; padding: 0 1em; border-left: 3px solid #d3d6dc; color: #5c6270; }
        table { border-collapse: collapse; } th, td { border: 1px solid #d3d6dc; padding: 6px 12px; text-align: left; }
        img { max-width: 100%; } hr { border: 0; border-top: 1px solid #d3d6dc; margin: 2em 0; } li p { margin: .2em 0; }
        </style></head><body><div id="c">\(body)</div></body></html>
        """
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        let web = WKWebView()
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        web.loadHTMLString(Self.page(html), baseURL: nil)
        context.coordinator.last = html
        return web
    }

    func updateNSView(_ web: WKWebView, context: Context) {
        guard context.coordinator.last != html else { return }
        context.coordinator.last = html
        // Swap the body in place so the scroll position survives typing.
        web.evaluateJavaScript("document.getElementById('c').innerHTML = \(JSONValue.quote(html))")
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var last = ""

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }
    }
}

// MARK: - Color

struct ColorPage: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .color].input
        let rgba = RGBA(input)
        ToolPage(tool: .color, status: input.isEmpty ? nil : rgba == nil ? .error("Not a color") : Status(text: rgba!.hex),
                 meta: ["HEX, RGB(A), HSL(A)"]) {
            HStack(spacing: 10) {
                Text("Color panel")
                ColorPicker("Color", selection: Binding(get: { color(rgba) }, set: { store[doc: .color].input = hex($0) }), supportsOpacity: true)
                    .labelsHidden()
            }
            .padding(.trailing, 8)
            .optionCapsule()
            CapsuleButton(title: "Pick from Screen", systemImage: "eyedropper") {
                let store = store
                NSColorSampler().show { picked in
                    guard let c = picked?.usingColorSpace(.sRGB) else { return }
                    let h = RGBA(r: c.redComponent, g: c.greenComponent, b: c.blueComponent, a: c.alphaComponent).hex
                    Task { @MainActor in store[doc: .color].input = h }
                }
            }
        } content: {
            HStack(alignment: .top, spacing: 14) {
                VStack(spacing: 0) {
                    ZStack {
                        Checkerboard()
                        Rectangle().fill(color(rgba))
                    }
                    .frame(maxWidth: .infinity, minHeight: 200, maxHeight: .infinity)
                    Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                    TextField("#3366CC, rgb(51 102 204), hsl(220 60% 50%)", text: $store[doc: .color].input)
                        .textFieldStyle(.plain)
                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                        .padding(18)
                }
                .card()
                Pane("Formats") {
                    if let rgba {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                DetailRows(rows: [
                                    Detail("HEX", rgba.hex),
                                    Detail("RGB", rgba.rgb),
                                    Detail("HSL", rgba.hsl),
                                    Detail("SwiftUI", rgba.swiftUI),
                                    Detail("CSS variable", "--color: \(rgba.hex.lowercased());"),
                                ])
                                Text("Contrast").font(.system(size: 11, weight: .semibold)).tracking(0.8).textCase(.uppercase)
                                    .foregroundStyle(Palette.text3).padding(.top, 16).padding(.bottom, 6)
                                DetailRows(rows: [
                                    contrast("On white", rgba.contrast(with: RGBA(r: 1, g: 1, b: 1))),
                                    contrast("On black", rgba.contrast(with: RGBA(r: 0, g: 0, b: 0))),
                                ], mono: false)
                            }
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                        }
                    } else {
                        Text("Type a color, or use the color panel or the eyedropper.").foregroundStyle(Palette.text4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: 420)
            }
        }
    }

    private func contrast(_ label: String, _ ratio: Double) -> Detail {
        Detail(label, String(format: "%.2f:1", ratio) + (ratio >= 7 ? " · AAA" : ratio >= 4.5 ? " · AA" : ratio >= 3 ? " · AA large text" : " · fails"))
    }

    private func color(_ c: RGBA?) -> Color {
        guard let c else { return .clear }
        return Color(.sRGB, red: c.r, green: c.g, blue: c.b, opacity: c.a)
    }

    private func hex(_ color: Color) -> String {
        guard let ns = NSColor(color).usingColorSpace(.sRGB) else { return "" }
        return RGBA(r: ns.redComponent, g: ns.greenComponent, b: ns.blueComponent, a: ns.alphaComponent).hex
    }
}

struct Checkerboard: View {
    var body: some View {
        Canvas { context, size in
            let s: CGFloat = 10
            for x in stride(from: 0, to: size.width, by: s) {
                for y in stride(from: 0, to: size.height, by: s) where (Int(x / s) + Int(y / s)).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: x, y: y, width: s, height: s)), with: .color(.gray.opacity(0.18)))
                }
            }
        }
    }
}

// MARK: - Cron

struct CronPage: View {
    @Environment(Store.self) private var store

    private static let presets = [
        ("Every minute", "* * * * *"), ("Every 5 minutes", "*/5 * * * *"), ("Every hour", "0 * * * *"),
        ("Every day at midnight", "0 0 * * *"), ("Weekdays at 9:00", "0 9 * * MON-FRI"), ("Every Sunday at 3:30", "30 3 * * SUN"),
        ("First of the month", "0 0 1 * *"), ("Every quarter", "0 0 1 */3 *"),
    ]

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .cron].input
        let parsed = Result { try Cron(input) }
        let cron = try? parsed.get()
        ToolPage(tool: .cron, status: input.isEmpty ? nil : cron == nil ? .error("Invalid expression") : Status(text: "Valid"),
                 meta: ["minute hour day month weekday", "Times in \(TimeZone.current.identifier)"]) {
            Menu {
                ForEach(Self.presets, id: \.1) { name, expr in
                    Button("\(name)  ·  \(expr)") { store[doc: .cron].input = expr }
                }
            } label: {
                Text("Presets").padding(.trailing, 8)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .optionCapsule()
        } content: {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("*/15 9-17 * * MON-FRI", text: $store[doc: .cron].input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 30, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 22)
                            .padding(.top, 18)
                            .padding(.bottom, 8)
                        fieldLabels(input)
                        Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                        Group {
                            switch parsed {
                            case .success(let cron) where !input.isEmpty:
                                Text(cron.description).font(.system(size: 20, weight: .semibold))
                            case .failure(let e) where !input.isEmpty:
                                Text(String(describing: e)).foregroundStyle(.red)
                            default:
                                Text("Type a cron expression, or pick a preset.").foregroundStyle(Palette.text4)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(22)
                    }
                    .card()
                    if let cron, !input.isEmpty {
                        Pane("Next Runs") {
                            DetailRows(rows: cron.next(after: Date(), count: 5).enumerated().map { i, d in
                                Detail("\(i + 1)", "\(d.formatted(date: .complete, time: .shortened))  ·  \(d.formatted(.relative(presentation: .named)))")
                            }, mono: false)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 6)
                        }
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollClipDisabled()
        }
    }

    private func fieldLabels(_ input: String) -> some View {
        let parts = input.split(whereSeparator: \.isWhitespace).map(String.init)
        let names = ["minute", "hour", "day (month)", "month", "day (week)"]
        return HStack(spacing: 18) {
            ForEach(names.indices, id: \.self) { i in
                VStack(alignment: .leading, spacing: 2) {
                    Text(i < parts.count && parts.count == 5 ? parts[i] : "–").font(.system(size: 12.5, design: .monospaced))
                    Text(names[i]).font(.system(size: 10.5)).foregroundStyle(Palette.text4)
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.bottom, 14)
    }
}

// MARK: - QR code

struct QRPage: View {
    @Environment(Store.self) private var store
    @AppStorage("qrCorrection") private var level = "M"
    @State private var readStatus: Status?

    private static let context = CIContext()

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .qr].input
        let code = image(input)
        ToolPage(tool: .qr, status: readStatus ?? (code != nil ? Status(text: "Generated") : nil),
                 meta: code.map { ["\($0.modules) × \($0.modules) modules", "Error correction \(level)", "\(input.utf8.count) bytes"] } ?? ["Generate or read QR codes"]) {
            OptionSegments(title: "Error correction", selection: $level, options: [("L", "L"), ("M", "M"), ("Q", "Q"), ("H", "H")])
            CapsuleButton(title: "Read from Image…", systemImage: "qrcode.viewfinder") {
                let panel = NSOpenPanel()
                panel.allowedContentTypes = [.image]
                if panel.runModal() == .OK, let url = panel.url { read(NSImage(contentsOf: url)) }
            }
            CapsuleButton(title: "Paste Image", systemImage: "doc.on.clipboard") {
                read(NSImage(pasteboard: .general))
            }
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Text", text: Binding(get: { input }, set: { readStatus = nil; store[doc: .qr].input = $0 }),
                           placeholder: "Type text or a URL to encode. To read a code, drop an image on the right or use Read from Image…",
                           onFile: { read(NSImage(contentsOf: $0)) })
                Pane("QR Code") {
                    ZStack {
                        if let code {
                            Image(nsImage: code.image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .frame(maxWidth: 420, maxHeight: 420)
                                .padding(16)
                                .background(.white, in: RoundedRectangle(cornerRadius: 12))  // quiet zone, also in dark mode
                                .padding(28)
                                .onDrag { Output.dragItem(code.png, name: "QR Code.png") }
                        } else {
                            VStack(spacing: 10) {
                                Image(systemName: "qrcode").font(.system(size: 40)).foregroundStyle(Palette.text4)
                                Text("Drop an image with a QR code here to read it.").foregroundStyle(Palette.text4)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .dropDestination(for: URL.self) { urls, _ in
                        guard let url = urls.first else { return false }
                        read(NSImage(contentsOf: url))
                        return true
                    }
                } accessory: {
                    if let code {
                        IconButton(systemImage: "square.and.arrow.down", help: "Save PNG… (⌘S)") { Output.save(code.png, name: "QR Code.png") }
                        IconButton(systemImage: "doc.on.doc", help: "Copy Image (⇧⌘C)") { copy(code.image) }
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .outputCommand)) { note in
                    guard let code else { return }
                    if note.object as? String == OutputCommand.copy.rawValue { copy(code.image) }
                    if note.object as? String == OutputCommand.save.rawValue { Output.save(code.png, name: "QR Code.png") }
                }
            }
        }
        .onAppear { if let url = store.pendingFile { store.pendingFile = nil; read(NSImage(contentsOf: url)) } }
        .onChange(of: store.pendingFile) { _, url in
            if let url { store.pendingFile = nil; read(NSImage(contentsOf: url)) }
        }
    }

    private func image(_ text: String) -> (image: NSImage, png: Data, modules: Int)? {
        guard !text.isEmpty else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = level
        guard let output = filter.outputImage else { return nil }
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))
        guard let cg = Self.context.createCGImage(scaled, from: scaled.extent) else { return nil }
        let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) ?? Data()
        return (NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height)), png, Int(output.extent.width) - 2)
    }

    private func read(_ image: NSImage?) {
        guard let image, let tiff = image.tiffRepresentation, let ci = CIImage(data: tiff) else {
            readStatus = .error("Couldn't open the image")
            return
        }
        let detector = CIDetector(ofType: CIDetectorTypeQRCode, context: nil, options: [CIDetectorAccuracy: CIDetectorAccuracyHigh])
        let messages = (detector?.features(in: ci) ?? []).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        if let first = messages.first {
            store[doc: .qr].input = first
            readStatus = Status(text: messages.count > 1 ? "Read 1 of \(messages.count) codes" : "Read from image")
        } else {
            readStatus = .error("No QR code found in the image")
        }
    }

    private func copy(_ image: NSImage) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.writeObjects([image])
    }
}
