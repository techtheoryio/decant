import Foundation

// MARK: - Diff

public enum Diff {
    public enum Kind: Sendable { case same, removed, added, changed }

    public struct Segment: Sendable, Hashable {
        public let text: String
        public let emphasized: Bool
    }

    public struct Line: Sendable, Hashable {
        public let number: Int
        public let segments: [Segment]
        public var text: String { segments.map(\.text).joined() }
    }

    public struct Row: Sendable, Hashable {
        public let kind: Kind
        public let left: Line?
        public let right: Line?
    }

    /// Side-by-side rows from a line diff (Myers, via the standard library). Changed lines are paired
    /// and carry word-level emphasis.
    public static func rows(_ a: String, _ b: String, ignoreWhitespace: Bool = false, ignoreCase: Bool = false) -> [Row] {
        let left = a.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let right = b.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        func key(_ s: String) -> String {
            var k = ignoreWhitespace ? s.split(whereSeparator: \.isWhitespace).joined(separator: " ") : s
            if ignoreCase { k = k.lowercased() }
            return k
        }
        let diff = right.map(key).difference(from: left.map(key))
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }
        var rows: [Row] = []
        var i = 0, j = 0
        func plain(_ s: String, _ n: Int) -> Line { Line(number: n + 1, segments: [Segment(text: s, emphasized: false)]) }
        while i < left.count || j < right.count {
            if (i < left.count && removed.contains(i)) || (j < right.count && inserted.contains(j)) {
                var dels: [Int] = [], adds: [Int] = []
                while i < left.count, removed.contains(i) { dels.append(i); i += 1 }
                while j < right.count, inserted.contains(j) { adds.append(j); j += 1 }
                for k in 0..<max(dels.count, adds.count) {
                    switch (k < dels.count ? dels[k] : nil, k < adds.count ? adds[k] : nil) {
                    case let (l?, r?):
                        let (ls, rs) = words(left[l], right[r])
                        rows.append(Row(kind: .changed, left: Line(number: l + 1, segments: ls), right: Line(number: r + 1, segments: rs)))
                    case let (l?, nil): rows.append(Row(kind: .removed, left: plain(left[l], l), right: nil))
                    case let (nil, r?): rows.append(Row(kind: .added, left: nil, right: plain(right[r], r)))
                    default: break
                    }
                }
            } else {
                rows.append(Row(kind: .same, left: plain(left[i], i), right: plain(right[j], j)))
                i += 1
                j += 1
            }
        }
        return rows
    }

    /// Word-level emphasis for one changed line pair.
    static func words(_ a: String, _ b: String) -> ([Segment], [Segment]) {
        func tokens(_ s: String) -> [String] {
            var out: [String] = [], word = ""
            for c in s {
                if c.isLetter || c.isNumber || c == "_" { word.append(c); continue }
                if !word.isEmpty { out.append(word); word = "" }
                out.append(String(c))
            }
            if !word.isEmpty { out.append(word) }
            return out
        }
        let ta = tokens(a), tb = tokens(b)
        let diff = tb.difference(from: ta)
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let o, _, _): removed.insert(o)
            case .insert(let o, _, _): inserted.insert(o)
            }
        }
        func segments(_ t: [String], _ marked: Set<Int>) -> [Segment] {
            var out: [Segment] = []
            for (i, s) in t.enumerated() {
                let e = marked.contains(i)
                if let last = out.last, last.emphasized == e { out[out.count - 1] = Segment(text: last.text + s, emphasized: e) }
                else { out.append(Segment(text: s, emphasized: e)) }
            }
            return out
        }
        return (segments(ta, removed), segments(tb, inserted))
    }
}

// MARK: - Regex

public enum RegexGroups {
    /// Names of capture groups by group number (1-based), from `(?<name>…)` / `(?P<name>…)`.
    public static func names(_ pattern: String) -> [Int: String] {
        var names: [Int: String] = [:], group = 0, inClass = false
        let c = Array(pattern)
        var i = 0
        while i < c.count {
            switch c[i] {
            case "\\": i += 1
            case "[": inClass = true
            case "]": inClass = false
            case "(" where !inClass:
                if i + 1 < c.count, c[i + 1] == "?" {
                    var j = i + 2
                    if j < c.count, c[j] == "P" { j += 1 }
                    if j < c.count, c[j] == "<" || c[j] == "'", j + 1 < c.count, c[j + 1] != "=", c[j + 1] != "!" {
                        group += 1
                        let close: Character = c[j] == "<" ? ">" : "'"
                        if let end = c[(j + 1)...].firstIndex(of: close) { names[group] = String(c[(j + 1)..<end]) }
                    }
                } else {
                    group += 1
                }
            default: break
            }
            i += 1
        }
        return names
    }
}

// MARK: - Text statistics

public struct TextStats: Sendable {
    public var characters = 0, nonWhitespace = 0, words = 0, lines = 0, sentences = 0, paragraphs = 0, bytes = 0, utf16 = 0

    public init(_ s: String) {
        characters = s.count
        nonWhitespace = s.filter { !$0.isWhitespace }.count
        bytes = s.utf8.count
        utf16 = s.utf16.count
        lines = s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count
        paragraphs = s.components(separatedBy: "\n").split { $0.trimmingCharacters(in: .whitespaces).isEmpty }.count
        var w = 0, sentences = 0
        s.enumerateSubstrings(in: s.startIndex..., options: [.byWords, .substringNotRequired]) { _, _, _, _ in w += 1 }
        s.enumerateSubstrings(in: s.startIndex..., options: .bySentences) { sub, _, _, _ in
            if sub?.contains(where: { $0.isLetter || $0.isNumber }) == true { sentences += 1 }
        }
        words = w
        self.sentences = sentences
    }

    /// At 230 words per minute.
    public var readingTime: String {
        let seconds = Int((Double(words) / 230 * 60).rounded())
        return seconds < 60 ? "\(seconds) s" : "\(seconds / 60) min \(seconds % 60) s"
    }
}

// MARK: - Colors

public struct RGBA: Equatable, Sendable {
    public var r, g, b, a: Double  // 0...1

    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }

    /// `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()/rgba()`, `hsl()/hsla()`; commas or spaces, `/ alpha`.
    public init?(_ raw: String) {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let hex = s.hasPrefix("#") ? String(s.dropFirst()) : s
        if [3, 4, 6, 8].contains(hex.count), hex.allSatisfy(\.isHexDigit) {
            let full = hex.count <= 4 ? String(hex.flatMap { [$0, $0] }) : hex
            let v = stride(from: 0, to: full.count, by: 2).map { Double(Int(full.dropFirst($0).prefix(2), radix: 16)!) / 255 }
            self.init(r: v[0], g: v[1], b: v[2], a: v.count > 3 ? v[3] : 1)
            return
        }
        guard let m = s.wholeMatch(of: /(rgba?|hsla?)\(\s*([^)]*)\)/) else { return nil }
        let parts = m.2.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        func number(_ p: String, scale: Double) -> Double? {
            p.hasSuffix("%") ? Double(p.dropLast()).map { $0 / 100 } : Double(p.replacingOccurrences(of: "deg", with: "")).map { $0 / scale }
        }
        guard let alpha = parts.count == 4 ? number(parts[3], scale: 1) : 1 else { return nil }
        if m.1.hasPrefix("rgb") {
            guard let r = number(parts[0], scale: 255), let g = number(parts[1], scale: 255), let b = number(parts[2], scale: 255) else { return nil }
            self.init(r: r, g: g, b: b, a: alpha)
        } else {
            guard let h = Double(parts[0].replacingOccurrences(of: "deg", with: "")), let sat = number(parts[1], scale: 100),
                  let l = number(parts[2], scale: 100) else { return nil }
            self = RGBA.hsl(h, sat, l, alpha)
        }
        guard [r, g, b, a].allSatisfy({ (0...1).contains($0) }) else { return nil }
    }

    public static func hsl(_ h: Double, _ s: Double, _ l: Double, _ a: Double = 1) -> RGBA {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = (h.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r, g, b): (Double, Double, Double) = switch hp {
        case ..<1: (c, x, 0)
        case ..<2: (x, c, 0)
        case ..<3: (0, c, x)
        case ..<4: (0, x, c)
        case ..<5: (x, 0, c)
        default: (c, 0, x)
        }
        let m = l - c / 2
        return RGBA(r: r + m, g: g + m, b: b + m, a: a)
    }

    var hslComponents: (h: Double, s: Double, l: Double) {
        let mx = max(r, g, b), mn = min(r, g, b), l = (mx + mn) / 2, d = mx - mn
        guard d > 0 else { return (0, 0, l) }
        let s = d / (1 - abs(2 * l - 1))
        var h: Double
        switch mx {
        case r: h = ((g - b) / d).truncatingRemainder(dividingBy: 6)
        case g: h = (b - r) / d + 2
        default: h = (r - g) / d + 4
        }
        h *= 60
        if h < 0 { h += 360 }
        return (h, s, l)
    }

    static func byte(_ v: Double) -> Int { Int((v * 255).rounded()) }
    static func trim(_ v: Double) -> String { String(format: "%g", (v * 100).rounded() / 100) }

    public var hex: String {
        "#" + [r, g, b].map { String(format: "%02X", RGBA.byte($0)) }.joined() + (a < 1 ? String(format: "%02X", RGBA.byte(a)) : "")
    }

    public var rgb: String {
        let rgb = [r, g, b].map { "\(RGBA.byte($0))" }.joined(separator: ", ")
        return a < 1 ? "rgba(\(rgb), \(RGBA.trim(a)))" : "rgb(\(rgb))"
    }

    public var hsl: String {
        let c = hslComponents
        let body = "\(Int(c.h.rounded())), \(Int((c.s * 100).rounded()))%, \(Int((c.l * 100).rounded()))%"
        return a < 1 ? "hsla(\(body), \(RGBA.trim(a)))" : "hsl(\(body))"
    }

    public var swiftUI: String {
        "Color(red: \(RGBA.trim(r)), green: \(RGBA.trim(g)), blue: \(RGBA.trim(b))" + (a < 1 ? ", opacity: \(RGBA.trim(a)))" : ")")
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func contrast(with other: RGBA) -> Double {
        let (x, y) = (luminance, other.luminance)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}

// MARK: - Cron

/// Five-field cron (minute hour day-of-month month day-of-week) with ranges, steps, lists, names and @macros.
public struct Cron: Sendable {
    public struct Failure: Error, CustomStringConvertible { public let description: String }

    struct Field: Sendable {
        let raw: String
        let values: Set<Int>
        let isAll: Bool
    }

    let minute, hour, day, month, weekday: Field

    static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
    static let dayNames = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    static let macros = ["@yearly": "0 0 1 1 *", "@annually": "0 0 1 1 *", "@monthly": "0 0 1 * *", "@weekly": "0 0 * * 0",
                         "@daily": "0 0 * * *", "@midnight": "0 0 * * *", "@hourly": "0 * * * *"]

    public init(_ expression: String) throws {
        let e = expression.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = (Cron.macros[e.lowercased()] ?? e).split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count == 5 else { throw Failure(description: "Expected 5 fields (minute hour day month weekday), got \(parts.count)") }
        minute = try Cron.field(parts[0], "minute", 0...59, names: [])
        hour = try Cron.field(parts[1], "hour", 0...23, names: [])
        day = try Cron.field(parts[2], "day of month", 1...31, names: [])
        month = try Cron.field(parts[3], "month", 1...12, names: Cron.monthNames, offset: 1)
        let w = try Cron.field(parts[4], "day of week", 0...7, names: Cron.dayNames)
        weekday = Field(raw: w.raw, values: Set(w.values.map { $0 % 7 }), isAll: w.isAll)
    }

    static func field(_ raw: String, _ name: String, _ range: ClosedRange<Int>, names: [String], offset: Int = 0) throws -> Field {
        func number(_ s: Substring) throws -> Int {
            if let i = names.firstIndex(of: s.uppercased()) { return i + offset }
            guard let n = Int(s), range.contains(n) else { throw Failure(description: "'\(s)' isn't a valid \(name) (\(range.lowerBound)–\(range.upperBound))") }
            return n
        }
        var values = Set<Int>()
        for part in raw.split(separator: ",") {
            let pieces = part.split(separator: "/", omittingEmptySubsequences: false)
            guard pieces.count <= 2 else { throw Failure(description: "Invalid \(name) '\(part)'") }
            var step = 1
            if pieces.count == 2 {
                guard let s = Int(pieces[1]), s > 0 else { throw Failure(description: "Invalid step in \(name) '\(part)'") }
                step = s
            }
            let base = pieces[0]
            var lo = range.lowerBound, hi = range.upperBound
            if base != "*" && base != "?" {
                let bounds = base.split(separator: "-")
                lo = try number(bounds[0])
                hi = bounds.count == 2 ? try number(bounds[1]) : (pieces.count == 2 ? range.upperBound : lo)
                guard bounds.count <= 2, lo <= hi else { throw Failure(description: "Invalid range in \(name) '\(part)'") }
            }
            values.formUnion(stride(from: lo, through: hi, by: step))
        }
        return Field(raw: raw, values: values, isAll: raw == "*" || raw == "?")
    }

    func dayMatches(_ dom: Int, _ dow: Int) -> Bool {
        if day.isAll && weekday.isAll { return true }
        if day.isAll { return weekday.values.contains(dow) }
        if weekday.isAll { return day.values.contains(dom) }
        return day.values.contains(dom) || weekday.values.contains(dow)  // classic cron: either matches
    }

    public func next(after start: Date, count: Int, calendar: Calendar = .current) -> [Date] {
        var out: [Date] = []
        guard var d = calendar.dateInterval(of: .minute, for: start)?.end else { return [] }
        var guardCount = 0
        while out.count < count, guardCount < 200_000 {
            guardCount += 1
            let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .weekday], from: d)
            if !month.values.contains(c.month!) {
                d = calendar.dateInterval(of: .month, for: d)!.end
            } else if !dayMatches(c.day!, c.weekday! - 1) {
                d = calendar.dateInterval(of: .day, for: d)!.end
            } else if !hour.values.contains(c.hour!) {
                d = calendar.dateInterval(of: .hour, for: d)!.end
            } else if !minute.values.contains(c.minute!) {
                d = calendar.dateInterval(of: .minute, for: d)!.end
            } else {
                out.append(d)
                d = calendar.dateInterval(of: .minute, for: d)!.end
            }
        }
        return out
    }

    // MARK: Plain words

    public var description: String {
        var s = timePhrase
        if !day.isAll { s += ", on " + list(day.raw, unit: "day", name: { "day \($0)" }) + " of the month" }
        if !weekday.isAll {
            s += (day.isAll ? ", only on " : ", or on ") + list(weekday.raw, unit: "day of the week", name: { Cron.weekdayName($0) })
        }
        if !month.isAll { s += ", in " + list(month.raw, unit: "month", name: { Cron.monthName($0) }) }
        return s
    }

    static func weekdayName(_ s: String) -> String {
        let names = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]
        if let i = dayNames.firstIndex(of: s.uppercased()) { return names[i] }
        return Int(s).map { names[$0 % 7] } ?? s
    }

    static func monthName(_ s: String) -> String {
        let names = Calendar(identifier: .gregorian).monthSymbols
        if let i = monthNames.firstIndex(of: s.uppercased()) { return names[i] }
        return Int(s).flatMap { (1...12).contains($0) ? names[$0 - 1] : nil } ?? s
    }

    func list(_ raw: String, unit: String, name: (String) -> String) -> String {
        let items = raw.split(separator: ",").map { part -> String in
            let pieces = part.split(separator: "/")
            let base = String(pieces[0])
            let range = base.split(separator: "-").map { name(String($0)) }
            if pieces.count == 2 {
                let nth = ordinal(Int(pieces[1]) ?? 1)
                let every = "every " + (nth.isEmpty ? "" : nth + " ") + unit
                if base == "*" { return every }
                return range.count == 2 ? "\(every) from \(range[0]) through \(range[1])" : "\(every) starting \(range[0])"
            }
            return range.joined(separator: " through ")
        }
        return items.count <= 1 ? items.joined() : items.dropLast().joined(separator: ", ") + " and " + items.last!
    }

    func ordinal(_ n: Int) -> String {
        n == 1 ? "" : n == 2 ? "other" : { let f = NumberFormatter(); f.numberStyle = .ordinal; f.locale = Locale(identifier: "en_US"); return f.string(from: n as NSNumber) ?? "\(n)th" }()
    }

    var timePhrase: String {
        let singleMinute = Int(minute.raw), hours = hour.raw.split(separator: ",").compactMap { Int($0) }
        if let m = singleMinute, !hours.isEmpty, hours.count == hour.raw.split(separator: ",").count {
            return "At " + hours.map { String(format: "%02d:%02d", $0, m) }.joined(separator: ", ").replacingLastComma()
        }
        let minutePart: String
        if minute.isAll { minutePart = "Every minute" }
        else if minute.raw.hasPrefix("*/") { minutePart = "Every \(minute.raw.dropFirst(2)) minutes" }
        else if let m = singleMinute { minutePart = m == 0 ? "At the start of the hour" : "At \(m) minutes past the hour" }
        else { minutePart = "At minutes " + list(minute.raw, unit: "minute", name: { $0 }) }
        if hour.isAll { return minutePart }
        if let m = hour.raw.wholeMatch(of: /(\d+)-(\d+)/), let a = Int(m.1), let b = Int(m.2) {
            return minutePart + String(format: ", between %02d:00 and %02d:59", a, b)
        }
        return minutePart + ", during " + list(hour.raw, unit: "hour", name: { Int($0).map { String(format: "%02d:00", $0) } ?? $0 })
    }
}

extension String {
    fileprivate func replacingLastComma() -> String {
        guard let r = range(of: ", ", options: .backwards) else { return self }
        return replacingCharacters(in: r, with: " and ")
    }
}

// MARK: - Markdown

public enum Markdown {
    /// CommonMark + GFM tables via Foundation's parser, rendered to HTML by walking the block intents.
    public static func html(_ source: String) -> String {
        guard let attributed = try? AttributedString(markdown: source, options: .init(
            allowsExtendedAttributes: true, interpretedSyntax: .full, failurePolicy: .returnPartiallyParsedIfPossible))
        else { return "<pre>\(escape(source))</pre>" }
        var html = ""
        var open: [PresentationIntent.IntentType] = []

        func tags(_ t: PresentationIntent.IntentType, inHeader: Bool) -> (String, String) {
            switch t.kind {
            case .paragraph: ("<p>", "</p>\n")
            case .header(let level): ("<h\(level)>", "</h\(level)>\n")
            case .orderedList: ("<ol>\n", "</ol>\n")
            case .unorderedList: ("<ul>\n", "</ul>\n")
            case .listItem: ("<li>", "</li>\n")
            case .codeBlock(let lang): ("<pre><code\(lang.map { " class=\"language-\(escape($0))\"" } ?? "")>", "</code></pre>\n")
            case .blockQuote: ("<blockquote>\n", "</blockquote>\n")
            case .thematicBreak: ("<hr>", "\n")
            case .table: ("<table>\n", "</table>\n")
            case .tableHeaderRow: ("<thead><tr>", "</tr></thead>\n")
            case .tableRow: ("<tr>", "</tr>\n")
            case .tableCell: inHeader ? ("<th>", "</th>") : ("<td>", "</td>")
            @unknown default: ("<div>", "</div>")
            }
        }

        for run in attributed.runs {
            let path = Array((run.presentationIntent?.components ?? []).reversed())  // outermost first
            var common = 0
            while common < open.count, common < path.count, open[common].identity == path[common].identity { common += 1 }
            for t in open[common...].reversed() { html += tags(t, inHeader: isHeader(open)).1 }
            let inHeader = isHeader(path)
            for t in path[common...] { html += tags(t, inHeader: inHeader).0 }
            open = path
            if case .thematicBreak? = path.last?.kind { continue }

            var text = escape(String(attributed[run.range].characters))
            let inline = run.inlinePresentationIntent ?? []
            if inline.contains(.lineBreak) { text = "<br>\n" }
            if inline.contains(.code) { text = "<code>\(text)</code>" }
            if inline.contains(.stronglyEmphasized) { text = "<strong>\(text)</strong>" }
            if inline.contains(.emphasized) { text = "<em>\(text)</em>" }
            if inline.contains(.strikethrough) { text = "<del>\(text)</del>" }
            if let url = run.imageURL { text = "<img src=\"\(escape(url.absoluteString))\" alt=\"\(text)\">" }
            else if let url = run.link { text = "<a href=\"\(escape(url.absoluteString))\">\(text)</a>" }
            html += text
        }
        for t in open.reversed() { html += tags(t, inHeader: isHeader(open)).1 }
        return html
    }

    static func isHeader(_ path: [PresentationIntent.IntentType]) -> Bool {
        path.contains { if case .tableHeaderRow = $0.kind { true } else { false } }
    }

    static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
