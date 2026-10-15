/// Why a link was flagged.
public enum FindingKind: String, Sendable, CaseIterable {
    /// `javascript:`, `data:`, `file:` or any scheme the policy does not list.
    case schemeNotAllowed
    /// A host outside the policy's allowlist, including one carried in a query value.
    case hostNotAllowed
    /// An image from a host not allowed to serve images: a renderer fetches it unasked.
    case imageAutoload
    /// `https://bank.example@evil.example/`: the part a reader notices is not the host.
    case userinfo
    /// One of the app's sensitive values, in any spelling or encoding.
    case sensitiveValue
    /// A long run of the conversation outside the path.
    case conversationText
    /// A long run of the conversation inside the path, where a page title's slug can match by
    /// accident.
    case conversationTextInPath
    /// The second half of a sensitive value whose first half went to the same host earlier.
    case shardedValue
    /// A long, high-entropy part with no other explanation.
    case opaquePayload
    /// A query value that is itself a URL to another host.
    case embeddedURL
    /// Link text that names one host over a link to another.
    case labelMismatch
    /// A host with non-ASCII letters or Punycode labels.
    case lookalikeHost
    /// A host written as a number.
    case numericHost
    /// A host already caught collecting data.
    case quarantinedHost

    /// Which finding a notice names when several ask for the same action: what the link
    /// carried first, the host it was already caught at last.
    static let noticeOrder: [FindingKind] = [
        .sensitiveValue, .shardedValue, .conversationText, .schemeNotAllowed, .userinfo, .embeddedURL,
        .hostNotAllowed, .imageAutoload, .opaquePayload, .conversationTextInPath, .labelMismatch,
        .lookalikeHost, .numericHost, .quarantinedHost
    ]

    /// Whether a link with this finding taints its host for the rest of the session.
    public var quarantinesHost: Bool {
        self == .sensitiveValue || self == .conversationText || self == .shardedValue
    }
}

/// One reason a link was flagged, and what the policy does about it.
public struct LinkFinding: Sendable, Hashable {
    public let kind: FindingKind
    public let action: LinkAction
    public let part: URLPart?
    public let encodings: [PayloadEncoding]
    /// A host, a scheme, a value's label or a source's label. Never the sensitive value itself.
    public let detail: String
    public let length: Int?

    public init(kind: FindingKind, action: LinkAction, part: URLPart? = nil,
                encodings: [PayloadEncoding] = [], detail: String, length: Int? = nil) {
        self.kind = kind
        self.action = action
        self.part = part
        self.encodings = encodings
        self.detail = detail
        self.length = length
    }

    /// A short phrase for a notice shown to the reader. Hosts are defanged so the notice can
    /// never become a link itself.
    public var phrase: String {
        switch kind {
        case .schemeNotAllowed: return "\(detail): links are not allowed"
        case .hostNotAllowed: return "\(Defang.host(detail)) is not on the allowlist"
        case .imageAutoload: return "images load without a tap"
        case .userinfo: return "it hides its real host"
        case .sensitiveValue: return "it carried \(detail)"
        case .conversationText, .conversationTextInPath: return "it carried text from \(detail)"
        case .shardedValue: return "it carried the rest of \(detail)"
        case .opaquePayload: return "it carried an opaque payload"
        case .embeddedURL: return "it forwards to \(Defang.host(detail))"
        case .labelMismatch: return "goes to \(Defang.host(detail))"
        case .lookalikeHost: return "look-alike host \(Defang.host(detail))"
        case .numericHost: return "numeric host \(Defang.host(detail))"
        case .quarantinedHost: return "\(Defang.host(detail)) already received conversation data"
        }
    }

    /// One line for a log or a diagnostics screen.
    public var summary: String {
        var parts = [kind.rawValue, detail]
        if let part { parts.append("in \(part.rawValue)") }
        if let length { parts.append("\(length) chars") }
        if !encodings.isEmpty { parts.append("via " + encodings.map(\.rawValue).joined(separator: "+")) }
        return parts.joined(separator: " ") + " -> " + action.rawValue
    }
}
