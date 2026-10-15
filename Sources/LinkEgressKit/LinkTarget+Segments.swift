/// Where in a URL a piece of data was found.
public enum URLPart: String, Sendable, CaseIterable {
    case userinfo, host, path, query, fragment, recipient
    /// Across part boundaries, such as a value split over two path segments.
    case spanning
}

struct Segment: Sendable, Equatable {
    let part: URLPart
    let raw: String
}

extension LinkTarget {
    var queryItems: [(name: String, value: String)] {
        guard let query else { return [] }
        return query.split(whereSeparator: { $0 == "&" || $0 == ";" }).map { item in
            guard let equals = item.firstIndex(of: "=") else { return (String(item), "") }
            return (String(item[..<equals]), String(item[item.index(after: equals)...]))
        }
    }

    var pathSegments: [String] {
        path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init)
    }

    /// Host labels left of the last two, where DNS-style exfiltration puts its payload.
    var subdomainLabels: [String] {
        guard hostKind == .name, let host else { return [] }
        return host.split(separator: ".").dropLast(2).map(String.init)
    }

    /// Every piece of the URL that could carry data, in order.
    var segments: [Segment] {
        var result: [Segment] = []
        if let userinfo, !userinfo.isEmpty { result.append(Segment(part: .userinfo, raw: userinfo)) }
        if scheme == "mailto" {
            result += recipients.map { Segment(part: .recipient, raw: $0) }
        } else if let host {
            result.append(Segment(part: .host, raw: host))
        }
        result += pathSegments.map { Segment(part: .path, raw: $0) }
        for item in queryItems {
            result += [item.name, item.value].filter { !$0.isEmpty }.map { Segment(part: .query, raw: $0) }
        }
        if let fragment, !fragment.isEmpty { result.append(Segment(part: .fragment, raw: fragment)) }
        return result
    }

    /// The pieces an opaque payload is hidden in: query values, the fragment, subdomain labels.
    /// Path segments are left out because long identifiers there are ordinary routing.
    var payloadCarriers: [Segment] {
        var result = queryItems.map { Segment(part: .query, raw: $0.value) }
        if let fragment { result.append(Segment(part: .fragment, raw: fragment)) }
        result += subdomainLabels.map { Segment(part: .host, raw: $0) }
        return result.filter { !$0.raw.isEmpty }
    }

    /// Host, path, query and fragment run together, so a value split across them is still seen.
    var spanning: String {
        [host ?? "", path, query ?? "", fragment ?? ""].joined(separator: " ")
    }

    /// The query values and fragment, decoded and run together: what a sharded payload is
    /// reassembled from.
    var shardPayload: String {
        (queryItems.map(\.value) + [fragment ?? ""]).map(PayloadDecoder.fullyDecoded).joined()
    }

    /// Hosts of absolute URLs carried in query values: a redirector on an allowed host that
    /// forwards somewhere else.
    var embeddedHosts: [String] {
        queryItems.compactMap { item in
            let decoded = PayloadDecoder.fullyDecoded(item.value)
            let lowered = decoded.lowercased()
            guard lowered.hasPrefix("http://") || lowered.hasPrefix("https://") || lowered.hasPrefix("//") else {
                return nil
            }
            return LinkTarget(parsing: decoded).host
        }
    }
}
