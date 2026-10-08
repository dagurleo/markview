import Foundation

/// The colours of a theme, each in a light and a dark version, as sRGB hex.
///
/// GitHub's are GitHub's page, with a softer dark background. The others follow their
/// authors' published palettes: Solarized (Ethan Schoonover), One (Atom's One Light and One
/// Dark), Dracula (Zeno Rocha; Alucard is its light side), Tokyo Night (Day and Night, Enkia),
/// Catppuccin (Latte and Mocha), Gruvbox (Pavel Pertsev), Ayu (Light and Mirage, Konstantin
/// Pschera), Nord (Sven Greb) and Rosé Pine (Dawn and Main), all under the MIT licence, and
/// Monokai (Wimer Hazenberg). Monokai and Nord are dark themes: their light sides are
/// Markview's, in their own hues darkened to read on a light page. Paper is Markview's own.
struct Palette {
    typealias Pair = (light: UInt32, dark: UInt32)

    /// What Settings stores.
    let id: String
    let name: String
    let background, text, muted, border, subtle, link, mark: Pair
    /// Callouts: GitHub's five alerts, and Obsidian's abstract.
    let note, tip, important, warning, caution, abstract: Pair
    /// Code, by highlight.js's classes (see HighlightEngine).
    let keyword, title, literal, string, comment, builtin, tag: Pair

    static let all: [Palette] = [.github, .solarized, .one, .monokai, .dracula, .nord,
                                 .tokyoNight, .catppuccin, .gruvbox, .ayu, .rosePine, .paper]

    static func named(_ id: String?) -> Palette { all.first { $0.id == id } ?? .github }

    static let github = Palette(
        id: "github", name: "GitHub",
        background: (0xffffff, 0x1c1c1e), text: (0x1f2328, 0xe4e4e7), muted: (0x656d76, 0x9b9ba3),
        border: (0xd8dee4, 0x3a3a40), subtle: (0xf6f8fa, 0x27272b), link: (0x0969da, 0x58a6ff), mark: (0xfff8c5, 0x5a4a00),
        note: (0x0969da, 0x58a6ff), tip: (0x1a7f37, 0x3fb950), important: (0x8250df, 0xa371f7),
        warning: (0x9a6700, 0xd29922), caution: (0xcf222e, 0xf85149), abstract: (0x0e7490, 0x22d3ee),
        keyword: (0xcf222e, 0xff7b72), title: (0x8250df, 0xd2a8ff), literal: (0x0550ae, 0x79c0ff),
        string: (0x0a3069, 0xa5d6ff), comment: (0x6e7781, 0x8b949e), builtin: (0x953800, 0xffa657), tag: (0x116329, 0x7ee787))

    static let solarized = Palette(
        id: "solarized", name: "Solarized",
        background: (0xfdf6e3, 0x002b36), text: (0x586e75, 0x93a1a1), muted: (0x839496, 0x657b83),
        border: (0xe3dcc6, 0x1c4652), subtle: (0xeee8d5, 0x073642), link: (0x268bd2, 0x268bd2), mark: (0xf6e2a4, 0x4a4300),
        note: (0x268bd2, 0x268bd2), tip: (0x859900, 0x859900), important: (0x6c71c4, 0x6c71c4),
        warning: (0xb58900, 0xb58900), caution: (0xdc322f, 0xdc322f), abstract: (0x2aa198, 0x2aa198),
        keyword: (0x859900, 0x859900), title: (0x268bd2, 0x268bd2), literal: (0xb58900, 0xb58900),
        string: (0x2aa198, 0x2aa198), comment: (0x93a1a1, 0x586e75), builtin: (0xcb4b16, 0xcb4b16), tag: (0x268bd2, 0x268bd2))

    static let one = Palette(
        id: "one", name: "One",
        background: (0xfafafa, 0x282c34), text: (0x383a42, 0xabb2bf), muted: (0x696c77, 0x7f848e),
        border: (0xdbdbdc, 0x3e4451), subtle: (0xf0f0f1, 0x21252b), link: (0x4078f2, 0x61afef), mark: (0xf6e6a8, 0x514a35),
        note: (0x4078f2, 0x61afef), tip: (0x50a14f, 0x98c379), important: (0xa626a4, 0xc678dd),
        warning: (0xc18401, 0xe5c07b), caution: (0xe45649, 0xe06c75), abstract: (0x0184bc, 0x56b6c2),
        keyword: (0xa626a4, 0xc678dd), title: (0x4078f2, 0x61afef), literal: (0x986801, 0xd19a66),
        string: (0x50a14f, 0x98c379), comment: (0xa0a1a7, 0x5c6370), builtin: (0xc18401, 0xe5c07b), tag: (0xe45649, 0xe06c75))

    static let monokai = Palette(
        id: "monokai", name: "Monokai",
        background: (0xfafaf8, 0x272822), text: (0x272822, 0xf8f8f2), muted: (0x75715e, 0xa59f85),
        border: (0xe2e1d8, 0x49483e), subtle: (0xf0efe7, 0x3e3d32), link: (0x0083a8, 0x66d9ef), mark: (0xf6efb0, 0x5f5b30),
        note: (0x0083a8, 0x66d9ef), tip: (0x5c8a00, 0xa6e22e), important: (0x7351c9, 0xae81ff),
        warning: (0xc06000, 0xfd971f), caution: (0xd0154f, 0xf92672), abstract: (0x00877c, 0xa1efe4),
        keyword: (0xd0154f, 0xf92672), title: (0x5c8a00, 0xa6e22e), literal: (0x7351c9, 0xae81ff),
        string: (0x8d7a00, 0xe6db74), comment: (0x8e8b7a, 0x75715e), builtin: (0x0083a8, 0x66d9ef), tag: (0xd0154f, 0xf92672))

    static let dracula = Palette(
        id: "dracula", name: "Dracula",
        background: (0xfffbeb, 0x282a36), text: (0x1f1f1f, 0xf8f8f2), muted: (0x6c664b, 0xa1a7c4),
        border: (0xddd6c0, 0x44475a), subtle: (0xf4eedb, 0x343746), link: (0x036a96, 0x8be9fd), mark: (0xf3e5a0, 0x5f6132),
        note: (0x036a96, 0x8be9fd), tip: (0x14710a, 0x50fa7b), important: (0x644ac9, 0xbd93f9),
        warning: (0xa34d14, 0xffb86c), caution: (0xcb3a2a, 0xff5555), abstract: (0xa3144d, 0xff79c6),
        keyword: (0xa3144d, 0xff79c6), title: (0x14710a, 0x50fa7b), literal: (0x644ac9, 0xbd93f9),
        string: (0x846e15, 0xf1fa8c), comment: (0x6c664b, 0x6272a4), builtin: (0x036a96, 0x8be9fd), tag: (0xa3144d, 0xff79c6))

    static let nord = Palette(
        id: "nord", name: "Nord",
        background: (0xeceff4, 0x2e3440), text: (0x2e3440, 0xd8dee9), muted: (0x4c566a, 0x9da5b4),
        border: (0xd8dee9, 0x434c5e), subtle: (0xe5e9f0, 0x3b4252), link: (0x5e81ac, 0x88c0d0), mark: (0xf0dfae, 0x5a5440),
        note: (0x5e81ac, 0x81a1c1), tip: (0x5f7e47, 0xa3be8c), important: (0x8a5f87, 0xb48ead),
        warning: (0x9c7a24, 0xebcb8b), caution: (0xb04e58, 0xbf616a), abstract: (0x4b8584, 0x8fbcbb),
        keyword: (0x5e81ac, 0x81a1c1), title: (0x3f7d91, 0x88c0d0), literal: (0x8a5f87, 0xb48ead),
        string: (0x5f7e47, 0xa3be8c), comment: (0x7b88a1, 0x616e88), builtin: (0x4b8584, 0x8fbcbb), tag: (0x5e81ac, 0x81a1c1))

    static let tokyoNight = Palette(
        id: "tokyo-night", name: "Tokyo Night",
        background: (0xe1e2e7, 0x1a1b26), text: (0x3760bf, 0xc0caf5), muted: (0x6172b0, 0x939bc4),
        border: (0xc4c8da, 0x3b4261), subtle: (0xd0d5e3, 0x1f2335), link: (0x2e7de9, 0x7aa2f7), mark: (0xe6d8b0, 0x4b4232),
        note: (0x2e7de9, 0x7aa2f7), tip: (0x587539, 0x9ece6a), important: (0x9854f1, 0xbb9af7),
        warning: (0x8c6c3e, 0xe0af68), caution: (0xf52a65, 0xf7768e), abstract: (0x007197, 0x7dcfff),
        keyword: (0x9854f1, 0xbb9af7), title: (0x2e7de9, 0x7aa2f7), literal: (0xb15c00, 0xff9e64),
        string: (0x587539, 0x9ece6a), comment: (0x848cb5, 0x565f89), builtin: (0x007197, 0x7dcfff), tag: (0xf52a65, 0xf7768e))

    static let ayu = Palette(
        id: "ayu", name: "Ayu",
        background: (0xfcfcfc, 0x1f2430), text: (0x5c6166, 0xcccac2), muted: (0x828c99, 0x8a919e),
        border: (0xe1e4e8, 0x343d4f), subtle: (0xf0f2f4, 0x272d38), link: (0x399ee6, 0x73d0ff), mark: (0xffeccc, 0x4d4530),
        note: (0x399ee6, 0x73d0ff), tip: (0x86b300, 0xbae67e), important: (0xa37acc, 0xd4bfff),
        warning: (0xfa8d3e, 0xffcc66), caution: (0xe65050, 0xf28779), abstract: (0x4cbf99, 0x95e6cb),
        keyword: (0xfa8d3e, 0xffa759), title: (0xf2ae49, 0xffd580), literal: (0xa37acc, 0xd4bfff),
        string: (0x86b300, 0xbae67e), comment: (0xabb0b6, 0x5c6773), builtin: (0x399ee6, 0x73d0ff), tag: (0x55b4d4, 0x5ccfe6))

    static let catppuccin = Palette(
        id: "catppuccin", name: "Catppuccin",
        background: (0xeff1f5, 0x1e1e2e), text: (0x4c4f69, 0xcdd6f4), muted: (0x6c6f85, 0xa6adc8),
        border: (0xccd0da, 0x45475a), subtle: (0xe6e9ef, 0x181825), link: (0x1e66f5, 0x89b4fa), mark: (0xf6e3b4, 0x4b4536),
        note: (0x1e66f5, 0x89b4fa), tip: (0x40a02b, 0xa6e3a1), important: (0x8839ef, 0xcba6f7),
        warning: (0xdf8e1d, 0xf9e2af), caution: (0xd20f39, 0xf38ba8), abstract: (0x179299, 0x94e2d5),
        keyword: (0x8839ef, 0xcba6f7), title: (0x1e66f5, 0x89b4fa), literal: (0xfe640b, 0xfab387),
        string: (0x40a02b, 0xa6e3a1), comment: (0x7c7f93, 0x9399b2), builtin: (0xd20f39, 0xf38ba8), tag: (0x179299, 0x94e2d5))

    static let gruvbox = Palette(
        id: "gruvbox", name: "Gruvbox",
        background: (0xfbf1c7, 0x282828), text: (0x3c3836, 0xebdbb2), muted: (0x7c6f64, 0xa89984),
        border: (0xd5c4a1, 0x504945), subtle: (0xf2e5bc, 0x32302f), link: (0x076678, 0x83a598), mark: (0xf5df9f, 0x5a4a1a),
        note: (0x076678, 0x83a598), tip: (0x79740e, 0xb8bb26), important: (0x8f3f71, 0xd3869b),
        warning: (0xb57614, 0xfabd2f), caution: (0x9d0006, 0xfb4934), abstract: (0x427b58, 0x8ec07c),
        keyword: (0x9d0006, 0xfb4934), title: (0x427b58, 0x8ec07c), literal: (0x8f3f71, 0xd3869b),
        string: (0x79740e, 0xb8bb26), comment: (0x928374, 0x928374), builtin: (0xaf3a03, 0xfe8019), tag: (0x076678, 0x83a598))

    static let rosePine = Palette(
        id: "rose-pine", name: "Rosé Pine",
        background: (0xfaf4ed, 0x191724), text: (0x575279, 0xe0def4), muted: (0x797593, 0x908caa),
        border: (0xdfdad9, 0x403d52), subtle: (0xf2e9e1, 0x1f1d2e), link: (0x286983, 0x9ccfd8), mark: (0xf6e0b5, 0x4a3f36),
        note: (0x286983, 0x9ccfd8), tip: (0x56949f, 0x3e8fb0), important: (0x907aa9, 0xc4a7e7),
        warning: (0xea9d34, 0xf6c177), caution: (0xb4637a, 0xeb6f92), abstract: (0xd7827e, 0xebbcba),
        keyword: (0x286983, 0x3e8fb0), title: (0xd7827e, 0xebbcba), literal: (0x907aa9, 0xc4a7e7),
        string: (0xea9d34, 0xf6c177), comment: (0x9893a5, 0x6e6a86), builtin: (0xb4637a, 0xeb6f92), tag: (0x56949f, 0x9ccfd8))

    static let paper = Palette(
        id: "paper", name: "Paper",
        background: (0xf8f1e3, 0x26221d), text: (0x3b3226, 0xe6dccb), muted: (0x7a6c5a, 0xa89a85),
        border: (0xe0d4bf, 0x443d33), subtle: (0xefe5d3, 0x2f2a24), link: (0x9b4d1f, 0xe0a36b), mark: (0xf3dc9a, 0x5a4820),
        note: (0x2f6690, 0x7fb0d8), tip: (0x4f7a28, 0x9cc271), important: (0x7a4e9a, 0xc49be0),
        warning: (0xa5670a, 0xe0b04f), caution: (0xa8322a, 0xec7a6a), abstract: (0x2b7a78, 0x6cc3bd),
        keyword: (0xa8322a, 0xec7a6a), title: (0x7a4e9a, 0xc49be0), literal: (0x2f6690, 0x7fb0d8),
        string: (0x4f7a28, 0xa5c77a), comment: (0x8e806b, 0x8f8270), builtin: (0xa5670a, 0xe0b04f), tag: (0x2b7a78, 0x6cc3bd))
}
