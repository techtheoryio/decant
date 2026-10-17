import Foundation

public enum TokenKind: Sendable { case space, comment, string, number, word, punct }

public struct Token: Sendable {
    public let kind: TokenKind
    public let text: String
}

/// Small JS/TS lexer shared by the formatter and the highlighter. JSON is a subset, so it lexes too.
// ponytail: no regex-literal support; `/re/` lexes as operators, which only affects spacing.
enum JSLexer {
    private static let puncts: [[UInt8]] = [
        ">>>=", "...", "===", "!==", "**=", "<<=", ">>=", ">>>", "&&=", "||=", "??=",
        "=>", "==", "!=", "<=", ">=", "&&", "||", "??", "?.", "++", "--",
        "+=", "-=", "*=", "/=", "%=", "&=", "|=", "^=", "**", "<<", ">>",
    ].map { Array($0.utf8) }

    static func isWord(_ c: UInt8) -> Bool {
        c >= 0x80 || c == UInt8(ascii: "$") || c == UInt8(ascii: "_")
            || (0x30...0x39).contains(c) || (0x41...0x5A).contains(c) || (0x61...0x7A).contains(c)
    }

    static func isSpace(_ c: UInt8) -> Bool { c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D }

    static func tokenize(_ source: String) -> [Token] {
        let b = Array(source.utf8)
        let slash = UInt8(ascii: "/"), star = UInt8(ascii: "*"), dot = UInt8(ascii: ".")
        func at(_ j: Int) -> UInt8 { j < b.count ? b[j] : 0 }
        var tokens: [Token] = []
        var i = 0
        while i < b.count {
            let start = i, c = b[i]
            let kind: TokenKind
            if isSpace(c) {
                while i < b.count, isSpace(b[i]) { i += 1 }
                kind = .space
            } else if c == slash, at(i + 1) == slash {
                while i < b.count, b[i] != 0x0A { i += 1 }
                kind = .comment
            } else if c == slash, at(i + 1) == star {
                i += 2
                while i < b.count, !(b[i] == star && at(i + 1) == slash) { i += 1 }
                i = min(i + 2, b.count)
                kind = .comment
            } else if c == UInt8(ascii: "\"") || c == UInt8(ascii: "'") || c == UInt8(ascii: "`") {
                i += 1
                while i < b.count, b[i] != c { i += b[i] == UInt8(ascii: "\\") ? 2 : 1 }
                i = min(i + 1, b.count)
                kind = .string
            } else if (0x30...0x39).contains(c) || (c == dot && (0x30...0x39).contains(at(i + 1))) {
                i += 1
                while i < b.count, isWord(b[i]) || b[i] == dot
                    || ((b[i] == UInt8(ascii: "+") || b[i] == UInt8(ascii: "-")) && (b[i - 1] | 0x20) == UInt8(ascii: "e")) { i += 1 }
                kind = .number
            } else if isWord(c) {
                while i < b.count, isWord(b[i]) { i += 1 }
                kind = .word
            } else {
                i += puncts.first { b[i...].starts(with: $0) }?.count ?? 1
                kind = .punct
            }
            tokens.append(Token(kind: kind, text: String(decoding: b[start..<i], as: UTF8.self)))
        }
        return tokens
    }
}

/// Deterministic token-based formatter for JavaScript and TypeScript: re-indents blocks,
/// normalises spacing and adds missing semicolons before `}`. It does not reflow long lines.
// ponytail: no line-width wrapping and generics (`a<T>`) get operator spacing; bundle Prettier via JavaScriptCore if that matters.
public enum JSFormatter {
    static let bodyControl: Set = ["if", "for", "while"]
    static let control: Set = ["if", "for", "while", "switch", "catch", "with"]
    static let spaceBeforeParen: Set = [
        "if", "for", "while", "switch", "catch", "with", "return", "typeof", "await", "yield", "of", "in",
        "function", "throw", "new", "delete", "void", "case", "else", "do", "instanceof", "extends", "async", "as",
    ]
    static let operandWords: Set = [
        "return", "typeof", "case", "throw", "new", "delete", "void", "yield", "await", "in", "of",
        "instanceof", "else", "do", "export", "import", "default", "extends",
    ]
    static let objectAfterWords: Set = [
        "return", "import", "export", "typeof", "in", "of", "case", "yield", "await", "throw", "new", "default", "as", "satisfies",
    ]
    static let noSpaceAfter: Set = ["(", "[", ".", "?.", "...", "@", "#"]
    static let noSpaceBefore: Set = [")", "]", ",", ";", ".", "?."]

    private enum Context: Equatable { case block, inline, bracket, paren(String?) }

    public static func format(_ source: String, indent unit: String) -> (text: String, balanced: Bool) {
        let tokens = JSLexer.tokenize(source).filter { $0.kind != .space }
        var balanced = tokens.allSatisfy { $0.kind != .string || ($0.text.count >= 2 && $0.text.last == $0.text.first) }
        var out = ""
        var stack: [Context] = []
        var singles: [Int] = []  // block depths at which a brace-less `if`/`for` body is indented
        var newline = false
        var last: Token?
        var lastUnary = false
        var awaitingBody = false
        var ternary = 0

        func depth() -> Int { stack.filter { $0 == .block }.count }

        func emit(_ text: String, space: Bool, kind: TokenKind = .punct) {
            if newline {
                if !out.isEmpty { out += "\n" + String(repeating: unit, count: depth() + singles.count) }
                newline = false
            } else if space, !out.isEmpty {
                out += " "
            }
            out += text
            last = Token(kind: kind, text: text)
        }

        func operandExpected() -> Bool {
            guard let p = last else { return true }
            switch p.kind {
            case .punct: return ![")", "]", "}"].contains(p.text)
            case .word: return operandWords.contains(p.text)
            default: return false
            }
        }

        func spaceBefore(_ t: Token) -> Bool {
            guard let p = last else { return false }
            if p.kind == .comment { return true }
            if lastUnary || (p.kind == .punct && noSpaceAfter.contains(p.text)) { return false }
            if t.kind == .punct {
                if noSpaceBefore.contains(t.text) { return false }
                if t.text == "(" || t.text == "[" {
                    switch p.kind {
                    case .word: return spaceBeforeParen.contains(p.text)
                    case .punct: return ![")", "]", "}"].contains(p.text)
                    default: return false
                    }
                }
            }
            return true
        }

        func isBlockBrace() -> Bool {
            guard let p = last else { return true }
            switch p.kind {
            case .word: return !objectAfterWords.contains(p.text)
            case .punct: return [")", "=>", ";", "{", "}"].contains(p.text)
            case .comment: return true
            default: return false
            }
        }

        for (index, t) in tokens.enumerated() {
            let c = t.text
            let next = index + 1 < tokens.count ? tokens[index + 1].text : nil
            var thisUnary = false
            defer { lastUnary = thisUnary }

            // `} else`, `} catch`, `}),` stay on the closing brace's line.
            if newline, last?.text == "}",
               (t.kind == .word && ["else", "catch", "finally"].contains(c)) || (t.kind == .punct && [")", ",", ";", ".", "?."].contains(c)) {
                newline = false
            }

            let wasAwaiting = awaitingBody
            if awaitingBody {
                awaitingBody = false
                if c != "{" && c != ";" && !(c == "if" && last?.text == "else") {
                    singles.append(depth())
                    newline = true
                }
            }

            switch t.kind {
            case .comment:
                emit(c, space: true, kind: .comment)
                if c.hasPrefix("//") { newline = true }
                continue
            case .word, .number, .string:
                emit(c, space: spaceBefore(t), kind: t.kind)
                if c == "else" || c == "do" { awaitingBody = true }
                continue
            default:
                break
            }

            switch c {
            case "{":
                if wasAwaiting || isBlockBrace() {
                    emit("{", space: last != nil)
                    stack.append(.block)
                    newline = true
                } else {
                    emit("{", space: spaceBefore(t))
                    stack.append(.inline)
                }
            case "}":
                guard let top = stack.popLast() else { balanced = false; emit("}", space: true); continue }
                if top == .block {
                    singles.removeAll { $0 > depth() }
                    if last?.text == "{" {
                        newline = false
                        emit("}", space: false)
                    } else {
                        if let l = last, l.kind == .word || l.kind == .number || l.kind == .string || l.text == ")" || l.text == "]" {
                            out += ";"
                        }
                        newline = true
                        emit("}", space: false)
                    }
                    newline = true
                    ternary = 0
                } else {
                    if top != .inline { balanced = false }
                    emit("}", space: last?.text != "{")
                }
            case "(":
                let keyword = last.flatMap { $0.kind == .word && control.contains($0.text) ? $0.text : nil }
                emit("(", space: spaceBefore(t))
                stack.append(.paren(keyword))
            case ")":
                guard case .paren(let keyword)? = stack.popLast() else { balanced = false; emit(")", space: false); continue }
                emit(")", space: false)
                if let keyword, bodyControl.contains(keyword) { awaitingBody = true }
            case "[":
                emit("[", space: spaceBefore(t))
                stack.append(.bracket)
            case "]":
                if stack.popLast() != .bracket { balanced = false }
                emit("]", space: false)
            case ";":
                emit(";", space: false)
                if case .paren = stack.last {} else if stack.last != .inline {
                    newline = true
                    ternary = 0
                    let d = depth()
                    singles.removeAll { $0 >= d }
                }
            case "?":
                if let next, [":", ",", ")", "="].contains(next) {
                    emit("?", space: false)  // TS optional marker: `name?: string`
                } else {
                    ternary += 1
                    emit("?", space: spaceBefore(t))
                }
            case ":":
                emit(":", space: ternary > 0)
                if ternary > 0 { ternary -= 1 }
            default:
                let operand = operandExpected()
                var space = spaceBefore(t)
                if ["!", "++", "--"].contains(c), !operand { space = false }  // postfix / non-null assertion
                emit(c, space: space)
                thisUnary = (["!", "~", "-", "+", "++", "--"].contains(c) && operand) || ["...", "@", "#"].contains(c)
            }
        }
        if !stack.isEmpty { balanced = false }
        return (out, balanced)
    }
}

public enum Role: Sendable { case plain, key, string, number, keyword, function, type, punctuation, comment }

public struct Span: Sendable {
    public let text: String
    public let role: Role
}

public enum Highlighter {
    static let keywords: Set = [
        "break", "case", "catch", "class", "const", "continue", "debugger", "default", "delete", "do", "else", "enum",
        "export", "extends", "false", "finally", "for", "function", "if", "import", "in", "instanceof", "new", "null",
        "return", "super", "switch", "this", "throw", "true", "try", "typeof", "var", "void", "while", "with", "yield",
        "let", "static", "async", "await", "of", "as", "implements", "interface", "private", "protected", "public",
        "type", "from", "readonly", "declare", "namespace", "abstract", "keyof", "satisfies", "undefined",
    ]
    static let types: Set = ["string", "number", "boolean", "any", "void", "unknown", "never", "object", "symbol", "bigint"]

    public static func spans(_ text: String, format: Format) -> [Span] {
        let isJSON = format == .json
        guard isJSON || format == .typescript || format == .javascript else { return [Span(text: text, role: .plain)] }
        let tokens = JSLexer.tokenize(text)
        return tokens.indices.map { i in
            let t = tokens[i]
            let next = tokens[(i + 1)...].first { $0.kind != .space }?.text
            let role: Role
            switch t.kind {
            case .space: role = .plain
            case .comment: role = .comment
            case .string: role = isJSON && next == ":" ? .key : .string
            case .number: role = .number
            case .punct: role = .punctuation
            case .word:
                if isJSON { role = .number }
                else if keywords.contains(t.text) { role = .keyword }
                else if types.contains(t.text) || t.text.first?.isUppercase == true { role = .type }
                else if next == "(" { role = .function }
                else { role = .plain }
            }
            return Span(text: t.text, role: role)
        }
    }
}
