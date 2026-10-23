import Foundation

/// YAML 1.2 (core schema) to and from `JSONValue`: block and flow collections, plain, quoted and block scalars,
/// comments, anchors, aliases and `<<` merges. Tags are skipped; several documents become an array.
public enum YAML {
    public static func parse(_ text: String) throws -> JSONValue {
        var p = YAMLParser(c: Array(text.replacingOccurrences(of: "\r\n", with: "\n")))
        if p.c.first == "\u{FEFF}" { p.i = 1 }
        return try p.stream()
    }

    public static func write(_ value: JSONValue) -> String {
        var l = lines(value)
        if case .string = value { l = [l[0]] + l.dropFirst().map(indent) }  // keep a top-level `---` line off column 0
        return l.joined(separator: "\n") + "\n"
    }

    static func indent(_ s: String) -> String { s.isEmpty ? s : "  " + s }

    static func lines(_ v: JSONValue) -> [String] {
        switch v {
        case .object(let members) where !members.isEmpty:
            members.flatMap { nested((plain($0.key) && $0.key != "<<" ? $0.key : JSONValue.quote($0.key)) + ":", $0.value, dash: false) }
        case .array(let items) where !items.isEmpty: items.flatMap { nested("-", $0, dash: true) }
        case .object: ["{}"]
        case .array: ["[]"]
        case .string(let s): string(s)
        default: [v.formatted(indent: nil)]
        }
    }

    /// A key or `-` and its value: scalars go on the same line, collections below it, a sequence item's collection
    /// starts on the dash line.
    static func nested(_ prefix: String, _ v: JSONValue, dash: Bool) -> [String] {
        let l = lines(v)
        let block = switch v {
        case .object(let m): !m.isEmpty
        case .array(let a): !a.isEmpty
        default: false
        }
        return block && !dash ? [prefix] + l.map(indent) : [prefix + " " + l[0]] + l.dropFirst().map(indent)
    }

    /// Plain when that reads back as the same string, a `|` block for multi-line text, JSON-quoted otherwise.
    static func string(_ s: String) -> [String] {
        if plain(s) { return [s] }
        var body = Substring(s), trailing = 0
        while body.hasSuffix("\n") { body.removeLast(); trailing += 1 }
        let lines = body.split(separator: "\n", omittingEmptySubsequences: false)
        if body.contains("\n") || trailing > 0, !body.isEmpty, !body.hasPrefix(" "),
           !s.unicodeScalars.contains(where: { $0.value < 0x20 && $0 != "\n" && $0 != "\t" || $0.value == 0x7F }),
           !lines.contains(where: { !$0.isEmpty && $0.allSatisfy { $0 == " " || $0 == "\t" } }) {
            return [trailing == 0 ? "|-" : trailing == 1 ? "|" : "|+"] + lines.map(String.init) + Array(repeating: "", count: max(trailing - 1, 0))
        }
        return [JSONValue.quote(s)]
    }

    /// Also quotes what YAML 1.1 parsers would read differently (`yes`, `on`, dates, `1_000`, `1:30`).
    static func plain(_ s: String) -> Bool {
        guard let f = s.first, let l = s.last, case .string = YAMLParser.resolve(s) else { return false }
        if f.isWhitespace || l.isWhitespace || f.isNumber || "-?:,[]{}#&*!|>'\"%@`.".contains(f) || l == ":" { return false }
        if s.contains(": ") || s.contains(" #") || s.contains("\t#") || s.contains(":\t") { return false }
        if s.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F || $0 == "\u{FEFF}" }) { return false }
        return !["y", "n", "yes", "no", "on", "off"].contains(s.lowercased())
    }
}

private struct YAMLParser {
    let c: [Character]
    var i = 0
    var anchors: [String: (value: JSONValue, size: Int)] = [:]
    /// Nodes produced so far, aliases counted at full size, so a billion-laughs document fails instead of hanging.
    var nodes = 0

    var peek: Character? { i < c.count ? c[i] : nil }
    func at(_ k: Int) -> Character? { i + k < c.count ? c[i + k] : nil }
    var atEOL: Bool { peek == nil || peek == "\n" }
    static func isSpace(_ ch: Character?) -> Bool { ch == nil || ch == " " || ch == "\t" || ch == "\n" }
    static func isFlow(_ ch: Character?) -> Bool { ch.map(",[]{}".contains) ?? false }

    var column: Int {
        var j = i
        while j > 0, c[j - 1] != "\n" { j -= 1 }
        return i - j
    }

    func fail(_ message: String) -> JSONError {
        let line = c[..<min(i, c.count)].reduce(1) { $1 == "\n" ? $0 + 1 : $0 }
        return JSONError(message: message, line: line, column: column + 1)
    }

    func marker(_ m: String) -> Bool { c[i...].starts(with: m) && Self.isSpace(at(3)) && column == 0 }
    var isDocMarker: Bool { marker("---") || marker("...") }
    var isSeqEntry: Bool { peek == "-" && Self.isSpace(at(1)) }

    /// Spaces, tabs and a comment up to the end of the line.
    mutating func skipInline() {
        while peek == " " || peek == "\t" { i += 1 }
        if peek == "#", i == 0 || Self.isSpace(c[i - 1]) { while !atEOL { i += 1 } }
    }

    /// Blank and comment lines, up to the next content.
    mutating func skipBlank() throws {
        var crossed = false
        while true {
            let start = i
            skipInline()
            if peek == "\n" { i += 1; crossed = true; continue }
            if crossed, peek != nil, c[start..<i].contains("\t") { throw fail("Tabs can't indent YAML, use spaces") }
            return
        }
    }

    mutating func stream() throws -> JSONValue {
        var docs: [JSONValue] = []
        while true {
            try skipBlank()
            while peek == "%", column == 0 {  // %YAML / %TAG directives
                while !atEOL { i += 1 }
                try skipBlank()
            }
            guard peek != nil else { break }
            if marker("...") { i += 3; continue }
            if marker("---") { i += 3 }
            docs.append(try value(parent: -1))
            try skipBlank()
            if marker("...") { i += 3 } else if peek != nil, !marker("---") { throw fail("Unexpected content") }
        }
        return docs.count == 1 ? docs[0] : docs.isEmpty ? .null : .array(docs)
    }

    /// Skips `!tags` and returns an `&anchor`, if any.
    mutating func properties() -> String? {
        var anchor: String?
        while peek == "&" || peek == "!" {
            let isAnchor = peek == "&"
            i += 1
            let start = i
            while !Self.isSpace(peek), !Self.isFlow(peek) { i += 1 }
            if isAnchor { anchor = String(c[start..<i]) }
            while peek == " " || peek == "\t" { i += 1 }
        }
        return anchor
    }

    mutating func remember(_ anchor: String?, _ v: JSONValue, since before: Int) {
        nodes += 1
        if let anchor { anchors[anchor] = (v, nodes - before) }
    }

    /// The node after `key:`, `- ` or at the document root; `parent` is that indicator's column. A mapping's value
    /// may be a sequence at the key's own column (`seqAtParent`).
    mutating func value(parent: Int, seqAtParent: Bool = false) throws -> JSONValue {
        skipInline()
        let before = nodes
        let anchor = properties()
        skipInline()
        var v = JSONValue.null
        if atEOL {
            try skipBlank()
            if peek != nil, !isDocMarker, column > parent || column == parent && seqAtParent && isSeqEntry { v = try node(parent: parent) }
        } else {
            v = try node(parent: parent)
        }
        remember(anchor, v, since: before)
        return v
    }

    mutating func node(parent: Int) throws -> JSONValue {
        guard let ch = peek else { return .null }
        if isSeqEntry { return try sequence(column) }
        if ch == "|" || ch == ">" { return try blockScalar(parent: parent) }
        if ch == "?", Self.isSpace(at(1)) { throw fail("Explicit keys (?) aren't supported") }
        if isKey() { return try mapping(column) }
        let v: JSONValue
        switch ch {
        case "[", "{": v = try flow()
        case "\"", "'": v = .string(try quoted())
        case "*": v = try alias()
        case "]", "}", ",", "@", "`": throw fail("Unexpected \(ch)")
        default: return try plain(parent: parent)
        }
        skipInline()
        guard atEOL else { throw fail("Unexpected text after the value") }
        return v
    }

    /// Whether the current line starts with `key:` (plain or quoted key).
    func isKey() -> Bool {
        var j = i
        func colon() -> Bool { j < c.count && c[j] == ":" && (j + 1 == c.count || Self.isSpace(c[j + 1])) }
        if c[j] == "\"" || c[j] == "'" {
            let q = c[j]
            j += 1
            while j < c.count, c[j] != q || q == "'" && j + 1 < c.count && c[j + 1] == "'" {
                if c[j] == "\n" { return false }
                j += c[j] == "\\" && q == "\"" || c[j] == "'" && q == "'" ? 2 : 1
            }
            j += 1
            while j < c.count, c[j] == " " || c[j] == "\t" { j += 1 }
            return colon()
        }
        if "[{#&*!|>%@`".contains(c[j]) { return false }
        while j < c.count, c[j] != "\n" {
            if colon() { return true }
            if c[j] == "#", Self.isSpace(c[j - 1]) { return false }
            j += 1
        }
        return false
    }

    mutating func mapping(_ col: Int) throws -> JSONValue {
        var members: [JSONMember] = [], index: [String: Int] = [:]
        func set(_ key: String, _ v: JSONValue, replace: Bool) {
            if let k = index[key] {
                if replace { members[k].value = v }
            } else {
                index[key] = members.count
                members.append(JSONMember(key: key, value: v))
            }
        }
        while true {
            let quotedKey = peek == "\"" || peek == "'"
            let key: String
            if quotedKey {
                key = try quoted()
                while peek == " " || peek == "\t" { i += 1 }
            } else {
                let start = i
                while !(peek == ":" && Self.isSpace(at(1))) { i += 1 }
                key = String(c[start..<i]).trimmingCharacters(in: .whitespaces)
            }
            i += 1  // ':'
            let v = try value(parent: col, seqAtParent: true)
            if key == "<<", !quotedKey {
                // Merged keys never override the mapping's own, and earlier sources win over later ones.
                let sources = if case .array(let a) = v { a } else { [v] }
                for case .object(let m) in sources { for member in m { set(member.key, member.value, replace: false) } }
            } else {
                set(key, v, replace: true)
            }
            try skipBlank()
            guard peek != nil, !isDocMarker, column >= col else { break }
            guard column == col, isKey() else { throw fail(column > col ? "Bad indentation" : "Expected a key") }
        }
        return .object(members)
    }

    mutating func sequence(_ col: Int) throws -> JSONValue {
        var items: [JSONValue] = []
        while true {
            i += 1  // '-'
            items.append(try value(parent: col))
            try skipBlank()
            guard peek != nil, !isDocMarker, column > col || column == col && isSeqEntry else { break }
            guard column == col else { throw fail("Bad indentation") }
        }
        return .array(items)
    }

    /// The rest of the line, without a trailing comment.
    mutating func lineContent() -> String {
        let start = i
        while let ch = peek, ch != "\n", !(ch == "#" && i > start && Self.isSpace(c[i - 1])) { i += 1 }
        return String(c[start..<i]).trimmingCharacters(in: .whitespaces)
    }

    /// A plain scalar; it continues on following lines indented deeper than `parent`.
    mutating func plain(parent: Int) throws -> JSONValue {
        var text = lineContent()
        var comment = peek == "#"
        skipInline()
        while !comment, peek == "\n" {
            let save = i
            var breaks = 0
            while peek == "\n" {
                i += 1
                breaks += 1
                while peek == " " || peek == "\t" { i += 1 }
            }
            if peek == nil || column <= parent || peek == "#" || isDocMarker { i = save; break }
            if isKey() { throw fail("Bad indentation") }  // `a: b` followed by a deeper `c: d`
            let more = lineContent()
            text += breaks == 1 ? " " + more : String(repeating: "\n", count: breaks - 1) + more
            comment = peek == "#"
            skipInline()
        }
        return Self.resolve(text)
    }

    /// `|` keeps line breaks, `>` folds them; `-` strips the final break, `+` keeps trailing blank lines.
    mutating func blockScalar(parent: Int) throws -> JSONValue {
        let folded = peek == ">"
        i += 1
        var chomp: Character?, indent: Int?
        while let ch = peek, ch == "-" || ch == "+" || ch.isASCII && ch.isNumber {
            if let n = ch.wholeNumberValue { indent = max(parent, 0) + n } else { chomp = ch }
            i += 1
        }
        skipInline()
        guard atEOL else { throw fail("Expected a line break after the block scalar indicator") }
        var lines: [String] = [], breaks: [Bool] = []  // whether each line ended with a line break
        while peek == "\n" {
            i += 1
            let start = i
            while peek == " " { i += 1 }
            if atEOL {
                lines.append("")
            } else {
                let ind = i - start
                if indent == nil, ind > parent, !isDocMarker { indent = ind }
                guard let n = indent, ind >= n, !isDocMarker else { i = start; break }
                i = start + n
                let from = i
                while !atEOL { i += 1 }
                lines.append(String(c[from..<i]))
            }
            breaks.append(peek == "\n")
        }
        let last = lines.lastIndex { !$0.isEmpty }
        let body = last.map { Array(lines[...$0]) } ?? []
        let trailing = breaks[(last ?? 0)...].filter { $0 }.count
        var text = folded ? Self.fold(body) : body.joined(separator: "\n")
        switch chomp {
        case "-": break
        case "+": text += String(repeating: "\n", count: trailing)
        default: if !body.isEmpty, trailing > 0 { text += "\n" }
        }
        return .string(text)
    }

    /// Folded block: adjacent lines join with a space, blank lines become breaks, more-indented lines stay as they are.
    static func fold(_ lines: [String]) -> String {
        var out = "", empties = 0, prevNormal: Bool?
        for l in lines {
            if l.isEmpty { empties += 1; continue }
            let normal = l.first != " " && l.first != "\t"
            if let p = prevNormal {
                out += p && normal ? (empties == 0 ? " " : String(repeating: "\n", count: empties)) : String(repeating: "\n", count: empties + 1)
            } else {
                out += String(repeating: "\n", count: empties)
            }
            out += l
            empties = 0
            prevNormal = normal
        }
        return out
    }

    mutating func quoted() throws -> String {
        let q = c[i]
        i += 1
        var out = "", spaces = ""  // raw spaces are held back: a line break drops them, escaped ones stay
        while true {
            guard let ch = peek else { throw fail("Unterminated string") }
            i += 1
            if ch == " " || ch == "\t" { spaces.append(ch); continue }
            if ch != "\n" { out += spaces }
            spaces = ""
            switch ch {
            case "'" where q == "'" && peek == "'": out.append("'"); i += 1
            case q: return out
            case "\\" where q == "\"": try escape(&out)
            case "\n":
                // Line folding: one break becomes a space, n + 1 breaks become n.
                var breaks = 0
                while true {
                    while peek == " " || peek == "\t" { i += 1 }
                    guard peek == "\n" else { break }
                    i += 1
                    breaks += 1
                }
                out += breaks == 0 ? " " : String(repeating: "\n", count: breaks)
            default: out.append(ch)
            }
        }
    }

    mutating func escape(_ out: inout String) throws {
        guard let e = peek else { throw fail("Unterminated string") }
        i += 1
        func hex(_ n: Int) throws -> UInt32 {
            guard i + n <= c.count, let v = UInt32(String(c[i..<i + n]), radix: 16) else { throw fail("Invalid \\\(e) escape") }
            i += n
            return v
        }
        switch e {
        case "0": out += "\0"
        case "a": out += "\u{07}"
        case "b": out += "\u{08}"
        case "t", "\t": out += "\t"
        case "n": out += "\n"
        case "v": out += "\u{0B}"
        case "f": out += "\u{0C}"
        case "r": out += "\r"
        case "e": out += "\u{1B}"
        case " ", "\"", "/", "\\": out.append(e)
        case "N": out += "\u{85}"
        case "_": out += "\u{A0}"
        case "L": out += "\u{2028}"
        case "P": out += "\u{2029}"
        case "x", "u", "U":
            var v = try hex(e == "x" ? 2 : e == "u" ? 4 : 8)
            // JSON-style surrogate pairs, since JSON documents are YAML too.
            if (0xD800..<0xDC00).contains(v), peek == "\\", at(1) == "u" {
                i += 2
                let low = try hex(4)
                guard (0xDC00..<0xE000).contains(low) else { throw fail("Invalid \\u surrogate pair") }
                v = 0x10000 + (v - 0xD800) << 10 + (low - 0xDC00)
            }
            guard let u = Unicode.Scalar(v) else { throw fail("Invalid \\\(e) escape") }
            out.unicodeScalars.append(u)
        case "\n":  // escaped line break: joins the lines without a space
            while peek == " " || peek == "\t" { i += 1 }
        default: throw fail("Invalid escape \\\(e)")
        }
    }

    mutating func alias() throws -> JSONValue {
        i += 1
        let start = i
        while !Self.isSpace(peek), !Self.isFlow(peek) { i += 1 }
        let name = String(c[start..<i])
        guard let a = anchors[name] else { throw fail("Unknown alias *\(name)") }
        nodes += a.size
        guard nodes < 2_000_000 else { throw fail("Aliases expand to too many nodes") }
        return a.value
    }

    // MARK: Flow collections

    mutating func skipFlow() {
        while let ch = peek {
            if Self.isSpace(ch) { i += 1 } else if ch == "#", Self.isSpace(c[i - 1]) { while !atEOL { i += 1 } } else { return }
        }
    }

    mutating func flow() throws -> JSONValue {
        let open = c[i], close: Character = open == "[" ? "]" : "}"
        i += 1
        var items: [JSONValue] = [], members: [JSONMember] = []
        while true {
            skipFlow()
            guard let ch = peek else { throw fail("Missing \(close)") }
            if ch == close { i += 1; break }
            if open == "[" {
                items.append(try flowNode())
            } else {
                let key = ch == "\"" || ch == "'" ? try quoted() : flowPlain()
                skipFlow()
                var v = JSONValue.null
                if peek == ":" {
                    i += 1
                    skipFlow()
                    if peek != ",", peek != close { v = try flowNode() }
                }
                if let k = members.firstIndex(where: { $0.key == key }) { members[k].value = v } else { members.append(JSONMember(key: key, value: v)) }
            }
            skipFlow()
            if peek == "," { i += 1 } else if peek != close { throw fail("Expected , or \(close)") }
        }
        return open == "[" ? .array(items) : .object(members)
    }

    mutating func flowNode() throws -> JSONValue {
        let before = nodes
        let anchor = properties()
        skipFlow()
        let v: JSONValue = switch peek {
        case "[", "{": try flow()
        case "\"", "'": .string(try quoted())
        case "*": try alias()
        default: Self.resolve(flowPlain())
        }
        remember(anchor, v, since: before)
        return v
    }

    /// A plain scalar inside `[]` or `{}`: ends at a flow indicator, `: ` or a comment; line breaks fold to spaces.
    mutating func flowPlain() -> String {
        let start = i
        while let ch = peek, !Self.isFlow(ch), !(ch == ":" && (Self.isSpace(at(1)) || Self.isFlow(at(1)))), !(ch == "#" && Self.isSpace(c[i - 1])) { i += 1 }
        return c[start..<i].split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
    }

    // MARK: Scalars

    /// Core schema: null, booleans, ints (also 0x/0o) and floats; numbers are rewritten as JSON literals.
    /// ponytail: .inf/.nan stay strings, JSON has no literal for them.
    static func resolve(_ s: String) -> JSONValue {
        switch s {
        case "", "~", "null", "Null", "NULL": return .null
        case "true", "True", "TRUE": return .bool(true)
        case "false", "False", "FALSE": return .bool(false)
        default: break
        }
        guard let f = s.first, f.isASCII, f.isNumber || f == "-" || f == "+" || f == "." else { return .string(s) }
        if case .number? = try? JSONValue.parse(s) { return .number(s) }
        if s.hasPrefix("0x"), let n = Int(s.dropFirst(2), radix: 16) { return .number("\(n)") }
        if s.hasPrefix("0o"), let n = Int(s.dropFirst(2), radix: 8) { return .number("\(n)") }
        if s.wholeMatch(of: /[-+]?[0-9]+/) != nil, let n = Int(s) { return .number("\(n)") }
        if s.wholeMatch(of: /[-+]?(\.[0-9]+|[0-9]+(\.[0-9]*)?)([eE][-+]?[0-9]+)?/) != nil, let d = Double(s), d.isFinite { return .number("\(d)") }
        return .string(s)
    }
}

// MARK: - OpenAPI

public struct OpenAPISummary: Sendable, Equatable {
    /// "OpenAPI 3.1.0" or "Swagger 2.0".
    public var version: String
    public var title: String?
    public var paths = 0
    public var operations = 0

    static let methods: Set = ["get", "put", "post", "delete", "options", "head", "patch", "trace"]

    /// Nil when the document has no `openapi` or `swagger` version.
    public init?(_ doc: JSONValue) {
        guard case .object(let root) = doc else { return nil }
        func field(_ key: String, _ m: [JSONMember]) -> JSONValue? { m.first { $0.key == key }?.value }
        func text(_ v: JSONValue?) -> String? {
            switch v {
            case .string(let s)?, .number(let s)?: s
            default: nil
            }
        }
        if let v = text(field("openapi", root)) { version = "OpenAPI " + v } else if let v = text(field("swagger", root)) { version = "Swagger " + v } else { return nil }
        if case .object(let info)? = field("info", root) { title = text(field("title", info)) }
        if case .object(let paths)? = field("paths", root) {
            self.paths = paths.count
            for case .object(let ops) in paths.map(\.value) { operations += ops.filter { Self.methods.contains($0.key) }.count }
        }
    }
}
