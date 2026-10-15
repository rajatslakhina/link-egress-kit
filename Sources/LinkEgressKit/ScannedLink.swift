/// The ways a Markdown renderer can turn text into something that opens or loads a URL.
public enum LinkKind: String, Sendable, CaseIterable {
    /// `[label](destination)`.
    case inline
    /// `![alt](source)`. A renderer that shows images fetches the source without a tap.
    case image
    /// `<https://...>` or `<name@host>`.
    case autolink
    /// `https://...`, `http://...`, `ftp://...` or `www.` written into the text with no markup.
    case bareURL
    /// `name@host.tld` written into the text. Renderers that autolink turn it into `mailto:`.
    case bareEmail
    /// `[label]: destination` on its own line. Every `[text][label]` that uses it becomes a link,
    /// and an inline-only renderer shows the line and autolinks its URL.
    case definition

    /// Whether the renderer fetches the URL with no action from the reader.
    public var loadsWithoutTap: Bool { self == .image }
}

/// One link construct found in a text, before it is judged.
public struct ScannedLink: Sendable, Hashable {
    public let kind: LinkKind
    /// Unicode scalar offsets of the whole construct, markup included.
    public let range: Range<Int>
    /// The text the reader sees: the link text, the image's alt text, or the URL itself for
    /// autolinks and bare links. `nil` for a definition, which shows no label of its own.
    public let label: String?
    /// The URL the construct points at, with backslash escapes and entities resolved.
    public let destination: String
    /// For a definition, its normalised label (case-folded, whitespace collapsed).
    public let referenceLabel: String?

    public init(kind: LinkKind, range: Range<Int>, label: String?, destination: String, referenceLabel: String? = nil) {
        self.kind = kind
        self.range = range
        self.label = label
        self.destination = destination
        self.referenceLabel = referenceLabel
    }
}
