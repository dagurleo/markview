import Cocoa
import CoreText
import Sparkle
import SwiftUI

/// Markview > Settings…: General, Appearance and Editor panes, each a SwiftUI form, under
/// toolbar tabs as in macOS's own apps. A change is written to the defaults at once, and
/// the app delegate shows it in the open windows.
final class SettingsWindowController: NSWindowController {
    convenience init(updater: SPUUpdater) {
        let tabs = SettingsTabs()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(Self.pane("General", symbol: "gearshape", GeneralSettings(updater: updater)))
        tabs.addTabViewItem(Self.pane("Appearance", symbol: "paintpalette", AppearanceSettings()))
        tabs.addTabViewItem(Self.pane("Editor", symbol: "pencil.line", EditorPane()))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.toolbarStyle = .preference
        window.center()
        self.init(window: window)
    }

    private static func pane(_ title: String, symbol: String, _ content: some View) -> NSTabViewItem {
        let controller = NSHostingController(rootView: content)
        controller.sizingOptions = .preferredContentSize
        controller.title = title
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        return item
    }
}

/// Fits the window to each pane as it is chosen, keeping its top edge in place.
private final class SettingsTabs: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect item: NSTabViewItem?) {
        super.tabView(tabView, didSelect: item)
        guard let window = view.window, let size = item?.viewController?.preferredContentSize, size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        window.setFrame(frame, display: true, animate: window.isVisible)
    }
}

private struct GeneralSettings: View {
    let updater: SPUUpdater
    /// Bumped to read the updater and the default app again.
    @State private var refresh = 0

    var body: some View {
        let _ = refresh
        Form {
            // Bound to Sparkle itself, so that opening Settings does not answer the question it asks on the second launch.
            Toggle("Check for updates automatically", isOn: Binding(
                get: { updater.automaticallyChecksForUpdates },
                set: { updater.automaticallyChecksForUpdates = $0; refresh += 1 }))
            LabeledContent {
                if AppDelegate.isDefaultViewer {
                    Text("Markview").foregroundStyle(.secondary)
                } else {
                    Button("Make Default") { AppDelegate.makeDefaultViewer { refresh += 1 } }
                }
            } label: {
                Text("Default Markdown viewer")
                Text("The app that opens Markdown files from Finder")
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 560)
        .fixedSize()
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refresh += 1 }
    }
}

private struct AppearanceSettings: View {
    @AppStorage(Settings.Key.theme) private var theme = Palette.github.id
    @AppStorage(Settings.Key.appearance) private var appearance = "system"
    @AppStorage(Settings.Key.textSize) private var textSize = Double(Settings.defaultTheme.bodySize)
    @AppStorage(Settings.Key.textFont) private var textFont = ""
    @AppStorage(Settings.Key.codeFont) private var codeFont = ""
    @AppStorage(Settings.Key.lineLength) private var lineLength = Double(Settings.defaultTheme.columnWidth)
    @AppStorage(Settings.Key.lineSpacing) private var lineSpacing = Double(Settings.defaultTheme.lineSpacing)
    @State private var families = FontFamilies()

    var body: some View {
        Form {
            Section("Theme") {
                ThemePicker(selection: $theme)
            }
            Section {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            Section {
                LabeledContent {
                    HStack(spacing: 10) {
                        Slider(value: $textSize, in: 12...24, step: 1) {
                            EmptyView()
                        } minimumValueLabel: {
                            Text("A").font(.system(size: 10))
                        } maximumValueLabel: {
                            Text("A").font(.system(size: 16))
                        }
                        Text("\(Int(textSize)) pt").monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                    }
                    .frame(width: 250)
                } label: {
                    Text("Text size")
                    Text("The whole page grows with it")
                }
                Picker("Text font", selection: $textFont) {
                    Text("System").tag("")
                    Text("New York").tag("New York")
                    Divider()
                    ForEach(families.choices(families.text, keeping: textFont, besides: ["", "New York"]), id: \.self) { Text($0).tag($0) }
                }
                Picker(selection: $codeFont) {
                    Text("SF Mono").tag("")
                    Divider()
                    ForEach(families.choices(families.code, keeping: codeFont, besides: [""]), id: \.self) { Text($0).tag($0) }
                } label: {
                    Text("Code font")
                    Text("Drawings made of box characters keep SF Mono, so their lines join")
                }
                Picker("Line length", selection: $lineLength) {
                    Text("Narrow").tag(600.0)
                    Text("Default").tag(736.0)
                    Text("Wide").tag(920.0)
                    Text("Extra wide").tag(1200.0)
                }
                Picker("Line spacing", selection: $lineSpacing) {
                    Text("Tight").tag(1.15)
                    Text("Default").tag(1.3)
                    Text("Loose").tag(1.5)
                }
                .pickerStyle(.segmented)
                .fixedSize()
            }
            HStack {
                Text("Changes show at once in open windows and in Quick Look.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { Settings.Key.all.forEach(UserDefaults.standard.removeObject) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 560)
        .fixedSize()
        .task { families = await FontFamilies.installed() }
    }
}

/// The editor beside the page: its font, line numbers and wrapping, what Tab inserts, and what
/// typing changes by itself.
private struct EditorPane: View {
    @AppStorage(EditorSettings.Key.font) private var font = ""
    @AppStorage(EditorSettings.Key.lineNumbers) private var lineNumbers = EditorSettings().lineNumbers
    @AppStorage(EditorSettings.Key.wraps) private var wraps = EditorSettings().wraps
    @AppStorage(EditorSettings.Key.indentWithTabs) private var indentWithTabs = EditorSettings().indentWithTabs
    @AppStorage(EditorSettings.Key.indentWidth) private var indentWidth = EditorSettings().indentWidth
    @AppStorage(EditorSettings.Key.spelling) private var spelling = EditorSettings().spelling
    @AppStorage(EditorSettings.Key.smartQuotes) private var smartQuotes = EditorSettings().smartQuotes
    @AppStorage(EditorSettings.Key.smartDashes) private var smartDashes = EditorSettings().smartDashes
    @AppStorage(EditorSettings.Key.textReplacement) private var textReplacement = EditorSettings().textReplacement
    @AppStorage(EditorSettings.Key.slashMenu) private var slashMenu = EditorSettings().slashMenu
    @State private var families = FontFamilies()

    var body: some View {
        Form {
            Section {
                Picker(selection: $font) {
                    Text("Same as code").tag("")
                    Divider()
                    ForEach(families.choices(families.code, keeping: font, besides: [""]), id: \.self) { Text($0).tag($0) }
                } label: {
                    Text("Font")
                    Text("At the size of code on the page, which the text size sets")
                }
                Toggle("Show line numbers", isOn: $lineNumbers)
                Toggle("Wrap long lines", isOn: $wraps)
            }
            Section {
                Picker("Tab inserts", selection: $indentWithTabs) {
                    Text("Spaces").tag(false)
                    Text("A tab").tag(true)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                Picker("Indent width", selection: $indentWidth) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }
                .pickerStyle(.segmented)
                .fixedSize()
                .disabled(indentWithTabs)
                Text("On a list item, Tab nests it under the item above, lined up with that item's text.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Section("While typing") {
                Toggle("Check spelling", isOn: $spelling)
                Toggle("Smart quotes", isOn: $smartQuotes)
                Toggle("Smart dashes", isOn: $smartDashes)
                Toggle("Text replacement", isOn: $textReplacement)
                Toggle(isOn: $slashMenu) {
                    Text("Slash menu")
                    Text("Type / at the start of a line or after a space to insert a heading, list, table, code block and more")
                }
            }
            HStack {
                Text("Spelling leaves code, addresses and tags alone.").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Restore Defaults") { EditorSettings.Key.all.forEach(UserDefaults.standard.removeObject) }
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 560)
        .fixedSize()
        .task { families = await FontFamilies.installed() }
    }
}

/// The themes as swatches, six to a row, each half light and half dark.
private struct ThemePicker: View {
    @Binding var selection: String

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(76), spacing: 10), count: 6), spacing: 12) {
            ForEach(Palette.all, id: \.id) { palette in
                let chosen = palette.id == selection
                Button { selection = palette.id } label: {
                    VStack(spacing: 6) {
                        HStack(spacing: 0) {
                            half(palette, dark: false)
                            half(palette, dark: true)
                        }
                        .frame(width: 70, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay {
                            RoundedRectangle(cornerRadius: 7).strokeBorder(Color.primary.opacity(0.15))
                        }
                        .padding(3)
                        .overlay {
                            if chosen { RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3) }
                        }
                        Text(palette.name).font(.caption)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(palette.name)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func half(_ palette: Palette, dark: Bool) -> some View {
        func color(_ pair: Palette.Pair) -> Color { Color(nsColor: Theme.rgb(dark ? pair.dark : pair.light)) }
        return VStack(alignment: .leading, spacing: 4) {
            Text("Aa").font(.system(size: 13, weight: .semibold)).foregroundStyle(color(palette.text))
            Capsule().fill(color(palette.link)).frame(width: 20, height: 3)
            Capsule().fill(color(palette.keyword)).frame(width: 14, height: 3)
            Capsule().fill(color(palette.muted)).frame(width: 24, height: 3)
        }
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(color(palette.background))
    }
}

/// The installed font families, and which of them are monospaced. Finding out takes a tenth
/// of a second or more, so it is done off the main thread when the pane opens.
private struct FontFamilies {
    var text: [String] = []
    var code: [String] = []

    static func installed() async -> FontFamilies {
        await Task.detached(priority: .userInitiated) {
            let families = (CTFontManagerCopyAvailableFontFamilyNames() as? [String] ?? [])
                .filter { !$0.hasPrefix(".") }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            return FontFamilies(text: families, code: families.filter(isMonospaced))
        }.value
    }

    /// Some monospaced families do not say so, so the widths of a few letters decide.
    private static func isMonospaced(_ family: String) -> Bool {
        let font = CTFontCreateWithFontDescriptor(CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary), 12, nil)
        if CTFontGetSymbolicTraits(font).contains(.traitMonoSpace) { return true }
        var characters = Array("iMW.".utf16), glyphs = [CGGlyph](repeating: 0, count: 4), advances = [CGSize](repeating: .zero, count: 4)
        guard CTFontGetGlyphsForCharacters(font, &characters, &glyphs, 4) else { return false }
        CTFontGetAdvancesForGlyphs(font, .horizontal, glyphs, &advances, 4)
        return advances.allSatisfy { abs($0.width - advances[0].width) < 0.01 }
    }

    /// The families to offer, with the chosen one among them even before the list is in or
    /// once it is uninstalled, so the menu never shows a blank.
    func choices(_ families: [String], keeping chosen: String, besides fixed: [String]) -> [String] {
        families.contains(chosen) || fixed.contains(chosen) ? families : [chosen] + families
    }
}
