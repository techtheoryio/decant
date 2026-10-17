import DecantCore
import SwiftUI

struct FormatterResult: Sendable {
    var text = ""
    var language = Language.json
    /// The JSON shown in the tree (after the query).
    var json: JSONValue?
    var status: Status?
    var meta: [String] = []
    var error: String?
    var errorLine: Int?
    var errorColumn: Int?
}

struct FormatterPage: View {
    @Environment(Store.self) private var store
    @AppStorage("indent") private var indent: Indent = .two
    @AppStorage("sortKeys") private var sortKeys = false
    @AppStorage("minify") private var minify = false
    @AppStorage("unescape") private var unescape = true
    @State private var languageChoice = ""  // "" = auto; not persisted, or a stale pick would mis-format the next paste
    @AppStorage("useExternalFormatter") private var useExternal = true
    @AppStorage("formatterTree") private var showTree = false
    @State private var query = ""
    @State private var selection: TreeNode.ID?
    @State private var result = FormatterResult()
    @State private var jump: Jump?

    struct Settings: Equatable, Sendable {
        var input: String
        var language: Language?
        var indent: Indent
        var sortKeys: Bool
        var minify: Bool
        var unescape: Bool
        var useExternal: Bool
        var query: String
    }

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .formatter].input
        let settings = Settings(input: input, language: Language(rawValue: languageChoice), indent: indent, sortKeys: sortKeys,
                                minify: minify, unescape: unescape, useExternal: useExternal, query: query)
        let isJSON = (settings.language ?? result.language) == .json
        ToolPage(tool: .formatter, status: input.isEmpty ? nil : result.status, meta: input.isEmpty ? ["JSON, JS, TS, CSS, HTML, XML, Markdown, YAML, GraphQL"] : result.meta) {
            OptionMenu(title: "Language", selection: $languageChoice,
                       options: [(input.isEmpty || !languageChoice.isEmpty ? "Auto" : "Auto (\(result.language.name))", "")] + Language.allCases.map { ($0.name, $0.rawValue) })
            if isJSON {
                OptionSegments(selection: $minify, options: [("Pretty", false), ("Minified", true)])
            }
            if !(isJSON && minify) {
                OptionSegments(title: "Indent", selection: $indent, options: [("2", .two), ("4", .four), ("Tab", .tab)])
            }
            if isJSON {
                OptionToggle(title: "Sort keys", isOn: $sortKeys)
                OptionToggle(title: "Unescape", isOn: $unescape)
                queryField
            }
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Input", text: $store[doc: .formatter].input,
                           placeholder: "Paste JSON, JavaScript, TypeScript, CSS, HTML, XML, Markdown, YAML or GraphQL. Loose JSON with comments, trailing commas, single quotes or unquoted keys is repaired.",
                           syntax: result.language.syntax, errorLine: result.errorLine, jump: jump,
                           footer: result.error.map { message in
                               AnyView(ErrorBar(message: message, line: result.errorLine) {
                                   if let l = result.errorLine { jump = Jump(line: l, column: result.errorColumn ?? 1) }
                               })
                           })
                if showTree, isJSON, let root = result.json {
                    JSONTreePane(root: root, selection: $selection, accessory: AnyView(modePicker)) { query = $0 }
                } else {
                    EditorPane(title: "Output", text: .constant(result.text), placeholder: "The formatted result appears here.",
                               syntax: result.language.syntax, editable: false, output: true, primary: true,
                               diffBase: input.isEmpty ? nil : input, fileExtension: result.language.fileExtension,
                               accessory: isJSON && result.json != nil ? AnyView(modePicker) : nil)
                }
            }
        }
        .task(id: settings) {
            if settings.input.utf8.count > 20_000 { try? await Task.sleep(for: .milliseconds(250)) }
            guard !Task.isCancelled else { return }
            let r = await Task.detached { FormatterPage.compute(settings) }.value
            guard !Task.isCancelled else { return }
            result = r
        }
    }

    private var modePicker: some View {
        Segments(selection: $showTree, options: [("Text", false), ("Tree", true)], compact: true)
            .padding(2)
            .background(Palette.cardSeparator, in: Capsule())
            .padding(.trailing, 4)
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "line.3.horizontal.decrease").foregroundStyle(Palette.icon)
            TextField("Filter: $.users[0].name or .items[]", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5, design: .monospaced))
                .frame(width: 240)
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Palette.text4) }
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 32)
        .glassCapsule()
    }

    // MARK: Formatting

    nonisolated static func compute(_ s: Settings) -> FormatterResult {
        guard !s.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return FormatterResult() }
        let language = s.language ?? Language.detect(s.input)
        let external = s.useExternal ? ExternalFormatters.shared : .none
        var r = FormatterResult(language: language)
        if language == .json { return json(s, external) }
        guard let outcome = external.format(s.input, language: language, indent: s.indent)
                ?? BuiltInFormatter.format(s.input, language: language, indent: s.indent) else {
            r.text = s.input
            r.status = .warning("No formatter for \(language.name)")
            r.meta = ["Install Biome or Prettier to format \(language.name)"]
            return r
        }
        r.text = outcome.text
        r.meta = [language.name, outcome.engine, lines(outcome.text)]
        if let e = outcome.error {
            r.error = e
            r.errorLine = outcome.errorLine
            r.errorColumn = outcome.errorColumn
            r.status = .error(outcome.errorLine.map { "Syntax error at line \($0)" } ?? "Syntax error")
        } else {
            r.status = Status(text: "Formatted")
        }
        return r
    }

    nonisolated static func json(_ s: Settings, _ external: ExternalFormatters) -> FormatterResult {
        var r = FormatterResult(language: .json)
        var value: JSONValue
        var fixes: [String] = []
        var notes: [String] = []
        do {
            (value, fixes) = try JSONValue.parseLoose(s.input)
        } catch {
            // Escaped JSON without the surrounding quotes: {\"a\":1}
            let t = s.input.trimmingCharacters(in: .whitespacesAndNewlines)
            if s.unescape, t.contains("\\\""), case .string(let inner)? = try? JSONValue.parse("\"\(t)\""),
               let v = try? JSONValue.parseLoose(inner) {
                (value, fixes) = v
                notes.append("unescaped")
            } else {
                let e = error as? JSONError
                r.error = "\(error)"
                r.errorLine = e?.line
                r.errorColumn = e?.column
                r.status = .error(e?.message ?? "Invalid JSON")
                r.meta = ["JSON"] + (e.map { ["Line \($0.line), column \($0.column)"] } ?? [])
                return r
            }
        }
        if s.unescape, case .string(let str) = value, let inner = try? JSONValue.parseLoose(str), inner.value.isContainer {
            value = inner.value
            notes.append("unescaped")
        }
        var shown = value
        var queryError: String?
        if !s.query.trimmingCharacters(in: .whitespaces).isEmpty {
            do {
                let matches = try JSONQuery.evaluate(s.query, on: value)
                shown = matches.count == 1 ? matches[0] : .array(matches)
                notes.append(matches.count == 1 ? "1 match" : "\(matches.count) matches")
            } catch {
                queryError = "\(error)"
            }
        }
        r.json = shown
        var engine = "Built-in"
        if s.minify {
            r.text = shown.formatted(indent: nil, sortKeys: s.sortKeys)
        } else {
            let ours = shown.formatted(indent: s.indent.unit, sortKeys: s.sortKeys)
            // Untouched input goes to Biome/Prettier as typed, so their layout rules apply.
            let untouched = fixes.isEmpty && notes.isEmpty && !s.sortKeys && queryError == nil
            if let ext = external.format(untouched ? s.input : ours, language: .json, indent: s.indent), ext.error == nil {
                r.text = ext.text
                engine = ext.engine
            } else {
                r.text = ours
            }
        }
        if let queryError {
            r.status = .error("Filter: \(queryError)")
        } else if !fixes.isEmpty {
            r.status = .warning("Repaired " + fixes.joined(separator: ", "))
        } else {
            r.status = Status(text: "Valid JSON")
        }
        r.meta = ["JSON", value.keyCount == 1 ? "1 key" : "\(value.keyCount) keys", engine] + notes
        return r
    }

    nonisolated static func lines(_ s: String) -> String {
        let n = s.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        return n == 1 ? "1 line" : "\(n) lines"
    }
}

// MARK: - Tree

struct TreeNode: Identifiable, Hashable {
    /// The node's JSONPath, e.g. `$.users[0].name`.
    let id: String
    let key: String
    let value: JSONValue
    var isIndex = false

    static func == (a: TreeNode, b: TreeNode) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }

    var children: [TreeNode]? {
        guard let c = value.children, !c.isEmpty else { return nil }
        let array = { if case .array = value { true } else { false } }()
        return c.map { TreeNode(id: id + $0.segment, key: $0.key, value: $0.value, isIndex: array) }
    }
}

struct JSONTreePane: View {
    let root: JSONValue
    @Binding var selection: TreeNode.ID?
    let accessory: AnyView
    let filter: (String) -> Void

    var body: some View {
        let top = TreeNode(id: "$", key: "$", value: root)
        Pane("Tree") {
            VStack(spacing: 0) {
                List(top.children ?? [top], children: \.children, selection: $selection) { node in
                    TreeRow(node: node)
                        .contextMenu {
                            Button("Copy Path") { Output.copy(node.id) }
                            Button("Copy Value") { Output.copy(node.value.formatted(indent: "  ")) }
                            Button("Filter to This") { filter(node.id) }
                        }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                if let selection {
                    HStack(spacing: 8) {
                        Text(selection)
                            .font(.system(size: 12, design: .monospaced))
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                        Spacer(minLength: 8)
                        Button("Filter") { filter(selection) }.controlSize(.small)
                        Button("Copy Path") { Output.copy(selection) }.controlSize(.small)
                    }
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(Palette.cardFoot)
                    .overlay(alignment: .top) { Rectangle().fill(Palette.cardSeparator).frame(height: 1) }
                }
            }
        } accessory: {
            accessory
        }
    }
}

struct TreeRow: View {
    let node: TreeNode

    var body: some View {
        HStack(spacing: 8) {
            Text(node.isIndex ? "[\(node.key)]" : node.key)
                .foregroundStyle(node.isIndex ? Palette.text4 : Palette.key)
            Text(node.value.typeName)
                .font(.system(size: 9.5, weight: .bold))
                .textCase(.uppercase)
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .foregroundStyle(Palette.text3)
                .background(Palette.cardSeparator, in: RoundedRectangle(cornerRadius: 4))
            Text(summary)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .font(.system(size: 12.5, design: .monospaced))
    }

    private var summary: String {
        switch node.value {
        case .object(let m): m.count == 1 ? "1 key" : "\(m.count) keys"
        case .array(let a): a.count == 1 ? "1 item" : "\(a.count) items"
        default: node.value.preview
        }
    }

    private var color: Color {
        switch node.value {
        case .string: Palette.string
        case .number, .bool: Palette.number
        case .null: Palette.keyword
        default: Palette.text4
        }
    }
}
