import Foundation

/// What a link's host is, as far as a reader could tell by looking at it.
public enum HostKind: String, Sendable, CaseIterable {
    /// No host: a relative link, `javascript:`, `data:` and the like.
    case none
    /// An ordinary ASCII host name.
    case name
    /// A dotted or bare number, which browsers read as an IPv4 address (`127.0.0.1`, `2130706433`).
    case ipv4
    /// A bracketed IPv6 literal.
    case ipv6
    /// A host with an `xn--` label: a non-ASCII name already in its encoded form.
    case punycode
    /// A host written with non-ASCII letters, which can look exactly like another host.
    case nonASCII
}

/// A link destination taken apart the way a browser would, leaning towards finding a host
/// wherever a browser might: `https:evil.example` and `https:\\evil.example` both have one.
public struct LinkTarget: Sendable, Hashable {
    /// The destination with tabs, line breaks and invisible format characters removed.
    public let destination: String
    /// Lowercased, or `nil` for a relative link.
    public let scheme: String?
    public let userinfo: String?
    /// Lowercased and percent-decoded, trailing dot removed. For `mailto:`, the first recipient's domain.
    public let host: String?
    public let hostKind: HostKind
    public let port: String?
    public let path: String
    public let query: String?
    public let fragment: String?
    /// `mailto:` recipients, lowercased.
    public let recipients: [String]

    public init(parsing raw: String) {
        let parts = TargetParser.parse(TargetParser.clean(raw))
        destination = parts.cleaned
        scheme = parts.scheme
        userinfo = parts.userinfo
        host = parts.host
        hostKind = TargetParser.classify(parts.host)
        port = parts.port
        path = parts.path
        query = parts.query
        fragment = parts.fragment
        recipients = parts.recipients
    }

    /// Every host the link could send to: the host, or each `mailto:` recipient's domain.
    public var hosts: [String] {
        guard scheme == "mailto" else { return host.map { [$0] } ?? [] }
        return recipients.compactMap(TargetParser.domain(of:))
    }

    /// The host in the ASCII form a browser would send, with non-ASCII labels Punycode-encoded.
    public var asciiHost: String? {
        host.map(Punycode.asciiHost)
    }
}

struct TargetParts {
    var cleaned = ""
    var scheme: String?
    var userinfo: String?
    var host: String?
    var port: String?
    var path = ""
    var query: String?
    var fragment: String?
    var recipients: [String] = []
}

enum TargetParser {
    static let special: Set<String> = ["http", "https", "ftp", "ws", "wss"]

    static func clean(_ raw: String) -> String {
        let kept = raw.unicodeScalars.filter {
            $0 != "\t" && $0 != "\n" && $0 != "\r" && $0.properties.generalCategory != .format
        }
        return String(scalars: kept).trimmingCharacters(in: CharacterSet(charactersIn: " ").union(.controlCharacters))
    }

    static func parse(_ cleaned: String) -> TargetParts {
        var parts = TargetParts()
        parts.cleaned = cleaned
        let (scheme, rest) = splitScheme(cleaned)
        parts.scheme = scheme
        if scheme == "mailto" { return mailto(rest, parts: parts) }
        var remainder = Substring(rest)
        if let authority = authority(of: rest, scheme: scheme) {
            applyAuthority(authority.text, to: &parts)
            remainder = authority.remainder
        }
        splitPath(remainder, into: &parts)
        return parts
    }

    static func splitScheme(_ text: String) -> (String?, String) {
        guard let colon = text.firstIndex(of: ":") else { return (nil, text) }
        let candidate = text[..<colon].unicodeScalars
        guard let first = candidate.first, first.isASCIILetter,
              candidate.allSatisfy({ $0.isASCIIAlphanumeric || $0 == "+" || $0 == "." || $0 == "-" }) else {
            return (nil, text)
        }
        return (String(candidate).lowercased(), String(text[text.index(after: colon)...]))
    }

    /// For the special schemes a browser skips any run of slashes or backslashes, even none;
    /// anything else has an authority only after `//`.
    static func authority(of rest: String, scheme: String?) -> (text: Substring, remainder: Substring)? {
        let isSpecial = scheme.map(special.contains) ?? false
        var start = rest.startIndex
        if isSpecial {
            while start < rest.endIndex, rest[start] == "/" || rest[start] == "\\" { start = rest.index(after: start) }
        } else {
            guard rest.hasPrefix("//") else { return nil }
            start = rest.index(rest.startIndex, offsetBy: 2)
        }
        let ends: Set<Character> = isSpecial ? ["/", "\\", "?", "#"] : ["/", "?", "#"]
        let end = rest[start...].firstIndex(where: ends.contains) ?? rest.endIndex
        return (rest[start..<end], rest[end...])
    }

    static func applyAuthority(_ authority: Substring, to parts: inout TargetParts) {
        var hostPort = authority
        if let at = authority.lastIndex(of: "@") {
            parts.userinfo = String(authority[..<at])
            hostPort = authority[authority.index(after: at)...]
        }
        let (host, port) = splitPort(hostPort)
        parts.host = normalizedHost(host)
        parts.port = port
    }

    static func splitPort(_ hostPort: Substring) -> (Substring, String?) {
        if hostPort.hasPrefix("["), let close = hostPort.firstIndex(of: "]") {
            let after = hostPort[hostPort.index(after: close)...]
            return (hostPort[...close], after.hasPrefix(":") ? String(after.dropFirst()) : nil)
        }
        guard let colon = hostPort.lastIndex(of: ":") else { return (hostPort, nil) }
        let port = hostPort[hostPort.index(after: colon)...]
        guard port.allSatisfy({ $0.isASCII && $0.isNumber }) else { return (hostPort, nil) }
        return (hostPort[..<colon], String(port))
    }

    static func normalizedHost(_ raw: Substring) -> String? {
        var host = PayloadDecoder.percentDecoded(String(raw)).lowercased()
        while host.hasSuffix(".") { host.removeLast() }
        return host.isEmpty ? nil : host
    }

    static func splitPath(_ remainder: Substring, into parts: inout TargetParts) {
        var rest = remainder
        if let hash = rest.firstIndex(of: "#") {
            parts.fragment = String(rest[rest.index(after: hash)...])
            rest = rest[..<hash]
        }
        if let mark = rest.firstIndex(of: "?") {
            parts.query = String(rest[rest.index(after: mark)...])
            rest = rest[..<mark]
        }
        parts.path = String(rest)
    }

    static func mailto(_ rest: String, parts: TargetParts) -> TargetParts {
        var parts = parts
        splitPath(Substring(rest), into: &parts)
        parts.recipients = PayloadDecoder.percentDecoded(parts.path)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
        parts.path = ""
        parts.host = parts.recipients.first.flatMap(domain(of:))
        return parts
    }

    static func domain(of address: String) -> String? {
        guard let at = address.lastIndex(of: "@") else { return nil }
        let domain = address[address.index(after: at)...]
        return domain.isEmpty ? nil : String(domain)
    }

    static func classify(_ host: String?) -> HostKind {
        guard let host else { return .none }
        if host.unicodeScalars.contains(where: { !$0.isASCII }) { return .nonASCII }
        if host.hasPrefix("[") { return .ipv6 }
        let labels = host.split(separator: ".")
        if labels.contains(where: { $0.hasPrefix("xn--") }) { return .punycode }
        if let last = labels.last, isNumericLabel(last) { return .ipv4 }
        return .name
    }

    static func isNumericLabel(_ label: Substring) -> Bool {
        let lowered = label.lowercased()
        if lowered.hasPrefix("0x") { return lowered.dropFirst(2).allSatisfy(\.isHexDigit) }
        return lowered.allSatisfy { $0.isASCII && $0.isNumber }
    }
}
