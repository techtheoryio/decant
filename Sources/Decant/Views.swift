import AppKit
import DecantCore
import SwiftUI

// MARK: - Palette (values from the design canvas; the accent is always the system accent)

extension NSColor {
    static func dynamic(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let v = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255,
                           blue: CGFloat(v & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        }
    }
}

extension Color {
    init(_ light: UInt32, _ dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: .dynamic(light, dark, lightAlpha: lightAlpha, darkAlpha: darkAlpha))
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
    static let gutter = Color(0xB4B8BF, 0x5A5E67)
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

    static let added = Color(0x2EAD6B, 0x2EAD6B)
    static let removed = Color(0xD64545, 0xF07070)

    static func nsColor(for role: Role) -> NSColor {
        switch role {
        case .plain: .labelColor
        case .key: .dynamic(0x2D3A8C, 0xB3B9FF)
        case .string: .dynamic(0x2F6B4F, 0x8FD6A8)
        case .number, .type: .dynamic(0xA0561B, 0xF2B97C)
        case .keyword: .dynamic(0x9B2457, 0xFF8DB5)
        case .function: .dynamic(0x1F4FA8, 0x86B8FF)
        case .punctuation, .comment: .dynamic(0xA09A92, 0x7D828C)
        }
    }

    static func color(for role: Role) -> Color { Color(nsColor: nsColor(for: role)) }

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
    @State private var copied = false
    @State private var hideCopied: Task<Void, Never>?

    var body: some View {
        @Bindable var store = store
        HStack(spacing: 0) {
            SidebarView()
                .frame(width: 236)
                // Keep the scroll view clear of the titlebar safe area: touching it, the scroll view grows under the
                // titlebar and rows scroll up behind the traffic lights. Only the panel extends up around them.
                .padding(.top, 10)
                .background { SidebarPanel().padding(.top, 10).ignoresSafeArea(.container, edges: .top) }
                .padding([.horizontal, .bottom], 10)
            DetailView()
        }
        .background(Palette.window)
        .navigationTitle("")
        .toolbar { toolbar }
        .inspector(isPresented: Binding(get: { showInspector && store.tool == .detect && store.detectResult != nil }, set: { showInspector = $0 })) {
            InspectorView().inspectorColumnWidth(min: 240, ideal: 280, max: 360)
        }
        .floatingToolbar()
        .fileImporter(isPresented: $store.importing, allowedContentTypes: [.item]) { result in
            if case .success(let url) = result { store.load(url) }
        }
        .sheet(isPresented: $store.showPalette) { CommandPalette().environment(store) }
        .overlay(alignment: .bottom) {
            if copied {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
                    .glassCapsule()
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .allowsHitTesting(false)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .copied)) { _ in
            withAnimation(.snappy) { copied = true }
            hideCopied?.cancel()
            hideCopied = Task {
                try? await Task.sleep(for: .seconds(1.4))
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut) { copied = false }
            }
        }
        #if DEBUG
        .task { await debugSnapshot() }
        #endif
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Command Palette", systemImage: "magnifyingglass") { store.showPalette = true }
                .help("Jump to a tool or history entry (⌘K)")
            Button("Open File", systemImage: "folder") { store.importing = true }
                .help("Open a file in the current tool (⌘O)")
            if store.tool == .detect {
                Button {
                    showInspector.toggle()
                } label: {
                    Label(showInspector ? "Hide Inspector" : "Show Inspector", systemImage: "sidebar.trailing")
                }
                .disabled(store.detectResult == nil)
            }
        }
        if ![.unixTime, .cron, .color, .counter].contains(store.tool) {
            ToolbarItem(placement: .primaryAction) {
                // ⌘C stays the system Copy for selected text; the whole output is ⇧⌘C.
                Button { post(.copy) } label: {
                    HStack(spacing: 8) {
                        Text("Copy").fontWeight(.semibold)
                        Text("⇧⌘C").font(.system(size: 11.5)).opacity(0.8)
                    }
                }
                .prominentCapsule()
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
            .frame(height: 30)
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
    @AppStorage("toolOrder") private var order = ""
    @AppStorage("hiddenTools") private var hidden = ""
    @AppStorage("groupTools") private var group = true
    @State private var renaming: Entry?
    @State private var newTitle = ""
    @State private var confirmClear = false

    var body: some View {
        let tools = ToolLayout.visible(order: order, hidden: hidden)
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    SidebarRow(title: "New", shortcut: "⌘N", selected: store.tool == .detect && store.activeEntry == nil, action: {
                        store.open(.detect)
                        store.newDocument()
                    }) {
                        Image(systemName: Tool.detect.icon).foregroundStyle(store.tool == .detect ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.icon))
                    }

                    let pinned = store.entries.filter(\.pinned)
                    if !pinned.isEmpty {
                        header("Pinned")
                        ForEach(pinned) { entryRow($0) }
                    }

                    if group {
                        ForEach(Category.allCases, id: \.self) { category in
                            let members = tools.filter { $0.category == category }
                            if !members.isEmpty {
                                header(category.rawValue)
                                ForEach(members) { toolRow($0, index: tools.firstIndex(of: $0)!) }
                            }
                        }
                    } else {
                        header("Tools")
                        ForEach(Array(tools.enumerated()), id: \.element) { toolRow($1, index: $0) }
                    }

                    let history = store.entries.filter { !$0.pinned }
                    if !history.isEmpty {
                        header("History") {
                            Button("Clear") { confirmClear = true }
                                .buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(Palette.text4)
                        }
                        ForEach(history) { entryRow($0) }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.never)
            footer
        }
        .alert("Rename Entry", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") { if let renaming { store.rename(renaming, to: newTitle) } }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Clear the history?", isPresented: $confirmClear) {
            Button("Clear History", role: .destructive) { store.clearHistory() }
        } message: {
            Text("Pinned entries are kept.")
        }
    }

    private func toolRow(_ tool: Tool, index: Int) -> some View {
        let selected = store.tool == tool && store.activeEntry == nil
        return SidebarRow(title: tool.name, shortcut: index < 9 ? "⌘\(index + 1)" : nil, selected: selected, action: { store.open(tool) }) {
            Image(systemName: tool.icon).foregroundStyle(store.tool == tool ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.icon))
        }
    }

    private func entryRow(_ entry: Entry) -> some View {
        SidebarRow(title: entry.title, selected: store.tool == entry.tool && store.activeEntry == entry.id, action: { store.open(entry) }) {
            if entry.pinned {
                Image(systemName: "pin.fill").font(.system(size: 10)).foregroundStyle(entry.dot)
            } else {
                Dot(color: entry.dot)
            }
        }
        .help("\(entry.tool.name) · \(entry.date.formatted(date: .abbreviated, time: .shortened))")
        .contextMenu {
            Button(entry.pinned ? "Unpin" : "Pin") { store.togglePin(entry) }
            Button("Rename…") {
                newTitle = entry.title
                renaming = entry
            }
            Divider()
            Button("Delete", role: .destructive) { store.delete(entry) }
        }
    }

    private func header(_ title: String) -> some View { header(title) { EmptyView() } }

    private func header<Trailing: View>(_ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.text3)
            Spacer()
            trailing()
        }
        .padding(.horizontal, 10)
        .padding(.top, 14)
        .padding(.bottom, 5)
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
        Group {
            switch store.tool {
            case .detect: DetectPage()
            case .formatter: FormatterPage()
            case .base64: Base64Page()
            case .url: URLPage()
            case .unixTime: UnixTimePage()
            case .cron: CronPage()
            case .jwt: JWTPage()
            case .uuid: UUIDPage()
            case .password: PasswordPage()
            case .csv: CSVPage()
            case .diff: DiffPage()
            case .regex: RegexPage()
            case .counter: CounterPage()
            case .markdown: MarkdownPage()
            case .color: ColorPage()
            case .qr: QRPage()
            }
        }
        .id(store.tool)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Palette.window)
    }
}

struct Status: Equatable {
    enum Tone { case ok, warning, error, neutral }
    var text: String
    var tone: Tone = .ok

    static func error(_ text: String) -> Status { Status(text: text, tone: .error) }
    static func warning(_ text: String) -> Status { Status(text: text, tone: .warning) }
}

struct PageHeader: View {
    let eyebrow: [String]
    let title: String
    var status: Status?
    var meta: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ForEach(Array(eyebrow.enumerated()), id: \.offset) { i, part in
                    if i > 0 { Image(systemName: "arrow.right").font(.system(size: 10, weight: .bold)) }
                    Text(part).foregroundStyle(i == eyebrow.count - 1 && eyebrow.count > 1 ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.text3))
                }
            }
            .font(.system(size: 11, weight: .semibold))
            .tracking(1)
            .textCase(.uppercase)
            .foregroundStyle(Palette.text3)
            Text(title)
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.8)
                .lineLimit(1)
                .truncationMode(.tail)
            HStack(spacing: 16) {
                if let status {
                    HStack(spacing: 6) {
                        Dot(color: dot(status.tone), size: 7)
                        Text(status.text)
                    }
                    .foregroundStyle(color(status.tone))
                    .fontWeight(.medium)
                }
                ForEach(Array(meta.enumerated()), id: \.offset) { i, item in
                    if i > 0 || status != nil { Rectangle().fill(Palette.hairline).frame(width: 1, height: 12) }
                    Text(item)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(Palette.text2)
            .lineLimit(1)
            .frame(height: 17)
        }
    }

    private func color(_ tone: Status.Tone) -> Color {
        switch tone {
        case .ok: Palette.ok
        case .warning: .orange
        case .error: .red
        case .neutral: Palette.text2
        }
    }

    private func dot(_ tone: Status.Tone) -> Color { tone == .ok ? Palette.okDot : color(tone) }
}

/// Header, a fixed options bar, then the working area. Every tool page uses this.
struct ToolPage<Options: View, Content: View>: View {
    var eyebrow: [String]
    var title: String
    var status: Status?
    var meta: [String] = []
    @ViewBuilder var options: Options
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PageHeader(eyebrow: eyebrow, title: title, status: status, meta: meta)
                .padding(.horizontal, 6)
                .padding(.top, 14)
                .padding(.bottom, 14)
            ScrollView(.horizontal) {
                HStack(spacing: 8) { options }
                    .padding(.vertical, 6)
                    .padding(.leading, 24)
                    .padding(.trailing, 20)
            }
            .scrollIndicators(.never)
            // Clipped at the page edges (not the sidebar) so scrolled options can't slide over the sidebar.
            .padding(.leading, -22)
            .padding(.trailing, -18)
            .padding(.bottom, 8)
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(.leading, 22)
        .padding(.trailing, 18)
        .padding(.bottom, 16)
    }
}

extension ToolPage {
    init(tool: Tool, status: Status? = nil, meta: [String] = [], @ViewBuilder options: () -> Options, @ViewBuilder content: () -> Content) {
        self.init(eyebrow: [tool.category.rawValue], title: tool.name, status: status, meta: meta, options: options, content: content)
    }
}

// MARK: - Shared controls

extension View {
    func card(radius: CGFloat = 20) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return background(Palette.card)
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.cardRing, lineWidth: 0.5))
            .shadow(color: Palette.cardShadow, radius: 16, y: 8)
    }

    /// The glass capsule every control in the options bar sits in.
    func optionCapsule() -> some View {
        font(.system(size: 12.5))
            .padding(.leading, 14)
            .padding(.trailing, 6)
            .frame(height: 32)
            .glassCapsule()
    }
}

struct OptionToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
            Toggle(title, isOn: $isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
        }
        .optionCapsule()
    }
}

struct OptionSegments<Value: Hashable>: View {
    var title: String?
    @Binding var selection: Value
    let options: [(String, Value)]

    var body: some View {
        HStack(spacing: 10) {
            if let title { Text(title) }
            Segments(selection: $selection, options: options)
        }
        .font(.system(size: 12.5))
        .padding(.leading, title == nil ? 4 : 14)
        .padding(.trailing, 4)
        .frame(height: 32)
        .glassCapsule()
    }
}

/// Segmented control drawn in SwiftUI. The AppKit segmented Picker misreports its size on first layout
/// inside the glass capsules, which clipped the selected segment until the first click.
struct Segments<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]
    var compact = false
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let selected = options[i].1 == selection
                Button { selection = options[i].1 } label: {
                    Text(options[i].0)
                        .font(.system(size: compact ? 11.5 : 12.5, weight: .medium))
                        .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                        .padding(.horizontal, compact ? 9 : 11)
                        .frame(height: compact ? 22 : 24)
                        .background {
                            if selected { Capsule().fill(Color.accentColor).matchedGeometryEffect(id: "pill", in: pill) }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .fixedSize()
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

struct OptionMenu<Value: Hashable>: View {
    let title: String
    @Binding var selection: Value
    let options: [(String, Value)]

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
            Picker(title, selection: $selection) {
                ForEach(options.indices, id: \.self) { Text(options[$0].0).tag(options[$0].1) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .buttonStyle(.borderless)
            .fixedSize()
        }
        .optionCapsule()
    }
}

struct CapsuleButton: View {
    let title: String
    var systemImage: String?
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
            .padding(.horizontal, 14)
            .frame(height: 32)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .glassCapsule(tinted: selected)
    }
}

struct IconButton: View {
    let systemImage: String
    let help: String
    var active = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(active ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.icon))
                .frame(width: 28, height: 26)
                .background(active ? Palette.accentTint : .clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

/// A card with a small uppercase title row; accessories sit on the right of the title.
struct Pane<Accessory: View, Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @ViewBuilder var accessory: Accessory

    init(_ title: String, @ViewBuilder content: () -> Content, @ViewBuilder accessory: () -> Accessory) {
        self.title = title
        self.content = content()
        self.accessory = accessory()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.8)
                    .textCase(.uppercase)
                    .foregroundStyle(Palette.text3)
                    .lineLimit(1)
                Spacer(minLength: 8)
                accessory
            }
            .padding(.leading, 18)
            .padding(.trailing, 8)
            .frame(height: 40)
            Rectangle().fill(Palette.cardSeparator).frame(height: 1)
            content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .card()
    }
}

extension Pane where Accessory == EmptyView {
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

/// Red strip under an editor: the error, and a button that jumps to it.
struct ErrorBar: View {
    let message: String
    var line: Int?
    var jump: (() -> Void)?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            Text(message).lineLimit(2).textSelection(.enabled)
            Spacer(minLength: 8)
            if let line, let jump {
                Button("Go to Line \(line)", action: jump).controlSize(.small)
            }
        }
        .font(.system(size: 12))
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(Color.red.opacity(0.08))
        .overlay(alignment: .top) { Rectangle().fill(Color.red.opacity(0.2)).frame(height: 1) }
    }
}

@MainActor enum Output {
    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copied()
    }

    /// Shows the "Copied" toast and tells VoiceOver.
    static func copied() {
        NotificationCenter.default.post(name: .copied, object: nil)
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: "Copied", .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    static func save(_ data: Data, name: String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            do { try data.write(to: url) } catch { NSAlert(error: error).runModal() }
        }
    }

    /// Dragging hands out a real file, so it can land in Finder as well as in other apps.
    static func dragItem(_ data: Data, name: String) -> NSItemProvider {
        let url = FileManager.default.temporaryDirectory.appending(path: name)
        try? data.write(to: url)
        return NSItemProvider(contentsOf: url) ?? NSItemProvider()
    }

    static func lineColumn(in message: String) -> (line: Int, column: Int)? {
        guard let m = message.firstMatch(of: /line (\d+), column (\d+)/), let l = Int(m.1), let c = Int(m.2) else { return nil }
        return (l, c)
    }
}

/// Text editor card. Inputs get Paste/Clear; outputs get wrap, compare-with-input, save, drag-out and copy.
struct EditorPane: View {
    let title: String
    @Binding var text: String
    var placeholder = ""
    var syntax: Format = .text
    var editable = true
    var output = false
    /// Answers the Copy/Save/Find Output commands.
    var primary = false
    /// When set, the pane can show a diff from this text to its own.
    var diffBase: String?
    var fileExtension = "txt"
    var errorLine: Int?
    var jump: Jump?
    var marks: [EditorMark] = []
    var onFile: ((URL) -> Void)?
    var accessory: AnyView?
    var footer: AnyView?
    /// Always wrap, whatever the global setting (tokens and other single-line blobs).
    var forceWrap = false

    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("fontName") private var fontName = ""
    @AppStorage("wrapLines") private var wrap = false
    @State private var showDiff = false

    var body: some View {
        Pane(title) { content } accessory: { accessories }
            .onReceive(NotificationCenter.default.publisher(for: .outputCommand)) { note in
                guard primary else { return }
                switch OutputCommand(rawValue: note.object as? String ?? "") {
                case .copy?: Output.copy(text)
                case .save?: save()
                default: break
                }
            }
    }

    private var content: some View {
        VStack(spacing: 0) {
            if showDiff, let diffBase {
                DiffView(rows: Diff.rows(diffBase, text), unified: true)
            } else {
                ZStack(alignment: .topLeading) {
                    editor
                    if text.isEmpty && !placeholder.isEmpty {
                        Text(placeholder)
                            .font(.system(size: fontSize))
                            .foregroundStyle(Palette.text4)
                            .padding(.leading, 50)
                            .padding(.top, 13)
                            .padding(.trailing, 24)
                            .allowsHitTesting(false)
                    }
                }
            }
            if let footer { footer }
        }
    }

    private var editor: CodeEditor {
        var drop = onFile
        if drop == nil, editable {
            let binding = $text
            drop = { url in
                if let s = try? String(contentsOf: url, encoding: .utf8) { binding.wrappedValue = s } else { NSSound.beep() }
            }
        }
        return CodeEditor(text: $text, editable: editable, syntax: syntax, errorLine: errorLine, jump: jump, marks: marks,
                          findable: primary, onFile: drop, font: EditorFont.make(family: fontName, size: fontSize), wrap: wrap || forceWrap)
    }

    @ViewBuilder private var accessories: some View {
        if let accessory { accessory }
        if editable && !output {
            IconButton(systemImage: "doc.on.clipboard", help: "Paste") {
                if let s = NSPasteboard.general.string(forType: .string) { text = s }
            }
            IconButton(systemImage: "xmark.circle", help: "Clear") { text = "" }
                .disabled(text.isEmpty)
        }
        if !forceWrap {
            IconButton(systemImage: "arrow.turn.down.left", help: wrap ? "Don't Wrap Lines (⌥⌘Z)" : "Wrap Lines (⌥⌘Z)", active: wrap) { wrap.toggle() }
        }
        if output {
            if diffBase != nil {
                IconButton(systemImage: "plusminus", help: "Compare Input and Output", active: showDiff) { showDiff.toggle() }
            }
            IconButton(systemImage: "square.and.arrow.down", help: "Save Output… (⌘S)") { save() }
                .disabled(text.isEmpty)
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(Palette.icon)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
                .help("Drag the output out as a file")
                .onDrag { Output.dragItem(Data(text.utf8), name: "Output.\(fileExtension)") }
            IconButton(systemImage: "doc.on.doc", help: "Copy Output (⇧⌘C)") { Output.copy(text) }
                .disabled(text.isEmpty)
        }
    }

    private func save() { Output.save(Data(text.utf8), name: "Output.\(fileExtension)") }

}

/// Small read-only highlighted snippet for result panels (JWT header/payload and the like).
struct CodeBlock: View {
    let text: String
    var format: Format = .json

    var body: some View {
        Text(Highlighter.spans(text, format: format).reduce(into: AttributedString()) { result, span in
            var part = AttributedString(span.text)
            part.foregroundColor = Palette.color(for: span.role)
            result += part
        })
        .font(.system(size: 12.5, design: .monospaced))
        .lineSpacing(4)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Label / value / copy rows.
struct DetailRows: View {
    let rows: [Detail]
    var mono = true

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { i, row in
                GridRow {
                    Text(row.label).foregroundStyle(Palette.text3).gridColumnAlignment(.trailing)
                    Text(row.value)
                        .font(mono ? .system(size: 13, design: .monospaced) : .system(size: 13))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    IconButton(systemImage: "doc.on.doc", help: "Copy \(row.label)") { Output.copy(row.value) }
                }
                .frame(minHeight: 32)
                if i < rows.count - 1 {
                    Rectangle().fill(Palette.cardSeparator).frame(height: 1).gridCellUnsizedAxes(.horizontal)
                }
            }
        }
        .font(.system(size: 13))
    }
}

// MARK: - Auto Detect

struct DetectPage: View {
    @Environment(Store.self) private var store
    @State private var jump: Jump?

    private struct Key: Equatable { var input: String; var options: Options }

    var body: some View {
        @Bindable var store = store
        let input = store[doc: .detect].input
        let r = store.detectResult
        let position = r?.error.flatMap(Output.lineColumn)
        ToolPage(eyebrow: chain, title: input.isEmpty ? "New" : (r?.title ?? "Text"), status: status, meta: meta) {
            options
        } content: {
            HStack(spacing: 14) {
                EditorPane(title: "Input", text: $store[doc: .detect].input,
                           placeholder: "Paste anything: JSON, escaped JSON, Base64, JavaScript, TypeScript or a Unix timestamp. The format is detected and converted automatically.",
                           errorLine: position?.line, jump: jump,
                           footer: r?.error.map { message in
                               AnyView(ErrorBar(message: message, line: position?.line) { if let p = position { jump = Jump(line: p.line, column: p.column) } })
                           })
                EditorPane(title: "Output", text: .constant(output), placeholder: "The converted result appears here.",
                           syntax: store.detectTarget?.format ?? r?.output ?? .text, editable: false, output: true, primary: true,
                           diffBase: input.isEmpty ? nil : input, fileExtension: r?.output == .json ? "json" : "txt")
            }
        }
        .task(id: Key(input: input, options: store.detectOptions)) {
            let options = store.detectOptions
            let result = await Task.detached { Engine.convert(input, options: options) }.value
            store.detectResult = result
            if let t = store.detectTarget, result?.targets.contains(t) != true { store.detectTarget = nil }
        }
    }

    private var output: String {
        guard let r = store.detectResult else { return "" }
        return store.detectTarget.map { Engine.apply($0, to: r) } ?? r.text
    }

    /// "ESCAPED STRING → JSON", "BASE64 → TEXT → JSON", "TYPESCRIPT → FORMATTED".
    private var chain: [String] {
        guard let r = store.detectResult else { return [store[doc: .detect].input.isEmpty ? "Auto detect" : "No format detected"] }
        func name(_ f: Format) -> String { f == .escapedJSON ? "Escaped string" : f.name }
        var parts = r.steps.count > 1 ? r.steps.map(\.format) : [r.input, r.output]
        parts = parts.reduce(into: []) { if $0.last != $1 { $0.append($1) } }
        var names = parts.map(name)
        if names.count == 1 { names.append(r.error == nil ? "Formatted" : "Error") }
        if let target = store.detectTarget { names.append(target.rawValue) }
        return names
    }

    private var status: Status? {
        guard let r = store.detectResult else { return nil }
        if let e = r.error { return .error(e) }
        return r.status.map { Status(text: $0) }
    }

    private var meta: [String] {
        guard let r = store.detectResult else {
            return store[doc: .detect].input.isEmpty ? ["Supported: \(Format.supported)"] : []
        }
        return r.meta
    }

    @ViewBuilder private var options: some View {
        @Bindable var store = store
        if let r = store.detectResult {
            ForEach(r.targets, id: \.self) { target in
                CapsuleButton(title: target.rawValue, selected: store.detectTarget == target) {
                    store.detectTarget = store.detectTarget == target ? nil : target
                }
            }
            if r.output == .json, r.error == nil, store.detectTarget == nil {
                OptionSegments(selection: $store.detectOptions.minify, options: [("Pretty", false), ("Minified", true)])
                OptionToggle(title: "Sort keys", isOn: $store.detectOptions.sortKeys)
            }
            if r.output == .typescript || r.output == .javascript || (r.output == .json && !store.detectOptions.minify) {
                OptionSegments(title: "Indent", selection: $store.detectOptions.indent, options: [("2", .two), ("4", .four), ("Tab", .tab)])
            }
            if r.input == .json || r.input == .escapedJSON {
                OptionToggle(title: "Unescape", isOn: $store.detectOptions.unescape)
            }
            if r.input == .base64 {
                OptionToggle(title: "Decode nested formats", isOn: $store.detectOptions.decodeNested)
            }
        } else {
            CapsuleButton(title: "Paste from Clipboard", systemImage: "doc.on.clipboard") {
                if let s = NSPasteboard.general.string(forType: .string) { store[doc: .detect].input = s }
            }
            CapsuleButton(title: "Open File…", systemImage: "folder") { store.importing = true }
        }
    }
}

// MARK: - Inspector (detection details for the Auto Detect page)

struct InspectorView: View {
    @Environment(Store.self) private var store

    var body: some View {
        Form {
            if let r = store.detectResult {
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
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Command palette

struct CommandPalette: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var index = 0

    private enum Item: Identifiable {
        case tool(Tool), entry(Entry)
        var id: String {
            switch self {
            case .tool(let t): "tool-" + t.rawValue
            case .entry(let e): e.id.uuidString
            }
        }
    }

    private var items: [Item] {
        let q = query.lowercased()
        func match(_ s: String) -> Bool {
            guard !q.isEmpty else { return true }
            var it = s.lowercased().makeIterator()
            return q.allSatisfy { c in while let n = it.next() { if n == c { return true } }; return false }
        }
        let tools = Tool.allCases.filter { match($0.name) || match($0.category.rawValue) }.map(Item.tool)
        let entries = store.entries.filter { match($0.title) || (!q.isEmpty && $0.input.prefix(2000).lowercased().contains(q)) }.prefix(50).map(Item.entry)
        return tools + entries
    }

    var body: some View {
        let items = items
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.text3)
                TextField("Jump to a tool or history entry", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 17))
                    .onSubmit { if items.indices.contains(index) { open(items[index]) } }
                    .onKeyPress(.downArrow) { index = min(index + 1, items.count - 1); return .handled }
                    .onKeyPress(.upArrow) { index = max(index - 1, 0); return .handled }
            }
            .padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { i, item in
                            row(item, selected: i == index)
                                .onTapGesture { open(item) }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: index) { _, i in if items.indices.contains(i) { proxy.scrollTo(items[i].id) } }
            }
        }
        .frame(width: 560, height: 420)
        .onChange(of: query) { index = 0 }
        .onExitCommand { dismiss() }
    }

    private func row(_ item: Item, selected: Bool) -> some View {
        HStack(spacing: 10) {
            switch item {
            case .tool(let t):
                Image(systemName: t.icon).frame(width: 18).foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(Palette.icon))
                Text(t.name)
                Spacer()
                Text(t.category.rawValue).foregroundStyle(Palette.text4).font(.system(size: 11.5))
            case .entry(let e):
                Dot(color: e.dot).frame(width: 18)
                Text(e.title).lineLimit(1)
                Spacer()
                Text("\(e.tool.name) · \(e.date.formatted(.relative(presentation: .named)))").foregroundStyle(Palette.text4).font(.system(size: 11.5))
            }
        }
        .font(.system(size: 13.5))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(selected ? Palette.accentTint : .clear, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }

    private func open(_ item: Item) {
        switch item {
        case .tool(let t): store.open(t)
        case .entry(let e): store.open(e)
        }
        dismiss()
    }
}

// MARK: - Settings

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }
            EditorSettings().tabItem { Label("Editor", systemImage: "character.cursor.ibeam") }
            SidebarSettings().tabItem { Label("Sidebar", systemImage: "sidebar.left") }
            HistorySettings().tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
        }
        .frame(width: 520)
    }
}

struct GeneralSettings: View {
    @Environment(Store.self) private var store
    @AppStorage("darkMode") private var darkMode: Bool?
    @AppStorage("indent") private var indent: Indent = .two
    @AppStorage("sortKeys") private var sortKeys = false
    @AppStorage("timeZone") private var timeZone = ""
    @AppStorage("useExternalFormatter") private var useExternal = true
    @State private var formatters: ExternalFormatters?

    var body: some View {
        Form {
            Picker("Appearance", selection: $darkMode) {
                Text("System").tag(Bool?.none)
                Text("Light").tag(Bool?.some(false))
                Text("Dark").tag(Bool?.some(true))
            }
            Section("Defaults") {
                Picker("Indent", selection: $indent) {
                    ForEach(Indent.allCases, id: \.self) { Text($0.rawValue) }
                }
                Toggle("Sort JSON keys", isOn: $sortKeys)
                Picker("Time zone", selection: $timeZone) {
                    Text("System (\(TimeZone.current.identifier))").tag("")
                    Divider()
                    ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0).tag($0) }
                }
            }
            Section("Formatter") {
                Toggle("Use Biome or Prettier when installed", isOn: $useExternal)
                LabeledContent("Biome", value: formatters.map { $0.biome ?? "Not found" } ?? "Looking…")
                LabeledContent("Prettier", value: formatters.map { $0.prettier ?? "Not found" } ?? "Looking…")
            }
            Section {
                Link("Decant on GitHub", destination: githubURL)
            }
        }
        .formStyle(.grouped)
        .onChange(of: indent) { _, v in store.detectOptions.indent = v }
        .onChange(of: sortKeys) { _, v in store.detectOptions.sortKeys = v }
        .task { formatters = await Task.detached { ExternalFormatters.shared }.value }
    }
}

struct EditorSettings: View {
    @AppStorage("fontName") private var fontName = ""
    @AppStorage("fontSize") private var fontSize = 13.0
    @AppStorage("wrapLines") private var wrap = false

    var body: some View {
        Form {
            Picker("Font", selection: $fontName) {
                Text("System Monospaced").tag("")
                Divider()
                ForEach(EditorFont.families, id: \.self) { Text($0).tag($0) }
            }
            Stepper("Size: \(Int(fontSize)) pt", value: $fontSize, in: 9...32)
            Toggle("Wrap lines", isOn: $wrap)
            Text("⌘+ and ⌘− change the size, ⌥⌘Z toggles wrapping.").foregroundStyle(.secondary).font(.callout)
        }
        .formStyle(.grouped)
    }
}

struct SidebarSettings: View {
    @AppStorage("toolOrder") private var order = ""
    @AppStorage("hiddenTools") private var hidden = ""
    @AppStorage("groupTools") private var group = true

    var body: some View {
        let hiddenSet = ToolLayout.hiddenSet(hidden)
        Form {
            Toggle("Group tools by category", isOn: $group)
            Section {
                List {
                    ForEach(ToolLayout.ordered(order)) { tool in
                        HStack {
                            Image(systemName: tool.icon).frame(width: 20).foregroundStyle(.secondary)
                            Text(tool.name)
                            Spacer()
                            Text(tool.category.rawValue).foregroundStyle(.tertiary)
                            Toggle(tool.name, isOn: Binding(get: { !hiddenSet.contains(tool) }, set: { show in
                                var h = hiddenSet
                                if show { h.remove(tool) } else { h.insert(tool) }
                                hidden = ToolLayout.encode(Tool.sidebarTools.filter(h.contains))
                            }))
                            .labelsHidden()
                        }
                    }
                    .onMove { from, to in
                        var tools = ToolLayout.ordered(order)
                        tools.move(fromOffsets: from, toOffset: to)
                        order = ToolLayout.encode(tools)
                    }
                }
                .frame(height: 300)
            } header: {
                Text("Drag to reorder. ⌘1–⌘9 follow this order.")
            }
            Button("Restore Defaults") {
                order = ""
                hidden = ""
                group = true
            }
        }
        .formStyle(.grouped)
    }
}

struct HistorySettings: View {
    @Environment(Store.self) private var store
    @AppStorage("historyDays") private var days = 0
    @AppStorage("historyLimit") private var limit = 200

    var body: some View {
        Form {
            Picker("Keep entries", selection: $days) {
                Text("Forever").tag(0)
                Text("For a day").tag(1)
                Text("For a week").tag(7)
                Text("For a month").tag(30)
                Text("For three months").tag(90)
            }
            Picker("Maximum entries", selection: $limit) {
                ForEach([25, 50, 100, 200, 500, 1000], id: \.self) { Text("\($0)").tag($0) }
            }
            Text("Pinned entries are never removed automatically.").foregroundStyle(.secondary).font(.callout)
            LabeledContent("Entries", value: "\(store.entries.count)")
            Button("Clear History", role: .destructive) { store.clearHistory() }
        }
        .formStyle(.grouped)
        .onChange(of: days) { store.prune() }
        .onChange(of: limit) { store.prune() }
    }
}

#if DEBUG
// Debug-only visual check from the CLI: `[DECANT_TOOL=base64] DECANT_INPUT=… [DECANT_AUX=…] DECANT_SNAPSHOT=out.png [DECANT_DARK=1] .build/debug/Decant`
// loads the input, writes a PNG of the window and quits. Needs no screen-recording permission.
extension ContentView {
    func debugSnapshot() async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["DECANT_SNAPSHOT"] else { return }
        if let dark = env["DECANT_DARK"] { UserDefaults.standard.set(dark == "1", forKey: "darkMode") }
        try? await Task.sleep(for: .seconds(0.5))
        if let tool = env["DECANT_TOOL"].flatMap(Tool.init(rawValue:)) { store.open(tool) }
        if let input = env["DECANT_INPUT"] { store[doc: store.tool].input = input }
        if let aux = env["DECANT_AUX"] { store[doc: store.tool].aux = aux }
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
