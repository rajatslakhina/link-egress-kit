/// What happens to a link.
public enum LinkAction: String, Sendable, CaseIterable, Comparable {
    /// Left as written; any finding is only reported.
    case keep
    /// Left live, with a note after it saying where it really goes.
    case annotate
    /// Replaced by its visible text, defanged, and a notice saying why.
    case unlink

    var rank: Int {
        switch self {
        case .keep: return 0
        case .annotate: return 1
        case .unlink: return 2
        }
    }

    public static func < (lhs: LinkAction, rhs: LinkAction) -> Bool { lhs.rank < rhs.rank }
}

/// A host, and optionally every host under it.
public struct HostRule: Sendable, Hashable {
    public let host: String
    public let includesSubdomains: Bool

    public init(_ host: String, includesSubdomains: Bool = true) {
        var host = host.lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        self.host = host
        self.includesSubdomains = includesSubdomains
    }

    public func matches(_ candidate: String) -> Bool {
        candidate == host || (includesSubdomains && candidate.hasSuffix("." + host))
    }
}

/// Which hosts a kind of link may point at.
public enum HostSet: Sendable, Hashable {
    case any
    case none
    case only([HostRule])

    public func contains(_ host: String) -> Bool {
        switch self {
        case .any: return true
        case .none: return false
        case let .only(rules): return rules.contains { $0.matches(host.lowercased()) }
        }
    }
}

/// Which links are allowed, and what is done about each kind of finding.
public struct LinkPolicy: Sendable {
    public var schemes: Set<String>
    public var linkHosts: HostSet
    public var imageHosts: HostSet
    /// A kind with no entry is ignored: not reported, not acted on.
    public var actions: [FindingKind: LinkAction]

    public init(schemes: Set<String>, linkHosts: HostSet, imageHosts: HostSet, actions: [FindingKind: LinkAction]) {
        self.schemes = Set(schemes.map { $0.lowercased() })
        self.linkHosts = linkHosts
        self.imageHosts = imageHosts
        self.actions = actions
    }

    /// For a chat client: links to any web host stay live unless they carry data out, images
    /// load from nowhere, look-alikes and mismatched labels are pointed out.
    public static let standard = LinkPolicy(
        schemes: ["https", "http", "mailto", "tel"], linkHosts: .any, imageHosts: .none,
        actions: [
            .schemeNotAllowed: .unlink, .hostNotAllowed: .unlink, .imageAutoload: .unlink, .userinfo: .unlink,
            .sensitiveValue: .unlink, .conversationText: .unlink, .conversationTextInPath: .keep,
            .shardedValue: .unlink, .opaquePayload: .keep, .embeddedURL: .keep, .labelMismatch: .annotate,
            .lookalikeHost: .annotate, .numericHost: .annotate, .quarantinedHost: .unlink
        ]
    )

    /// Every finding reported, nothing changed.
    public static let audit = LinkPolicy(
        schemes: standard.schemes, linkHosts: .any, imageHosts: .none,
        actions: Dictionary(uniqueKeysWithValues: FindingKind.allCases.map { ($0, LinkAction.keep) })
    )

    /// Only `https` and `mailto` to the listed hosts; every finding removes the link.
    public static func strict(allowing hosts: [HostRule]) -> LinkPolicy {
        LinkPolicy(
            schemes: ["https", "mailto"], linkHosts: .only(hosts), imageHosts: .only(hosts),
            actions: Dictionary(uniqueKeysWithValues: FindingKind.allCases.map { ($0, LinkAction.unlink) })
        )
    }
}
