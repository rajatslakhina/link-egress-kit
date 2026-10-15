/// Rewrites URLs and addresses so no autolinker will turn them back into links.
enum Defang {
    static func host(_ host: String) -> String {
        host.replacingOccurrences(of: ".", with: "[.]")
    }

    static func token(_ text: String) -> String {
        text.replacingOccurrences(of: "://", with: "[:]//")
            .replacingOccurrences(of: ".", with: "[.]")
            .replacingOccurrences(of: "@", with: "[@]")
    }

    /// A label about to become plain text: every URL or address in it is defanged, the rest is
    /// left as written.
    static func text(_ label: String) -> String {
        let scalars = Array(label.unicodeScalars)
        var output = ""
        var index = 0
        for link in LinkScanner(scalars).scan().links {
            output += String(scalars: scalars[index..<link.range.lowerBound])
            output += token(String(scalars: scalars[link.range]))
            index = link.range.upperBound
        }
        return output + String(scalars: scalars[index...])
    }
}

/// Writes a judged text back out.
enum LinkRenderer {
    static func render(_ text: [Unicode.Scalar], range: Range<Int>, links: [JudgedLink], escapes: [Int]) -> String {
        var output = ""
        var index = range.lowerBound
        var pendingEscapes = ArraySlice(escapes.filter { range.contains($0) })
        func copy(upTo end: Int) {
            while let escape = pendingEscapes.first, escape < end {
                output += String(scalars: text[index..<escape]) + "\\"
                index = escape
                pendingEscapes = pendingEscapes.dropFirst()
            }
            output += String(scalars: text[index..<end])
            index = end
        }
        for judged in links {
            copy(upTo: judged.link.range.lowerBound)
            output += replacement(for: judged, original: String(scalars: text[judged.link.range]))
            index = judged.link.range.upperBound
        }
        copy(upTo: range.upperBound)
        return output
    }

    static func replacement(for judged: JudgedLink, original: String) -> String {
        guard let finding = judged.decidingFinding else { return original }
        switch finding.action {
        case .keep: return original
        case .annotate: return original + " (" + finding.phrase + ")"
        case .unlink: return unlinked(judged, finding: finding)
        }
    }

    static func unlinked(_ judged: JudgedLink, finding: LinkFinding) -> String {
        let isImage = judged.link.kind == .image
        let noun = isImage ? "image" : "link"
        let host = judged.target.hosts.first.map { (isImage ? " from " : " to ") + Defang.host($0) } ?? ""
        let notice = "(\(noun)\(host) removed: \(finding.phrase))"
        guard let label = judged.link.label, !label.isEmpty else { return notice }
        return Defang.text(label) + " " + notice
    }
}
