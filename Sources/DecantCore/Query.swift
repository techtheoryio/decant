import Foundation

/// JSONPath subset (`$.users[0].name`, `$..id`, `$.items[*]`, `[1:3]`, `[-1]`, `[?(@.age > 30)]`)
/// and the matching jq-style spelling (`.users[0].name`, `.items[]`).
public enum JSONQuery {
    public struct Failure: Error, CustomStringConvertible {
        public let description: String
    }

    enum Step {
        case key(String), index(Int), slice(Int?, Int?), wildcard, filter(Filter)
        indirect case recursive(Step)
    }

    struct Filter {
        var path: [String]
        var op: String?
        var literal: JSONValue?
    }

    /// One match is returned as itself, several as an array.
    public static func run(_ query: String, on root: JSONValue) throws -> JSONValue {
        let matches = try evaluate(query, on: root)
        return matches.count == 1 ? matches[0] : .array(matches)
    }

    public static func evaluate(_ query: String, on root: JSONValue) throws -> [JSONValue] {
        try parse(query).reduce([root]) { values, step in values.flatMap { apply(step, to: $0) } }
    }

    static func apply(_ step: Step, to v: JSONValue) -> [JSONValue] {
        switch step {
        case .key(let k):
            guard case .object(let m) = v else { return [] }
            return m.filter { $0.key == k }.map(\.value)
        case .index(let n):
            guard case .array(let a) = v else { return [] }
            let i = n < 0 ? a.count + n : n
            return a.indices.contains(i) ? [a[i]] : []
        case .slice(let from, let to):
            guard case .array(let a) = v else { return [] }
            func clamp(_ x: Int?, _ fallback: Int) -> Int { x.map { min(max($0 < 0 ? a.count + $0 : $0, 0), a.count) } ?? fallback }
            let lo = clamp(from, 0), hi = clamp(to, a.count)
            return lo < hi ? Array(a[lo..<hi]) : []
        case .wildcard:
            return v.children?.map(\.value) ?? []
        case .filter(let f):
            return (v.children?.map(\.value) ?? []).filter { f.matches($0) }
        case .recursive(let inner):
            return descendants(v).flatMap { apply(inner, to: $0) }
        }
    }

    static func descendants(_ v: JSONValue) -> [JSONValue] {
        [v] + (v.children ?? []).flatMap { descendants($0.value) }
    }

    // MARK: Parsing

    static func parse(_ q: String) throws -> [Step] {
        let c = Array(q.trimmingCharacters(in: .whitespaces))
        var i = 0
        if i < c.count, c[i] == "$" { i += 1 }
        var steps: [Step] = []
        func fail(_ what: String) -> Failure { Failure(description: "\(what) at position \(i + 1)") }
        func name() -> String {
            let start = i
            while i < c.count, c[i].isLetter || c[i].isNumber || c[i] == "_" || c[i] == "$" || c[i] == "-" { i += 1 }
            return String(c[start..<i])
        }
        func bracket() throws -> Step {
            i += 1
            guard let close = c[i...].firstIndex(of: "]") else { throw fail("Missing ']'") }
            let body = String(c[i..<close]).trimmingCharacters(in: .whitespaces)
            i = close + 1
            if body.isEmpty || body == "*" { return .wildcard }
            if let f = body.first, f == "'" || f == "\"", body.count >= 2, body.last == f {
                return .key(String(body.dropFirst().dropLast()).replacingOccurrences(of: "\\'", with: "'"))
            }
            if let n = Int(body) { return .index(n) }
            if body.contains(":"), !body.hasPrefix("?") {
                let parts = body.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
                guard parts.count == 2, parts.allSatisfy({ $0.isEmpty || Int($0) != nil }) else { throw fail("Invalid slice") }
                return .slice(Int(parts[0]), Int(parts[1]))
            }
            if body.hasPrefix("?(") && body.hasSuffix(")") {
                return .filter(try filter(String(body.dropFirst(2).dropLast())))
            }
            throw fail("Invalid selector '\(body)'")
        }

        func filter(_ expr: String) throws -> Filter {
            guard let m = expr.wholeMatch(of: /\s*@((?:\.[\w$-]+)*)\s*(?:(==|!=|<=|>=|<|>)\s*(.+?))?\s*/) else {
                throw Failure(description: "Filters look like ?(@.key > 3)")
            }
            let path = m.1.split(separator: ".").map(String.init)
            var literal: JSONValue?
            if let raw = m.3 {
                let text = raw.first == "'" ? "\"" + raw.dropFirst().dropLast() + "\"" : String(raw)
                guard let v = try? JSONValue.parse(text) else { throw Failure(description: "Invalid value \(raw)") }
                literal = v
            }
            return Filter(path: path, op: m.2.map(String.init), literal: literal)
        }

        while i < c.count {
            if c[i] == "." {
                i += 1
                let recursive = i < c.count && c[i] == "."
                if recursive { i += 1 }
                let step: Step
                if i < c.count, c[i] == "*" {
                    i += 1
                    step = .wildcard
                } else if i < c.count, c[i] == "[" {
                    step = try bracket()
                } else {
                    let n = name()
                    if n.isEmpty {
                        if !recursive && i == c.count && steps.isEmpty { break }  // `.` or `$.` alone
                        throw fail("Expected a key")
                    }
                    step = .key(n)
                }
                steps.append(recursive ? .recursive(step) : step)
            } else if c[i] == "[" {
                steps.append(try bracket())
            } else {
                throw fail("Unexpected '\(c[i])'")
            }
        }
        return steps
    }
}

extension JSONQuery.Filter {
    func matches(_ v: JSONValue) -> Bool {
        var current = v
        for key in path {
            guard case .object(let m) = current, let next = m.first(where: { $0.key == key }) else { return false }
            current = next.value
        }
        guard let op, let literal else { return true }
        let order: ComparisonResult?
        switch (current, literal) {
        case (.number(let a), .number(let b)):
            let x = Double(a) ?? 0, y = Double(b) ?? 0
            order = x < y ? .orderedAscending : x > y ? .orderedDescending : .orderedSame
        case (.string(let a), .string(let b)):
            order = a < b ? .orderedAscending : a > b ? .orderedDescending : .orderedSame
        default:
            order = current.formatted(indent: nil) == literal.formatted(indent: nil) ? .orderedSame : nil
        }
        switch op {
        case "==": return order == .orderedSame
        case "!=": return order != .orderedSame
        case "<": return order == .orderedAscending
        case "<=": return order == .orderedAscending || order == .orderedSame
        case ">": return order == .orderedDescending
        default: return order == .orderedDescending || order == .orderedSame
        }
    }
}
