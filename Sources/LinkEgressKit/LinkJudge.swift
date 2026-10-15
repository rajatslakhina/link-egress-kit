import Foundation

struct Candidate {
    let kind: FindingKind
    var part: URLPart?
    var encodings: [PayloadEncoding] = []
    let detail: String
    var length: Int?

    init(_ kind: FindingKind, part: URLPart? = nil, encodings: [PayloadEncoding] = [],
         detail: String, length: Int? = nil) {
        self.kind = kind
        self.part = part
        self.encodings = encodings
        self.detail = detail
        self.length = length
    }
}

/// Judges links one at a time, in order. Each judgement sees the links before it and nothing
/// after, so a streamed answer and the same answer judged whole get the same verdicts.
struct LinkJudge {
    static let opaqueLength = 24
    static let opaqueEntropy = 3.5
    static let fileExtensions: Set<String> = [
        "md", "swift", "py", "js", "ts", "json", "txt", "html", "css", "yml", "yaml", "sh", "rb", "go", "rs",
        "kt", "java", "c", "h", "m", "mm", "plist", "xml", "csv", "pdf", "png", "jpg", "gif", "svg", "zip",
        "log", "lock", "toml"
    ]

    let policy: LinkPolicy
    let context: PreparedContext

    func judge(_ link: ScannedLink, history: inout ShardHistory) -> JudgedLink {
        let target = LinkTarget(parsing: link.destination)
        let provenance = provenance(of: link.destination)
        var found = schemeChecks(target) + hostChecks(link, target, quarantined: history.quarantined)
        found += labelChecks(link, target) + payloadChecks(target, provenance: provenance)
        found += shardChecks(target, history: &history)
        let findings = found.compactMap(finding(for:))
        if findings.contains(where: { $0.kind.quarantinesHost }) {
            history.quarantined.formUnion(target.hosts)
        }
        return JudgedLink(link: link, target: target, provenance: provenance, findings: findings)
    }

    func finding(for candidate: Candidate) -> LinkFinding? {
        policy.actions[candidate.kind].map {
            LinkFinding(kind: candidate.kind, action: $0, part: candidate.part, encodings: candidate.encodings,
                        detail: candidate.detail, length: candidate.length)
        }
    }

    func provenance(of destination: String) -> Provenance {
        guard destination.count >= 8,
              let source = context.sources.first(where: { $0.text.contains(destination) }) else { return .composed }
        return .copied(source: source.label, origin: source.origin)
    }

    func schemeChecks(_ target: LinkTarget) -> [Candidate] {
        guard let scheme = target.scheme, !policy.schemes.contains(scheme) else { return [] }
        return [Candidate(.schemeNotAllowed, detail: scheme)]
    }

    func hostChecks(_ link: ScannedLink, _ target: LinkTarget, quarantined: Set<String>) -> [Candidate] {
        let allowed = link.kind == .image ? policy.imageHosts : policy.linkHosts
        var found: [Candidate] = []
        for host in target.hosts {
            if quarantined.contains(host) || context.quarantined.contains(host) {
                found.append(Candidate(.quarantinedHost, detail: host))
            }
            if !allowed.contains(host) {
                found.append(Candidate(link.kind == .image ? .imageAutoload : .hostNotAllowed, detail: host))
            }
        }
        if let userinfo = target.userinfo, !userinfo.isEmpty {
            found.append(Candidate(.userinfo, part: .userinfo, detail: target.host ?? ""))
        }
        return found + hostShapeChecks(target) + embeddedChecks(target)
    }

    func hostShapeChecks(_ target: LinkTarget) -> [Candidate] {
        guard let host = target.host else { return [] }
        switch target.hostKind {
        case .punycode, .nonASCII: return [Candidate(.lookalikeHost, part: .host, detail: Punycode.asciiHost(host))]
        case .ipv4, .ipv6: return [Candidate(.numericHost, part: .host, detail: host)]
        case .name, .none: return []
        }
    }

    func embeddedChecks(_ target: LinkTarget) -> [Candidate] {
        target.embeddedHosts.filter { $0 != target.host }.flatMap { embedded in
            var found = [Candidate(.embeddedURL, part: .query, detail: embedded)]
            if !policy.linkHosts.contains(embedded) {
                found.append(Candidate(.hostNotAllowed, part: .query, detail: embedded))
            }
            return found
        }
    }

    /// Link text that reads as a host: `apple.com` over a link to anywhere but apple.com.
    func labelChecks(_ link: ScannedLink, _ target: LinkTarget) -> [Candidate] {
        guard link.kind == .inline || link.kind == .image, let label = link.label,
              let shown = Self.shownHost(in: label), let actual = target.host else { return [] }
        let shownBare = shown.hasPrefix("www.") ? String(shown.dropFirst(4)) : shown
        let actualBare = actual.hasPrefix("www.") ? String(actual.dropFirst(4)) : actual
        guard actualBare != shownBare, !actualBare.hasSuffix("." + shownBare) else { return [] }
        return [Candidate(.labelMismatch, detail: actual)]
    }

    static func shownHost(in label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "*_`~<>"))
            .lowercased()
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") { return LinkTarget(parsing: trimmed).host }
        let hostPart = String(trimmed.prefix { !"/?#:".contains($0) })
        let labels = hostPart.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2,
              labels.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }),
              let tld = labels.last, tld.count >= 2, tld.allSatisfy(\.isLetter),
              !fileExtensions.contains(String(tld)) else { return nil }
        return hostPart
    }
}
