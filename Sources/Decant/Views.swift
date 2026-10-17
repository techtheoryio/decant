import AppKit
import DecantCore
import SwiftUI

// MARK: - Palette (values from the design canvas)

extension Color {
    init(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

enum Palette {
    static let background = Color(0xFFFFFF, 0x1E1E1D)
    static let inputBackground = Color(0xFAF9F7, 0x191918)
    static let gutter = Color(0xBDB7AD, 0x5A5650)
    static let ok = Color(0x1C7A4A, 0x6FD39C)
    static let key = Color(0x4338CA, 0xA9ACFF)
    static let string = Color(0x1C6B47, 0x86D9AE)
    static let number = Color(0xB4530A, 0xF5B26B)
    static let punctuation = Color(0x8A8378, 0x8C867E)
    static let keyword = Color(0x9B2457, 0xFF8DB5)
    static let function = Color(0x1F4FA8, 0x86B8FF)

    static func color(for role: Role) -> Color {
        switch role {
        case .plain: .primary
        case .key: key
        case .string: string
        case .number, .type: number
        case .keyword: keyword
        case .function: function
        case .punctuation, .comment: punctuation
        }
    }

    static func badge(_ format: Format) -> (background: Color, foreground: Color) {
        switch format {
        case .json, .escapedJSON: (Color(0xFBEFD9, 0xD9940F, darkAlpha: 0.22), Color(0x8A5A00, 0xF3C66B))
        case .typescript, .javascript: (Color(0xE3EDFC, 0x3B78E0, darkAlpha: 0.26), Color(0x1F4FA8, 0x9CC2FF))
        case .base64: (Color(0xDDF2E8, 0x2E9A68, darkAlpha: 0.26), Color(0x1C6B47, 0x86D9AE))
        case .unixTime: (Color(0xFBE4EC, 0xC8467A, darkAlpha: 0.26), Color(0x9B2457, 0xF59BC0))
        case .text: (Color(0x000000, 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.08), Color(0x5F5951, 0xB0AAA2))
        }
    }
}

// MARK: - Small pieces

struct Badge: View {
    let format: Format
    var short = false

    var body: some View {
        let colors = Palette.badge(format)
        Text(short ? format.shortName : format.name.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, short ? 0 : 6)
            .padding(.vertical, 2)
            .frame(width: short ? 32 : nil)
            .foregroundStyle(colors.foreground)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct ShortcutHint: View {
    let keys: String
    init(_ keys: String) { self.keys = keys }
    var body: some View { Text(keys).font(.system(size: 11)).foregroundStyle(.tertiary) }
}

struct TintLabel: View {
    let title: String
    let icon: String
    var body: some View {
        Label { Text(title) } icon: { Image(systemName: icon).foregroundStyle(.tint) }
    }
}

// MARK: - Window

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var search = ""
    @State private var showInspector = true
    @State private var importing = false

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            SidebarView(search: search)
        } detail: {
            DetailView()
                .navigationTitle(store.title)
                .navigationSubtitle(store.subtitle)
                .toolbar { toolbar }
                .inspector(isPresented: Binding(get: { showInspector && store.result != nil }, set: { showInspector = $0 })) {
                    InspectorView().inspectorColumnWidth(min: 240, ideal: 280, max: 360)
                }
        }
        .searchable(text: $search, placement: .sidebar)
        .onChange(of: store.sidebar) { _, item in store.select(item) }
        #if DEBUG
        .task { await debugSnapshot() }
        #endif
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                store.newDocument()
                store.input = text
            }
        }
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var store = store
        ToolbarItemGroup(placement: .primaryAction) {
            if store.input.isEmpty {
                Button("Open File", systemImage: "folder") { importing = true }
            }
            if let r = store.result, r.output == .json, r.error == nil, store.target == nil {
                Picker("Output Style", selection: $store.options.minify) {
                    Text("Pretty").tag(false)
                    Text("Minified").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            if store.result != nil {
                Button { store.copyOutput() } label: {
                    Label("Copy Output", systemImage: "doc.on.doc").labelStyle(.titleAndIcon)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
            Button {
                showInspector.toggle()
            } label: {
                Label(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .disabled(store.result == nil)
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("darkMode") private var darkMode: Bool?
    let search: String

    var body: some View {
        @Bindable var store = store
        List(selection: $store.sidebar) {
            HStack {
                Label("New", systemImage: "square.and.pencil")
                Spacer()
                ShortcutHint("⌘N")
            }
            .tag(SidebarItem.new)

            if !filtered.isEmpty {
                Section("History") {
                    ForEach(filtered) { entry in
                        HStack(spacing: 8) {
                            Badge(format: entry.format, short: true)
                            Text(entry.title).lineLimit(1).truncationMode(.tail)
                        }
                        .tag(SidebarItem.entry(entry.id))
                        .contextMenu {
                            Button("Delete", role: .destructive) { store.delete(entry) }
                        }
                    }
                }
            }

            Section("Tools") {
                ForEach(Tool.allCases) { tool in
                    Label(tool.rawValue, systemImage: tool.icon).tag(SidebarItem.tool(tool))
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { footer }
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 320)
    }

    private var filtered: [Entry] {
        guard !search.isEmpty else { return store.entries }
        return store.entries.filter { $0.title.localizedCaseInsensitiveContains(search) || $0.input.localizedCaseInsensitiveContains(search) }
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider().padding(.horizontal, 16).padding(.bottom, 6)
            HStack {
                TintLabel(title: "Dark Mode", icon: "moon")
                Spacer()
                Toggle("Dark Mode", isOn: Binding(get: { darkMode ?? (colorScheme == .dark) }, set: { darkMode = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
            }
            .frame(height: 30)
            SettingsLink {
                HStack {
                    TintLabel(title: "Settings", icon: "gearshape")
                    Spacer()
                    ShortcutHint("⌘,")
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(height: 28)
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 10)
    }
}

// MARK: - Detail

struct DetailView: View {
    @Environment(Store.self) private var store
    @FocusState private var editorFocused: Bool

    var body: some View {
        @Bindable var store = store
        let empty = store.input.isEmpty
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                if !empty { PaneHeader(title: "Input", format: store.result?.input) }
                TextEditor(text: $store.input)
                    .font(.system(size: empty ? 13 : 12, design: .monospaced))
                    .foregroundStyle(empty ? .primary : .secondary)
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(empty ? .never : .automatic)
                    .focused($editorFocused)
                    .padding(.horizontal, 15)
                    .padding(.top, empty ? 16 : 0)
                    .padding(.bottom, empty ? 0 : 10)
            }
            .frame(maxWidth: .infinity, maxHeight: empty ? .infinity : 140)
            .background(empty ? Palette.background : Palette.inputBackground)
            .overlay {
                if empty { EmptyState { if let s = NSPasteboard.general.string(forType: .string) { store.input = s } } }
            }

            if !empty {
                Divider()
                OutputPane()
            }
            StatusBar()
        }
        .background(Palette.background)
        .onAppear { editorFocused = true }
    }
}

struct EmptyState: View {
    let paste: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("No Input", systemImage: "doc.on.clipboard")
        } description: {
            Text("Paste, open a file or start typing. The format is detected and converted automatically.")
        } actions: {
            Button(action: paste) {
                HStack(spacing: 8) {
                    Text("Paste from Clipboard")
                    ShortcutHint("⌘V")
                }
            }
        }
    }
}

struct PaneHeader: View {
    let title: String
    var format: Format?
    var status: String?
    var error: String?

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            if let format { Badge(format: format) }
            Spacer()
            if let error {
                Label(error, systemImage: "xmark").foregroundStyle(.red)
            } else if let status {
                Label(status, systemImage: "checkmark").foregroundStyle(Palette.ok)
            }
        }
        .font(.system(size: 11, weight: .medium))
        .padding(.horizontal, 20)
        .frame(height: 30)
    }
}

struct OutputPane: View {
    @Environment(Store.self) private var store

    var body: some View {
        if let r = store.result {
            VStack(spacing: 0) {
                PaneHeader(title: "Output", format: store.outputFormat, status: r.status, error: r.error)
                CodeView(text: store.output, format: store.outputFormat ?? .text)
            }
        } else {
            ContentUnavailableView("No Format Detected", systemImage: "doc.text.magnifyingglass",
                                   description: Text("Supported: \(Format.supported)"))
                .frame(maxHeight: .infinity)
        }
    }
}

// ponytail: one Text per document; switch to an NSTextView if multi-megabyte outputs feel slow.
struct CodeView: View {
    let text: String
    let format: Format

    var body: some View {
        let lineCount = text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 16) {
                Text((1...lineCount).map(String.init).joined(separator: "\n"))
                    .foregroundStyle(Palette.gutter)
                    .multilineTextAlignment(.trailing)
                    .accessibilityHidden(true)
                ScrollView(.horizontal) {
                    Text(highlighted)
                        .textSelection(.enabled)
                        .fixedSize()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollIndicators(.never)
            }
            .font(.system(size: 13.5, design: .monospaced))
            .lineSpacing(8)
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var highlighted: AttributedString {
        Highlighter.spans(text, format: format).reduce(into: AttributedString()) { result, span in
            var part = AttributedString(span.text)
            part.foregroundColor = Palette.color(for: span.role)
            result += part
        }
    }
}

struct StatusBar: View {
    @Environment(Store.self) private var store

    var body: some View {
        HStack {
            Text(left).lineLimit(1)
            Spacer()
            Text(right)
        }
        .font(.system(size: 11.5))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 26)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }

    private var left: String {
        if let r = store.result { return r.summary }
        return store.input.isEmpty ? Format.supported : "No format detected"
    }

    private var right: String {
        guard store.result != nil else { return "\(store.input.count) characters" }
        let n = store.output.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        return n == 1 ? "1 line" : "\(n) lines"
    }
}

// MARK: - Inspector

struct InspectorView: View {
    @Environment(Store.self) private var store

    var body: some View {
        @Bindable var store = store
        Form {
            if let r = store.result {
                if r.steps.count > 1 {
                    Section("Steps") {
                        ForEach(Array(r.steps.enumerated()), id: \.offset) { i, step in
                            HStack(spacing: 10) {
                                Badge(format: step.format)
                                Text(step.label)
                                Spacer()
                                Text("\(i + 1)").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section(r.steps.count > 1 ? "Details" : "Detection") {
                    ForEach(r.details, id: \.self) { LabeledContent($0.label, value: $0.value) }
                }

                outputOptions(r, $store.options)

                if !r.targets.isEmpty {
                    Section("Convert To") {
                        ForEach(r.targets, id: \.self) { target in
                            Button {
                                store.target = store.target == target ? nil : target
                            } label: {
                                HStack {
                                    Text(target.rawValue)
                                    Spacer()
                                    if store.target == target { Image(systemName: "checkmark").foregroundStyle(.tint) }
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func outputOptions(_ r: Conversion, _ options: Binding<Options>) -> some View {
        let isJSON = r.output == .json && r.error == nil
        let isCode = r.output == .typescript || r.output == .javascript
        let escapable = r.input == .json || r.input == .escapedJSON
        let decodes = r.input == .base64
        if isJSON || isCode || escapable || decodes {
            Section(isCode ? "Formatting" : "Output") {
                if isJSON || isCode {
                    Picker("Indent", selection: options.indent) {
                        ForEach(Indent.allCases, id: \.self) { Text($0.rawValue) }
                    }
                }
                if isJSON { Toggle("Sort keys", isOn: options.sortKeys).toggleStyle(.switch) }
                if escapable { Toggle("Unescape automatically", isOn: options.unescape).toggleStyle(.switch) }
                if decodes { Toggle("Decode nested formats", isOn: options.decodeNested).toggleStyle(.switch) }
            }
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @AppStorage("darkMode") private var darkMode: Bool?

    var body: some View {
        Form {
            Picker("Appearance", selection: $darkMode) {
                Text("System").tag(Bool?.none)
                Text("Light").tag(Bool?.some(false))
                Text("Dark").tag(Bool?.some(true))
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}

#if DEBUG
// Debug-only visual check from the CLI: `DECANT_INPUT=… DECANT_SNAPSHOT=out.png [DECANT_DARK=1] .build/debug/Decant`
// loads the input, writes a PNG of the window and quits. Needs no screen-recording permission.
extension ContentView {
    func debugSnapshot() async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["DECANT_SNAPSHOT"] else { return }
        if let dark = env["DECANT_DARK"] { UserDefaults.standard.set(dark == "1", forKey: "darkMode") }
        try? await Task.sleep(for: .seconds(0.5))
        if let input = env["DECANT_INPUT"] { store.input = input }
        try? await Task.sleep(for: .seconds(1.5))
        guard let view = NSApp.windows.first(where: \.isVisible)?.contentView?.superview,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        NSApp.terminate(nil)
    }
}
#endif
