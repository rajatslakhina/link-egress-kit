/// Where a link's URL came from.
public enum Provenance: Sendable, Hashable {
    /// Written by the model: it appears in no source.
    case composed
    /// Copied character for character out of a source.
    case copied(source: String, origin: SourceOrigin)
}

/// A link, what it points at, and what was decided about it.
public struct JudgedLink: Sendable, Hashable {
    public let link: ScannedLink
    public let target: LinkTarget
    public let provenance: Provenance
    public let findings: [LinkFinding]

    public init(link: ScannedLink, target: LinkTarget, provenance: Provenance, findings: [LinkFinding]) {
        self.link = link
        self.target = target
        self.provenance = provenance
        self.findings = findings
    }

    /// The strongest action any finding asks for.
    public var action: LinkAction {
        findings.map(\.action).max() ?? .keep
    }

    /// The finding that decided the action, for the notice the reader sees.
    public var decidingFinding: LinkFinding? {
        let deciding = findings.filter { $0.action == action }
        return FindingKind.noticeOrder.lazy.compactMap { kind in deciding.first { $0.kind == kind } }.first
    }
}

/// The result of sanitizing one text.
public struct LinkReport: Sendable, Hashable {
    public let original: String
    /// What to render.
    public let text: String
    public let links: [JudgedLink]

    public init(original: String, text: String, links: [JudgedLink]) {
        self.original = original
        self.text = text
        self.links = links
    }

    public var unlinked: [JudgedLink] { links.filter { $0.action == .unlink } }
    public var annotated: [JudgedLink] { links.filter { $0.action == .annotate } }
    public var findings: [LinkFinding] { links.flatMap(\.findings) }
    public var isChanged: Bool { text != original }
}
