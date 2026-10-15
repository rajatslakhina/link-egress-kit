struct DefinitionMatch {
    let label: String
    let destination: String
    let end: Int
}

extension LinkScanner {
    /// Constructs that only start a line: reference definitions and backtick fences.
    func lineConstruct(at index: Int, state: inout ScanState) -> Int? {
        if let next = definition(at: index, state: &state) { return next }
        return fence(at: index, state: &state)
    }

    func definition(at lineStart: Int, state: inout ScanState) -> Int? {
        let open = skipIndent(from: lineStart)
        guard open < count, text[open] == "[" else { return nil }
        switch definitionMatch(open: open) {
        case let .value(match):
            let link = ScannedLink(
                kind: .definition, range: lineStart..<match.end, label: nil,
                destination: match.destination, referenceLabel: match.label
            )
            state.add(link, partial: partial)
            return match.end
        case .incomplete:
            state.stop(at: lineStart)
            return count
        case .absent:
            return nil
        }
    }

    func definitionMatch(open: Int) -> Step<DefinitionMatch> {
        definitionLabelEnd(from: open + 1).then { close in
            colon(after: close).then { start in
                destination(from: skipLinkSpace(from: start)).then { found in
                    guard !found.text.isEmpty else { return .absent }
                    return lineEnd(from: found.end).then { end in
                        .value(DefinitionMatch(label: Self.normalizedLabel(string(open + 1, close)),
                                               destination: found.text, end: end))
                    }
                }
            }
        }
    }

    func definitionLabelEnd(from start: Int) -> Step<Int> {
        var index = start
        while index < count, index - start <= Self.definitionLabelLimit {
            switch text[index] {
            case "]":
                let label = text[start..<index]
                return label.allSatisfy(\.isLinkWhitespace) ? .absent : .value(index)
            case "[":
                return .absent
            case "\\":
                index += 2
                continue
            case "\n" where isBlankLine(after: index):
                return .absent
            default:
                break
            }
            index += 1
        }
        return index - start > Self.definitionLabelLimit ? .absent : endReached()
    }

    func colon(after close: Int) -> Step<Int> {
        guard close + 1 < count else { return endReached() }
        return text[close + 1] == ":" ? .value(close + 2) : .absent
    }

    func lineEnd(from index: Int) -> Step<Int> {
        var end = index
        while end < count, text[end] != "\n" { end += 1 }
        if end < count { return .value(end) }
        return partial ? .incomplete : .value(count)
    }

    /// A line-start run of three or more backticks. Both kinds of renderer treat what follows as
    /// code up to its closing run, blank lines included. An unclosed fence is code to a full
    /// renderer but literal text to an inline-only one, so it is scanned as text.
    func fence(at index: Int, state: inout ScanState) -> Int? {
        let start = skipIndent(from: index)
        guard start < count, text[start] == "`" else { return nil }
        let length = run(at: start)
        guard length >= 3 else { return nil }
        if case let .closed(end) = closing(from: start + length, length: length, fence: true) {
            state.consumed = end
            return end
        }
        if partial, state.openCode == nil { state.openCode = start }
        return start + length
    }

    static func normalizedLabel(_ label: String) -> String {
        label.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
