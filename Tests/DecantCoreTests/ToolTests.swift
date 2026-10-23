import Foundation
import Testing
@testable import DecantCore

@Test func looseJSONIsRepaired() throws {
    let (v, fixes) = try JSONValue.parseLoose("{\n  // note\n  name: 'Ada', tags: ['a', 'b',], /* x */\n}")
    #expect(v.formatted(indent: nil) == #"{"name":"Ada","tags":["a","b"]}"#)
    #expect(fixes == ["comments", "trailing commas", "single quotes", "unquoted keys"])
    #expect(try JSONValue.parseLoose(#"{"a":1}"#).fixes.isEmpty)
}

@Test func jsonPathAndJqQueries() throws {
    let v = try JSONValue.parse(#"{"users":[{"name":"Ada","age":36},{"name":"Bob","age":25},{"name":"Cy","age":41}]}"#)
    #expect(try JSONQuery.run("$.users[0].name", on: v).formatted(indent: nil) == #""Ada""#)
    #expect(try JSONQuery.run(".users[].name", on: v).formatted(indent: nil) == #"["Ada","Bob","Cy"]"#)
    #expect(try JSONQuery.run("$..age", on: v).formatted(indent: nil) == "[36,25,41]")
    #expect(try JSONQuery.run("$.users[-1].name", on: v).formatted(indent: nil) == #""Cy""#)
    #expect(try JSONQuery.run("$.users[0:2].name", on: v).formatted(indent: nil) == #"["Ada","Bob"]"#)
    #expect(try JSONQuery.run("$.users[?(@.age > 30)].name", on: v).formatted(indent: nil) == #"["Ada","Cy"]"#)
    #expect(try JSONQuery.run("$.users[?(@.name == 'Bob')].age", on: v).formatted(indent: nil) == "25")
    #expect(throws: JSONQuery.Failure.self) { try JSONQuery.run("$.users[", on: v) }
    #expect(JSONValue.segment(key: "first name") == "['first name']")
}

@Test func base64VariantsAndSniffing() throws {
    let data = Data([0xFB, 0xFF, 0xBF])
    #expect(Base64.encode(data) == "+/+/")
    #expect(Base64.encode(data, urlSafe: true) == "-_-_")
    #expect(Base64.encode(Data("a".utf8), padding: false) == "YQ")
    #expect(Base64.decode("YQ") == Data("a".utf8))
    #expect(Base64.encode(Data(count: 100), wrap: true).split(separator: "\n").first?.count == 76)
    #expect(Base64.dataURI("data:image/png;base64,iVBO")?.mime == "image/png")
    #expect(FileKind.sniff(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A]))?.ext == "png")
    #expect(Bytes.text(Data([0x00, 0x01])) == nil)
}

@Test func urlQueryRoundTrip() throws {
    let s = "https://x.com/p?q=hello%20world&a=b%26c#top"
    let range = try #require(URLCoding.query(of: s))
    let items = URLCoding.items(s[range])
    #expect(items.map(\.value) == ["hello world", "b&c"])
    #expect(URLCoding.query(items) == "q=hello%20world&a=b%26c")
    #expect(URLCoding.encode("a b/c", component: true) == "a%20b%2Fc")
    #expect(URLCoding.encode("a b/c", component: false) == "a%20b/c")
}

@Test func jwtDecodesAndVerifies() throws {
    // HS256, secret "secret"
    let token = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIiwiaWF0IjoxNTE2MjM5MDIyfQ.XbPfbIHMI6arZ3Y922BhjWgQzWXcXNrz0ogtVhfEd2o"
    let jwt = try JWT(token)
    #expect(jwt.algorithm == "HS256")
    #expect(jwt.date("iat") == Date(timeIntervalSince1970: 1516239022))
    #expect(jwt.verify(secret: "secret") == true)
    #expect(jwt.verify(secret: "nope") == false)
}

@Test func idsCarryTimestamps() throws {
    let date = Date(timeIntervalSince1970: 1_792_249_669.123)
    let v7 = IDs.uuidV7(date)
    #expect(IDs.inspect(v7)?.contains(Detail("Unix ms", "1792249669123")) == true)
    #expect(IDs.inspect(v7)?.contains(Detail("Version", "7 (Unix time)")) == true)
    let ulid = IDs.ulid(date)
    #expect(ulid.count == 26)
    #expect(IDs.inspect(ulid)?.contains(Detail("Unix ms", "1792249669123")) == true)
    // RFC 9562 test vector for v1: 2022-02-22T19:22:22Z
    #expect(IDs.inspect("C232AB00-9414-11EC-B3C8-9F6BDECED846")?.contains(Detail("Timestamp", "2022-02-22T19:22:22.000Z")) == true)
}

@Test func passwordsUseEverySet() {
    var o = Password.Options()
    o.length = 12
    for _ in 0..<50 {
        let p = Password.generate(o)
        #expect(p.count == 12)
        #expect(p.contains(where: \.isUppercase) && p.contains(where: \.isLowercase) && p.contains(where: \.isNumber))
    }
}

@Test func csvRoundTrip() throws {
    let csv = "name,note,age\nAda,\"likes \"\"quotes\"\", commas\",36\nBob,\"two\nlines\",25"
    let rows = CSV.parse(csv, delimiter: CSV.detectDelimiter(csv))
    #expect(rows.count == 3)
    #expect(rows[1][1] == #"likes "quotes", commas"#)
    let json = CSV.json(rows, header: true, inferTypes: true)
    #expect(json.formatted(indent: nil).hasPrefix(#"[{"name":"Ada","note":"likes \"quotes\", commas","age":36}"#))
    #expect(CSV.write(try CSV.rows(json), delimiter: ",") == csv)
    #expect(CSV.detectDelimiter("a;b;c\n1;2;3") == ";")
}

@Test func diffPairsChangedLines() {
    let rows = Diff.rows("a\nhello world\nc", "a\nhello there\nc\nd")
    #expect(rows.map(\.kind) == [.same, .changed, .same, .added])
    #expect(rows[1].right?.segments.filter(\.emphasized).map(\.text) == ["there"])
    #expect(Diff.rows("A  b", "a b", ignoreWhitespace: true, ignoreCase: true).map(\.kind) == [.same])
}

@Test func regexGroupNames() {
    #expect(RegexGroups.names(#"(?<year>\d{4})-(\d\d)(?:x)(?<day>\d\d)[(]"#) == [1: "year", 3: "day"])
}

@Test func colorsConvert() throws {
    let c = try #require(RGBA("#3366CC"))
    #expect(c.rgb == "rgb(51, 102, 204)")
    #expect(c.hsl == "hsl(220, 60%, 50%)")
    #expect(RGBA("hsl(220, 60%, 50%)")?.hex == "#3366CC")
    #expect(RGBA("rgba(255 0 0 / 0.5)")?.hex == "#FF000080")
    #expect(RGBA("#fff")?.hex == "#FFFFFF")
}

@Test func cronNextRunsAndWords() throws {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let start = Date(timeIntervalSince1970: 1_792_249_669)  // Sat 2026-10-17 15:07:49 UTC
    let cron = try Cron("30 9 * * MON-FRI")
    let runs = cron.next(after: start, count: 3, calendar: cal)
    #expect(runs.map { TimeFormat.string($0, "EEE HH:mm", cal.timeZone) } == ["Mon 09:30", "Tue 09:30", "Wed 09:30"])
    #expect(cron.description == "At 09:30, only on Monday through Friday")
    #expect(try Cron("*/15 * * * *").description == "Every 15 minutes")
    #expect(try Cron("@daily").next(after: start, count: 1, calendar: cal).first.map { TimeFormat.string($0, "d HH:mm", cal.timeZone) } == "18 00:00")
    #expect(throws: Cron.Failure.self) { try Cron("61 * * * *") }
}

@Test func markdownRendersBlocks() {
    let html = Markdown.html("# Hi\n\nSome *em* and `code`.\n\n- a\n- b\n\n| A | B |\n|---|---|\n| 1 | 2 |")
    #expect(html.contains("<h1>Hi</h1>"))
    #expect(html.contains("<em>em</em>"))
    #expect(html.contains("<ul>\n<li><p>a</p>\n</li>"))
    #expect(html.contains("<thead><tr><th>A</th><th>B</th></tr></thead>"))
}

@Test func timeParsingAndRows() throws {
    #expect(TimeFormat.parse("1792249669") == Date(timeIntervalSince1970: 1_792_249_669))
    #expect(TimeFormat.parse("1792249669000") == Date(timeIntervalSince1970: 1_792_249_669))
    #expect(TimeFormat.parse("2026-10-17T15:07:49Z") == Date(timeIntervalSince1970: 1_792_249_669))
    let rows = TimeFormat.rows(Date(timeIntervalSince1970: 1_792_249_669), zone: TimeZone(identifier: "Europe/Berlin")!)
    #expect(rows.contains(Detail("RFC 2822", "Sat, 17 Oct 2026 17:07:49 +0200")))
    #expect(rows.contains(Detail("Week", "42 (ISO 2026)")))
    #expect(TimeFormat.duration(93784) == "1d 2h 3m 4s")
}

@Test func languageDetection() {
    #expect(Language.detect("{a: 1,}") == .json)
    #expect(Language.detect("<?xml version=\"1.0\"?><a/>") == .xml)
    #expect(Language.detect(".a { color: red; }") == .css)
    #expect(Language.detect("const a = 1") == .javascript)
    #expect(Language.detect("# Title\n\ntext") == .markdown)
    #expect(Language.detect("name: x\nlist:\n  - a") == .yaml)
}

@Test func externalFormatterRunsAndReportsErrors() throws {
    // A stand-in for prettier: echoes stdin, or fails with a prettier-style position when the input says so.
    let script = FileManager.default.temporaryDirectory.appending(path: "fake-prettier-\(UUID().uuidString)")
    try """
    #!/bin/sh
    input=$(cat)
    case "$input" in
      *broken*) echo "[error] input.css: SyntaxError: Unexpected token (3:5)" >&2; exit 2 ;;
      *) printf '%s|%s' "$*" "$input" ;;
    esac
    """.write(to: script, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
    defer { try? FileManager.default.removeItem(at: script) }

    let f = ExternalFormatters(biome: nil, prettier: script.path, path: "/usr/bin:/bin")
    let ok = try #require(f.format("a{}", language: .css, indent: .tab))
    #expect(ok.engine == "Prettier")
    #expect(ok.text == "--stdin-filepath input.css --tab-width 2 --no-color --use-tabs|a{}")
    let bad = try #require(f.format("broken", language: .css, indent: .two))
    #expect(bad.errorLine == 3 && bad.errorColumn == 5)
    #expect(f.format("x", language: .xml, indent: .two) == nil)  // Prettier doesn't do XML without a plugin
}

@Test func gitDiffDropsNoiseAndFilters() {
    let diff = """
    commit abc
    diff --git a/src/api/user.ts b/src/api/user.ts
    index 1..2 100644
    --- a/src/api/user.ts
    +++ b/src/api/user.ts
    @@ -1 +1 @@
    -old
    +new
    diff --git a/yarn.lock b/yarn.lock
    --- a/yarn.lock
    +++ b/yarn.lock
    @@ -1 +1 @@
    -a
    +b
    diff --git a/src/api/user.test.ts b/src/api/user.test.ts
    deleted file mode 100644
    --- a/src/api/user.test.ts
    +++ /dev/null
    @@ -1,2 +0,0 @@
    -x
    -y
    diff --git a/logo.png b/logo.png
    Binary files a/logo.png and b/logo.png differ
    diff --git a/README.md b/README.md
    --- a/README.md
    +++ b/README.md
    @@ -1 +1 @@
    -r
    +s
    """
    let all = GitDiff.clean(diff)
    #expect(all.files.map(\.path) == ["src/api/user.ts", "yarn.lock", "src/api/user.test.ts", "logo.png", "README.md"])
    #expect(all.files.map(\.skipped) == [nil, "Lockfile", nil, "Binary", nil])
    #expect(all.files[2].removed == 2 && all.files[2].deleted)
    #expect(all.output.hasPrefix("commit abc\ndiff --git a/src/api/user.ts"))
    #expect(!all.output.contains("yarn.lock"))

    let api = GitDiff.clean(diff, patterns: "src/api, !*.test.ts")
    #expect(api.files.filter { $0.skipped == nil }.map(\.path) == ["src/api/user.ts"])
    #expect(GitDiff.clean(diff, patterns: "src/**/*.ts").files.filter { $0.skipped == nil }.count == 2)
    #expect(GitDiff.clean(diff, patterns: GitDiff.excludePattern("README.md")).files.last?.skipped == "Excluded")
    #expect(GitDiff.clean(diff, skipNoise: false).files.allSatisfy { $0.skipped == nil })
    #expect(!GitDiff.clean(diff, collapseDeleted: true).output.contains("-x"))
}

@Test func yamlParsesBlockFlowAndScalars() throws {
    let yaml = """
    %YAML 1.2
    ---
    # OpenAPI-ish
    openapi: 3.1.0
    info: &info
      title: "Pets \\u00e9"   # comment
      version: '1.0'
      description: |
        Line one
          indented

        after blank
      summary: >-
        folded
        text
    tags: [a, "b", {c: 1}]
    servers:
    - url: http://x.io/v1
      flags: [yes, ~, 0x1F, +7, 1.5e3, .inf]
    - - nested
      - seq
    plain: multi
      line
    copy:
      <<: *info
      title: Own
    empty:
    '200': ok
    """
    let v = try YAML.parse(yaml)
    #expect(v.formatted(indent: nil) == #"""
    {"openapi":"3.1.0","info":{"title":"Pets é","version":"1.0","description":"Line one\n  indented\n\nafter blank\n","summary":"folded text"},"tags":["a","b",{"c":1}],"servers":[{"url":"http://x.io/v1","flags":["yes",null,31,7,1.5e3,".inf"]},["nested","seq"]],"plain":"multi line","copy":{"title":"Own","version":"1.0","description":"Line one\n  indented\n\nafter blank\n","summary":"folded text"},"empty":null,"200":"ok"}
    """#)
    #expect(try YAML.parse("a: 1\n---\n- b").formatted(indent: nil) == #"[{"a":1},["b"]]"#)
    #expect(try YAML.parse(#"{"a": [1, 2], "b": "\ud83d\ude00"}"#).formatted(indent: nil) == #"{"a":[1,2],"b":"😀"}"#)
    #expect(try YAML.parse("k: |+\n  x\n\n").formatted(indent: nil) == #"{"k":"x\n\n"}"#)
    #expect(throws: JSONError.self) { try YAML.parse("a: 1\n  b: 2") }
    #expect((try? YAML.parse("a:\n  - 1\n\tb: 2")) == nil)
    let bomb = "a: &a [x, x, x, x, x, x, x, x, x, x]\n" + (1...8).map { "\(Character(UnicodeScalar(97 + $0)!)): &\(Character(UnicodeScalar(97 + $0)!)) [" + Array(repeating: "*\(Character(UnicodeScalar(96 + $0)!))", count: 10).joined(separator: ", ") + "]" }.joined(separator: "\n")
    #expect(throws: JSONError.self) { try YAML.parse(bomb) }
}

@Test func yamlRoundTripsJSON() throws {
    let json = #"""
    {"name":"Ada","n":-1.5e3,"ok":true,"none":null,"e":{},"l":[],"s":["yes","1.0","2024-01-01","","- x","a: b","#c","  pad","<<","null"],
     "multi":"line 1\nline 2\n","strip":"a\nb","keep":"x\n\n","odd":"\tq\r","nested":[[1,[2]],{"k":{"z":"y"}}],"key with: colon":1,"200":{"d":"ok"}}
    """#
    let v = try JSONValue.parse(json)
    let yaml = YAML.write(v)
    #expect(try YAML.parse(yaml).formatted(indent: nil) == v.formatted(indent: nil))
    #expect(yaml.contains("multi: |\n  line 1\n  line 2\n"))
    #expect(yaml.contains("- - 1\n    - - 2\n"))
    #expect(YAML.write(.string("x")) == "x\n")
}

@Test func openAPISummary() throws {
    let doc = try YAML.parse("swagger: 2.0\ninfo: {title: Pets}\npaths:\n  /pets:\n    get: {}\n    post: {}\n    parameters: []\n  /pets/{id}:\n    get: {}")
    let summary = try #require(OpenAPISummary(doc))
    #expect(summary.version == "Swagger 2.0" && summary.title == "Pets" && summary.paths == 2 && summary.operations == 3)
    #expect(OpenAPISummary(try YAML.parse("a: 1")) == nil)
}
