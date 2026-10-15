extension LinkScanner {
    static let trailingPunctuation = Set("?!.,:*_~'\";".unicodeScalars)
    static let schemes = ["https://", "http://", "ftp://"]

    /// `<scheme:...>` or `<name@host>`.
    func autolink(at open: Int, state: inout ScanState) -> Int {
        var index = open + 1
        while index < count, !Self.endsAutolink(text[index]) { index += 1 }
        guard index < count else {
            if partial { state.stop(at: open) }
            return partial ? count : open + 1
        }
        guard text[index] == ">", index > open + 1 else { return open + 1 }
        let inner = string(open + 1, index)
        guard let destination = Self.autolinkDestination(inner) else { return open + 1 }
        state.add(ScannedLink(kind: .autolink, range: open..<(index + 1), label: inner, destination: destination),
                  partial: partial)
        return index + 1
    }

    static func endsAutolink(_ scalar: Unicode.Scalar) -> Bool {
        scalar == ">" || scalar == "<" || scalar.isLinkWhitespace || scalar.isControl
    }

    static func autolinkDestination(_ inner: String) -> String? {
        if hasAutolinkScheme(inner) { return inner }
        return isAutolinkEmail(inner) ? "mailto:" + inner : nil
    }

    static func hasAutolinkScheme(_ inner: String) -> Bool {
        let scalars = Array(inner.unicodeScalars)
        guard let colon = scalars.firstIndex(of: ":"), (2...32).contains(colon), scalars[0].isASCIILetter else {
            return false
        }
        return scalars[1..<colon].allSatisfy { $0.isASCIIAlphanumeric || $0 == "+" || $0 == "." || $0 == "-" }
    }

    static func isAutolinkEmail(_ inner: String) -> Bool {
        let parts = inner.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty else { return false }
        let localExtras = Set(".!#$%&'*+/=?^_`{|}~-".unicodeScalars)
        let localOK = parts[0].unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || localExtras.contains($0) }
        let domainOK = parts[1].unicodeScalars.allSatisfy { $0.isASCIIAlphanumeric || $0 == "." || $0 == "-" }
        return localOK && domainOK
    }

    /// A URL written into the text with no markup: what GitHub-flavoured Markdown and SwiftUI's
    /// `Text` autolink.
    func bare(at index: Int, state: inout ScanState) -> Int {
        guard let prefix = urlPrefix(at: index) else { return index + 1 }
        var end = index
        while end < count, !Self.endsBareURL(text[end]) { end += 1 }
        if end == count, partial {
            state.stop(at: index)
            return count
        }
        end = trimmedBareEnd(start: index, end: end)
        guard hasHost(from: index + prefix.length, to: end) else { return index + 1 }
        let written = string(index, end)
        let link = ScannedLink(kind: .bareURL, range: index..<end, label: written,
                               destination: prefix.isWWW ? "http://" + written : written)
        state.add(link, partial: partial)
        return end
    }

    static func endsBareURL(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isLinkWhitespace || scalar == "<" || scalar.isControl
    }

    func urlPrefix(at index: Int) -> (length: Int, isWWW: Bool)? {
        guard index == 0 || !text[index - 1].isASCIIAlphanumeric else { return nil }
        for scheme in Self.schemes where matches(scheme, at: index, ignoringCase: true) {
            return (scheme.unicodeScalars.count, false)
        }
        guard matches("www.", at: index, ignoringCase: false), index == 0 || text[index - 1] != "." else {
            return nil
        }
        return (4, true)
    }

    func matches(_ literal: String, at index: Int, ignoringCase: Bool) -> Bool {
        let scalars = Array(literal.unicodeScalars)
        guard index + scalars.count <= count else { return false }
        let written = string(index, index + scalars.count)
        return ignoringCase ? written.lowercased() == literal : written == literal
    }

    /// Drops what an autolinker leaves out of the URL: trailing punctuation, an unbalanced
    /// closing parenthesis, and a trailing character reference such as `&lt;`.
    func trimmedBareEnd(start: Int, end: Int) -> Int {
        var end = end
        while end > start {
            let last = text[end - 1]
            if last == ";", let ampersand = entityStart(before: end - 1, floor: start) {
                end = ampersand
            } else if Self.trailingPunctuation.contains(last) {
                end -= 1
            } else if last == ")", hasUnbalancedClose(from: start, to: end) {
                end -= 1
            } else {
                break
            }
        }
        return end
    }

    func entityStart(before semicolon: Int, floor: Int) -> Int? {
        var index = semicolon
        while index > floor, text[index - 1].isASCIIAlphanumeric { index -= 1 }
        guard index < semicolon, index > floor, text[index - 1] == "&" else { return nil }
        return index - 1
    }

    func hasUnbalancedClose(from start: Int, to end: Int) -> Bool {
        let slice = text[start..<end]
        return slice.filter { $0 == ")" }.count > slice.filter { $0 == "(" }.count
    }

    func hasHost(from start: Int, to end: Int) -> Bool {
        start < end && !"/?#".unicodeScalars.contains(text[start])
    }

    /// `name@host.tld`, found from its `@`.
    func email(at sign: Int, state: inout ScanState) -> Int {
        var start = sign
        while start > state.consumed, Self.isLocalScalar(text[start - 1]) { start -= 1 }
        var end = sign + 1
        while end < count, Self.isDomainScalar(text[end]) { end += 1 }
        if end == count, partial {
            state.stop(at: start)
            return count
        }
        while end > sign + 1, text[end - 1] == "." { end -= 1 }
        guard start < sign, isEmailDomain(from: sign + 1, to: end) else { return sign + 1 }
        let address = string(start, end)
        state.add(ScannedLink(kind: .bareEmail, range: start..<end, label: address, destination: "mailto:" + address),
                  partial: partial)
        return end
    }

    static func isLocalScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCIIAlphanumeric || scalar == "." || scalar == "+" || scalar == "_" || scalar == "-"
    }

    static func isDomainScalar(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCIIAlphanumeric || scalar == "." || scalar == "_" || scalar == "-"
    }

    func isEmailDomain(from start: Int, to end: Int) -> Bool {
        start < end && text[start..<end].contains(".") && text[end - 1] != "_"
    }
}
