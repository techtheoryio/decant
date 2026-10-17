import AppKit
import DecantCore
import SwiftUI

// MARK: - Palette (values from the design canvas; the accent is always the system accent)

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
    static let window = Color(0xECEEF1, 0x16171A)
    static let card = Color(0xFFFFFF, 0x1E1F23)
    static let cardRing = Color(0x141820, 0xFFFFFF, lightAlpha: 0.07, darkAlpha: 0.06)
    static let cardShadow = Color(0x141E32, 0x000000, lightAlpha: 0.12, darkAlpha: 0.45)
    static let cardFoot = Color(0xFAFBFC, 0x222327)
    static let cardSeparator = Color(0xEEF0F3, 0x2B2C31)
    static let glassRing = Color(0x141820, 0x000000, lightAlpha: 0.08, darkAlpha: 0.5)
    static let text2 = Color(0x5C6270, 0xA4A9B3)
    static let text3 = Color(0x6A707C, 0x959AA5)
    static let text4 = Color(0x868C97, 0x7D828C)
    static let icon = Color(0x5C6270, 0xA4A9B3)
    static let hairline = Color(0xD3D6DC, 0x383B42)
    static let gutter = Color(0xC9CCD2, 0x4A4E57)
    static let ok = Color(0x1E7A4C, 0x6FD39C)
    static let okDot = Color(0x2EAD6B, 0x2EAD6B)
    static let key = Color(0x2D3A8C, 0xB3B9FF)
    static let string = Color(0x2F6B4F, 0x8FD6A8)
    static let number = Color(0xA0561B, 0xF2B97C)
    static let punctuation = Color(0xA09A92, 0x7D828C)
    static let keyword = Color(0x9B2457, 0xFF8DB5)
    static let function = Color(0x1F4FA8, 0x86B8FF)
    /// Accent-tinted fill for selected rows and the empty-state tile.
    static let accentTint = Color(nsColor: NSColor(name: nil) { appearance in
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        return NSColor.controlAccentColor.withAlphaComponent(isDark ? 0.2 : 0.12)
    })

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

    static func dot(_ format: Format) -> Color {
        switch format {
        case .json, .escapedJSON: Color(0xD99A1E, 0xD99A1E)
        case .typescript, .javascript: Color(0x3B78E0, 0x3B78E0)
        case .base64: Color(0x2E9A68, 0x2E9A68)
        case .unixTime: Color(0xC8467A, 0xC8467A)
        case .text: text4
        }
    }

    static func badge(_ format: Format) -> (background: Color, foreground: Color) {
        switch format {
        case .json, .escapedJSON: (Color(0xFBEFD9, 0xD9940F, darkAlpha: 0.22), Color(0x8A5A00, 0xF3C66B))
        case .typescript, .javascript: (Color(0xE3EDFC, 0x3B78E0, darkAlpha: 0.26), Color(0x1F4FA8, 0x9CC2FF))
        case .base64: (Color(0xDDF2E8, 0x2E9A68, darkAlpha: 0.26), Color(0x1C6B47, 0x86D9AE))
        case .unixTime: (Color(0xFBE4EC, 0xC8467A, darkAlpha: 0.26), Color(0x9B2457, 0xF59BC0))
        case .text: (Color(0x000000, 0xFFFFFF, lightAlpha: 0.055, darkAlpha: 0.08), Color(0x5C6270, 0xA4A9B3))
        }
    }
}

// MARK: - Glass helpers

/// System Liquid Glass on macOS 26, a material capsule before that.
struct GlassCapsule: ViewModifier {
    var tinted = false

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.glassEffect(tinted ? .regular.tint(.accentColor.opacity(0.3)).interactive() : .regular.interactive(), in: Capsule())
        } else {
            content
                .background(tinted ? AnyShapeStyle(Palette.accentTint) : AnyShapeStyle(.ultraThinMaterial), in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.glassRing, lineWidth: 0.5))
                .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
        }
    }
}

extension View {
    func glassCapsule(tinted: Bool = false) -> some View { modifier(GlassCapsule(tinted: tinted)) }

    /// Large accent capsule (Copy, Paste from Clipboard).
    func prominentCapsule() -> some View {
        buttonStyle(.borderedProminent).buttonBorderShape(.capsule).controlSize(.large)
    }

    /// The header carries the title, so the toolbar shows only its floating controls.
    @ViewBuilder func floatingToolbar() -> some View {
        if #available(macOS 15, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
    }
}

struct Badge: View {
    let format: Format

    var body: some View {
        let colors = Palette.badge(format)
        Text(format.name.uppercased())
            .font(.system(size: 9.5, weight: .bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(colors.foreground)
            .background(colors.background, in: RoundedRectangle(cornerRadius: 4))
    }
}

struct Dot: View {
    let color: Color
    var size: CGFloat = 6
    var body: some View { Circle().fill(color).frame(width: size, height: size) }
}

// MARK: - Window

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var showInspector = false
    @State private var importing = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 232)
                .padding(.top, 40)  // the traffic lights sit inside the panel
                .background { SidebarPanel() }
                .padding(10)
                .ignoresSafeArea(.container, edges: .top)
            DetailView()
        }
        .background(Palette.window)
        .navigationTitle("")
        .toolbar { toolbar }
        .inspector(isPresented: Binding(get: { showInspector && store.result != nil }, set: { showInspector = $0 })) {
            InspectorView().inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .floatingToolbar()
        .onChange(of: store.sidebar) { _, item in store.select(item) }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.plainText, .json, .data]) { result in
            guard case .success(let url) = result else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                store.newDocument()
                store.originalExpanded = false
                store.input = text
            }
        }
        #if DEBUG
        .task { await debugSnapshot() }
        #endif
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        @Bindable var store = store
        if let r = store.result, r.output == .json, r.error == nil, store.target == nil {
            ToolbarItem(placement: .primaryAction) {
                Picker("Output Style", selection: $store.options.minify) {
                    Text("Pretty").tag(false)
                    Text("Minified").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if store.input.isEmpty {
                Button("Open File", systemImage: "folder") { importing = true }
            } else {
                ShareLink(item: store.output)
            }
            Button {
                showInspector.toggle()
            } label: {
                Label(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
            }
            .disabled(store.result == nil)
        }
        if store.result != nil {
            ToolbarItem(placement: .primaryAction) {
                // ⌘C stays the system Copy for selected text; the whole output is ⇧⌘C.
                Button { store.copyOutput() } label: {
                    HStack(spacing: 8) {
                        Text("Copy").fontWeight(.semibold)
                        Text("⇧⌘C").font(.system(size: 11.5)).opacity(0.8)
                    }
                }
                .prominentCapsule()
                .keyboardShortcut("c", modifiers: [.command, .shift])
            }
        }
    }
}

// MARK: - Sidebar

struct SidebarRow<Leading: View>: View {
    let title: String
    var shortcut: String?
    let selected: Bool
    let action: () -> Void
    @ViewBuilder let leading: Leading

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                leading.frame(width: 16)
                Text(title).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                if let shortcut {
                    Text(shortcut).font(.system(size: 11, weight: .medium)).opacity(selected ? 0.75 : 1)
                        .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.text4))
                }
            }
            .font(.system(size: 13, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(selected ? Palette.accentTint : .clear, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Floating, inset sidebar panel: system Liquid Glass on macOS 26, a material panel before that.
struct SidebarPanel: View {
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        Group {
            if #available(macOS 26, *) {
                Color.clear.glassEffect(.regular, in: shape)
            } else {
                shape.fill(.ultraThinMaterial).overlay(shape.strokeBorder(.white.opacity(0.5), lineWidth: 1))
            }
        }
        .overlay(shape.strokeBorder(Palette.glassRing, lineWidth: 0.5))
        .shadow(color: .black.opacity(0.08), radius: 15, y: 10)
    }
}

struct SidebarView: View {
    @Environment(Store.self) private var store
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("darkMode") private var darkMode: Bool?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    row("New", item: .new, shortcut: "⌘N", icon: "square.and.pencil")

                    if !store.entries.isEmpty {
                        header("History")
                        ForEach(store.entries) { entry in
                            let item = SidebarItem.entry(entry.id)
                            SidebarRow(title: entry.title, selected: store.sidebar == item, action: { store.sidebar = item }) {
                                Dot(color: Palette.dot(entry.format))
                            }
                            .contextMenu {
                                Button("Delete", role: .destructive) { store.delete(entry) }
                            }
                        }
                    }

                    header("Tools")
                    ForEach(Tool.allCases) { tool in
                        row(tool.rawValue, item: .tool(tool), icon: tool.icon)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
            }
            .scrollIndicators(.never)
            footer
        }
    }

    private func row(_ title: String, item: SidebarItem, shortcut: String? = nil, icon: String) -> some View {
        let selected = store.sidebar == item
        return SidebarRow(title: title, shortcut: shortcut, selected: selected, action: { store.sidebar = item }) {
            Image(systemName: icon).foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.icon))
        }
    }

    private func header(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Palette.text3)
            .padding(.horizontal, 10)
            .padding(.top, 16)
            .padding(.bottom, 6)
    }

    private var footer: some View {
        VStack(spacing: 2) {
            HStack(spacing: 10) {
                Image(systemName: "moon").foregroundStyle(Palette.icon).frame(width: 16)
                Text("Dark Mode")
                Spacer()
                Toggle("Dark Mode", isOn: Binding(get: { darkMode ?? (colorScheme == .dark) }, set: { darkMode = $0 }))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            SettingsLink {
                HStack(spacing: 10) {
                    Image(systemName: "gearshape").foregroundStyle(Palette.icon).frame(width: 16)
                    Text("Settings")
                    Spacer()
                    Text("⌘,").font(.system(size: 11)).foregroundStyle(Palette.text4)
                }
                .padding(.horizontal, 10)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
    }
}

// MARK: - Detail

struct DetailView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView()
                .padding(.horizontal, 6)
                .padding(.top, 18)
                .padding(.bottom, 22)
            CardView()
            if let r = store.result {
                ActionBar(result: r).padding(.top, 16)
            }
        }
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.window)
    }
}

struct HeaderView: View {
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            eyebrow
            Text(store.title)
                .font(.system(size: 40, weight: .semibold))
                .tracking(-1)
                .lineLimit(1)
                .truncationMode(.tail)
            meta
        }
    }

    /// "ESCAPED STRING → JSON", "BASE64 → TEXT → JSON", "TYPESCRIPT → FORMATTED".
    private var chain: [String] {
        guard let r = store.result else { return [store.input.isEmpty ? "Waiting for input" : "No format detected"] }
        func name(_ f: Format) -> String { f == .escapedJSON ? "Escaped string" : f.name }
        var parts = r.steps.count > 1 ? r.steps.map(\.format) : [r.input, r.output]
        parts = parts.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
        var names = parts.map(name)
        if names.count == 1 { names.append(r.error == nil ? "Formatted" : "Error") }
        if let target = store.target { names.append(target.rawValue) }
        return names
    }

    private var eyebrow: some View {
        let parts = chain
        return HStack(spacing: 10) {
            ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
                if i > 0 { Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)) }
                Text(part).foregroundStyle(i == parts.count - 1 && parts.count > 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.text3))
            }
        }
        .font(.system(size: 11, weight: .semibold))
        .tracking(1)
        .textCase(.uppercase)
        .foregroundStyle(Palette.text3)
    }

    @ViewBuilder private var meta: some View {
        if let r = store.result {
            HStack(spacing: 18) {
                if let error = r.error {
                    status(error, color: .red, dot: .red)
                } else if let status = r.status {
                    self.status(status, color: Palette.ok, dot: Palette.okDot)
                }
                ForEach(r.meta + dateText, id: \.self) { item in
                    Rectangle().fill(Palette.hairline).frame(width: 1, height: 12)
                    Text(item)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
        } else {
            HStack(spacing: 14) {
                ForEach([Format.json, .escapedJSON, .typescript, .javascript, .base64, .unixTime], id: \.self) { format in
                    HStack(spacing: 6) {
                        Dot(color: Palette.dot(format))
                        Text(format.name)
                    }
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text2)
        }
    }

    private func status(_ text: String, color: Color, dot: Color) -> some View {
        HStack(spacing: 6) {
            Dot(color: dot, size: 7)
            Text(text)
        }
        .foregroundStyle(color)
        .fontWeight(.medium)
    }

    private var dateText: [String] {
        guard let date = store.date else { return [] }
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        f.doesRelativeDateFormatting = true
        return [f.string(from: date)]
    }
}

struct CardView: View {
    @Environment(Store.self) private var store
    @FocusState private var editorFocused: Bool

    var body: some View {
        let empty = store.input.isEmpty
        let shape = RoundedRectangle(cornerRadius: 24, style: .continuous)
        VStack(spacing: 0) {
            if !empty {
                if store.result != nil {
                    CodeView(text: store.output, format: store.outputFormat ?? .text)
                } else {
                    ContentUnavailableView("No Format Detected", systemImage: "doc.text.magnifyingglass",
                                           description: Text("Supported: \(Format.supported)"))
                        .frame(maxHeight: .infinity)
                }
                OriginalRow()
            }
            if empty || store.originalExpanded {
                TextEditor(text: input)
                    .font(.system(size: empty ? 15 : 12, design: .monospaced))
                    .foregroundStyle(empty ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.text2))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(empty ? .never : .automatic)
                    .focused($editorFocused)
                    .padding(.horizontal, empty ? 31 : 23)
                    .padding(.vertical, empty ? 30 : 12)
                    .frame(maxHeight: empty ? .infinity : 150)
                    .background(empty ? Color.clear : Palette.cardFoot)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if empty {
                EmptyState {
                    if let s = NSPasteboard.general.string(forType: .string) {
                        store.originalExpanded = false
                        store.input = s
                    }
                }
            }
        }
        .background(Palette.card)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Palette.cardRing, lineWidth: 0.5))
        .shadow(color: Palette.cardShadow, radius: 24, y: 14)
        .onAppear { editorFocused = true }
    }

    /// Typing into the empty card keeps the editor open; a paste collapses it into the Original row.
    private var input: Binding<String> {
        Binding(get: { store.input }, set: { new in
            if store.input.isEmpty { store.originalExpanded = new.count <= 1 }
            store.input = new
        })
    }
}

struct OriginalRow: View {
    @Environment(Store.self) private var store

    var body: some View {
        Button {
            withAnimation(.snappy(duration: 0.25)) { store.originalExpanded.toggle() }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 10, weight: .bold))
                    .rotationEffect(.degrees(store.originalExpanded ? 90 : 0))
                Text("Original").fontWeight(.semibold).foregroundStyle(.primary)
                if !store.originalExpanded {
                    Text(String(store.input.prefix(400)).replacingOccurrences(of: "\n", with: " "))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Palette.text4)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .font(.system(size: 12.5))
            .foregroundStyle(Palette.text2)
            .padding(.horizontal, 28)
            .frame(maxWidth: .infinity, minHeight: 52, maxHeight: 52)
            .background(Palette.cardFoot)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Rectangle().fill(Palette.cardSeparator).frame(height: 1) }
    }
}

struct EmptyState: View {
    let paste: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(.tint)
                .frame(width: 64, height: 64)
                .background(Palette.accentTint, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .padding(.bottom, 10)
            Text("No Input").font(.system(size: 20, weight: .semibold))
            Text("Paste, open a file or start typing. The format is detected and converted automatically.")
                .font(.system(size: 13.5))
                .foregroundStyle(Palette.text2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)
            Button(action: paste) {
                HStack(spacing: 8) {
                    Text("Paste from Clipboard").fontWeight(.semibold)
                    Text("⌘V").font(.system(size: 11.5)).opacity(0.8)
                }
            }
            .prominentCapsule()
            .padding(.top, 14)
        }
    }
}

struct ActionBar: View {
    @Environment(Store.self) private var store
    let result: Conversion

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 8) {
            if !result.targets.isEmpty {
                Text("Convert to")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.text3)
                    .padding(.trailing, 6)
                ForEach(result.targets, id: \.self) { target in
                    targetButton(target)
                }
            }
            Spacer(minLength: 12)
            if result.output == .json, result.error == nil, store.target == nil {
                option("Sort keys", isOn: $store.options.sortKeys)
            }
            if result.output == .typescript || result.output == .javascript {
                HStack(spacing: 10) {
                    Text("Indent")
                    Picker("Indent", selection: $store.options.indent) {
                        Text("2").tag(Indent.two)
                        Text("4").tag(Indent.four)
                        Text("Tab").tag(Indent.tab)
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .fixedSize()
                }
                .font(.system(size: 12.5))
                .padding(.leading, 14)
                .padding(.trailing, 4)
                .frame(height: 32)
                .glassCapsule()
            }
            if result.input == .base64 {
                option("Decode nested formats", isOn: $store.options.decodeNested)
            }
        }
    }

    private func targetButton(_ target: Target) -> some View {
        let selected = store.target == target
        return Button {
            store.target = selected ? nil : target
        } label: {
            Text(target.rawValue)
                .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(tinted: selected)
    }

    private func option(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 10) {
            Text(title)
            Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .font(.system(size: 12.5))
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .frame(height: 32)
        .glassCapsule()
    }
}

// ponytail: one Text per document; switch to an NSTextView if multi-megabyte outputs feel slow.
struct CodeView: View {
    let text: String
    let format: Format

    var body: some View {
        let lineCount = text.utf8.reduce(1) { $1 == 10 ? $0 + 1 : $0 }
        ScrollView(.vertical) {
            HStack(alignment: .top, spacing: 22) {
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
            .font(.system(size: 15, design: .monospaced))
            .lineSpacing(12)
            .padding(.horizontal, 36)
            .padding(.vertical, 30)
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

// MARK: - Inspector (hidden by default; holds the full detail list and every option)

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
        if let input = env["DECANT_INPUT"] {
            store.originalExpanded = false
            store.input = input
        }
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: \.isVisible)?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .seconds(1.5))
        guard let window = NSApp.windows.first(where: \.isVisible) else { return }
        // The compositor image includes Liquid Glass; an app may capture its own windows without
        // screen-recording permission. The symbol is unavailable in the SDK, so look it up at runtime.
        typealias CreateImage = @convention(c) (CGRect, UInt32, UInt32, UInt32) -> Unmanaged<CGImage>?
        if let symbol = dlsym(dlopen(nil, RTLD_NOW), "CGWindowListCreateImage"),
           let image = unsafeBitCast(symbol, to: CreateImage.self)(.null, 1 << 3, UInt32(window.windowNumber), 1 << 0)?.takeRetainedValue() {
            try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        } else if let view = window.contentView?.superview, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        NSApp.terminate(nil)
    }
}
#endif
