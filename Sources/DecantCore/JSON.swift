import Foundation

public struct JSONMember: Sendable {
    public var key: String
    public var value: JSONValue
}

/// Order-preserving JSON tree. Numbers keep their source literal so nothing is reformatted.
public enum JSONValue: Sendable {
    case object([JSONMember])
    case array([JSONValue])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = JSONParser(bytes: Array(text.utf8))
        return try parser.document()
    }

    public var isContainer: Bool {
        switch self {
        case .object, .array: true
        default: false
        }
    }

    /// Total number of object keys, nested ones included.
    public var keyCount: Int {
        switch self {
        case .object(let members): members.count + members.reduce(0) { $0 + $1.value.keyCount }
        case .array(let items): items.reduce(0) { $0 + $1.keyCount }
        default: 0
        }
    }

    /// First top-level string value of an object, used as a readable history title.
    public var firstString: String? {
        guard case .object(let members) = self else { return nil }
        for member in members { if case .string(let s) = member.value { return s } }
        return nil
    }

    /// `indent == nil` produces minified output.
    public func formatted(indent: String?, sortKeys: Bool = false) -> String {
        var out = ""
        write(to: &out, indent: indent, level: 0, sortKeys: sortKeys)
        return out
    }

    private func write(to out: inout String, indent: String?, level: Int, sortKeys: Bool) {
        switch self {
        case .string(let s): out += JSONValue.quote(s)
        case .number(let n): out += n
        case .bool(let b): out += b ? "true" : "false"
        case .null: out += "null"
        case .array(let items):
            JSONValue.container("[", "]", count: items.count, out: &out, indent: indent, level: level) { i, out in
                items[i].write(to: &out, indent: indent, level: level + 1, sortKeys: sortKeys)
            }
        case .object(let members):
            let sorted = sortKeys ? members.sorted { $0.key < $1.key } : members
            JSONValue.container("{", "}", count: sorted.count, out: &out, indent: indent, level: level) { i, out in
                out += JSONValue.quote(sorted[i].key)
                out += indent == nil ? ":" : ": "
                sorted[i].value.write(to: &out, indent: indent, level: level + 1, sortKeys: sortKeys)
            }
        }
    }

    private static func container(_ open: String, _ close: String, count: Int, out: inout String, indent: String?, level: Int, item: (Int, inout String) -> Void) {
        out += open
        guard count > 0 else { out += close; return }
        for i in 0..<count {
            if i > 0 { out += "," }
            if let indent { out += "\n" + String(repeating: indent, count: level + 1) }
            item(i, &out)
        }
        if let indent { out += "\n" + String(repeating: indent, count: level) }
        out += close
    }

    public static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case _ where u.value < 0x20: out += String(format: "\\u%04x", u.value)
            default: out.unicodeScalars.append(u)
            }
        }
        return out + "\""
    }
}

public struct JSONError: Error, CustomStringConvertible, Sendable {
    public let message: String
    public let line: Int
    public let column: Int
    public var description: String { "\(message) at line \(line), column \(column)" }
}

private struct JSONParser {
    let b: [UInt8]
    var i = 0

    init(bytes: [UInt8]) { b = bytes }

    mutating func document() throws -> JSONValue {
        let v = try value(depth: 0)
        skip()
        if i < b.count { throw fail("Unexpected character") }
        return v
    }

    func fail(_ message: String) -> JSONError {
        let prefix = b[..<min(i, b.count)]
        let line = prefix.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        let column = i - (prefix.lastIndex(of: 10).map { $0 + 1 } ?? 0) + 1
        return JSONError(message: message, line: line, column: column)
    }

    func peek(_ c: Unicode.Scalar) -> Bool { i < b.count && b[i] == UInt8(ascii: c) }

    mutating func skip() {
        while i < b.count, b[i] == 0x20 || b[i] == 0x0A || b[i] == 0x0D || b[i] == 0x09 { i += 1 }
    }

    mutating func value(depth: Int) throws -> JSONValue {
        skip()
        guard depth < 512 else { throw fail("Nesting too deep") }
        guard i < b.count else { throw fail("Unexpected end of input") }
        switch b[i] {
        case UInt8(ascii: "{"):
            i += 1
            skip()
            if peek("}") { i += 1; return .object([]) }
            var members: [JSONMember] = []
            while true {
                skip()
                guard peek("\"") else { throw fail("Expected a key") }
                let key = try string()
                skip()
                guard peek(":") else { throw fail("Expected ':'") }
                i += 1
                members.append(JSONMember(key: key, value: try value(depth: depth + 1)))
                skip()
                if peek(",") { i += 1; continue }
                if peek("}") { i += 1; return .object(members) }
                throw fail("Expected ',' or '}'")
            }
        case UInt8(ascii: "["):
            i += 1
            skip()
            if peek("]") { i += 1; return .array([]) }
            var items: [JSONValue] = []
            while true {
                items.append(try value(depth: depth + 1))
                skip()
                if peek(",") { i += 1; continue }
                if peek("]") { i += 1; return .array(items) }
                throw fail("Expected ',' or ']'")
            }
        case UInt8(ascii: "\""): return .string(try string())
        case UInt8(ascii: "t"): try literal("true"); return .bool(true)
        case UInt8(ascii: "f"): try literal("false"); return .bool(false)
        case UInt8(ascii: "n"): try literal("null"); return .null
        default: return .number(try number())
        }
    }

    mutating func literal(_ word: String) throws {
        let w = Array(word.utf8)
        guard b[i...].starts(with: w) else { throw fail("Unexpected character") }
        i += w.count
    }

    mutating func digits() -> Int {
        let start = i
        while i < b.count, (0x30...0x39).contains(b[i]) { i += 1 }
        return i - start
    }

    mutating func number() throws -> String {
        let start = i
        if peek("-") { i += 1 }
        if peek("0") { i += 1 } else if digits() == 0 { throw fail("Unexpected character") }
        if peek(".") { i += 1; guard digits() > 0 else { throw fail("Expected a digit") } }
        if peek("e") || peek("E") {
            i += 1
            if peek("+") || peek("-") { i += 1 }
            guard digits() > 0 else { throw fail("Expected a digit") }
        }
        return String(decoding: b[start..<i], as: UTF8.self)
    }

    mutating func hex4() throws -> UInt32 {
        guard i + 4 <= b.count, let v = UInt32(String(decoding: b[i..<i + 4], as: UTF8.self), radix: 16) else {
            throw fail("Invalid \\u escape")
        }
        i += 4
        return v
    }

    mutating func string() throws -> String {
        i += 1
        var out: [UInt8] = []
        while i < b.count {
            let c = b[i]
            i += 1
            switch c {
            case UInt8(ascii: "\""):
                return String(decoding: out, as: UTF8.self)
            case UInt8(ascii: "\\"):
                guard i < b.count else { break }
                let e = b[i]
                i += 1
                switch e {
                case UInt8(ascii: "\""), UInt8(ascii: "\\"), UInt8(ascii: "/"): out.append(e)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var code = try hex4()
                    if (0xD800..<0xDC00).contains(code), b[i...].starts(with: [0x5C, 0x75]) {
                        i += 2
                        let low = try hex4()
                        guard (0xDC00..<0xE000).contains(low) else { throw fail("Invalid surrogate pair") }
                        code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                    }
                    out.append(contentsOf: Array(String(Unicode.Scalar(code) ?? "\u{FFFD}").utf8))
                default:
                    i -= 1
                    throw fail("Invalid escape")
                }
            case 0..<0x20:
                i -= 1
                throw fail("Unescaped control character in string")
            default:
                out.append(c)
            }
        }
        throw fail("Unterminated string")
    }
}
