import Cocoa

/// A folder's Markdown files, the sidebar's Files: a folder opens and closes, a file opens in the
/// window, and the one on show is marked. The list follows the folder as files come and go.
final class FileList: NSViewController, NSOutlineViewDataSource, NSOutlineViewDelegate {
    var onSelect: (URL) -> Void = { _ in }
    private(set) var folder: URL?
    private var tree: FileNode?
    /// The document on show, marked if it is in the folder.
    var current: URL? { didSet { if current != oldValue { markCurrent() } } }
    private var theme = Settings.theme
    private let list = NSOutlineView()
    private let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 220, height: 400))
    private var watcher: FolderWatcher?
    private var rescanning = false

    override func loadView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        column.resizingMask = .autoresizingMask
        list.addTableColumn(column)
        list.outlineTableColumn = column
        list.headerView = nil
        list.style = .plain
        list.backgroundColor = .clear
        list.rowSizeStyle = .custom
        list.rowHeight = 26
        list.intercellSpacing = NSSize(width: 0, height: 1)
        list.indentationPerLevel = 14
        list.selectionHighlightStyle = .none
        list.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        list.refusesFirstResponder = true
        list.dataSource = self
        list.delegate = self
        list.target = self
        list.action = #selector(clicked)
        listInScroll(list, scroll)
        view = scroll
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        list.tableColumns.first?.width = scroll.contentSize.width
    }

    func show(folder: URL, tree: FileNode) {
        _ = view
        self.folder = folder
        self.tree = tree
        list.reloadData()
        markCurrent()
        watcher = FolderWatcher(folder) { [weak self] in self?.rescan() }
    }

    func apply(_ theme: Theme) {
        self.theme = theme
        list.reloadData()
        markCurrent()
    }

    /// Looks through the folder again after a change, keeping open the folders that were open.
    private func rescan() {
        guard let folder, !rescanning else { return }
        rescanning = true
        let open = Set((0..<list.numberOfRows).compactMap { list.item(atRow: $0) as? FileNode }.filter { list.isItemExpanded($0) }.map(\.url))
        DispatchQueue.global(qos: .utility).async {
            let tree = Folders.tree(of: folder)
            DispatchQueue.main.async {
                self.rescanning = false
                guard let tree else { return }
                self.tree = tree
                self.list.reloadData()
                func reopen(_ node: FileNode) {
                    guard node.isFolder, open.contains(node.url) else { return }
                    self.list.expandItem(node)
                    node.children?.forEach(reopen)
                }
                tree.children?.forEach(reopen)
                self.markCurrent()
            }
        }
    }

    /// Opens the folders the document on show is in, and marks it.
    private func markCurrent() {
        guard let tree, isViewLoaded else { return }
        let path = current?.standardizedFileURL.path ?? ""
        var node = tree
        while let child = node.children?.first(where: { $0.isFolder && path.hasPrefix($0.url.standardizedFileURL.path + "/") }) {
            list.expandItem(child)
            node = child
        }
        for row in 0..<list.numberOfRows {
            guard let item = list.item(atRow: row) as? FileNode else { continue }
            let marked = !item.isFolder && item.url.standardizedFileURL.path == path
            (list.rowView(atRow: row, makeIfNecessary: false) as? SidebarRow)?.isCurrent = marked
            if marked { list.scrollRowToVisible(row) }
        }
        list.reloadData(forRowIndexes: IndexSet(integersIn: 0..<list.numberOfRows), columnIndexes: IndexSet(integer: 0))
    }

    @objc private func clicked() {
        guard let node = list.item(atRow: list.clickedRow) as? FileNode else { return }
        if node.isFolder {
            if list.isItemExpanded(node) { list.collapseItem(node) } else { list.expandItem(node) }
        } else {
            onSelect(node.url)
        }
    }

    private func node(_ item: Any?) -> FileNode? { item as? FileNode ?? tree }

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int { node(item)?.children?.count ?? 0 }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any { node(item)!.children![index] }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool { (item as? FileNode)?.isFolder ?? false }

    func outlineView(_ outlineView: NSOutlineView, rowViewForItem item: Any) -> NSTableRowView? {
        let view = outlineView.makeView(withIdentifier: SidebarRow.identifier, owner: self) as? SidebarRow ?? SidebarRow()
        view.colors = (theme.link, theme.text)
        view.isCurrent = (item as? FileNode).map { !$0.isFolder && $0.url.standardizedFileURL == current?.standardizedFileURL } ?? false
        return view
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }
        let cell = outlineView.makeView(withIdentifier: SidebarCell.identifier, owner: self) as? SidebarCell ?? SidebarCell()
        let marked = !node.isFolder && node.url.standardizedFileURL == current?.standardizedFileURL
        cell.label.stringValue = node.name
        cell.toolTip = node.url.lastPathComponent
        cell.label.font = .systemFont(ofSize: 13, weight: marked ? .semibold : .regular)
        cell.label.textColor = marked ? theme.link : theme.text
        cell.indent.constant = 2
        cell.show(icon: NSImage(systemSymbolName: node.isFolder ? "folder" : "doc.text", accessibilityDescription: nil))
        cell.icon.contentTintColor = marked ? theme.link : theme.muted
        return cell
    }
}
