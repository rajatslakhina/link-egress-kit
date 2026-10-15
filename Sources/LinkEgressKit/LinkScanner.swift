/// A parsing step's answer: a value, "not this construct", or, in a partial scan, "cannot tell
/// until more text arrives".
enum Step<Value> {
    case value(Value)
    case incomplete
    case absent

    func then<Next>(_ next: (Value) -> Step<Next>) -> Step<Next> {
        switch self {
        case let .value(value): return next(value)
        case .incomplete: return .incomplete
        case .absent: return .absent
        }
    }
}

/// Where a backtick run's closing run is, if it has one.
enum Closing: Equatable {
    case closed(end: Int)
    case blocked
    case open
}

/// What one pass over a text found.
struct ScanOutcome: Sendable {
    var links: [ScannedLink]
    /// Literal `[`s whose label held a nested link. Once that link is rewritten the outer
    /// brackets would form a link of their own, so the renderer escapes them.
    var escapes: [Int]
    /// The first scalar that later text could still change. The text's length when the scan is
    /// final.
    var holdFrom: Int
}

struct ScanState {
    var links: [ScannedLink] = []
    var escapes: [Int] = []
    var holdFrom: Int
    /// A backtick run with no closing run yet, in a partial scan. Anything after it could still
    /// turn out to be code, so the first link after it is held.
    var openCode: Int?
    /// The end of the last construct, so an email's local part is never read back across it.
    var consumed = 0
    var stopped = false

    init(count: Int) {
        holdFrom = count
    }

    mutating func hold(from position: Int) {
        holdFrom = min(holdFrom, position)
    }

    mutating func stop(at position: Int) {
        hold(from: position)
        stopped = true
    }

    mutating func add(_ link: ScannedLink, partial: Bool) {
        if partial, openCode != nil {
            stop(at: link.range.lowerBound)
            return
        }
        links.append(link)
        consumed = link.range.upperBound
    }
}

/// Finds every construct a Markdown renderer could turn into a live link.
///
/// It is deliberately wider than any one renderer. Something a renderer would leave as text but
/// the scanner reports costs a judgement; something a renderer links but the scanner misses is a
/// bypass. Code is the one place it stays quiet, and only where both an inline-only renderer
/// (SwiftUI's `Text`) and a full CommonMark renderer agree the text is code.
struct LinkScanner {
    static let labelLimit = 2_000
    static let definitionLabelLimit = 999

    let text: [Unicode.Scalar]
    let partial: Bool

    init(_ text: [Unicode.Scalar], partial: Bool = false) {
        self.text = text
        self.partial = partial
    }

    init(_ text: String) {
        self.init(Array(text.unicodeScalars))
    }

    var count: Int { text.count }

    func scan() -> ScanOutcome {
        var state = ScanState(count: count)
        var index = 0
        var lineStart = true
        while index < count, !state.stopped {
            if lineStart, let next = lineConstruct(at: index, state: &state) {
                index = next
                lineStart = false
                continue
            }
            lineStart = text[index] == "\n"
            index = inlineConstruct(at: index, state: &state)
        }
        if partial { settle(&state) }
        return ScanOutcome(links: state.links, escapes: state.escapes, holdFrom: state.holdFrom)
    }

    func inlineConstruct(at index: Int, state: inout ScanState) -> Int {
        switch text[index] {
        case "\\": return escape(at: index, state: &state)
        case "`": return codeSpan(at: index, state: &state)
        case "!": return image(at: index, state: &state)
        case "[": return bracket(at: index, image: false, state: &state)
        case "<": return autolink(at: index, state: &state)
        case "@": return email(at: index, state: &state)
        default: return bare(at: index, state: &state)
        }
    }

    /// Holds the trailing word, which could still grow into a URL or an address, and any link
    /// that the hold point would cut in two.
    func settle(_ state: inout ScanState) {
        var start = count
        while start > 0, !text[start - 1].isLinkWhitespace { start -= 1 }
        state.hold(from: start)
        for link in state.links.reversed()
        where link.range.lowerBound < state.holdFrom && link.range.upperBound > state.holdFrom {
            state.hold(from: link.range.lowerBound)
        }
        let hold = state.holdFrom
        state.links.removeAll { $0.range.upperBound > hold }
        state.escapes.removeAll { $0 >= hold }
    }

    func escape(at index: Int, state: inout ScanState) -> Int {
        guard index + 1 < count, text[index + 1].isASCIIPunctuation else { return index + 1 }
        state.consumed = index + 2
        return index + 2
    }

    func codeSpan(at index: Int, state: inout ScanState) -> Int {
        let length = run(at: index)
        switch closing(from: index + length, length: length, fence: false) {
        case let .closed(end):
            state.consumed = end
            return end
        case .blocked:
            return index + length
        case .open:
            if partial, state.openCode == nil { state.openCode = index }
            return index + length
        }
    }

    func image(at index: Int, state: inout ScanState) -> Int {
        guard index + 1 < count, text[index + 1] == "[" else { return index + 1 }
        return bracket(at: index + 1, image: true, state: &state)
    }

    // MARK: - Shared helpers

    func endReached<Value>() -> Step<Value> {
        partial ? .incomplete : .absent
    }

    func string(_ start: Int, _ end: Int) -> String {
        String(scalars: text[start..<end])
    }

    func run(at index: Int) -> Int {
        var end = index
        while end < count, text[end] == "`" { end += 1 }
        return end - index
    }

    /// Finds the run that closes a code span of `length` backticks. An inline span may not cross
    /// a blank line (a full renderer ends the paragraph there); a fence may, and also closes at a
    /// longer run that starts a line.
    func closing(from start: Int, length: Int, fence: Bool) -> Closing {
        var index = start
        while index < count {
            if text[index] == "`" {
                let found = run(at: index)
                if found == length || (fence && found > length && startsLine(index)) {
                    return .closed(end: index + found)
                }
                index += found
            } else if !fence, text[index] == "\n", isBlankLine(after: index) {
                return .blocked
            } else {
                index += 1
            }
        }
        return .open
    }

    func isBlankLine(after newline: Int) -> Bool {
        var index = newline + 1
        while index < count, text[index].isSpaceOrTab { index += 1 }
        return index < count && text[index] == "\n"
    }

    func startsLine(_ index: Int) -> Bool {
        var start = index
        while start > 0, index - start < 3, text[start - 1] == " " { start -= 1 }
        return start == 0 || text[start - 1] == "\n"
    }

    func skipIndent(from index: Int) -> Int {
        var end = index
        while end < count, end - index < 3, text[end] == " " { end += 1 }
        return end
    }

    /// Spaces and tabs, and at most one line break, as CommonMark allows inside a link.
    func skipLinkSpace(from index: Int) -> Int {
        var end = index
        while end < count, text[end].isSpaceOrTab { end += 1 }
        guard end < count, text[end] == "\n" else { return end }
        end += 1
        while end < count, text[end].isSpaceOrTab { end += 1 }
        return end
    }
}
