import AppKit
import DecantCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Base64

struct LoadedFile: Equatable {
    var name: String
    var data: Data
    var mime: String
}

struct Base64Page: View {
    @Environment(Store.self) private var store
    @AppStorage("b64Decode") private var decodeMode = false
    @AppStorage("b64URLSafe") private var urlSafe = false
    @AppStorage("b64Padding") private var padding = true
    @AppStorage("b64Wrap") private var wrap = false
    @AppStorage("b64DataURI") private var dataURI = false
    @State private var file: LoadedFile?
    /// Decoded bytes that aren't text.
    @State private var binary: Data?
    @State private var error: String?

    private var doc: Doc { store[doc: .base64] }

    var body: some View {
        ToolPage(tool: .base64, status: status, meta: meta) {
            OptionSegments(selection: $decodeMode, options: [("Encode", false), ("Decode", true)])
            OptionToggle(title: "URL-safe", isOn: $urlSafe)
            OptionToggle(title: "Padding", isOn: $padding)
            OptionToggle(title: "Wrap at 76", isOn: $wrap)
            OptionToggle(title: "data: URI", isOn: $dataURI)
            CapsuleButton(title: "Open File…", systemImage: "folder") { store.importing = true }
        } content: {
            HStack(spacing: 14) {
                if decodeMode {
                    base64Pane
                    textPane
                } else {
                    textPane
                    base64Pane
                }
            }
        }
        .onAppear {
            if let url = store.pendingFile { load(url) } else if doc.input.isEmpty, !doc.aux.isEmpty { decode(doc.aux) }
        }
        .onChange(of: store.pendingFile) { _, url in if let url { load(url) } }
        .onChange(of: [urlSafe, padding, wrap, dataURI]) { reencode() }
    }

    @ViewBuilder private var textPane: some View {
        if let file {
            BinaryPane(title: "File", data: file.data, name: file.name) {
                self.file = nil
                store[doc: .base64] = Doc()
            }
        } else if let binary {
            BinaryPane(title: "Decoded", data: binary, name: nil, onRemove: nil)
        } else {
            EditorPane(title: "Text", text: Binding(get: { doc.input }, set: { new in
                           error = nil
                           store[doc: .base64] = Doc(input: new, aux: new.isEmpty ? "" : encode(Data(new.utf8), mime: "text/plain"))
                       }),
                       placeholder: "Type or paste text, or drop a file here to encode it.",
                       output: decodeMode, primary: decodeMode, onFile: load)
        }
    }

    private var base64Pane: some View {
        EditorPane(title: "Base64", text: Binding(get: { doc.aux }, set: decode),
                   placeholder: "Paste Base64 or a data: URI to decode it. Either alphabet works, with or without padding.",
                   output: !decodeMode, primary: !decodeMode,
                   footer: error.map { AnyView(ErrorBar(message: $0)) }, forceWrap: true)
    }

    private var status: Status? {
        if let error { return .error(error) }
        if let file { return Status(text: "Encoded \(file.name)") }
        if let binary { return Status(text: "Decoded \((FileKind.sniff(binary) ?? .binary).name)") }
        return doc.aux.isEmpty ? nil : Status(text: decodeMode ? "Decoded" : "Encoded")
    }

    private var meta: [String] {
        if let file { return [Bytes.size(file.data.count) + " → \(doc.aux.count) characters", file.mime] }
        if let binary { return [Bytes.size(binary.count), (FileKind.sniff(binary) ?? .binary).mime] }
        guard !doc.aux.isEmpty else { return ["Standard or URL-safe alphabet", "Text or files"] }
        return ["\(doc.input.utf8.count) bytes ↔ \(doc.aux.count) characters", urlSafe ? "URL-safe" : "Standard alphabet"]
    }

    private func encode(_ data: Data, mime: String) -> String {
        (dataURI ? "data:\(mime);base64," : "") + Base64.encode(data, urlSafe: urlSafe, padding: padding, wrap: wrap)
    }

    private func reencode() {
        if let file {
            store[doc: .base64].aux = encode(file.data, mime: file.mime)
        } else if binary == nil, !doc.input.isEmpty {
            store[doc: .base64].aux = encode(Data(doc.input.utf8), mime: "text/plain")
        }
    }

    private func decode(_ b64: String) {
        file = nil
        let payload = Base64.dataURI(b64)?.payload ?? b64
        guard !payload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            binary = nil
            error = nil
            store[doc: .base64] = Doc(input: "", aux: b64)
            return
        }
        guard let data = Base64.decode(payload) else {
            error = "Not valid Base64"
            store[doc: .base64].aux = b64
            return
        }
        error = nil
        if let text = Bytes.text(data) {
            binary = nil
            store[doc: .base64] = Doc(input: text, aux: b64)
        } else {
            binary = data
            store[doc: .base64] = Doc(input: "", aux: b64)
        }
    }

    private func load(_ url: URL) {
        store.pendingFile = nil
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { NSSound.beep(); return }
        let mime = UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? FileKind.sniff(data)?.mime ?? "application/octet-stream"
        binary = nil
        error = nil
        decodeMode = false
        file = LoadedFile(name: url.lastPathComponent, data: data, mime: mime)
        store[doc: .base64] = Doc(input: "", aux: encode(data, mime: mime))
    }
}

/// Binary content: an image preview or a hex dump, plus Save as File….
struct BinaryPane: View {
    let title: String
    let data: Data
    let name: String?
    var onRemove: (() -> Void)?
    @AppStorage("fontSize") private var fontSize = 13.0

    var body: some View {
        let kind = FileKind.sniff(data) ?? (name.map { FileKind(name: "File", mime: "application/octet-stream", ext: ($0 as NSString).pathExtension) } ?? .binary)
        Pane(title) {
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Image(systemName: kind.isImage ? "photo" : "doc.zipper")
                        .font(.system(size: 22))
                        .foregroundStyle(.tint)
                        .frame(width: 44, height: 44)
                        .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(name ?? kind.name).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                        Text("\(kind.name) · \(Bytes.size(data.count)) · \(kind.mime)").font(.system(size: 12)).foregroundStyle(Palette.text2)
                    }
                    Spacer()
                    Button("Save as File…") { Output.save(data, name: name ?? "decoded.\(kind.ext)") }
                    if let onRemove { Button("Remove", action: onRemove) }
                }
                .padding(16)
                Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                if kind.isImage, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(image.size.width < 128 ? .none : .high)
                        .scaledToFit()
                        .frame(maxWidth: min(image.size.width * 2, 900), maxHeight: .infinity)
                        .padding(24)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .onDrag { Output.dragItem(data, name: name ?? "decoded.\(kind.ext)") }
                } else {
                    CodeEditor(text: .constant(Bytes.hexDump(data, limit: 16 * 1024)), editable: false,
                               font: .monospacedSystemFont(ofSize: fontSize - 1, weight: .regular), wrap: false)
                }
            }
        }
    }
}

// MARK: - URL

struct URLPage: View {
    @Environment(Store.self) private var store
    @AppStorage("urlComponent") private var component = true
    @AppStorage("urlPlusAsSpace") private var plusAsSpace = true
    @State private var error: String?

    private var doc: Doc { store[doc: .url] }

    var body: some View {
        let items = queryItems
        ToolPage(tool: .url, status: error.map(Status.error) ?? (doc.input.isEmpty ? nil : Status(text: "Encoded")),
                 meta: doc.input.isEmpty ? ["Percent-encoding (RFC 3986)"] : ["\(doc.input.count) ↔ \(doc.aux.count) characters"] + (items.map { ["\($0.count) parameters"] } ?? [])) {
            OptionSegments(selection: $component, options: [("Component", true), ("Full URL", false)])
            OptionToggle(title: "Decode + as space", isOn: $plusAsSpace)
        } content: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    EditorPane(title: "Decoded", text: Binding(get: { doc.input }, set: { new in
                        error = nil
                        store[doc: .url] = Doc(input: new, aux: URLCoding.encode(new, component: component))
                    }), placeholder: "Type text or a URL to percent-encode it.", output: false)
                    EditorPane(title: "Encoded", text: Binding(get: { doc.aux }, set: decode),
                               placeholder: "Paste an encoded URL or query string to decode it.", output: true, primary: true,
                               footer: error.map { AnyView(ErrorBar(message: $0)) })
                }
                if let items {
                    QueryTable(items: items, update: setItems)
                        .frame(height: min(CGFloat(items.count) * 34 + 90, 260))
                }
            }
        }
        .onChange(of: component) { store[doc: .url].aux = URLCoding.encode(doc.input, component: component) }
    }

    private func decode(_ new: String) {
        if let d = URLCoding.decode(new, plusAsSpace: plusAsSpace) {
            error = nil
            store[doc: .url] = Doc(input: d, aux: new)
        } else {
            error = "Malformed percent-encoding"
            store[doc: .url].aux = new
        }
    }

    /// The encoded URL the table reads and writes: the Encoded side when it carries a query, else the Decoded side as a full URL.
    private var tableSource: String {
        URLCoding.query(of: doc.aux) != nil ? doc.aux : URLCoding.encode(doc.input, component: false)
    }

    private var queryItems: [(name: String, value: String)]? {
        let s = tableSource
        guard let range = URLCoding.query(of: s), !s[range].isEmpty else { return nil }
        return URLCoding.items(s[range])
    }

    private func setItems(_ items: [(name: String, value: String)]) {
        let s = tableSource
        guard let range = URLCoding.query(of: s) else { return }
        let url = s.replacingCharacters(in: range, with: URLCoding.query(items))
        let decoded = URLCoding.decode(url, plusAsSpace: false) ?? url
        store[doc: .url] = Doc(input: decoded, aux: component ? URLCoding.encode(decoded, component: true) : url)
    }
}

struct QueryTable: View {
    let items: [(name: String, value: String)]
    let update: ([(name: String, value: String)]) -> Void

    var body: some View {
        Pane("Query Parameters") {
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                    ForEach(items.indices, id: \.self) { i in
                        GridRow {
                            field("name", i, \.name).frame(width: 200)
                            field("value", i, \.value)
                            IconButton(systemImage: "minus.circle", help: "Remove Parameter") {
                                var it = items
                                it.remove(at: i)
                                update(it)
                            }
                        }
                    }
                }
                .padding(14)
            }
        } accessory: {
            IconButton(systemImage: "plus.circle", help: "Add Parameter") { update(items + [("name", "value")]) }
        }
    }

    private func field(_ placeholder: String, _ i: Int, _ key: WritableKeyPath<(name: String, value: String), String>) -> some View {
        TextField(placeholder, text: Binding(get: { items[i][keyPath: key] }, set: { v in
            var it = items
            it[i][keyPath: key] = v
            update(it)
        }))
        .textFieldStyle(.roundedBorder)
        .font(.system(size: 12.5, design: .monospaced))
    }
}

// MARK: - Unix time

struct UnixTimePage: View {
    @Environment(Store.self) private var store
    @AppStorage("timeZone") private var zoneID = ""
    @AppStorage("timeZones") private var zones = "UTC,America/New_York,Europe/London,Asia/Tokyo"
    @AppStorage("pickerMillis") private var millis = false

    private var zone: TimeZone { TimeZone(identifier: zoneID) ?? .current }
    private var doc: Doc { store[doc: .unixTime] }
    private var date: Date? { TimeFormat.parse(doc.input) }

    var body: some View {
        ToolPage(tool: .unixTime, status: status, meta: meta) {
            CapsuleButton(title: "Now", systemImage: "clock.arrow.circlepath") { setDate(Date()) }
            HStack(spacing: 8) {
                Text("Date")
                // `set: { setDate($0) }`, not `set: setDate`: the method reference crashes Swift 6.3 IRGen.
                DatePicker("Date", selection: Binding(get: { date ?? Date() }, set: { setDate($0) }), displayedComponents: [.date, .hourAndMinute])
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .environment(\.timeZone, zone)
            }
            .optionCapsule()
            OptionSegments(title: "Produces", selection: $millis, options: [("Seconds", false), ("Milliseconds", true)])
            ZoneMenu(pick: { zoneID = $0 }) {
                HStack(spacing: 6) {
                    Text("Local zone")
                    Text(zone.identifier).foregroundStyle(Palette.text2)
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold)).foregroundStyle(Palette.text3)
                }
                .padding(.trailing, 8)
            }
            .optionCapsule()
        } content: {
            ScrollView {
                VStack(spacing: 14) {
                    LiveClock(zone: zone) { setDate($0) }
                    HStack(alignment: .top, spacing: 14) {
                        timestampPane
                        zonesPane
                    }
                    differencePane
                }
                .padding(.bottom, 8)
            }
            .scrollClipDisabled()
        }
    }

    private var status: Status? {
        guard !doc.input.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        return date == nil ? .error("Not a timestamp or date") : Status(text: "Valid")
    }

    private var meta: [String] {
        let s = doc.input.trimmingCharacters(in: .whitespaces)
        guard let date else { return ["Seconds, milliseconds, microseconds, ISO 8601, RFC 2822"] }
        let digits = s.split(separator: ".").first?.filter(\.isNumber).count ?? 0
        let unit = Double(s) == nil ? "Date string" : digits <= 11 ? "Seconds" : digits <= 14 ? "Milliseconds" : digits <= 17 ? "Microseconds" : "Nanoseconds"
        return [unit, TimeFormat.string(date, "EEEE", zone)]
    }

    private func setDate(_ d: Date) {
        let t = d.timeIntervalSince1970
        store[doc: .unixTime].input = millis ? String(format: "%.0f", (t * 1000).rounded(.down)) : String(format: "%.0f", t.rounded(.down))
    }

    private var timestampPane: some View {
        Pane("Timestamp") {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Unix time, ISO 8601 or RFC 2822", text: Binding(get: { doc.input }, set: { store[doc: .unixTime].input = $0 }))
                    .textFieldStyle(.plain)
                    .font(.system(size: 22, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                if let date {
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        DetailRows(rows: TimeFormat.rows(date, zone: zone, now: context.date))
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                } else {
                    Text(doc.input.isEmpty ? "Type a timestamp, pick a date above, or click Now." : "Not a timestamp or date.")
                        .foregroundStyle(doc.input.isEmpty ? Palette.text4 : .red)
                        .padding(18)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var zonesPane: some View {
        let ids = zones.split(separator: ",").map(String.init)
        return Pane("Time Zones") {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let shown = date ?? context.date
                VStack(spacing: 0) {
                    ForEach(Array(ids.enumerated()), id: \.element) { i, id in
                        if let tz = TimeZone(identifier: id) {
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(id.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? id)
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("\(tz.abbreviation(for: shown) ?? "") · UTC\(TimeFormat.string(shown, "xxx", tz))")
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(Palette.text3)
                                }
                                Spacer(minLength: 8)
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(TimeFormat.string(shown, "HH:mm:ss", tz)).font(.system(size: 15, weight: .medium, design: .monospaced))
                                    Text(TimeFormat.string(shown, "EEE d MMM yyyy", tz)).font(.system(size: 11.5)).foregroundStyle(Palette.text3)
                                }
                                IconButton(systemImage: "xmark", help: "Remove \(id)") {
                                    zones = ids.filter { $0 != id }.joined(separator: ",")
                                }
                            }
                            .padding(.horizontal, 18)
                            .frame(height: 52)
                            if i < ids.count - 1 { Rectangle().fill(Palette.cardSeparator).frame(height: 1).padding(.leading, 18) }
                        }
                    }
                    if ids.isEmpty {
                        Text("Add time zones with the + button.").foregroundStyle(Palette.text4).padding(18)
                    }
                }
            }
        } accessory: {
            ZoneMenu(pick: { id in if !ids.contains(id) { zones = (ids + [id]).joined(separator: ",") } }) {
                Image(systemName: "plus").font(.system(size: 12.5, weight: .medium)).foregroundStyle(Palette.icon)
            }
            .help("Add Time Zone")
            .padding(.trailing, 6)
        }
        .frame(width: 360)
    }

    private var differencePane: some View {
        let other = TimeFormat.parse(doc.aux)
        return Pane("Difference") {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 12) {
                    Text("Compare with").foregroundStyle(Palette.text3)
                    TextField("Another timestamp or date", text: Binding(get: { doc.aux }, set: { store[doc: .unixTime].aux = $0 }))
                        .textFieldStyle(.plain)
                        .font(.system(size: 17, weight: .medium, design: .monospaced))
                    Button("Now") { store[doc: .unixTime].aux = String(Int(Date().timeIntervalSince1970)) }.controlSize(.small)
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                if let date, let other {
                    let d = other.timeIntervalSince(date)
                    Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                    DetailRows(rows: [
                        Detail("Duration", TimeFormat.duration(d) + (d == 0 ? "" : d > 0 ? " later" : " earlier")),
                        Detail("Seconds", String(format: "%.0f", d)),
                        Detail("Minutes", String(format: "%.2f", d / 60)),
                        Detail("Hours", String(format: "%.2f", d / 3600)),
                        Detail("Days", String(format: "%.3f", d / 86_400)),
                        Detail("Other date", TimeFormat.string(other, "EEE, d MMM yyyy HH:mm:ss", zone)),
                    ])
                    .padding(.horizontal, 18)
                    .padding(.vertical, 6)
                } else if !doc.aux.isEmpty, other == nil {
                    Text("Not a timestamp or date.").foregroundStyle(.red).padding(.horizontal, 18).padding(.bottom, 12)
                }
            }
        }
    }
}

struct LiveClock: View {
    let zone: TimeZone
    let use: (Date) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.05)) { context in
            let t = context.date.timeIntervalSince1970
            HStack(alignment: .center, spacing: 36) {
                block("Seconds", String(format: "%.0f", t.rounded(.down)))
                block("Milliseconds", String(format: "%.0f", (t * 1000).rounded(.down)))
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(TimeFormat.string(context.date, "HH:mm:ss", zone)).font(.system(size: 28, weight: .medium, design: .monospaced))
                    Text("\(TimeFormat.string(context.date, "EEE d MMM", zone)) · \(zone.identifier)").font(.system(size: 12)).foregroundStyle(Palette.text3)
                }
                Button("Use Now") { use(context.date) }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 18)
        }
        .card()
    }

    private func block(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).tracking(0.8).textCase(.uppercase).foregroundStyle(Palette.text3)
            HStack(spacing: 6) {
                Text(value).font(.system(size: 30, weight: .semibold, design: .monospaced)).monospacedDigit().lineLimit(1).fixedSize()
                IconButton(systemImage: "doc.on.doc", help: "Copy \(label)") { Output.copy(value) }
            }
        }
    }
}

/// Time zones grouped by region, as nested menus.
struct ZoneMenu<Label: View>: View {
    let pick: (String) -> Void
    @ViewBuilder let label: Label

    static var regions: [(String, [String])] {
        Dictionary(grouping: TimeZone.knownTimeZoneIdentifiers) { $0.split(separator: "/").first.map(String.init) ?? $0 }
            .map { ($0.key, $0.value.sorted()) }
            .sorted { $0.0 < $1.0 }
    }

    var body: some View {
        Menu {
            Button("UTC") { pick("UTC") }
            Button("System (\(TimeZone.current.identifier))") { pick(TimeZone.current.identifier) }
            Divider()
            ForEach(Self.regions, id: \.0) { region, ids in
                Menu(region) {
                    ForEach(ids, id: \.self) { id in
                        Button(id.split(separator: "/").dropFirst().joined(separator: " / ").replacingOccurrences(of: "_", with: " ")) { pick(id) }
                    }
                }
            }
        } label: {
            label
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - JWT

struct JWTPage: View {
    @Environment(Store.self) private var store

    private var doc: Doc { store[doc: .jwt] }

    var body: some View {
        @Bindable var store = store
        let parsed = Result { try JWT(doc.input) }
        let jwt = try? parsed.get()
        ToolPage(tool: .jwt, status: status(parsed), meta: meta(jwt)) {
            HStack(spacing: 8) {
                Image(systemName: "key").foregroundStyle(Palette.icon)
                TextField("HMAC secret to check the signature", text: $store[doc: .jwt].aux)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, design: .monospaced))
                    .frame(width: 280)
            }
            .padding(.horizontal, 14)
            .frame(height: 32)
            .glassCapsule()
            if let jwt { signatureBadge(jwt) }
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Token", text: $store[doc: .jwt].input,
                           placeholder: "Paste a JWT (eyJ…). The header, payload and signature are decoded locally.",
                           marks: marks, footer: doc.input.isEmpty ? nil : parsed.failure.map { AnyView(ErrorBar(message: "\($0)")) }, forceWrap: true)
                    .frame(maxWidth: 420)
                if let jwt {
                    ScrollView {
                        VStack(spacing: 14) {
                            claims(jwt)
                            jsonPane("Header", jwt.header)
                            jsonPane("Payload", jwt.payload)
                        }
                        .padding(.bottom, 8)
                    }
                    .scrollClipDisabled()
                } else {
                    Pane("Decoded") {
                        Text("Header, payload and claims appear here.").foregroundStyle(Palette.text4)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
    }

    private func status(_ r: Result<JWT, Error>) -> Status? {
        guard !doc.input.isEmpty else { return nil }
        guard case .success(let jwt) = r else { return .error("Not a JWT") }
        let now = Date()
        if let exp = jwt.date("exp"), exp < now { return .error("Expired \(exp.formatted(.relative(presentation: .named)))") }
        if let nbf = jwt.date("nbf"), nbf > now { return .warning("Not valid until \(nbf.formatted(date: .abbreviated, time: .shortened))") }
        if let exp = jwt.date("exp") { return Status(text: "Valid, expires \(exp.formatted(.relative(presentation: .named)))") }
        return Status(text: "Decoded, no expiry")
    }

    private func meta(_ jwt: JWT?) -> [String] {
        guard let jwt else { return ["HS256, HS384 and HS512 signatures can be checked"] }
        var m = [jwt.algorithm ?? "No algorithm"]
        if case .string(let typ)? = jwt.claim("typ", in: jwt.header) { m.append(typ) }
        m.append("\(jwt.signature.count)-byte signature")
        return m
    }

    @ViewBuilder private func signatureBadge(_ jwt: JWT) -> some View {
        let secret = doc.aux
        let (text, color): (String, Color) = switch secret.isEmpty ? nil : jwt.verify(secret: secret) {
        case true?: ("Signature verified", Palette.ok)
        case false?: ("Invalid signature", .red)
        case nil: (secret.isEmpty ? "Signature not checked" : "\(jwt.algorithm ?? "This algorithm") needs a public key", Palette.text2)
        }
        HStack(spacing: 6) {
            Image(systemName: color == Palette.ok ? "checkmark.seal.fill" : color == .red ? "xmark.seal.fill" : "seal")
            Text(text).fontWeight(.medium)
        }
        .foregroundStyle(color)
        .font(.system(size: 12.5))
        .padding(.horizontal, 14)
        .frame(height: 32)
        .glassCapsule()
    }

    /// Header, payload and signature tinted like jwt.io.
    private var marks: [EditorMark] {
        let ns = doc.input as NSString
        var marks: [EditorMark] = []
        var start = 0
        let colors: [NSColor] = [.systemRed, .systemPurple, .systemBlue]
        for color in colors {
            guard start <= ns.length else { break }
            let dot = ns.range(of: ".", range: NSRange(location: start, length: ns.length - start))
            let end = dot.location == NSNotFound ? ns.length : dot.location
            marks.append(EditorMark(range: NSRange(location: start, length: end - start), color: color.withAlphaComponent(0.13)))
            start = end + 1
        }
        return marks
    }

    private func claims(_ jwt: JWT) -> some View {
        let names = ["iss": "Issuer", "sub": "Subject", "aud": "Audience", "exp": "Expires", "nbf": "Not before", "iat": "Issued at", "jti": "Token ID"]
        let rows: [Detail] = ["iss", "sub", "aud", "exp", "nbf", "iat", "jti"].compactMap { key in
            guard let v = jwt.claim(key) else { return nil }
            if let d = jwt.date(key), ["exp", "nbf", "iat"].contains(key) {
                return Detail(names[key]!, "\(d.formatted(date: .abbreviated, time: .standard)) (\(d.formatted(.relative(presentation: .named))))")
            }
            if case .string(let s) = v { return Detail(names[key]!, s) }
            return Detail(names[key]!, v.formatted(indent: nil))
        }
        return Pane("Claims") {
            if rows.isEmpty {
                Text("No registered claims.").foregroundStyle(Palette.text4).padding(18).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                DetailRows(rows: rows, mono: false).padding(.horizontal, 18).padding(.vertical, 6)
            }
        }
    }

    private func jsonPane(_ title: String, _ value: JSONValue) -> some View {
        let text = value.formatted(indent: "  ")
        return Pane(title) {
            CodeBlock(text: text).padding(18)
        } accessory: {
            IconButton(systemImage: "doc.on.doc", help: "Copy \(title)") { Output.copy(text) }
        }
    }
}

extension Result {
    var failure: Failure? {
        if case .failure(let e) = self { return e }
        return nil
    }
}

// MARK: - UUID / ULID

struct UUIDPage: View {
    @Environment(Store.self) private var store
    @AppStorage("idKind") private var kind = "v4"
    @AppStorage("idCount") private var count = 10
    @AppStorage("idUppercase") private var uppercase = false
    @AppStorage("idHyphens") private var hyphens = true
    @State private var generated = ""

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .uuid].input
        let rows = IDs.inspect(input)
        ToolPage(tool: .uuid, status: input.isEmpty ? nil : rows.map { Status(text: "\($0[0].value) · \($0.first { $0.label == "Version" }?.value ?? "valid")") } ?? .error("Not a UUID or ULID"),
                 meta: ["\(count) × \(name)"]) {
            OptionSegments(selection: $kind, options: [("UUID v4", "v4"), ("UUID v7", "v7"), ("ULID", "ulid")])
            HStack(spacing: 8) {
                Text("Count")
                TextField("Count", value: $count, format: .number)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 40)
                Stepper("Count", value: $count, in: 1...1000).labelsHidden()
            }
            .optionCapsule()
            OptionToggle(title: "Uppercase", isOn: $uppercase)
            if kind != "ulid" { OptionToggle(title: "Hyphens", isOn: $hyphens) }
            CapsuleButton(title: "Generate", systemImage: "arrow.clockwise", selected: true) { generate() }
                .keyboardShortcut(.return, modifiers: .command)
        } content: {
            HStack(spacing: 14) {
                Pane("Inspect") {
                    VStack(alignment: .leading, spacing: 0) {
                        TextField("Paste a UUID or ULID", text: $store[doc: .uuid].input)
                            .textFieldStyle(.plain)
                            .font(.system(size: 15, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 14)
                        Rectangle().fill(Palette.cardSeparator).frame(height: 1)
                        if let rows {
                            DetailRows(rows: rows).padding(.horizontal, 18).padding(.vertical, 6)
                        } else {
                            Text(input.isEmpty ? "Version, variant and the embedded timestamp (v1, v6, v7, ULID) appear here." : "Not a UUID or ULID.")
                                .foregroundStyle(input.isEmpty ? Palette.text4 : .red)
                                .padding(18)
                        }
                        Spacer(minLength: 0)
                    }
                }
                EditorPane(title: "Generated", text: .constant(generated), editable: false, output: true, primary: true)
            }
        }
        .onAppear(perform: generate)
        .onChange(of: kind) { generate() }
        .onChange(of: count) { generate() }
        .onChange(of: uppercase) { generate() }
        .onChange(of: hyphens) { generate() }
    }

    private var name: String { kind == "ulid" ? "ULID" : "UUID \(kind)" }

    private func generate() {
        let n = min(max(count, 1), 1000)
        generated = (0..<n).map { _ in
            var id = kind == "v7" ? IDs.uuidV7() : kind == "ulid" ? IDs.ulid() : IDs.uuidV4()
            if kind != "ulid" && !hyphens { id = id.replacingOccurrences(of: "-", with: "") }
            return uppercase ? id.uppercased() : (kind == "ulid" ? id : id.lowercased())
        }.joined(separator: "\n")
    }
}

// MARK: - Passwords

struct PasswordPage: View {
    @AppStorage("pwLength") private var length = 20
    @AppStorage("pwUpper") private var upper = true
    @AppStorage("pwLower") private var lower = true
    @AppStorage("pwDigits") private var digits = true
    @AppStorage("pwSymbols") private var symbols = true
    @AppStorage("pwAmbiguous") private var avoidAmbiguous = false
    @AppStorage("pwCount") private var count = 8
    @State private var passwords: [String] = []

    private var options: Password.Options {
        var o = Password.Options()
        o.length = length
        o.upper = upper
        o.lower = lower
        o.digits = digits
        o.symbols = symbols
        o.avoidAmbiguous = avoidAmbiguous
        return o
    }

    var body: some View {
        let bits = Password.entropy(options)
        ToolPage(tool: .password, status: strength(bits), meta: ["\(Int(bits)) bits of entropy", "System CSPRNG"]) {
            HStack(spacing: 10) {
                Text("Length")
                Slider(value: Binding(get: { Double(length) }, set: { length = Int($0) }), in: 4...128, step: 1).frame(width: 150)
                Text("\(length)").monospacedDigit().frame(width: 28, alignment: .trailing)
            }
            .padding(.trailing, 8)
            .optionCapsule()
            OptionToggle(title: "A–Z", isOn: $upper)
            OptionToggle(title: "a–z", isOn: $lower)
            OptionToggle(title: "0–9", isOn: $digits)
            OptionToggle(title: "!#$", isOn: $symbols)
            OptionToggle(title: "Avoid look-alikes", isOn: $avoidAmbiguous)
            HStack(spacing: 8) {
                Text("Count")
                Stepper("\(count)", value: $count, in: 1...100)
            }
            .optionCapsule()
            CapsuleButton(title: "Generate", systemImage: "arrow.clockwise", selected: true) { generate() }
                .keyboardShortcut(.return, modifiers: .command)
        } content: {
            VStack(spacing: 14) {
                if let first = passwords.first {
                    HStack(spacing: 16) {
                        Text(first)
                            .font(.system(size: 26, weight: .medium, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        Spacer(minLength: 12)
                        Button("Copy") { Output.copy(first) }.prominentCapsule()
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .overlay(alignment: .bottom) {
                        GeometryReader { g in
                            Rectangle().fill(color(bits)).frame(width: g.size.width * min(bits / 128, 1), height: 3)
                        }
                        .frame(height: 3)
                    }
                    .card()
                }
                EditorPane(title: "Passwords", text: .constant(passwords.joined(separator: "\n")), editable: false, output: true, primary: true)
            }
        }
        .onAppear(perform: generate)
        .onChange(of: options) { generate() }
        .onChange(of: count) { generate() }
    }

    private func generate() { passwords = (0..<count).map { _ in Password.generate(options) } }

    private func strength(_ bits: Double) -> Status {
        switch bits {
        case 0: .error("Choose at least one character set")
        case ..<50: .error("Weak")
        case ..<80: .warning("Fair")
        case ..<110: Status(text: "Strong")
        default: Status(text: "Very strong")
        }
    }

    private func color(_ bits: Double) -> Color { bits < 50 ? .red : bits < 80 ? .orange : Palette.okDot }
}

// MARK: - CSV ↔ JSON

struct CSVPage: View {
    @Environment(Store.self) private var store
    @AppStorage("csvDelimiter") private var delimiterChoice = "auto"
    @AppStorage("csvHeader") private var header = true
    @AppStorage("csvInfer") private var infer = true
    @AppStorage("indent") private var indent: Indent = .two
    @State private var error: String?

    private var doc: Doc { store[doc: .csv] }

    private func delimiter(_ csv: String) -> Character {
        switch delimiterChoice {
        case "comma": ","
        case "semicolon": ";"
        case "tab": "\t"
        case "pipe": "|"
        default: CSV.detectDelimiter(csv)
        }
    }

    var body: some View {
        let rows = CSV.parse(doc.input, delimiter: delimiter(doc.input))
        ToolPage(tool: .csv, status: error.map(Status.error) ?? (rows.isEmpty ? nil : Status(text: "Converted")),
                 meta: rows.isEmpty ? ["RFC 4180 CSV", "Arrays of objects or arrays"] : ["\(max(rows.count - (header ? 1 : 0), 0)) rows", "\(rows.map(\.count).max() ?? 0) columns", "Delimiter \(name(delimiter(doc.input)))"]) {
            OptionMenu(title: "Delimiter", selection: $delimiterChoice, options: [("Auto", "auto"), ("Comma", "comma"), ("Semicolon", "semicolon"), ("Tab", "tab"), ("Pipe", "pipe")])
            OptionToggle(title: "Header row", isOn: $header)
            OptionToggle(title: "Detect numbers", isOn: $infer)
            OptionSegments(title: "Indent", selection: $indent, options: [("2", .two), ("4", .four), ("Tab", .tab)])
        } content: {
            VStack(spacing: 14) {
                HStack(spacing: 14) {
                    EditorPane(title: "CSV", text: Binding(get: { doc.input }, set: fromCSV),
                               placeholder: "Paste CSV (comma, semicolon, tab or pipe separated).", output: false)
                    EditorPane(title: "JSON", text: Binding(get: { doc.aux }, set: fromJSON),
                               placeholder: "Or paste a JSON array to turn it into CSV.", syntax: .json, output: true, primary: true, fileExtension: "json",
                               footer: error.map { AnyView(ErrorBar(message: $0)) })
                }
                TablePreview(rows: rows, header: header)
            }
        }
        .onChange(of: [delimiterChoice, indent.rawValue, "\(header)\(infer)"]) { fromCSV(doc.input) }
        .onAppear { if doc.aux.isEmpty, !doc.input.isEmpty { fromCSV(doc.input) } }
    }

    private func name(_ c: Character) -> String {
        switch c {
        case "\t": "tab"
        case ";": "semicolon"
        case "|": "pipe"
        default: "comma"
        }
    }

    private func fromCSV(_ csv: String) {
        error = nil
        let json = csv.isEmpty ? "" : CSV.json(CSV.parse(csv, delimiter: delimiter(csv)), header: header, inferTypes: infer).formatted(indent: indent.unit)
        store[doc: .csv] = Doc(input: csv, aux: json)
    }

    private func fromJSON(_ json: String) {
        guard !json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            error = nil
            store[doc: .csv] = Doc()
            return
        }
        do {
            let rows = try CSV.rows(try JSONValue.parseLoose(json).value)
            error = nil
            let d: Character = delimiterChoice == "auto" ? "," : delimiter("")
            store[doc: .csv] = Doc(input: CSV.write(rows, delimiter: d), aux: json)
        } catch {
            self.error = "\(error)"
            store[doc: .csv].aux = json
        }
    }
}

struct TablePreview: View {
    let rows: [[String]]
    let header: Bool

    var body: some View {
        let columns = rows.map(\.count).max() ?? 0
        let head = header ? rows.first : nil
        let body = Array(rows.dropFirst(header ? 1 : 0).prefix(1000))
        let widths = (0..<columns).map { c in
            CGFloat(min(max(rows.prefix(200).map { c < $0.count ? $0[c].count : 0 }.max() ?? 0, 4), 48)) * 8.2 + 30
        }
        Pane("Table") {
            if rows.isEmpty {
                Text("A table preview of the CSV appears here.").foregroundStyle(Palette.text4).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView([.vertical, .horizontal]) {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(body.indices, id: \.self) { i in
                                row(body[i], widths: widths, bold: false)
                                    .background(i % 2 == 1 ? Palette.cardFoot : Palette.card)
                            }
                        } header: {
                            if let head {
                                row(head, widths: widths, bold: true)
                                    .background(Palette.card)
                                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.hairline).frame(height: 1) }
                            }
                        }
                    }
                }
                .defaultScrollAnchor(.topLeading)
            }
        } accessory: {
            if !rows.isEmpty {
                Text(body.count < rows.count - (header ? 1 : 0) ? "First 1,000 rows" : "\(body.count) rows")
                    .font(.system(size: 11.5)).foregroundStyle(Palette.text4).padding(.trailing, 8)
            }
        }
    }

    private func row(_ cells: [String], widths: [CGFloat], bold: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(widths.indices, id: \.self) { c in
                Text(c < cells.count ? cells[c] : "")
                    .font(.system(size: 12.5, weight: bold ? .semibold : .regular, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 12)
                    .frame(width: widths[c], height: 30, alignment: .leading)
                    .overlay(alignment: .trailing) { Rectangle().fill(Palette.cardSeparator).frame(width: 1) }
            }
        }
    }
}
