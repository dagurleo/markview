import Cocoa

/// The editor's line numbers (View > Show Line Numbers), in a ruler beside the text: one number
/// to a line of the Markdown, beside the first row of a line that wraps.
final class LineNumbers: NSRulerView {
    private weak var editor: SourceEditor?
    var colors: (number: NSColor, background: NSColor) = (.secondaryLabelColor, .textBackgroundColor) { didSet { needsDisplay = true } }
    /// The editor's font, which the numbers are a size smaller than.
    var font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular) {
        didSet { fit() }
    }
    private var digits = 0

    init(editor: SourceEditor) {
        self.editor = editor
        super.init(scrollView: editor.scrollView, orientation: .verticalRuler)
        clientView = editor.textView
        fit()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private var numberFont: NSFont { NSFont.monospacedDigitSystemFont(ofSize: max(font.pointSize - 2, 9), weight: .regular) }

    /// Wide enough for the longest number, which grows as lines are added.
    private func fit() {
        let count = max(String(editor?.starts.count ?? 1).count, 2)
        digits = count
        let width = ("8" as NSString).size(withAttributes: [.font: numberFont]).width * CGFloat(count)
        ruleThickness = ceil(width + 18)
        needsDisplay = true
    }

    func textChanged() {
        guard !isHidden, scrollView?.rulersVisible == true else { return }
        if String(editor?.starts.count ?? 1).count != digits, digits > 2 || (editor?.starts.count ?? 0) >= 100 { fit() }
        needsDisplay = true
    }

    // Draws over the whole ruler, not just the part asked for: since macOS 14 views draw outside
    // the area they were asked to, and a stale strip would show through.
    override func drawHashMarksAndLabels(in rect: NSRect) {
        colors.background.setFill()
        bounds.fill()
        guard let editor, let textView = clientView as? NSTextView, let layout = textView.layoutManager,
              let container = textView.textContainer, let storage = textView.textStorage else { return }
        let starts = editor.starts
        let visible = textView.visibleRect
        let glyphs = layout.glyphRange(forBoundingRect: visible, in: container)
        let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        let attributes: [NSAttributedString.Key: Any] = [.font: numberFont, .foregroundColor: colors.number]
        var line = editor.line(of: characters.location)
        while line < starts.count {
            let start = starts[line]
            guard start <= NSMaxRange(characters) else { break }
            // On the baseline of the line's first row; the empty line after a final line break has none
            // of its own, and takes the font's.
            let fragment: NSRect, baseline: CGFloat
            if start < storage.length {
                let glyph = layout.glyphIndexForCharacter(at: start)
                fragment = layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
                baseline = layout.location(forGlyphAt: glyph).y
            } else {
                fragment = layout.extraLineFragmentRect
                baseline = layout.defaultBaselineOffset(for: font)
            }
            let number = "\(line + 1)" as NSString
            let width = number.size(withAttributes: attributes).width
            let y = convert(NSPoint(x: 0, y: fragment.minY + baseline + textView.textContainerOrigin.y), from: textView).y
            number.draw(with: NSRect(x: ruleThickness - width - 8, y: y, width: width, height: 0), options: [], attributes: attributes)
            line += 1
        }
    }
}
