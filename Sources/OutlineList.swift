import Cocoa

/// The document's headings, the sidebar's Contents, with the one being read marked; clicking
/// one goes to it.
final class OutlineList: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    var onSelect: (Heading) -> Void = { _ in }
    private(set) var headings: [Heading] = []
    /// The heading being read: the last one above the top of the page.
    private(set) var current: Int?
    private var theme = Settings.theme
    private var topLevel = 1
    private let table = NSTableView()
    private let empty = NSTextField(labelWithString: "No Headings")
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
        listInScroll(table, scroll)

        empty.font = .systemFont(ofSize: 13)
        empty.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView(frame: scroll.frame)
        container.addSubview(scroll)
        container.addSubview(empty)
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: container.topAnchor), scroll.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: container.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            empty.topAnchor.constraint(equalTo: container.topAnchor, constant: 2),
            empty.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 18),
        ])
        view = container
        apply(theme)
    }

    // The one column spans the sidebar, however wide it is dragged.
    override func viewDidLayout() {
        super.viewDidLayout()
        table.tableColumns.first?.width = scroll.contentSize.width
    }

    func show(_ headings: [Heading]) {
        _ = view
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
        for row in rows { (table.rowView(atRow: row, makeIfNecessary: false) as? SidebarRow)?.isCurrent = row == current }
        if let index { table.scrollRowToVisible(index) }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        empty.textColor = theme.muted
        table.reloadData()
    }

    @objc private func clicked() {
        guard headings.indices.contains(table.clickedRow) else { return }
        onSelect(headings[table.clickedRow])
    }

    func numberOfRows(in tableView: NSTableView) -> Int { headings.count }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        let view = tableView.makeView(withIdentifier: SidebarRow.identifier, owner: self) as? SidebarRow ?? SidebarRow()
        view.colors = (theme.link, theme.text)
        view.isCurrent = row == current
        return view
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = tableView.makeView(withIdentifier: SidebarCell.identifier, owner: self) as? SidebarCell ?? SidebarCell()
        let heading = headings[row], marked = row == current
        cell.label.stringValue = heading.title
        cell.toolTip = heading.title
        cell.label.font = .systemFont(ofSize: 13, weight: marked || heading.level == topLevel ? .semibold : .regular)
        cell.label.textColor = marked ? theme.link : heading.level - topLevel >= 2 ? theme.muted : theme.text
        cell.indent.constant = 18 + CGFloat(min(heading.level - topLevel, 4)) * 14
        cell.show(icon: nil)
        return cell
    }
}

/// A list in a scroll view of its own, with no background, as both lists of the sidebar are.
func listInScroll(_ list: NSTableView, _ scroll: NSScrollView) {
    scroll.documentView = list
    scroll.hasVerticalScroller = true
    scroll.autohidesScrollers = true
    scroll.drawsBackground = false
    scroll.automaticallyAdjustsContentInsets = false
    scroll.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 12, right: 0)
    scroll.translatesAutoresizingMaskIntoConstraints = false
}

/// One line of either list: an optional icon and a name, indented by its depth.
final class SidebarCell: NSTableCellView {
    static let identifier = NSUserInterfaceItemIdentifier("SidebarCell")
    let label = NSTextField(labelWithString: "")
    let icon = NSImageView()
    var indent: NSLayoutConstraint!
    private var iconWidth: NSLayoutConstraint!
    private var gap: NSLayoutConstraint!

    init() {
        super.init(frame: .zero)
        identifier = Self.identifier
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.imageScaling = .scaleProportionallyDown
        addSubview(icon)
        addSubview(label)
        indent = icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 18)
        iconWidth = icon.widthAnchor.constraint(equalToConstant: 0)
        gap = label.leadingAnchor.constraint(equalTo: icon.trailingAnchor)
        NSLayoutConstraint.activate([
            indent, iconWidth, gap, icon.heightAnchor.constraint(equalToConstant: 16), icon.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// An icon takes room and a gap after it; without one, the name starts where the icon would.
    func show(icon image: NSImage?) {
        icon.image = image
        iconWidth.constant = image == nil ? 0 : 16
        gap.constant = image == nil ? 0 : 6
    }
}
