/// One conversation's memory of where its links went.
///
/// Within one answer a sanitizer already catches a value split across several links to the same
/// host. The ledger carries that across turns: a value whose first half went out in one answer
/// is caught when its second half arrives in the next, and a host caught collecting data stays
/// blocked for the rest of the conversation.
public actor EgressLedger {
    public let sanitizer: LinkSanitizer
    private var history = ShardHistory()

    /// Answers sanitized or absorbed so far.
    public private(set) var turns = 0

    public init(sanitizer: LinkSanitizer = LinkSanitizer()) {
        self.sanitizer = sanitizer
    }

    public var quarantinedHosts: Set<String> { history.quarantined }

    /// Hosts that have received at least one payload this conversation.
    public var trackedHosts: [String] { history.fragments.keys.sorted() }

    public func sanitize(_ text: String, context: EgressContext = .empty) -> LinkReport {
        var turnHistory = history
        let report = sanitizer.sanitize(text, context: PreparedContext(context), history: &turnHistory)
        history = turnHistory
        turns += 1
        return report
    }

    /// A stream gate that starts from this conversation's history. Hand it back to `absorb`
    /// after `finish` so the next turn sees what it sent.
    public func streamGate(context: EgressContext = .empty) -> LinkStreamGate {
        LinkStreamGate(sanitizer: sanitizer, context: PreparedContext(context), history: history)
    }

    public func absorb(_ gate: LinkStreamGate) {
        history = gate.history
        turns += 1
    }

    public func forget() {
        history = ShardHistory()
        turns = 0
    }
}
