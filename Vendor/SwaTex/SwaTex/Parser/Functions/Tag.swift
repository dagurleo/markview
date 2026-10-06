// Port of RaTeX crates/ratex-parser/src/functions/tag.rs

func registerTag(_ map: inout [String: FunctionSpec]) {
    defineFunction(
        &map,
        names: ["\\tag"],
        nodeType: "tag",
        numArgs: 0,
        numOptionalArgs: 0,
        argTypes: nil,
        allowedInArgument: true,
        allowedInText: false,
        allowedInMath: true,
        infix: false,
        primitive: true,
        handler: handleTag)
}

private func handleTag(
    _ ctx: inout FunctionContext, _ args: [ParseNode], _ optArgs: [ParseNode?]
) throws(ParseError) -> ParseNode {
    // Markview: the tag is text, upright, with $…$ for any math in it, as in KaTeX, which
    // makes \tag{x} \text{(x)}. SwaTex read it as math, which set words in italics. The
    // star is looked for in the gullet, as for \hspace*, so the brace stays there for
    // parseArgumentGroup to read in text mode.
    ctx.parser.gullet.consumeSpaces()
    let star = ctx.parser.gullet.future().text == "*"
    if star { ctx.parser.gullet.popToken() }
    guard let arg = try ctx.parser.parseArgumentGroup(optional: false, mode: .text) else {
        throw ParseError("\\tag requires an argument")
    }
    var text = ParseNode.ordArgument(arg)
    if !star {
        text.insert(ParseNode(.textOrd(text: "("), mode: .text), at: 0)
        text.append(ParseNode(.textOrd(text: ")"), mode: .text))
    }
    let tag = text.isEmpty ? [] : [ParseNode(.text(body: text, font: "\\text"), mode: .math)]

    return ParseNode(.tag(body: [], tag: tag), mode: ctx.parser.mode)
}
