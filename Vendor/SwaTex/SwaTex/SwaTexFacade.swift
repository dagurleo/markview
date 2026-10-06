/// High-level convenience API: LaTeX in, display list out.
///
/// The full pipeline is `parse → layout → toDisplayList`. The resulting
/// ``DisplayList`` is in **em units**; renderers multiply by the font size.
public enum SwaTexEngine {
    /// Parse and lay out a LaTeX math string.
    ///
    /// - Parameters:
    ///   - latex: LaTeX source (outer `$...$` / `$$...$$` are stripped).
    ///   - style: initial math style (`.display` for display mode, `.text`
    ///     for inline mode).
    ///   - color: initial text color.
    ///   - displayWidth: Markview: the width (em) of the line a display formula is
    ///     centred on, which puts its equation numbers at the right edge.
    /// - Returns: a flat display list in em units.
    public static func displayList(
        for latex: String,
        style: MathStyle = .display,
        color: Color = .black,
        displayWidth: Double? = nil
    ) throws(ParseError) -> DisplayList {
        var equations = 0
        return try displayList(for: latex, style: style, color: color, displayWidth: displayWidth, equations: &equations)
    }

    /// Markview: the same, numbering equations on from `equations` and leaving it at the
    /// last number used, so that equations number on through a document, as on a KaTeX page.
    public static func displayList(
        for latex: String,
        style: MathStyle = .display,
        color: Color = .black,
        displayWidth: Double? = nil,
        equations: inout Int
    ) throws(ParseError) -> DisplayList {
        let nodes = try parseLaTeX(latex, equations: &equations)
        var options = LayoutOptions(style: style, color: color)
        options.displayWidth = displayWidth
        let box = layout(nodes, options: options)
        return toDisplayList(box)
    }
}
