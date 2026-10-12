import AppKit

private final class SearchResultsTable: NSTableView {
    var choose: ((Bool) -> Void)?
    var dismiss: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 36, 76: choose?(event.modifierFlags.contains(.option))
        case 53: dismiss?()
        default:
            if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "c" {
                choose?(true)
            } else {
                super.keyDown(with: event)
            }
        }
    }
}

final class HistorySearchController: NSWindowController, NSSearchFieldDelegate,
    NSTableViewDataSource, NSTableViewDelegate {
    private let store: HistoryStore
    private let search = NSSearchField()
    private let filter = NSSegmentedControl(labels: ["All", "Text", "Images"], trackingMode: .selectOne,
                                            target: nil, action: nil)
    private let table = SearchResultsTable()
    private let summary = NSTextField(labelWithString: "")
    private let copyButton = NSButton(title: "Copy", target: nil, action: nil)
    private let pasteButton = NSButton(title: "Paste", target: nil, action: nil)
    private var results: [ClipItem] = []
    private var excerpts: [String: String] = [:]
    private var generation = 0
    var onChoose: ((ClipItem, Bool) -> Void)?

    init(store: HistoryStore) {
        self.store = store
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
                            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "Search Clipboard History"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        super.init(window: panel)
        guard let content = panel.contentView else { return }

        search.frame = NSRect(x: 20, y: 420, width: 560, height: 28)
        search.placeholderString = "Search copied text or image dimensions"
        search.setAccessibilityLabel("Search clipboard history")
        search.delegate = self
        content.addSubview(search)

        filter.frame = NSRect(x: 20, y: 381, width: 215, height: 24)
        filter.selectedSegment = 0
        filter.target = self
        filter.action = #selector(filterChanged)
        content.addSubview(filter)

        summary.frame = NSRect(x: 250, y: 383, width: 330, height: 20)
        summary.alignment = .right
        summary.textColor = .secondaryLabelColor
        content.addSubview(summary)

        let scroll = NSScrollView(frame: NSRect(x: 20, y: 75, width: 560, height: 294))
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("clip"))
        column.width = 540
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = 60
        table.usesAlternatingRowBackgroundColors = true
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(pasteSelected)
        table.setAccessibilityLabel("Matching clipboard items")
        table.choose = { [weak self] copyOnly in self?.choose(copyOnly: copyOnly) }
        table.dismiss = { [weak self] in self?.window?.orderOut(nil) }
        scroll.documentView = table
        content.addSubview(scroll)

        let hint = NSTextField(labelWithString: "↑ ↓ Select · Return Paste · Esc Close")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.frame = NSRect(x: 20, y: 27, width: 330, height: 20)
        content.addSubview(hint)
        copyButton.frame = NSRect(x: 370, y: 20, width: 90, height: 32)
        copyButton.bezelStyle = .rounded
        copyButton.target = self
        copyButton.action = #selector(copySelected)
        content.addSubview(copyButton)
        pasteButton.frame = NSRect(x: 470, y: 20, width: 110, height: 32)
        pasteButton.bezelStyle = .rounded
        pasteButton.target = self
        pasteButton.action = #selector(pasteSelected)
        content.addSubview(pasteButton)
        updateButtons()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        search.stringValue = ""
        filter.selectedSegment = 0
        window?.center()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(search)
        reloadResults()
    }

    func refreshIfVisible() {
        if window?.isVisible == true { reloadResults() }
    }

    func controlTextDidChange(_ obj: Notification) { reloadResults() }
    @objc private func filterChanged() { reloadResults() }

    private func reloadResults() {
        generation += 1
        let request = generation
        let items = store.items
        let query = search.stringValue
        let kind: ClipKind? = filter.selectedSegment == 1 ? .text : filter.selectedSegment == 2 ? .image : nil
        let selectedID = table.selectedRow >= 0 && table.selectedRow < results.count
            ? results[table.selectedRow].id : nil
        // Disable actions while a newer query is pending; never paste a stale row.
        copyButton.isEnabled = false
        pasteButton.isEnabled = false
        summary.stringValue = "Searching…"
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            guard let self, self.generation == request else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let matches = HistorySearch.filter(items, query: query, kind: kind)
                let excerpts = matches.reduce(into: [String: String]()) { result, item in
                    result[item.id] = HistorySearch.excerpt(for: item, query: query)
                }
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == request else { return }
                    self.results = matches
                    self.excerpts = excerpts
                    self.table.reloadData()
                    if !matches.isEmpty {
                        let row = selectedID.flatMap { id in matches.firstIndex { $0.id == id } } ?? 0
                        self.table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
                    }
                    self.summary.stringValue = matches.isEmpty ? "No matching clips" : "\(matches.count) \(matches.count == 1 ? "clip" : "clips")"
                    self.updateButtons()
                }
            }
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard results.indices.contains(row) else { return nil }
        let item = results[row]
        let cell = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 60))
        let icon = NSImageView(frame: NSRect(x: 10, y: 10, width: 40, height: 40))
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.image = item.kind == .image ? ClipThumbnail.image(for: item)
            : NSImage(systemSymbolName: "text.alignleft", accessibilityDescription: "Text")
        cell.addSubview(icon)
        let label = NSTextField(wrappingLabelWithString: excerpts[item.id] ?? item.preview)
        label.frame = NSRect(x: 62, y: 12, width: max(100, tableView.bounds.width - 82), height: 38)
        label.maximumNumberOfLines = 2
        label.lineBreakMode = .byTruncatingTail
        cell.textField = label
        cell.imageView = icon
        cell.addSubview(label)
        cell.toolTip = DateFormatter.localizedString(from: Date(timeIntervalSince1970: item.created),
                                                    dateStyle: .medium, timeStyle: .short)
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) { updateButtons() }

    private func updateButtons() {
        let valid = results.indices.contains(table.selectedRow) && summary.stringValue != "Searching…"
        copyButton.isEnabled = valid
        pasteButton.isEnabled = valid
    }

    @objc private func copySelected() { choose(copyOnly: true) }
    @objc private func pasteSelected() { choose(copyOnly: NSEvent.modifierFlags.contains(.option)) }

    private func choose(copyOnly: Bool) {
        guard copyButton.isEnabled, results.indices.contains(table.selectedRow) else { return }
        let item = results[table.selectedRow]
        guard store.items.contains(where: { $0.id == item.id }) else { reloadResults(); return }
        window?.orderOut(nil)
        onChoose?(item, copyOnly)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveDown(_:)), #selector(NSResponder.moveUp(_:)):
            guard !results.isEmpty else { return true }
            let delta = commandSelector == #selector(NSResponder.moveDown(_:)) ? 1 : -1
            let row = max(0, min(results.count - 1, table.selectedRow + delta))
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            table.scrollRowToVisible(row)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            choose(copyOnly: NSEvent.modifierFlags.contains(.option))
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            window?.orderOut(nil)
            return true
        default: return false
        }
    }
}
