/// Finds every link in a model's answer, judges where it goes and what it carries, and rewrites
/// the answer so the links that would carry the conversation out are no longer links.
public struct LinkSanitizer: Sendable {
    public let policy: LinkPolicy

    public init(policy: LinkPolicy = .standard) {
        self.policy = policy
    }

    /// Every link construct in the text, unjudged.
    public func scan(_ text: String) -> [ScannedLink] {
        LinkScanner(text).scan().links
    }

    public func sanitize(_ text: String, context: EgressContext = .empty) -> LinkReport {
        var history = ShardHistory()
        return sanitize(text, context: PreparedContext(context), history: &history)
    }

    /// A gate for a streamed answer: it releases text as soon as no later chunk can change it.
    public func streamGate(context: EgressContext = .empty) -> LinkStreamGate {
        LinkStreamGate(sanitizer: self, context: PreparedContext(context), history: ShardHistory())
    }

    func sanitize(_ text: String, context: PreparedContext, history: inout ShardHistory) -> LinkReport {
        let scalars = Array(text.unicodeScalars)
        let outcome = LinkScanner(scalars).scan()
        let judged = judge(outcome.links, context: context, history: &history)
        let output = LinkRenderer.render(scalars, range: 0..<scalars.count, links: judged, escapes: outcome.escapes)
        return LinkReport(original: text, text: output, links: judged)
    }

    func judge(_ links: [ScannedLink], context: PreparedContext, history: inout ShardHistory) -> [JudgedLink] {
        let judge = LinkJudge(policy: policy, context: context)
        return links.map { judge.judge($0, history: &history) }
    }
}
