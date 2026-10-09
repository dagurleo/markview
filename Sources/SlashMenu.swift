import AppKit

/// The list the slash menu shows under the insertion point. It is in a panel that never takes the
/// keyboard: the text view goes on taking the typing, and passes the menu the arrow keys, Return,
/// Tab and Escape (see SourceTextView).
final class SlashMenu: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var onChoose: (SlashCommand) -> Void = { _ in }
    private(set) var commands: [SlashCommand] = []
    private let panel = Panel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
    private let table = Table()
    private static let rowHeight: CGFloat = 26, width: CGFloat = 300, rowsShown = 9, margin: CGFloat = 5

    var isShown: Bool { panel.parent != nil }
    var selected: SlashCommand? { commands.indices.contains(table.selectedRow) ? commands[table.selectedRow] : nil }

    override init() {
        super.init()
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none

        let background = NSVisualEffectView()
        background.material = .menu
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 10
        background.layer?.masksToBounds = true

        table.addTableColumn(NSTableColumn(identifier: .init("command")))
        table.headerView = nil
        table.style = .plain
        table.rowHeight = Self.rowHeight
        table.intercellSpacing = .zero
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.dataSource = self
        table.delegate = self
        table.onClick = { [weak self] row in
            guard let self, commands.indices.contains(row) else { return }
            onChoose(commands[row])
        }

        let scroll = NSScrollView()
        scroll.documentView = table
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.automaticallyAdjustsContentInsets = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: background.topAnchor, constant: Self.margin),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor, constant: -Self.margin),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: Self.margin),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor, constant: -Self.margin),
        ])
        panel.contentView = background
    }

    /// Shows commands under a character, given in screen coordinates, or above it if the screen
    /// has no room below. A new list starts with its first command chosen.
    func show(_ commands: [SlashCommand], under character: NSRect, in window: NSWindow) {
        let row = commands.map(\.title) == self.commands.map(\.title) ? table.selectedRow : 0
        self.commands = commands
        table.reloadData()
        select(max(row, 0))
        let height = CGFloat(min(commands.count, Self.rowsShown)) * Self.rowHeight + 2 * Self.margin
        place(height: height, under: character, in: window)
        if panel.parent == nil { window.addChildWindow(panel, ordered: .above) }
    }

    /// Follows the character the menu is under, as the text scrolls.
    func move(under character: NSRect, in window: NSWindow) {
        guard isShown else { return }
        place(height: panel.frame.height, under: character, in: window)
    }

    private func place(height: CGFloat, under character: NSRect, in window: NSWindow) {
        let screen = (window.screen ?? NSScreen.main)?.visibleFrame ?? .infinite
        var frame = NSRect(x: character.minX - 30, y: character.minY - 4 - height, width: Self.width, height: height)
        if frame.minY < screen.minY { frame.origin.y = character.maxY + 4 }
        frame.origin.x = max(min(frame.minX, screen.maxX - frame.width), screen.minX)
        panel.setFrame(frame, display: true)
    }

    /// Moves the choice up or down the list, stopping at either end.
    func step(_ by: Int) {
        guard !commands.isEmpty else { return }
        select(min(max(table.selectedRow + by, 0), commands.count - 1))
    }

    private func select(_ row: Int) {
        guard commands.indices.contains(row) else { return }
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        commands = []
        table.reloadData()
    }

    // MARK: Table

    func numberOfRows(in tableView: NSTableView) -> Int { commands.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? { Row() }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: Cell.identifier, owner: nil) as? Cell ?? Cell()
        cell.show(commands[row])
        return cell
    }

    /// Never takes the keyboard or the window's focus.
    private final class Panel: NSPanel {
        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    /// Chooses with one click, in a window that is not key.
    private final class Table: NSTableView {
        var onClick: (Int) -> Void = { _ in }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override var acceptsFirstResponder: Bool { false }
        override func mouseDown(with event: NSEvent) {
            onClick(row(at: convert(event.locationInWindow, from: nil)))
        }
    }

    /// The choice in the accent colour, as in a menu, though the panel is never key.
    private final class Row: NSTableRowView {
        override var isEmphasized: Bool {
            get { true }
            set {}
        }

        override func drawSelection(in dirtyRect: NSRect) {
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: bounds.insetBy(dx: 0, dy: 1), xRadius: 5, yRadius: 5).fill()
        }
    }

    /// A symbol, the command's title, and on the right the Markdown it writes.
    private final class Cell: NSTableCellView {
        static let identifier = NSUserInterfaceItemIdentifier("SlashCommand")
        private let symbol = NSImageView()
        private let title = NSTextField(labelWithString: "")
        private let hint = NSTextField(labelWithString: "")

        init() {
            super.init(frame: .zero)
            identifier = Self.identifier
            imageView = symbol
            textField = title
            symbol.symbolConfiguration = .init(pointSize: 13, weight: .regular)
            symbol.imageScaling = .scaleProportionallyDown
            title.font = .menuFont(ofSize: 13)
            title.lineBreakMode = .byTruncatingTail
            title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            hint.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            hint.alignment = .right
            hint.setContentHuggingPriority(.required, for: .horizontal)
            for view in [symbol, title, hint] {
                view.translatesAutoresizingMaskIntoConstraints = false
                addSubview(view)
            }
            NSLayoutConstraint.activate([
                symbol.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
                symbol.centerYAnchor.constraint(equalTo: centerYAnchor),
                symbol.widthAnchor.constraint(equalToConstant: 18),
                title.leadingAnchor.constraint(equalTo: symbol.trailingAnchor, constant: 8),
                title.centerYAnchor.constraint(equalTo: centerYAnchor),
                hint.leadingAnchor.constraint(greaterThanOrEqualTo: title.trailingAnchor, constant: 8),
                hint.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                hint.firstBaselineAnchor.constraint(equalTo: title.firstBaselineAnchor),
            ])
            backgroundStyle = .normal
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

        func show(_ command: SlashCommand) {
            symbol.image = NSImage(systemSymbolName: command.symbol, accessibilityDescription: nil)
            title.stringValue = command.title
            hint.stringValue = command.hint
        }

        override var backgroundStyle: NSView.BackgroundStyle {
            didSet {
                let chosen = backgroundStyle == .emphasized
                title.textColor = chosen ? .alternateSelectedControlTextColor : .labelColor
                hint.textColor = chosen ? .alternateSelectedControlTextColor.withAlphaComponent(0.8) : .secondaryLabelColor
                symbol.contentTintColor = chosen ? .alternateSelectedControlTextColor : .secondaryLabelColor
            }
        }
    }
}
