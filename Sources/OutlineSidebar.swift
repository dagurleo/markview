import Cocoa

/// The document's headings beside the page (View > Show Outline), with the one being read
/// marked; clicking one goes to it. In the theme's colours, as part of the page rather than
/// of the window.
final class OutlineSidebar: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: (Heading) -> Void = { _ in }
    private(set) var headings: [Heading] = []
    /// The heading being read: the last one above the top of the page.
    private(set) var current: Int?
    private var theme = Settings.theme
    private var topLevel = 1
    private let table = NSTableView()
    private let header = NSTextField(labelWithString: "Contents")
    private let empty = NSTextField(labelWithString: "No Headings")
    private let background = SidebarBackground()
    private let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 400))

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("heading"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        table.headerView = nil
        table.style = .plain
        table.backgroundColor = .clear
        table.rowSizeStyle = .custom
        table.rowHeight = 26
        table.intercellSpacing = NSSize(width: 0, height: 1)
        table.selectionHighlightStyle = .none
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        // The text keeps the keyboard, so the page still scrolls with the arrow keys after a click here.
        table.refusesFirstResponder = true
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(clicked)

        scroll.documentView = table
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
        scroll.translatesAutoresizingMaskIntoConstraints = false

        header.font = .systemFont(ofSize: 11, weight: .semibold)
        header.translatesAutoresizingMaskIntoConstraints = false
        empty.font = .systemFont(ofSize: 13)
        empty.translatesAutoresizingMaskIntoConstraints = false

        background.frame = scroll.frame
        background.addSubview(header)
        background.addSubview(scroll)
        background.addSubview(empty)
        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: background.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: background.leadingAnchor, constant: 18),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            empty.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            empty.leadingAnchor.constraint(equalTo: header.leadingAnchor),
        ])
        view = background
        apply(theme)
    }

    // The one column spans the sidebar, however wide it is dragged.
    override func viewDidLayout() {
        super.viewDidLayout()
        table.tableColumns.first?.width = scroll.contentSize.width
    }

    func show(_ headings: [Heading]) {
        self.headings = headings
        topLevel = headings.map(\.level).min() ?? 1
        current = nil
        empty.isHidden = !headings.isEmpty
        table.reloadData()
    }

    func mark(_ index: Int?) {
        guard index != current else { return }
        let rows = IndexSet([current, index].compactMap { $0 })
        current = index
        table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
        for row in rows { (table.rowView(atRow: row, makeIfNecessary: false) as? OutlineRow)?.isCurrent = row == current }
        if let index { table.scrollRowToVisible(index) }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        background.color = theme.subtle
        header.textColor = theme.muted
        empty.textColor = theme.muted
        table.reloadData()
    }

    @objc private func clicked() {
        guard headings.indices.contains(table.clickedRow) else { return }
        onSelect(headings[table.clickedRow])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: OutlineRow.identifier, owner: self) as? OutlineRow ?? OutlineRow()
        view.colors = (theme.link, theme.text)
        view.isCurrent = row == current
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: HeadingCell.identifier, owner: self) as? HeadingCell ?? HeadingCell()
        let heading = headings[row], marked = row == current
        cell.label.stringValue = heading.title
        cell.toolTip = heading.title
        cell.label.font = .systemFont(ofSize: 13, weight: marked || heading.level == topLevel ? .semibold : .regular)
        cell.label.textColor = marked ? theme.link : heading.level - topLevel >= 2 ? theme.muted : theme.text
        cell.indent.constant = 18 + CGFloat(min(heading.level - topLevel, 4)) * 14
        return cell
    }
}

/// One heading of the outline, indented by its level.
private final class HeadingCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("HeadingCell")
    let label = NSTextField(labelWithString: "")
    var indent: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        indent = label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16)
        NSLayoutConstraint.activate([
            indent,
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
}

/// A heading's row: a soft rounded highlight behind the heading being read, a fainter one under
/// the pointer, and the pointing hand over it, as over a link.
private final class OutlineRow: NSTableRowView {
    static let identifier = NSUserInterfaceItemIdentifier("OutlineRow")
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
private final class SidebarBackground: NSView {
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
