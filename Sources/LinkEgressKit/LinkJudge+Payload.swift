extension LinkJudge {
    /// What the URL carries. A link the user pasted is theirs to send; a link copied from any
    /// source is expected to share text with it, so only sensitive values are checked there.
    func payloadChecks(_ target: LinkTarget, provenance: Provenance) -> [Candidate] {
        if case .copied(_, .user) = provenance { return [] }
        let segments = target.segments
        var found = sensitiveChecks(target, segments: segments)
        if case .composed = provenance {
            found += conversationChecks(segments) + opaqueChecks(target)
        }
        return found
    }

    func sensitiveChecks(_ target: LinkTarget, segments: [Segment]) -> [Candidate] {
        context.values.compactMap { value in
            for segment in segments where !(segment.part == .recipient && segment.raw.lowercased() == value.lowered) {
                let variants = PayloadDecoder.variants(of: segment.raw)
                if let hit = variants.first(where: { context.matches(value, text: $0.text) }) {
                    return Candidate(.sensitiveValue, part: segment.part, encodings: hit.encodings, detail: value.label)
                }
            }
            let spanning = PayloadDecoder.percentChain(target.spanning)
            guard let hit = spanning.first(where: { context.matches(value, text: $0.text) }) else { return nil }
            return Candidate(.sensitiveValue, part: .spanning, encodings: hit.encodings, detail: value.label)
        }
    }

    /// The longest run of conversation text in any part, in any encoding.
    func conversationChecks(_ segments: [Segment]) -> [Candidate] {
        var best: Candidate?
        for segment in segments {
            for variant in PayloadDecoder.variants(of: segment.raw) {
                guard let overlap = context.longestOverlap(in: variant.text),
                      overlap.length > best?.length ?? 0 else { continue }
                let kind: FindingKind = segment.part == .path ? .conversationTextInPath : .conversationText
                best = Candidate(kind, part: segment.part, encodings: variant.encodings,
                                 detail: context.sources[overlap.source].label, length: overlap.length)
            }
        }
        return best.map { [$0] } ?? []
    }

    func opaqueChecks(_ target: LinkTarget) -> [Candidate] {
        guard let carrier = target.payloadCarriers.first(where: { Self.looksOpaque($0.raw) }) else { return [] }
        return [Candidate(.opaquePayload, part: carrier.part, detail: target.host ?? "", length: carrier.raw.count)]
    }

    /// Long, mixed-class and nearly separator-free: a token, not a word or a slug. Entropy alone
    /// is not enough, because a short sample of English scores as high as random text.
    static func looksOpaque(_ raw: String) -> Bool {
        let scalars = raw.unicodeScalars
        guard scalars.count >= opaqueLength else { return false }
        let classes = [
            scalars.contains { $0.value >= 0x61 && $0.value <= 0x7A },
            scalars.contains { $0.value >= 0x41 && $0.value <= 0x5A },
            scalars.contains(where: \.isASCIIDigit)
        ].filter { $0 }.count
        let separators = scalars.filter { "-_.~ ".unicodeScalars.contains($0) }.count
        return classes >= 2 && separators * 10 <= scalars.count && Skeleton.entropy(raw) >= opaqueEntropy
    }

    func shardChecks(_ target: LinkTarget, history: inout ShardHistory) -> [Candidate] {
        guard let host = target.hosts.first else { return [] }
        let payload = Skeleton.of(target.shardPayload)
        guard !payload.isEmpty else { return [] }
        return history.record(payload, host: host, values: context.values).map {
            Candidate(.shardedValue, part: .query, detail: $0.label)
        }
    }
}
