/// What earlier links sent to each host, so a value split across several links is still seen
/// when its last piece arrives.
struct ShardHistory: Sendable, Equatable {
    static let retained = 512

    var fragments: [String: [Unicode.Scalar]] = [:]
    var quarantined: Set<String> = []

    /// Appends a link's payload and returns the values that the join completes: those that
    /// start in an earlier link and end in this one.
    mutating func record(_ payload: [Unicode.Scalar], host: String, values: [PreparedValue]) -> [PreparedValue] {
        let prior = fragments[host, default: []]
        let joined = prior + payload
        fragments[host] = Array(joined.suffix(Self.retained))
        guard !prior.isEmpty else { return [] }
        return values.filter { value in
            value.skeleton.count >= PreparedContext.minimumSkeleton && joined.ranges(of: value.skeleton).contains {
                $0.lowerBound < prior.count && $0.upperBound > prior.count
            }
        }
    }
}
