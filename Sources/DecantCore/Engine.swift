import Foundation

public enum Format: String, Codable, Sendable, CaseIterable {
    case json, escapedJSON, base64, typescript, javascript, unixTime, text

    public var name: String {
        switch self {
        case .json: "JSON"
        case .escapedJSON: "Escaped JSON"
        case .base64: "Base64"
        case .typescript: "TypeScript"
        case .javascript: "JavaScript"
        case .unixTime: "Unix time"
        case .text: "Text"
        }
    }

    public var shortName: String {
        switch self {
        case .json, .escapedJSON: "JSON"
        case .base64: "B64"
        case .typescript: "TS"
        case .javascript: "JS"
        case .unixTime: "TIME"
        case .text: "TEXT"
        }
    }

    public static let supported = "JSON · Escaped JSON · TypeScript · JavaScript · Base64 · Unix time"
}

public enum Indent: String, CaseIterable, Codable, Sendable {
    case two = "2 spaces", four = "4 spaces", tab = "Tab"

    public var unit: String {
        switch self {
        case .two: "  "
        case .four: "    "
        case .tab: "\t"
        }
    }

    var summary: String { self == .tab ? "tabs" : rawValue }
}

public struct Options: Equatable, Sendable {
    public var indent: Indent = .two
    public var minify = false
    public var sortKeys = false
    public var unescape = true
    public var decodeNested = true
    public var timeZone: TimeZone = .current
    public var now: Date?

    public init() {}
}

public enum Target: String, CaseIterable, Sendable {
    case escapedString = "Escaped String"
    case base64 = "Base64"
    case base64URL = "Base64 (URL-safe)"
    case hex = "Hex"

    public var format: Format {
        switch self {
        case .escapedString: .escapedJSON
        case .base64, .base64URL: .base64
        case .hex: .text
        }
    }
}

public struct Step: Sendable, Hashable {
    public let format: Format
    public let label: String
    public init(_ format: Format, _ label: String) { self.format = format; self.label = label }
}

public struct Detail: Sendable, Hashable {
    public let label: String
    public let value: String
    public init(_ label: String, _ value: String) { self.label = label; self.value = value }
}

public struct Conversion: Sendable {
    public var input: Format
    public var output: Format
    public var text: String
    public var steps: [Step] = []
    public var details: [Detail] = []
    public var status: String?
    public var error: String?
    public var summary = ""
    /// Short facts for the header's meta row, e.g. "7 keys".
    public var meta: [String] = []
    public var title = ""
    /// The value "Convert To" targets operate on.
    public var source = ""
    public var targets: [Target] = []

    init(input: Format, output: Format, text: String) {
        self.input = input
        self.output = output
        self.text = text
    }
}

/// Deterministic detection and conversion. No heuristics beyond format grammar checks.
public enum Engine {
    /// Detects the format of `raw` and converts it. `force` pins the detector (used by the Tools list).
    public static func convert(_ raw: String, options: Options = Options(), force: Format? = nil) -> Conversion? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let result: Conversion?
        switch force {
        case nil: result = detect(t, options, depth: 0)
        case .json?, .escapedJSON?: result = json(t, options, allowScalars: true) ?? jsonError(t)
        case .base64?: result = base64(t, options, depth: 0) ?? encodeBase64(t)
        case .unixTime?: result = unixTime(t, options) ?? failure(t, as: .unixTime, "Not a Unix timestamp")
        default: result = code(t, options)
        }
        guard var r = result else { return nil }
        if r.title.isEmpty { r.title = String(t.prefix { $0 != "\n" }.prefix(80)) }
        return r
    }

    public static func apply(_ target: Target, to c: Conversion) -> String {
        let data = Data(c.source.utf8)
        switch target {
        case .escapedString:
            return String(JSONValue.quote(c.source).dropFirst().dropLast())
        case .base64:
            return data.base64EncodedString()
        case .base64URL:
            return data.base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        case .hex:
            return data.map { String(format: "%02x", $0) }.joined()
        }
    }

    static func detect(_ t: String, _ o: Options, depth: Int) -> Conversion? {
        if let r = unixTime(t, o) ?? json(t, o, allowScalars: false) ?? base64(t, o, depth: depth) ?? code(t, o) { return r }
        return t.first == "{" || t.first == "[" ? jsonError(t) : nil
    }

    static func lineCount(_ s: String) -> Int { s.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 } }
    static func lines(_ n: Int) -> String { n == 1 ? "1 line" : "\(n) lines" }

    static func failure(_ t: String, as format: Format, _ message: String) -> Conversion {
        var r = Conversion(input: format, output: .text, text: t)
        r.error = message
        r.summary = "\(t.count) characters"
        r.meta = [r.summary]
        return r
    }

    // MARK: JSON

    static func escapeCount(_ t: String) -> Int {
        var n = 0, skip = false
        for c in t.utf8 {
            if skip { skip = false } else if c == UInt8(ascii: "\\") { n += 1; skip = true }
        }
        return n
    }

    static func json(_ t: String, _ o: Options, allowScalars: Bool) -> Conversion? {
        var input = Format.json
        var value: JSONValue
        if let v = try? JSONValue.parse(t) {
            value = v
            if o.unescape, case .string(let s) = v, let inner = try? JSONValue.parse(s), inner.isContainer {
                value = inner
                input = .escapedJSON
            }
        } else if o.unescape, t.contains("\\\""),
                  case .string(let s)? = try? JSONValue.parse("\"\(t)\""),
                  let inner = try? JSONValue.parse(s), inner.isContainer {
            value = inner
            input = .escapedJSON
        } else {
            return nil
        }
        guard value.isContainer || allowScalars else { return nil }

        let text = value.formatted(indent: o.minify ? nil : o.indent.unit, sortKeys: o.sortKeys)
        var r = Conversion(input: input, output: .json, text: text)
        r.details = [Detail("Format", input == .escapedJSON ? "Escaped JSON string" : "JSON"), Detail("Converted to", "JSON")]
        if input == .escapedJSON { r.details.append(Detail("Escapes removed", "\(escapeCount(t))")) }
        r.details.append(Detail("Keys", "\(value.keyCount)"))
        r.meta = [value.keyCount == 1 ? "1 key" : "\(value.keyCount) keys"]
        if input == .escapedJSON { r.meta.append("\(escapeCount(t)) escapes removed") }
        r.status = "Valid"
        r.summary = "\(lines(lineCount(text))) · \(o.minify ? "minified" : o.indent.summary) · UTF-8"
        r.title = value.firstString ?? ""
        r.source = value.formatted(indent: nil, sortKeys: o.sortKeys)
        r.targets = [.escapedString, .base64]
        return r
    }

    static func jsonError(_ t: String) -> Conversion {
        var message = "Invalid JSON"
        do { _ = try JSONValue.parse(t) } catch { message = "\(error)" }
        var r = failure(t, as: .json, message)
        r.output = .json
        return r
    }

    // MARK: Base64

    static func base64(_ t: String, _ o: Options, depth: Int) -> Conversion? {
        let s = t.filter { $0 != "\n" && $0 != "\r" && $0 != "\r\n" }
        guard s.count >= 8 else { return nil }
        var body = Substring(s)
        var pad = 0
        while body.last == "=" { body.removeLast(); pad += 1 }
        let urlSafe = body.contains("-") || body.contains("_")
        let standard = body.contains("+") || body.contains("/")
        guard pad <= 2, !(urlSafe && standard), body.count % 4 != 1, pad == 0 || (body.count + pad) % 4 == 0,
              body.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "+/-_".contains($0)) }) else { return nil }
        // Plain words are valid Base64 too; require something a word wouldn't have.
        guard pad > 0 || body.contains(where: { $0.isNumber || "+/-_".contains($0) })
                || (body.contains(where: \.isUppercase) && body.contains(where: \.isLowercase)) else { return nil }

        var normalized = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        normalized += String(repeating: "=", count: (4 - normalized.count % 4) % 4)
        guard let data = Data(base64Encoded: normalized), let decoded = String(data: data, encoding: .utf8), !decoded.isEmpty,
              decoded.unicodeScalars.allSatisfy({ ($0.value >= 0x20 && $0.value != 0x7F) || "\n\r\t".unicodeScalars.contains($0) })
        else { return nil }

        var r = Conversion(input: .base64, output: .text, text: decoded)
        r.steps = [Step(.base64, "Decoded")]
        r.details = [
            Detail("Alphabet", urlSafe ? "URL-safe" : "Standard"),
            Detail("Padding", pad > 0 ? "Yes" : "No"),
            Detail("Text encoding", "UTF-8"),
        ]
        r.summary = "\(s.count) characters → \(data.count) bytes · UTF-8"
        r.meta = ["\(data.count) bytes · UTF-8", "\(urlSafe ? "URL-safe" : "Standard") alphabet, \(pad > 0 ? "padded" : "unpadded")"]
        r.source = decoded
        r.targets = [.base64URL, .hex]
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        if o.decodeNested, depth < 3, let inner = detect(trimmed, o, depth: depth + 1) {
            r.output = inner.output
            r.text = inner.text
            r.status = inner.status
            r.error = inner.error
            r.steps += [Step(.text, "Parsed as \(inner.input.name)")] + (inner.steps.isEmpty ? [Step(inner.output, "Formatted")] : inner.steps)
        }
        return r
    }

    static func encodeBase64(_ t: String) -> Conversion {
        var r = Conversion(input: .text, output: .base64, text: Data(t.utf8).base64EncodedString())
        r.steps = [Step(.text, "Encoded")]
        r.details = [Detail("Alphabet", "Standard"), Detail("Text encoding", "UTF-8")]
        r.summary = "\(t.utf8.count) bytes → \(r.text.count) characters"
        r.meta = [r.summary]
        r.source = t
        r.targets = [.base64URL, .hex]
        return r
    }

    // MARK: Code

    static func code(_ t: String, _ o: Options) -> Conversion? {
        guard t.contains(/\b(function|const|let|var|return|import|export|class|interface)\b|=>/) else { return nil }
        let isTS = t.contains(/:\s*(string|number|boolean|any|void|unknown|never)\b|\binterface\s+\w|\btype\s+\w+\s*=|\benum\s+\w/)
        let language: Format = isTS ? .typescript : .javascript
        let formatted = JSFormatter.format(t, indent: o.indent.unit)
        var r = Conversion(input: language, output: language, text: formatted.text)
        r.details = [Detail("Language", language.name), Detail("Characters", "\(t.count)")]
        if formatted.balanced { r.status = "Brackets balanced" } else { r.error = "Unbalanced brackets or quotes" }
        r.summary = "\(lines(lineCount(t))) → \(lines(lineCount(formatted.text))) · \(o.indent.summary) · UTF-8"
        r.meta = ["\(lineCount(t)) → \(lines(lineCount(formatted.text)))", "\(t.count) characters"]
        if let m = t.firstMatch(of: /\b(function|class|interface)\s+([\w$]+)/) {
            r.title = String(m.2) + (m.1 == "function" ? "()" : "")
        }
        return r
    }

    // MARK: Unix time

    static func unixTime(_ t: String, _ o: Options) -> Conversion? {
        guard t.first != "0", t.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int64(t) else { return nil }
        let ms: Bool
        switch t.count {
        case 9, 10: ms = false
        case 12, 13: ms = true
        default: return nil
        }
        let date = Date(timeIntervalSince1970: ms ? Double(n) / 1000 : Double(n))
        let utc = TimeZone(identifier: "UTC")!
        func format(_ pattern: String, _ zone: TimeZone) -> String {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = zone
            f.dateFormat = pattern
            return f.string(from: date)
        }
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "en_US_POSIX")
        let zoneName = "\(o.timeZone.identifier) (\(o.timeZone.abbreviation(for: date) ?? ""))"
        let rows = [
            ("Local", format("EEE, d MMM yyyy, HH:mm:ss", o.timeZone)),
            ("ISO 8601", format(ms && n % 1000 != 0 ? "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : "yyyy-MM-dd'T'HH:mm:ss'Z'", utc)),
            ("UTC", format("EEE, d MMM yyyy HH:mm:ss", utc)),
            ("Seconds", "\(ms ? n / 1000 : n)"),
            ("Milliseconds", "\(ms ? n : n * 1000)"),
            ("Relative", relative.localizedString(for: date, relativeTo: o.now ?? Date())),
        ]
        var r = Conversion(input: .unixTime, output: .text, text: rows.map { $0.0.padding(toLength: 14, withPad: " ", startingAt: 0) + $0.1 }.joined(separator: "\n"))
        r.details = [Detail("Unit", ms ? "Milliseconds" : "Seconds"), Detail("Time zone", zoneName)]
        r.summary = "Unix timestamp · \(ms ? "milliseconds" : "seconds")"
        r.meta = [ms ? "Milliseconds" : "Seconds", zoneName]
        r.title = t
        return r
    }
}
