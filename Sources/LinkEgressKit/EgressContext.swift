/// A value the app knows must not leave inside a URL: an address, an account number, a session
/// token such as `[EMAIL_1]`.
public struct SensitiveValue: Sendable, Hashable {
    /// Names the value in reports and notices. The value itself is never reported.
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

/// Who wrote a piece of the conversation.
public enum SourceOrigin: String, Sendable, CaseIterable {
    case user, system, tool, retrieved
}

/// Text the model has read this turn. A model-written URL that carries a long run of it is
/// carrying the conversation out.
public struct EgressSource: Sendable, Hashable {
    public let label: String
    public let text: String
    public let origin: SourceOrigin

    public init(label: String, text: String, origin: SourceOrigin) {
        self.label = label
        self.text = text
        self.origin = origin
    }
}

/// What a sanitizer knows about the conversation a text came out of.
public struct EgressContext: Sendable {
    public var sensitiveValues: [SensitiveValue]
    public var sources: [EgressSource]
    /// Hosts already caught collecting data, from an earlier turn or another session.
    public var quarantinedHosts: Set<String>
    /// The shortest run of letters and digits, shared with a source, that counts as carrying it.
    public var minimumOverlap: Int

    public init(
        sensitiveValues: [SensitiveValue] = [],
        sources: [EgressSource] = [],
        quarantinedHosts: Set<String> = [],
        minimumOverlap: Int = 16
    ) {
        self.sensitiveValues = sensitiveValues
        self.sources = sources
        self.quarantinedHosts = quarantinedHosts
        self.minimumOverlap = max(minimumOverlap, 4)
    }

    public static let empty = EgressContext()
}

struct PreparedValue: Sendable {
    let label: String
    let lowered: String
    let skeleton: [Unicode.Scalar]
}

/// The context with its lookups built once, so a stream gate can re-judge cheaply.
struct PreparedContext: Sendable {
    /// Values at least this long (letters and digits) are found inside other text; shorter
    /// ones only as a whole URL part, so `paris` does not match every Wikipedia link.
    static let minimumSkeleton = 6

    let values: [PreparedValue]
    let sources: [EgressSource]
    let grams: [String: Int]
    let overlap: Int
    let quarantined: Set<String>

    init(_ context: EgressContext) {
        values = context.sensitiveValues.map {
            PreparedValue(label: $0.label, lowered: $0.value.lowercased(), skeleton: Skeleton.of($0.value))
        }
        sources = context.sources
        overlap = context.minimumOverlap
        quarantined = context.quarantinedHosts
        var grams: [String: Int] = [:]
        for (index, source) in context.sources.enumerated() {
            let skeleton = Skeleton.of(source.text)
            guard skeleton.count >= context.minimumOverlap else { continue }
            for start in 0...(skeleton.count - context.minimumOverlap) {
                let gram = String(scalars: skeleton[start..<(start + context.minimumOverlap)])
                if grams[gram] == nil { grams[gram] = index }
            }
        }
        self.grams = grams
    }

    func matches(_ value: PreparedValue, text: String) -> Bool {
        guard value.skeleton.count >= Self.minimumSkeleton else { return text.lowercased() == value.lowered }
        return Skeleton.of(text).firstRange(of: value.skeleton) != nil
    }

    /// The longest run of `text` (letters and digits) that also appears in a source.
    func longestOverlap(in text: String) -> (source: Int, length: Int)? {
        let skeleton = Skeleton.of(text)
        guard skeleton.count >= overlap else { return nil }
        var best: (source: Int, length: Int)?
        var run = 0
        var runSource = 0
        for start in 0...(skeleton.count - overlap) {
            guard let source = grams[String(scalars: skeleton[start..<(start + overlap)])] else {
                run = 0
                continue
            }
            if run == 0 { runSource = source }
            run += 1
            let length = run + overlap - 1
            if length > best?.length ?? 0 { best = (runSource, length) }
        }
        return best
    }
}
