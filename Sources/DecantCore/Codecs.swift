import CryptoKit
import Foundation

// MARK: - Base64

public enum Base64 {
    public static func encode(_ data: Data, urlSafe: Bool = false, padding: Bool = true, wrap: Bool = false) -> String {
        var s = data.base64EncodedString(options: wrap ? [.lineLength76Characters, .endLineWithLineFeed] : [])
        if urlSafe { s = s.replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_") }
        if !padding { s = s.replacingOccurrences(of: "=", with: "") }
        return s
    }

    /// Accepts either alphabet, missing padding and line breaks.
    public static func decode(_ s: String) -> Data? {
        var body = s.filter { !$0.isWhitespace }
        while body.last == "=" { body.removeLast() }
        guard body.count % 4 != 1 else { return nil }
        body = body.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        body += String(repeating: "=", count: (4 - body.count % 4) % 4)
        return Data(base64Encoded: body)
    }

    /// Splits `data:image/png;base64,AAAA` into its MIME type and payload.
    public static func dataURI(_ s: String) -> (mime: String, payload: String)? {
        guard let m = s.firstMatch(of: /^\s*data:([\w.+\/-]*)(?:;[\w-]+=[\w-]+)*;base64,/) else { return nil }
        return (String(m.1), String(s[m.range.upperBound...]))
    }
}

public struct FileKind: Sendable, Equatable {
    public let name: String
    public let mime: String
    public let ext: String
    public var isImage: Bool { mime.hasPrefix("image/") }

    public init(name: String, mime: String, ext: String) {
        self.name = name
        self.mime = mime
        self.ext = ext
    }

    /// Magic-byte sniffing for common binary formats. nil means unknown binary.
    public static func sniff(_ d: Data) -> FileKind? {
        let b = [UInt8](d.prefix(16))
        func at(_ offset: Int, _ bytes: [UInt8]) -> Bool { b.count >= offset + bytes.count && Array(b[offset..<offset + bytes.count]) == bytes }
        func ascii(_ offset: Int, _ s: String) -> Bool { at(offset, Array(s.utf8)) }
        if at(0, [0x89, 0x50, 0x4E, 0x47]) { return FileKind(name: "PNG image", mime: "image/png", ext: "png") }
        if at(0, [0xFF, 0xD8, 0xFF]) { return FileKind(name: "JPEG image", mime: "image/jpeg", ext: "jpg") }
        if ascii(0, "GIF8") { return FileKind(name: "GIF image", mime: "image/gif", ext: "gif") }
        if ascii(0, "RIFF") && ascii(8, "WEBP") { return FileKind(name: "WebP image", mime: "image/webp", ext: "webp") }
        if ascii(0, "RIFF") && ascii(8, "WAVE") { return FileKind(name: "WAV audio", mime: "audio/wav", ext: "wav") }
        if ascii(4, "ftypheic") || ascii(4, "ftypheix") || ascii(4, "ftypmif1") { return FileKind(name: "HEIC image", mime: "image/heic", ext: "heic") }
        if ascii(4, "ftypavif") { return FileKind(name: "AVIF image", mime: "image/avif", ext: "avif") }
        if ascii(4, "ftyp") { return FileKind(name: "MP4 video", mime: "video/mp4", ext: "mp4") }
        if ascii(0, "BM") && d.count > 26 { return FileKind(name: "BMP image", mime: "image/bmp", ext: "bmp") }
        if at(0, [0x49, 0x49, 0x2A, 0x00]) || at(0, [0x4D, 0x4D, 0x00, 0x2A]) { return FileKind(name: "TIFF image", mime: "image/tiff", ext: "tiff") }
        if at(0, [0x00, 0x00, 0x01, 0x00]) { return FileKind(name: "ICO icon", mime: "image/x-icon", ext: "ico") }
        if ascii(0, "%PDF") { return FileKind(name: "PDF document", mime: "application/pdf", ext: "pdf") }
        if at(0, [0x50, 0x4B, 0x03, 0x04]) { return FileKind(name: "ZIP archive", mime: "application/zip", ext: "zip") }
        if at(0, [0x1F, 0x8B]) { return FileKind(name: "Gzip archive", mime: "application/gzip", ext: "gz") }
        if at(0, [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]) { return FileKind(name: "7-Zip archive", mime: "application/x-7z-compressed", ext: "7z") }
        if ascii(0, "Rar!") { return FileKind(name: "RAR archive", mime: "application/vnd.rar", ext: "rar") }
        if ascii(0, "SQLite format 3") { return FileKind(name: "SQLite database", mime: "application/vnd.sqlite3", ext: "sqlite") }
        if at(0, [0x00, 0x61, 0x73, 0x6D]) { return FileKind(name: "WebAssembly module", mime: "application/wasm", ext: "wasm") }
        if ascii(0, "ID3") || at(0, [0xFF, 0xFB]) { return FileKind(name: "MP3 audio", mime: "audio/mpeg", ext: "mp3") }
        if ascii(0, "OggS") { return FileKind(name: "Ogg media", mime: "audio/ogg", ext: "ogg") }
        if ascii(0, "fLaC") { return FileKind(name: "FLAC audio", mime: "audio/flac", ext: "flac") }
        if ascii(0, "wOFF") || ascii(0, "wOF2") { return FileKind(name: "Web font", mime: "font/woff2", ext: ascii(0, "wOF2") ? "woff2" : "woff") }
        if at(0, [0x7F, 0x45, 0x4C, 0x46]) { return FileKind(name: "ELF binary", mime: "application/octet-stream", ext: "bin") }
        if at(0, [0xCF, 0xFA, 0xED, 0xFE]) || at(0, [0xCA, 0xFE, 0xBA, 0xBE]) { return FileKind(name: "Mach-O binary", mime: "application/octet-stream", ext: "bin") }
        return nil
    }

    public static let binary = FileKind(name: "Binary data", mime: "application/octet-stream", ext: "bin")
}

public enum Bytes {
    /// UTF-8 without control characters other than tab and line breaks.
    public static func text(_ d: Data) -> String? {
        guard let s = String(data: d, encoding: .utf8) else { return nil }
        return s.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F || "\n\r\t".unicodeScalars.contains($0) }) ? s : nil
    }

    /// `xxd`-style dump of the first `limit` bytes.
    public static func hexDump(_ d: Data, limit: Int = 64 * 1024) -> String {
        let bytes = [UInt8](d.prefix(limit))
        var out = ""
        for start in stride(from: 0, to: bytes.count, by: 16) {
            let row = bytes[start..<min(start + 16, bytes.count)]
            let hex = row.enumerated().map { String(format: "%02x", $0.element) + ($0.offset == 7 ? " " : "") }.joined(separator: " ")
            let text = String(row.map { (0x20..<0x7F).contains($0) ? Character(UnicodeScalar($0)) : "." })
            out += String(format: "%08x  ", start) + hex.padding(toLength: 49, withPad: " ", startingAt: 0) + " |" + text + "|\n"
        }
        if d.count > limit { out += "… \(d.count - limit) more bytes" }
        return out
    }

    public static func size(_ n: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(n), countStyle: .file)
    }
}

// MARK: - URL

public enum URLCoding {
    static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    static let reserved = CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=%")

    /// `component` behaves like encodeURIComponent, otherwise like encodeURI (reserved characters stay).
    public static func encode(_ s: String, component: Bool) -> String {
        s.addingPercentEncoding(withAllowedCharacters: component ? unreserved : unreserved.union(reserved)) ?? s
    }

    public static func decode(_ s: String, plusAsSpace: Bool = true) -> String? {
        (plusAsSpace ? s.replacingOccurrences(of: "+", with: " ") : s).removingPercentEncoding
    }

    /// The query part of an encoded URL (after `?`, before `#`), or the whole string when it looks like `a=b&c=d`.
    public static func query(of s: String) -> Range<String.Index>? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let q = s.firstIndex(of: "?") {
            let start = s.index(after: q)
            return start..<(s[start...].firstIndex(of: "#") ?? s.endIndex)
        }
        guard t.contains("="), !t.contains(" "), !t.contains("://") else { return nil }
        return s.startIndex..<(s.firstIndex(of: "#") ?? s.endIndex)
    }

    public static func items(_ query: Substring) -> [(name: String, value: String)] {
        query.split(separator: "&").map { pair in
            let parts = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (decode(String(parts[0])) ?? String(parts[0]), parts.count > 1 ? decode(String(parts[1])) ?? String(parts[1]) : "")
        }
    }

    public static func query(_ items: [(name: String, value: String)]) -> String {
        items.map { encode($0.name, component: true) + "=" + encode($0.value, component: true) }.joined(separator: "&")
    }
}

// MARK: - JWT

public struct JWT: Sendable {
    public let header: JSONValue
    public let payload: JSONValue
    public let signature: Data
    let signingInput: String

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    public init(_ token: String) throws {
        let parts = token.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "Bearer ", with: "")
            .split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { throw Failure(description: "A JWT has three dot-separated parts, this has \(parts.count)") }
        func json(_ part: Substring, _ name: String) throws -> JSONValue {
            guard let data = Base64.decode(String(part)), let s = String(data: data, encoding: .utf8) else { throw Failure(description: "The \(name) isn't Base64URL") }
            do { return try JSONValue.parse(s) } catch { throw Failure(description: "The \(name) isn't JSON: \(error)") }
        }
        header = try json(parts[0], "header")
        payload = try json(parts[1], "payload")
        signature = Base64.decode(String(parts[2])) ?? Data()
        signingInput = parts[0] + "." + parts[1]
    }

    public func claim(_ key: String, in v: JSONValue? = nil) -> JSONValue? {
        guard case .object(let m) = v ?? payload else { return nil }
        return m.first { $0.key == key }?.value
    }

    public func date(_ key: String) -> Date? {
        guard case .number(let n)? = claim(key), let t = Double(n) else { return nil }
        return Date(timeIntervalSince1970: t)
    }

    public var algorithm: String? {
        if case .string(let s)? = claim("alg", in: header) { return s }
        return nil
    }

    /// nil when the algorithm isn't HMAC-based (HS256/384/512).
    public func verify(secret: String) -> Bool? {
        let key = SymmetricKey(data: Data(secret.utf8)), message = Data(signingInput.utf8)
        switch algorithm {
        case "HS256": return HMAC<SHA256>.isValidAuthenticationCode(signature, authenticating: message, using: key)
        case "HS384": return HMAC<SHA384>.isValidAuthenticationCode(signature, authenticating: message, using: key)
        case "HS512": return HMAC<SHA512>.isValidAuthenticationCode(signature, authenticating: message, using: key)
        default: return nil
        }
    }
}

// MARK: - UUID / ULID

public enum IDs {
    static let crockford = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func uuidV4() -> String { UUID().uuidString.lowercased() }

    public static func uuidV7(_ date: Date = Date()) -> String {
        var bytes = (0..<16).map { _ in UInt8.random(in: 0...255) }
        let ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        for i in 0..<6 { bytes[i] = UInt8(truncatingIfNeeded: ms >> (8 * (5 - i))) }
        bytes[6] = 0x70 | (bytes[6] & 0x0F)
        bytes[8] = 0x80 | (bytes[8] & 0x3F)
        return format(bytes)
    }

    public static func ulid(_ date: Date = Date()) -> String {
        var ms = UInt64(max(0, date.timeIntervalSince1970 * 1000))
        var time = [Character](repeating: "0", count: 10)
        for i in (0..<10).reversed() { time[i] = crockford[Int(ms & 31)]; ms >>= 5 }
        return String(time) + String((0..<16).map { _ in crockford[Int.random(in: 0..<32)] })
    }

    static func format(_ b: [UInt8]) -> String {
        let hex = b.map { String(format: "%02x", $0) }.joined()
        let c = Array(hex)
        return [0..<8, 8..<12, 12..<16, 16..<20, 20..<32].map { String(c[$0]) }.joined(separator: "-")
    }

    /// Version, variant and embedded timestamp of a UUID or ULID; nil when it's neither.
    public static func inspect(_ raw: String) -> [Detail]? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if s.count == 26, let first = s.uppercased().first, ("0"..."7").contains(first),
           s.uppercased().allSatisfy({ crockford.contains($0) }) {
            let ms = s.uppercased().prefix(10).reduce(UInt64(0)) { $0 << 5 | UInt64(crockford.firstIndex(of: $1)!) }
            let date = Date(timeIntervalSince1970: Double(ms) / 1000)
            return [Detail("Type", "ULID"), Detail("Timestamp", iso.string(from: date)), Detail("Unix ms", "\(ms)"),
                    Detail("Randomness", String(s.suffix(16)))]
        }
        let hex = s.lowercased().filter { $0 != "-" && $0 != "{" && $0 != "}" }.replacingOccurrences(of: "urn:uuid:", with: "")
        guard hex.count == 32, hex.allSatisfy(\.isHexDigit) else { return nil }
        let b = stride(from: 0, to: 32, by: 2).map { UInt8(hex[hex.index(hex.startIndex, offsetBy: $0)...].prefix(2), radix: 16)! }
        let version = Int(b[6] >> 4)
        let variant = b[8] >> 6 == 0b10 ? "RFC 9562" : b[8] >> 5 == 0b110 ? "Microsoft" : b[8] >> 7 == 0 ? "NCS" : "Reserved"
        var rows = [Detail("Type", "UUID"), Detail("Canonical", format(b)), Detail("Version", "\(version)" + (versionNames[version].map { " (\($0))" } ?? "")), Detail("Variant", variant)]
        if hex == String(repeating: "0", count: 32) { rows[2] = Detail("Version", "Nil UUID") }
        var date: Date?
        switch version {
        case 1, 6:
            let low = UInt64(b[0]) << 24 | UInt64(b[1]) << 16 | UInt64(b[2]) << 8 | UInt64(b[3])
            let mid = UInt64(b[4]) << 8 | UInt64(b[5])
            let high = UInt64(b[6] & 0x0F) << 8 | UInt64(b[7])
            let ticks = version == 1 ? high << 48 | mid << 32 | low : (low << 28 | mid << 12 | high)
            date = Date(timeIntervalSince1970: (Double(ticks) - 0x01B2_1DD2_1381_4000) / 10_000_000)
            rows.append(Detail("Node", b[10...].map { String(format: "%02x", $0) }.joined(separator: ":")))
        case 7:
            let ms = b[0..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            date = Date(timeIntervalSince1970: Double(ms) / 1000)
            rows.append(Detail("Unix ms", "\(ms)"))
        default: break
        }
        if let date { rows.insert(Detail("Timestamp", iso.string(from: date)), at: 4) }
        return rows
    }

    static let versionNames = [1: "time-based", 2: "DCE security", 3: "name-based, MD5", 4: "random", 5: "name-based, SHA-1",
                               6: "reordered time", 7: "Unix time", 8: "custom"]
}

// MARK: - Passwords

public enum Password {
    public struct Options: Equatable, Sendable {
        public var length = 20
        public var upper = true, lower = true, digits = true, symbols = true, avoidAmbiguous = false
        public init() {}
    }

    static func sets(_ o: Options) -> [[Character]] {
        let ambiguous = Set("Il1O0o|`'\"")
        return [(o.upper, "ABCDEFGHIJKLMNOPQRSTUVWXYZ"), (o.lower, "abcdefghijklmnopqrstuvwxyz"), (o.digits, "0123456789"),
                (o.symbols, "!@#$%^&*()-_=+[]{};:,.<>?/~")]
            .filter(\.0).map { Array($0.1).filter { !o.avoidAmbiguous || !ambiguous.contains($0) } }
    }

    /// Uses the system CSPRNG and contains at least one character from every enabled set.
    public static func generate(_ o: Options) -> String {
        var rng = SystemRandomNumberGenerator()
        let sets = sets(o)
        guard !sets.isEmpty else { return "" }
        let pool = sets.flatMap { $0 }
        var chars = sets.prefix(o.length).map { $0.randomElement(using: &rng)! }
        while chars.count < o.length { chars.append(pool.randomElement(using: &rng)!) }
        chars.shuffle(using: &rng)
        return String(chars)
    }

    public static func entropy(_ o: Options) -> Double {
        let pool = sets(o).reduce(0) { $0 + $1.count }
        return pool > 0 ? Double(o.length) * log2(Double(pool)) : 0
    }
}

// MARK: - CSV

public enum CSV {
    public static func detectDelimiter(_ s: String) -> Character {
        let line = s.prefix { $0 != "\n" && $0 != "\r\n" }
        return [",", ";", "\t", "|"].max { a, b in line.filter { $0 == a }.count < line.filter { $0 == b }.count } ?? ","
    }

    /// RFC 4180: quoted fields, doubled quotes and line breaks inside quotes.
    public static func parse(_ s: String, delimiter: Character) -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, wasQuoted = false
        var it = s.makeIterator()
        var pending: Character?
        while let c = pending ?? it.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let n = it.next() {
                        if n == "\"" { field.append("\"") } else { quoted = false; pending = n }
                    } else { quoted = false }
                } else { field.append(c) }
            } else if c == "\"" && field.isEmpty && !wasQuoted {
                quoted = true
                wasQuoted = true
            } else if c == delimiter {
                row.append(field); field = ""; wasQuoted = false
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); rows.append(row); row = []; field = ""; wasQuoted = false
            } else {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty || wasQuoted { row.append(field); rows.append(row) }
        return rows
    }

    public static func write(_ rows: [[String]], delimiter: Character) -> String {
        rows.map { row in
            row.map { f in
                f.contains(where: { $0 == delimiter || $0 == "\"" || $0.isNewline }) ? "\"" + f.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : f
            }.joined(separator: String(delimiter))
        }.joined(separator: "\n")
    }

    public static func json(_ rows: [[String]], header: Bool, inferTypes: Bool) -> JSONValue {
        func value(_ s: String) -> JSONValue {
            guard inferTypes else { return .string(s) }
            if s == "true" || s == "false" { return .bool(s == "true") }
            if s == "null" { return .null }
            if case .number? = try? JSONValue.parse(s) { return .number(s) }
            return .string(s)
        }
        guard header, let keys = rows.first else { return .array(rows.map { .array($0.map(value)) }) }
        return .array(rows.dropFirst().map { row in
            .object(keys.indices.map { JSONMember(key: keys[$0], value: value($0 < row.count ? row[$0] : "")) })
        })
    }

    public struct Failure: Error, CustomStringConvertible { public let description: String }

    /// Arrays of objects become a header plus rows (union of keys); arrays of arrays become rows.
    public static func rows(_ v: JSONValue) throws -> [[String]] {
        guard case .array(let items) = v else {
            if case .object = v { return try rows(.array([v])) }
            throw Failure(description: "CSV needs a JSON array")
        }
        func cell(_ v: JSONValue) -> String {
            switch v {
            case .string(let s): s
            case .null: ""
            default: v.formatted(indent: nil)
            }
        }
        if items.allSatisfy({ if case .object = $0 { true } else { false } }) {
            var keys: [String] = []
            for case .object(let m) in items { for k in m.map(\.key) where !keys.contains(k) { keys.append(k) } }
            return [keys] + items.map { item in
                guard case .object(let m) = item else { return [] }
                return keys.map { k in m.first { $0.key == k }.map { cell($0.value) } ?? "" }
            }
        }
        return items.map { item in
            if case .array(let a) = item { return a.map(cell) }
            return [cell(item)]
        }
    }
}

// MARK: - Time

public enum TimeFormat {
    static let posix = Locale(identifier: "en_US_POSIX")

    /// Epoch numbers (seconds, ms, µs or ns by magnitude), ISO 8601 or RFC 2822.
    public static func parse(_ raw: String) -> Date? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let n = Double(s), s.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" }) {
            let digits = s.split(separator: ".").first?.filter(\.isNumber).count ?? 0
            let divisor: Double = digits <= 11 ? 1 : digits <= 14 ? 1e3 : digits <= 17 ? 1e6 : 1e9
            return Date(timeIntervalSince1970: n / divisor)
        }
        let iso = ISO8601DateFormatter()
        for options: ISO8601DateFormatter.Options in [[.withInternetDateTime, .withFractionalSeconds], [.withInternetDateTime], [.withFullDate]] {
            iso.formatOptions = options
            if let d = iso.date(from: s) { return d }
        }
        let f = DateFormatter()
        f.locale = posix
        for pattern in ["EEE, dd MMM yyyy HH:mm:ss Z", "dd MMM yyyy HH:mm:ss Z", "yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            f.dateFormat = pattern
            if let d = f.date(from: s) { return d }
        }
        return nil
    }

    public static func string(_ date: Date, _ pattern: String, _ zone: TimeZone) -> String {
        let f = DateFormatter()
        f.locale = posix
        f.timeZone = zone
        f.dateFormat = pattern
        return f.string(from: date)
    }

    public static func rows(_ date: Date, zone: TimeZone, now: Date = Date()) -> [Detail] {
        let utc = TimeZone(identifier: "UTC")!
        let fraction = date.timeIntervalSince1970.truncatingRemainder(dividingBy: 1) != 0
        let relative = RelativeDateTimeFormatter()
        relative.locale = posix
        relative.unitsStyle = .abbreviated
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = zone
        let seconds = date.timeIntervalSince1970
        return [
            Detail("UTC", string(date, "EEE, d MMM yyyy HH:mm:ss", utc)),
            Detail("Local", string(date, "EEE, d MMM yyyy HH:mm:ss", zone) + " " + (zone.abbreviation(for: date) ?? "")),
            Detail("ISO 8601", string(date, fraction ? "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'" : "yyyy-MM-dd'T'HH:mm:ss'Z'", utc)),
            Detail("ISO 8601 local", string(date, fraction ? "yyyy-MM-dd'T'HH:mm:ss.SSSxxx" : "yyyy-MM-dd'T'HH:mm:ssxxx", zone)),
            Detail("RFC 2822", string(date, "EEE, dd MMM yyyy HH:mm:ss Z", zone)),
            Detail("Relative", relative.localizedString(for: date, relativeTo: now)),
            Detail("Weekday", string(date, "EEEE", zone)),
            Detail("Week", "\(calendar.component(.weekOfYear, from: date)) (ISO \(calendar.component(.yearForWeekOfYear, from: date)))"),
            Detail("Day of year", "\(calendar.ordinality(of: .day, in: .year, for: date) ?? 0)"),
            Detail("Seconds", String(format: "%.0f", seconds.rounded(.down))),
            Detail("Milliseconds", String(format: "%.0f", (seconds * 1000).rounded(.down))),
        ]
    }

    /// "2 d 3 h 4 min 5 s"
    public static func duration(_ seconds: TimeInterval) -> String {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.year, .day, .hour, .minute, .second]
        f.unitsStyle = .abbreviated
        f.maximumUnitCount = 5
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = posix
        f.calendar = calendar
        return f.string(from: abs(seconds)) ?? "\(abs(seconds)) s"
    }
}
