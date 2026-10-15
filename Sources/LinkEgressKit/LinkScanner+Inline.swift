struct FoundDestination {
    let text: String
    let end: Int
}

struct InlineMatch {
    let label: String
    let destination: String
    let end: Int
}

extension LinkScanner {
    func bracket(at open: Int, image: Bool, state: inout ScanState) -> Int {
        let start = image ? open - 1 : open
        if case let .value(close) = labelEnd(from: open + 1), containsNestedLink(from: open + 1, to: close) {
            state.escapes.append(open)
            return open + 1
        }
        switch inlineLink(at: open) {
        case let .value(match):
            let link = ScannedLink(
                kind: image ? .image : .inline, range: start..<match.end,
                label: match.label, destination: match.destination
            )
            state.add(link, partial: partial)
            return match.end
        case .incomplete:
            state.stop(at: start)
            return count
        case .absent:
            return open + 1
        }
    }

    /// `[label](destination "title")`. A label that itself contains a link is not a link: the
    /// inner one is, so `bracket` checks for that first and scanning resumes inside.
    func inlineLink(at open: Int) -> Step<InlineMatch> {
        labelEnd(from: open + 1).then { close in
            openParen(after: close).then { start in
                destination(from: skipLinkSpace(from: start)).then { found in
                    linkTail(from: found.end).then { end in
                        .value(InlineMatch(label: string(open + 1, close), destination: found.text, end: end))
                    }
                }
            }
        }
    }

    func labelEnd(from start: Int) -> Step<Int> {
        var depth = 0
        var index = start
        while index < count, index - start <= Self.labelLimit {
            switch text[index] {
            case "\\":
                index += 2
                continue
            case "`":
                switch skipCodeInLabel(at: index) {
                case let .value(next): index = next
                case .incomplete, .absent: return .incomplete
                }
                continue
            case "[":
                depth += 1
            case "]":
                if depth == 0 { return .value(index) }
                depth -= 1
            case "\n" where isBlankLine(after: index):
                return .absent
            default:
                break
            }
            index += 1
        }
        return index - start > Self.labelLimit ? .absent : endReached()
    }

    /// A code span inside a label binds tighter than the label's closing bracket. In a partial
    /// scan an unclosed one could still swallow that bracket, so the link waits for it.
    func skipCodeInLabel(at index: Int) -> Step<Int> {
        let length = run(at: index)
        switch closing(from: index + length, length: length, fence: false) {
        case let .closed(end): return .value(end)
        case .blocked: return .value(index + length)
        case .open: return partial ? .incomplete : .value(index + length)
        }
    }

    func containsNestedLink(from start: Int, to end: Int) -> Bool {
        var index = start
        while index + 1 < end {
            if text[index] == "]", text[index + 1] == "(" { return true }
            index += 1
        }
        return false
    }

    func openParen(after close: Int) -> Step<Int> {
        guard close + 1 < count else { return endReached() }
        return text[close + 1] == "(" ? .value(close + 2) : .absent
    }

    func destination(from index: Int) -> Step<FoundDestination> {
        guard index < count else { return endReached() }
        return text[index] == "<" ? angleDestination(from: index + 1) : rawDestination(from: index)
    }

    func angleDestination(from start: Int) -> Step<FoundDestination> {
        var index = start
        while index < count {
            switch text[index] {
            case ">":
                return .value(FoundDestination(text: DestinationText.decode(text[start..<index]), end: index + 1))
            case "\n", "<":
                return .absent
            case "\\":
                index += 2
            default:
                index += 1
            }
        }
        return endReached()
    }

    /// A destination without angle brackets: no spaces or controls, parentheses balanced.
    func rawDestination(from start: Int) -> Step<FoundDestination> {
        var depth = 0
        var index = start
        while index < count {
            let scalar = text[index]
            if scalar.isLinkWhitespace || scalar.isControl { break }
            if scalar == "\\" {
                index += 2
                continue
            }
            if scalar == "(" {
                depth += 1
            } else if scalar == ")" {
                if depth == 0 { break }
                depth -= 1
            }
            index += 1
        }
        if index >= count, partial { return .incomplete }
        let end = min(index, count)
        return .value(FoundDestination(text: DestinationText.decode(text[start..<end]), end: end))
    }

    /// An optional title, then the closing parenthesis.
    func linkTail(from index: Int) -> Step<Int> {
        let start = skipLinkSpace(from: index)
        guard start < count else { return endReached() }
        let closer: Unicode.Scalar
        switch text[start] {
        case ")": return .value(start + 1)
        case "\"": closer = "\""
        case "'": closer = "'"
        case "(": closer = ")"
        default: return .absent
        }
        return titleEnd(from: start + 1, closer: closer).then { after in
            let end = skipLinkSpace(from: after)
            guard end < count else { return endReached() }
            return text[end] == ")" ? .value(end + 1) : .absent
        }
    }

    func titleEnd(from start: Int, closer: Unicode.Scalar) -> Step<Int> {
        var index = start
        while index < count {
            let scalar = text[index]
            if scalar == "\\" {
                index += 2
                continue
            }
            if scalar == closer { return .value(index + 1) }
            if scalar == "\n", isBlankLine(after: index) { return .absent }
            index += 1
        }
        return endReached()
    }
}

/// Resolves what CommonMark resolves inside a destination: backslash escapes and the common
/// character references, so `&#106;ane` is read as `jane`.
enum DestinationText {
    static let named: [String: Unicode.Scalar] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]

    static func decode(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var result = String.UnicodeScalarView()
        var index = scalars.startIndex
        while index < scalars.endIndex {
            let scalar = scalars[index]
            if scalar == "\\", index + 1 < scalars.endIndex, scalars[index + 1].isASCIIPunctuation {
                result.append(scalars[index + 1])
                index += 2
            } else if scalar == "&", let (decoded, end) = entity(in: scalars, at: index) {
                result.append(decoded)
                index = end
            } else {
                result.append(scalar)
                index += 1
            }
        }
        return String(result)
    }

    static func entity(in scalars: ArraySlice<Unicode.Scalar>, at index: Int) -> (Unicode.Scalar, Int)? {
        var end = index + 1
        while end < scalars.endIndex, end - index <= 10, scalars[end] != ";" { end += 1 }
        guard end < scalars.endIndex, scalars[end] == ";" else { return nil }
        let name = String(scalars: scalars[(index + 1)..<end])
        guard let scalar = named[name] ?? numeric(name) else { return nil }
        return (scalar, end + 1)
    }

    static func numeric(_ name: String) -> Unicode.Scalar? {
        guard name.hasPrefix("#") else { return nil }
        let body = name.dropFirst()
        let isHex = body.hasPrefix("x") || body.hasPrefix("X")
        let value = isHex ? UInt32(body.dropFirst(), radix: 16) : UInt32(body, radix: 10)
        return value.flatMap(Unicode.Scalar.init)
    }
}
