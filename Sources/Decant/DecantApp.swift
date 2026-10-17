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
                .frame(minWidth: 860, minHeight: 520)
        }
        .defaultSize(width: 1240, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New") { store.newDocument() }.keyboardShortcut("n")
            }
        }

        Settings {
            SettingsView().preferredColorScheme(scheme)
        }
    }

    private var scheme: ColorScheme? { darkMode.map { $0 ? .dark : .light } }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare SwiftPM executable rather than a bundled .app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

struct Entry: Codable, Identifiable, Hashable {
    var id = UUID()
    var date = Date()
    var input: String
    var format: Format
    var title: String
}

enum Tool: String, CaseIterable, Identifiable, Hashable {
    case json = "JSON Formatter", base64 = "Base64", unixTime = "Unix Time"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .json: "curlybraces"
        case .base64: "doc.text"
        case .unixTime: "clock"
        }
    }

    var format: Format {
        switch self {
        case .json: .json
        case .base64: .base64
        case .unixTime: .unixTime
        }
    }
}

enum SidebarItem: Hashable { case new, entry(UUID), tool(Tool) }

@MainActor @Observable
final class Store {
    var entries: [Entry] = []
    var sidebar: SidebarItem? = .new
    var input = "" { didSet { if input != oldValue { refresh(); record() } } }
    var options = Options() { didSet { refresh() } }
    var target: Target?
    private(set) var result: Conversion?
    private var force: Format?
    private var currentID: UUID?
    private let fileURL = URL.applicationSupportDirectory.appending(path: "Decant/history.json")

    init() {
        if let data = try? Data(contentsOf: fileURL), let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = saved
        }
    }

    var output: String {
        guard let result else { return "" }
        return target.map { Engine.apply($0, to: result) } ?? result.text
    }

    var outputFormat: Format? { target?.format ?? result?.output }

    var title: String {
        let full = result?.title ?? (input.isEmpty ? "New" : String(input.prefix { $0 != "\n" }))
        return full.count > 40 ? full.prefix(40) + "…" : full
    }

    var subtitle: String {
        guard let result else { return "No format detected" }
        return "\(result.input.name) → \(target?.rawValue ?? result.output.name)"
    }

    func newDocument() {
        sidebar = .new
        start(force: nil)
    }

    func select(_ item: SidebarItem?) {
        switch item {
        case .new?, nil:
            start(force: nil)
        case .tool(let tool)?:
            start(force: tool.format)
        case .entry(let id)?:
            guard id != currentID, let entry = entries.first(where: { $0.id == id }) else { return }
            currentID = id
            force = nil
            target = nil
            input = entry.input
            refresh()
        }
    }

    func delete(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        if currentID == entry.id { newDocument() }
        save()
    }

    func copyOutput() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(output, forType: .string)
    }

    private func start(force: Format?) {
        currentID = nil
        target = nil
        self.force = force
        input = ""
        refresh()
    }

    private func refresh() {
        result = Engine.convert(input, options: options, force: force)
        if let target, result?.targets.contains(target) != true { self.target = nil }
    }

    /// The open document is a history entry once it converts; later edits update that entry.
    private func record() {
        guard let result else { return }
        if let i = entries.firstIndex(where: { $0.id == currentID }) {
            entries[i].input = input
            entries[i].format = result.input
            entries[i].title = result.title
        } else {
            let entry = Entry(input: input, format: result.input, title: result.title)
            entries.insert(entry, at: 0)
            entries = Array(entries.prefix(200))
            currentID = entry.id
            sidebar = .entry(entry.id)
        }
        save()
    }

    // ponytail: rewrites the whole file on every edit; debounce or move to SwiftData if history gets large.
    private func save() {
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(entries).write(to: fileURL, options: .atomic)
    }
}
