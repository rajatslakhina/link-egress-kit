/// Sanitizes an answer while it streams.
///
/// It holds back only what a later chunk could still change: the trailing word, an unclosed
/// link, a definition line still being written, and anything after an unclosed backtick run that
/// looks like a link. Everything it releases is exactly what `LinkSanitizer.sanitize` returns for
/// the same span of the finished answer.
public struct LinkStreamGate: Sendable {
    let sanitizer: LinkSanitizer
    let context: PreparedContext
    let startHistory: ShardHistory
    private(set) var history: ShardHistory
    private var seen: [Unicode.Scalar] = []
    private var released = 0

    /// Links released so far, judged.
    public private(set) var links: [JudgedLink] = []
    /// Everything released so far.
    public private(set) var output = ""

    init(sanitizer: LinkSanitizer, context: PreparedContext, history: ShardHistory) {
        self.sanitizer = sanitizer
        self.context = context
        self.startHistory = history
        self.history = history
    }

    /// Scalars received but not yet released.
    public var heldCount: Int { seen.count - released }

    /// Adds a chunk and returns the text that can be shown now.
    public mutating func append(_ chunk: String) -> String {
        seen.append(contentsOf: chunk.unicodeScalars)
        let outcome = LinkScanner(seen, partial: true).scan()
        return release(upTo: outcome.holdFrom, outcome: outcome)
    }

    /// Ends the stream and returns whatever was held.
    public mutating func finish() -> String {
        release(upTo: seen.count, outcome: LinkScanner(seen).scan())
    }

    /// The report for everything released so far; after `finish`, for the whole answer.
    public var report: LinkReport {
        LinkReport(original: String(scalars: seen), text: output, links: links)
    }

    private mutating func release(upTo hold: Int, outcome: ScanOutcome) -> String {
        guard hold > released else { return "" }
        var pass = startHistory
        let judged = sanitizer.judge(outcome.links, context: context, history: &pass)
        history = pass
        let fresh = judged.filter { $0.link.range.lowerBound >= released && $0.link.range.upperBound <= hold }
        let text = LinkRenderer.render(seen, range: released..<hold, links: fresh, escapes: outcome.escapes)
        links += fresh
        output += text
        released = hold
        return text
    }
}
