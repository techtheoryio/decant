import AppKit
import DecantCore
import SwiftUI

@main
struct DecantApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @State private var store = Store()
    @AppStorage("darkMode") private var darkMode: Bool?

    var body: some Scene {
        Window("Decant", id: "main") {
            ContentView()
                .environment(store)
                .preferredColorScheme(scheme)
                .frame(minWidth: 900, minHeight: 560)
        }
        .defaultSize(width: 1280, height: 820)
        .commands { AppCommands(store: store) }

        Settings {
            SettingsView().environment(store).preferredColorScheme(scheme)
        }
    }

    private var scheme: ColorScheme? { darkMode.map { $0 ? .dark : .light } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable rather than a bundled .app.
        NSApp.setActivationPolicy(.regular)
        if let url = Bundle.module.url(forResource: "AppIcon", withExtension: "icns") {
            NSApp.applicationIconImage = NSImage(contentsOf: url)
        }
        NSApp.activate()
        Task.detached { _ = ExternalFormatters.shared }  // the login-shell lookup takes a moment; warm it up
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

// MARK: - Commands

/// Output commands go to whichever output pane is marked primary on the current page.
enum OutputCommand: String { case find, save, copy }

extension Notification.Name {
    static let outputCommand = Notification.Name("DecantOutputCommand")
    static let copied = Notification.Name("DecantCopied")
}

func post(_ command: OutputCommand) {
    NotificationCenter.default.post(name: .outputCommand, object: command.rawValue)
}

struct AppCommands: Commands {
    let store: Store
    @AppStorage("toolOrder") private var order = ""
    @AppStorage("hiddenTools") private var hidden = ""
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("wrapLines") private var wrap = false

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New") { store.newDocument() }.keyboardShortcut("n")
            Button("Open File…") { store.importing = true }.keyboardShortcut("o")
        }
        CommandGroup(replacing: .saveItem) {
            Button("Save Output…") { post(.save) }.keyboardShortcut("s")
            Button("Copy Output") { post(.copy) }.keyboardShortcut("c", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find in Output…") { post(.find) }.keyboardShortcut("f")
            Button("Find Next") { finder(.nextMatch) }.keyboardShortcut("g")
            Button("Find Previous") { finder(.previousMatch) }.keyboardShortcut("g", modifiers: [.command, .shift])
        }
        CommandGroup(after: .toolbar) {
            Button("Increase Font Size") { fontSize = min(fontSize + 1, 32) }.keyboardShortcut("+")
            Button("Decrease Font Size") { fontSize = max(fontSize - 1, 9) }.keyboardShortcut("-")
            Button("Default Font Size") { fontSize = 13 }.keyboardShortcut("0")
            Toggle("Wrap Lines", isOn: $wrap).keyboardShortcut("z", modifiers: [.option])
            Divider()
        }
        CommandMenu("Tools") {
            Button("Command Palette…") { store.showPalette = true }.keyboardShortcut("k")
            Divider()
            let tools = ToolLayout.visible(order: order, hidden: hidden)
            ForEach(Array(tools.enumerated()), id: \.element) { i, tool in
                if i < 9 {
                    Button(tool.name) { store.open(tool) }.keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                } else {
                    Button(tool.name) { store.open(tool) }
                }
            }
        }
    }

    private func finder(_ action: NSTextFinder.Action) {
        let item = NSMenuItem()
        item.tag = action.rawValue
        NSApp.sendAction(#selector(NSTextView.performTextFinderAction(_:)), to: nil, from: item)
    }
}

// MARK: - Tools

enum Category: String, CaseIterable {
    case format = "Format", encoding = "Encoding", time = "Time", security = "Tokens & Security", data = "Data", text = "Text", misc = "Miscellaneous"
}

enum Tool: String, CaseIterable, Identifiable, Codable, Hashable {
    case detect, formatter, base64, url, unixTime, cron, jwt, uuid, password, csv, diff, regex, counter, markdown, color, qr

    var id: String { rawValue }

    var name: String {
        switch self {
        case .detect: "Auto Detect"
        case .formatter: "Formatter"
        case .base64: "Base64"
        case .url: "URL Encode"
        case .unixTime: "Unix Time"
        case .cron: "Cron"
        case .jwt: "JWT Decoder"
        case .uuid: "UUID / ULID"
        case .password: "Passwords"
        case .csv: "CSV ↔ JSON"
        case .diff: "Diff"
        case .regex: "Regex"
        case .counter: "Counter"
        case .markdown: "Markdown"
        case .color: "Color"
        case .qr: "QR Code"
        }
    }

    var icon: String {
        switch self {
        case .detect: "square.and.pencil"
        case .formatter: "curlybraces"
        case .base64: "doc.text"
        case .url: "link"
        case .unixTime: "clock"
        case .cron: "calendar.badge.clock"
        case .jwt: "key"
        case .uuid: "number"
        case .password: "lock"
        case .csv: "tablecells"
        case .diff: "plusminus"
        case .regex: "asterisk"
        case .counter: "textformat.123"
        case .markdown: "doc.richtext"
        case .color: "paintpalette"
        case .qr: "qrcode"
        }
    }

    var category: Category {
        switch self {
        case .detect, .formatter, .markdown: .format
        case .base64, .url: .encoding
        case .unixTime, .cron: .time
        case .jwt, .uuid, .password: .security
        case .csv: .data
        case .diff, .regex, .counter: .text
        case .color, .qr: .misc
        }
    }

    /// Generators have nothing worth keeping.
    var keepsHistory: Bool { self != .uuid && self != .password }

    var dot: Color {
        switch category {
        case .format: Color(0xD99A1E, 0xD99A1E)
        case .encoding: Color(0x2E9A68, 0x2E9A68)
        case .time: Color(0xC8467A, 0xC8467A)
        case .security: Color(0x8A5CD6, 0x8A5CD6)
        case .data: Color(0x3B78E0, 0x3B78E0)
        case .text: Color(0x2AA0A8, 0x2AA0A8)
        case .misc: Color(0xD9622B, 0xD9622B)
        }
    }

    static let sidebarTools = allCases.filter { $0 != .detect }
}

/// Sidebar order and visibility, stored as comma-separated raw values.
enum ToolLayout {
    static func ordered(_ order: String) -> [Tool] {
        let saved = order.split(separator: ",").compactMap { Tool(rawValue: String($0)) }.filter { $0 != .detect }
        return saved + Tool.sidebarTools.filter { !saved.contains($0) }
    }

    static func hiddenSet(_ hidden: String) -> Set<Tool> {
        Set(hidden.split(separator: ",").compactMap { Tool(rawValue: String($0)) })
    }

    static func visible(order: String, hidden: String) -> [Tool] {
        let h = hiddenSet(hidden)
        return ordered(order).filter { !h.contains($0) }
    }

    static func encode(_ tools: some Sequence<Tool>) -> String { tools.map(\.rawValue).joined(separator: ",") }
}

// MARK: - History

struct Entry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var tool: Tool = .detect
    var input: String
    var aux = ""
    var format: Format = .text
    var title: String
    var pinned = false
    var renamed = false

    init(tool: Tool, input: String, aux: String, format: Format, title: String) {
        self.tool = tool
        self.input = input
        self.aux = aux
        self.format = format
        self.title = title
    }

    // Older history files only have id, date, input, format and title.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        date = try c.decode(Date.self, forKey: .date)
        input = try c.decode(String.self, forKey: .input)
        title = try c.decode(String.self, forKey: .title)
        format = (try? c.decode(Format.self, forKey: .format)) ?? .text
        tool = (try? c.decodeIfPresent(Tool.self, forKey: .tool)) ?? .detect
        aux = try c.decodeIfPresent(String.self, forKey: .aux) ?? ""
        pinned = try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false
        renamed = try c.decodeIfPresent(Bool.self, forKey: .renamed) ?? false
    }

    var dot: Color { tool == .detect ? Palette.dot(format) : tool.dot }
}

/// A tool's working text: `input` is the main editor, `aux` the second field (Base64 side, pattern, secret, right-hand diff…).
struct Doc: Equatable {
    var input = ""
    var aux = ""
}

@MainActor @Observable
final class Store {
    var entries: [Entry] = []
    private(set) var tool: Tool = .detect
    private var docs: [Tool: Doc] = [:]
    /// The history entry each tool's document is saved into.
    private var linked: [Tool: UUID] = [:]
    var showPalette = false
    var importing = false
    /// A file opened or dropped while a tool that handles binary files (Base64, QR) is showing.
    var pendingFile: URL?
    var detectOptions = Options()
    var detectTarget: Target?
    var detectResult: Conversion?
    private var pendingRecord: (tool: Tool, task: Task<Void, Never>)?
    private var saveTask: Task<Void, Never>?
    private let fileURL = URL.applicationSupportDirectory.appending(path: "Decant/history.json")

    init() {
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
        let d = UserDefaults.standard
        if let indent = d.string(forKey: "indent").flatMap(Indent.init(rawValue:)) { detectOptions.indent = indent }
        detectOptions.sortKeys = d.bool(forKey: "sortKeys")
        prune()
    }

    subscript(doc tool: Tool) -> Doc {
        get { docs[tool] ?? Doc() }
        set {
            guard newValue != docs[tool] ?? Doc() else { return }
            docs[tool] = newValue
            scheduleRecord(tool)
        }
    }

    var activeEntry: UUID? { linked[tool] }

    func open(_ tool: Tool) {
        flush()
        self.tool = tool
    }

    func open(_ entry: Entry) {
        flush()
        tool = entry.tool
        docs[entry.tool] = Doc(input: entry.input, aux: entry.aux)
        linked[entry.tool] = entry.id
        detectTarget = nil
    }

    /// Clears the current tool's document; the previous one stays in history.
    func newDocument() {
        flush()
        docs[tool] = Doc()
        linked[tool] = nil
        detectTarget = nil
    }

    func load(_ url: URL) {
        if tool == .base64 || tool == .qr {
            pendingFile = url
            return
        }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { NSSound.beep(); return }
        if tool == .uuid || tool == .password { tool = .detect }
        newDocument()
        self[doc: tool].input = text
    }

    // MARK: History

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        unlinkMissing()
        save()
    }

    func rename(_ entry: Entry, to title: String) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        entries[i].title = t.isEmpty ? entries[i].title : t
        entries[i].renamed = !t.isEmpty
        save()
    }

    func togglePin(_ entry: Entry) {
        guard let i = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[i].pinned.toggle()
        save()
    }

    func clearHistory() {
        entries.removeAll { !$0.pinned }
        unlinkMissing()
        save()
    }

    func prune() {
        let d = UserDefaults.standard
        let limit = d.object(forKey: "historyLimit") as? Int ?? 200
        let days = d.integer(forKey: "historyDays")
        let cutoff = days > 0 ? Date().addingTimeInterval(-Double(days) * 86_400) : .distantPast
        var kept = 0
        let before = entries.count
        entries = entries.filter { e in
            if e.pinned { return true }
            guard e.date >= cutoff, kept < limit else { return false }
            kept += 1
            return true
        }
        if entries.count != before { unlinkMissing(); save() }
    }

    private func unlinkMissing() {
        let ids = Set(entries.map(\.id))
        linked = linked.filter { ids.contains($0.value) }
    }

    private func scheduleRecord(_ tool: Tool) {
        guard tool.keepsHistory else { return }
        if let p = pendingRecord, p.tool != tool { flush() }
        pendingRecord?.task.cancel()
        pendingRecord = (tool, Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.record(tool)
        })
    }

    private func flush() {
        guard let p = pendingRecord else { return }
        p.task.cancel()
        record(p.tool)
    }

    /// The open document becomes a history entry once it has content; later edits update that entry.
    private func record(_ tool: Tool) {
        pendingRecord = nil
        let doc = self[doc: tool]
        guard !doc.input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var title = String(doc.input.trimmingCharacters(in: .whitespacesAndNewlines).prefix { $0 != "\n" }.prefix(60))
        var format = Format.text
        if tool == .detect, doc.input.utf8.count < 1_000_000, let r = Engine.convert(doc.input, options: detectOptions) {
            title = r.title
            format = r.input
        }
        if let id = linked[tool], let i = entries.firstIndex(where: { $0.id == id }) {
            entries[i].input = doc.input
            entries[i].aux = doc.aux
            entries[i].format = format
            entries[i].date = Date()
            if !entries[i].renamed { entries[i].title = title }
        } else {
            let entry = Entry(tool: tool, input: doc.input, aux: doc.aux, format: format, title: title)
            entries.insert(entry, at: 0)
            linked[tool] = entry.id
            prune()
        }
        save()
    }

    private func save() {
        guard ProcessInfo.processInfo.environment["DECANT_SNAPSHOT"] == nil else { return }  // debug snapshots leave history alone
        saveTask?.cancel()
        let entries = entries, url = fileURL
        saveTask = Task.detached(priority: .utility) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(entries).write(to: url, options: .atomic)
        }
    }
}
