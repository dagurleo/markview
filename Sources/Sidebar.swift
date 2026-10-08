import Cocoa

/// The sidebar beside the page (View > Show Sidebar): the document's headings, and in a folder's
/// window the folder's files as well, under two tabs. In the theme's colours, as part of the
/// page rather than of the window.
final class Sidebar: NSViewController {
    let outline = OutlineList()
    let files = FileList()
    private var theme = Settings.theme
    private let background = SidebarBackground()
    private let filesTab = SidebarTab(title: "Files"), contentsTab = SidebarTab(title: "Contents")
    private let content = NSView()
    /// Whether the window shows a folder, whose files then have a tab of their own.
    private(set) var hasFolder = false
    private(set) var showsFiles = false

    override func loadView() {
        filesTab.target = self
        filesTab.action = #selector(chooseTab(_:))
        contentsTab.target = self
        contentsTab.action = #selector(chooseTab(_:))
        let tabs = NSStackView(views: [filesTab, contentsTab])
        tabs.spacing = 14
        tabs.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        background.frame = NSRect(x: 0, y: 0, width: 220, height: 400)
        background.addSubview(tabs)
        background.addSubview(content)
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: background.topAnchor, constant: 14),
            tabs.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            content.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8),
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
        ])
        view = background
        apply(theme)
        showTab(files: false)
    }

    /// A folder's window opens on its files.
    func show(folder: URL, tree: FileNode) {
        _ = view
        hasFolder = true
        files.show(folder: folder, tree: tree)
        showTab(files: true)
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        background.color = theme.subtle
        outline.apply(theme)
        files.apply(theme)
        styleTabs()
    }

    @objc private func chooseTab(_ sender: SidebarTab) { showTab(files: sender === filesTab) }

    private func showTab(files showFiles: Bool) {
        showsFiles = showFiles && hasFolder
        let shown = showsFiles ? files.view : outline.view
        content.subviews.forEach { $0.removeFromSuperview() }
        shown.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(shown)
        NSLayoutConstraint.activate([
            shown.topAnchor.constraint(equalTo: content.topAnchor), shown.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            shown.leadingAnchor.constraint(equalTo: content.leadingAnchor), shown.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ])
        styleTabs()
    }

    // Without a folder, Contents is the sidebar's heading rather than a tab.
    private func styleTabs() {
        filesTab.isHidden = !hasFolder
        filesTab.style(selected: showsFiles, colors: (theme.text, theme.muted))
        contentsTab.style(selected: hasFolder && !showsFiles, colors: (theme.text, theme.muted))
        contentsTab.isEnabled = hasFolder
    }
}

/// A tab of the sidebar: its name, darker when chosen.
final class SidebarTab: NSButton {
    convenience init(title: String) {
        self.init(frame: .zero)
        self.title = title
        isBordered = false
        setButtonType(.momentaryChange)
    }

    func style(selected: Bool, colors: (selected: NSColor, other: NSColor)) {
        attributedTitle = NSAttributedString(string: title, attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold), .foregroundColor: selected ? colors.selected : colors.other])
    }

    override func resetCursorRects() { if isEnabled { addCursorRect(bounds, cursor: .pointingHand) } }
}

/// A row of either list: a soft rounded highlight behind the one being read, a fainter one under
/// the pointer, and the pointing hand over it, as over a link.
final class SidebarRow: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarRow")
    var colors = (accent: NSColor.controlAccentColor, ink: NSColor.labelColor) { didSet { needsDisplay = true } }
    var isCurrent = false { didSet { if isCurrent != oldValue { needsDisplay = true } } }
    private var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func mouseEntered(with event: NSEvent) { isHovered = true }
    override func mouseExited(with event: NSEvent) { isHovered = false }
    override func prepareForReuse() {
        super.prepareForReuse()
        isHovered = false
    }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    // Drawn in the colours of the moment, light or dark, faded to a tint.
    override func drawBackground(in dirtyRect: NSRect) {
        guard isCurrent || isHovered else { return }
        let tint = (isCurrent ? colors.accent : colors.ink).usingColorSpace(.sRGB)?.withAlphaComponent(isCurrent ? 0.13 : 0.06)
        tint?.setFill()
        NSBezierPath(roundedRect: bounds.insetBy(dx: 8, dy: 1), xRadius: 6, yRadius: 6).fill()
    }
}

/// The sidebar's fill, in a colour that follows the appearance.
final class SidebarBackground: NSView {
    var color: NSColor = .clear { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        dirtyRect.fill()
    }
}

/// A split view whose divider takes the theme's border colour.
final class OutlineSplitView: NSSplitView {
    var color: NSColor = .separatorColor { didSet { needsDisplay = true } }
    override var dividerColor: NSColor { color }
}
