import Foundation

/// Languages the Formatter page handles. JSON has native support (tree, query, repair); the rest go
/// through Biome or Prettier when one is installed, with built-in fallbacks for JS/TS, XML and HTML.
public enum Language: String, CaseIterable, Sendable, Codable {
    case json, javascript, typescript, css, scss, less, html, xml, markdown, yaml, graphql

    public var name: String {
        switch self {
        case .json: "JSON"
        case .javascript: "JavaScript"
        case .typescript: "TypeScript"
        case .css: "CSS"
        case .scss: "SCSS"
        case .less: "Less"
        case .html: "HTML"
        case .xml: "XML"
        case .markdown: "Markdown"
        case .yaml: "YAML"
        case .graphql: "GraphQL"
        }
    }

    public var fileExtension: String {
        switch self {
        case .json: "json"
        case .javascript: "js"
        case .typescript: "ts"
        case .css: "css"
        case .scss: "scss"
        case .less: "less"
        case .html: "html"
        case .xml: "xml"
        case .markdown: "md"
        case .yaml: "yaml"
        case .graphql: "graphql"
        }
    }

    /// Highlighting the output editor understands.
    public var syntax: Format {
        switch self {
        case .json: .json
        case .javascript: .javascript
        case .typescript: .typescript
        default: .text
        }
    }

    /// Grammar-level guesses only; the picker overrides them.
    public static func detect(_ raw: String) -> Language {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if (try? JSONValue.parseLoose(t)) != nil || t.hasPrefix("{") || t.hasPrefix("[") { return .json }
        if t.hasPrefix("<?xml") { return .xml }
        if t.hasPrefix("<") { return t.range(of: #"<(!doctype html|html|head|body|div|span|p|a|script)\b"#, options: [.regularExpression, .caseInsensitive]) != nil ? .html : .xml }
        if t.contains(/^\s*(query|mutation|subscription|fragment|type|schema)\b[^=]*\{/) { return .graphql }
        if Engine.code(t, Options()) != nil { return t.contains(/:\s*(string|number|boolean|any|void|unknown)\b|\binterface\s+\w|\btype\s+\w+\s*=/) ? .typescript : .javascript }
        if t.contains(/(?m)^\s*[.#:\w\[\]\-*>, ]+\{[^}]*:[^}]*\}/) { return t.contains(/(?m)^\s*(\$[\w-]+\s*:|@mixin|@include)/) ? .scss : .css }
        if t.prefixMatch(of: /---\n|[\w-]+:(\s|$)/) != nil { return .yaml }
        return .markdown
    }
}

public struct FormatOutcome: Sendable {
    public var text: String
    public var engine: String
    public var error: String?
    public var errorLine: Int?
    public var errorColumn: Int?
}

/// Biome or Prettier found on the user's login-shell PATH. Looked up once; GUI apps don't inherit that PATH.
public struct ExternalFormatters: Sendable {
    public var biome: String?
    public var prettier: String?
    var path = ""

    public static let shared: ExternalFormatters = locate()

    /// No external formatters; everything uses the built-in fallbacks.
    public static let none = ExternalFormatters()

    public static let biomeLanguages: Set<Language> = [.json, .javascript, .typescript, .css, .graphql]
    public static let prettierLanguages: Set<Language> = [.json, .javascript, .typescript, .css, .scss, .less, .html, .markdown, .yaml, .graphql]

    static func locate() -> ExternalFormatters {
        let script = #"print -r -- "@@$(command -v biome)@@$(command -v prettier)@@$PATH@@""#
        guard let out = run("/bin/zsh", ["-lic", script], input: nil, env: nil, cwd: nil, timeout: 5)?.stdout,
              let m = out.firstMatch(of: /@@(.*)@@(.*)@@(.*)@@/) else { return ExternalFormatters() }
        func path(_ s: Substring) -> String? { s.hasPrefix("/") ? String(s) : nil }
        return ExternalFormatters(biome: path(m.1), prettier: path(m.2), path: String(m.3))
    }

    public func engine(for language: Language) -> (name: String, path: String)? {
        if let biome, Self.biomeLanguages.contains(language) { return ("Biome", biome) }
        if let prettier, Self.prettierLanguages.contains(language) { return ("Prettier", prettier) }
        return nil
    }

    public func format(_ text: String, language: Language, indent: Indent) -> FormatOutcome? {
        guard let (name, binary) = engine(for: language) else { return nil }
        let file = "input.\(language.fileExtension)"
        let width = indent == .four ? "4" : "2"
        let args = name == "Biome"
            ? ["format", "--stdin-file-path=\(file)", "--indent-style=\(indent == .tab ? "tab" : "space")", "--indent-width=\(width)", "--colors=off"]
            : ["--stdin-filepath", file, "--tab-width", width, "--no-color"] + (indent == .tab ? ["--use-tabs"] : [])
        // The binaries are usually `#!/usr/bin/env node` scripts, so node has to be on PATH.
        let env = ["PATH": (binary as NSString).deletingLastPathComponent + ":" + path, "HOME": NSHomeDirectory(), "NO_COLOR": "1"]
        guard let r = Self.run(binary, args, input: text, env: env, cwd: FileManager.default.temporaryDirectory, timeout: 15) else {
            return FormatOutcome(text: text, engine: name, error: "\(name) didn't respond")
        }
        if r.status == 0 { return FormatOutcome(text: r.stdout, engine: name) }
        let message = (r.stderr.isEmpty ? r.stdout : r.stderr).replacing(/\u{1B}\[[0-9;]*m/, with: "")
        let position = message.firstMatch(of: /:(\d+):(\d+)/) ?? message.firstMatch(of: /\((\d+):(\d+)\)/)
        let summary = message.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("[error] input") && !$0.contains("━━") } ?? "\(name) failed"
        return FormatOutcome(text: text, engine: name, error: summary, errorLine: position.flatMap { Int($0.1) }, errorColumn: position.flatMap { Int($0.2) })
    }

    struct Output { var status: Int32; var stdout: String; var stderr: String }

    /// Files instead of pipes so large inputs and outputs can't deadlock.
    static func run(_ executable: String, _ args: [String], input: String?, env: [String: String]?, cwd: URL?, timeout: TimeInterval) -> Output? {
        let dir = FileManager.default.temporaryDirectory.appending(path: "decant-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let inURL = dir.appending(path: "in"), outURL = dir.appending(path: "out"), errURL = dir.appending(path: "err")
        for url in [inURL, outURL, errURL] { FileManager.default.createFile(atPath: url.path, contents: nil) }
        try? Data((input ?? "").utf8).write(to: inURL)
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = args
        if let env { p.environment = env }
        if let cwd { p.currentDirectoryURL = cwd }
        guard let stdin = try? FileHandle(forReadingFrom: inURL), let stdout = try? FileHandle(forWritingTo: outURL),
              let stderr = try? FileHandle(forWritingTo: errURL) else { return nil }
        p.standardInput = stdin
        p.standardOutput = stdout
        p.standardError = stderr
        let done = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in done.signal() }
        guard (try? p.run()) != nil else { return nil }
        if done.wait(timeout: .now() + timeout) == .timedOut { p.terminate(); return nil }
        try? stdout.close()
        try? stderr.close()
        return Output(status: p.terminationStatus,
                      stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
                      stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "")
    }
}

public enum BuiltInFormatter {
    /// nil when there's no built-in formatter for the language.
    public static func format(_ text: String, language: Language, indent: Indent) -> FormatOutcome? {
        switch language {
        case .javascript, .typescript:
            let r = JSFormatter.format(text, indent: indent.unit)
            return FormatOutcome(text: r.text, engine: "Built-in", error: r.balanced ? nil : "Unbalanced brackets or quotes")
        case .xml, .html:
            do {
                let doc = try XMLDocument(xmlString: text, options: language == .html ? [.documentTidyHTML] : [])
                let out = doc.xmlString(options: [.nodePrettyPrint])
                return FormatOutcome(text: indent == .four ? out : reindent(out, from: 4, to: indent), engine: "Built-in")
            } catch {
                let ns = error as NSError
                let line = ns.userInfo["NSXMLParserErrorLineNumber"] as? Int
                return FormatOutcome(text: text, engine: "Built-in", error: ns.localizedDescription, errorLine: line)
            }
        default:
            return nil
        }
    }

    static func reindent(_ s: String, from width: Int, to indent: Indent) -> String {
        s.split(separator: "\n", omittingEmptySubsequences: false).map { (line: Substring) -> String in
            let spaces = line.prefix { $0 == " " }.count
            return String(repeating: indent.unit, count: spaces / width) + String(repeating: " ", count: spaces % width) + line.dropFirst(spaces)
        }.joined(separator: "\n")
    }
}
