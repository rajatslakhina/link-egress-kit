import LinkEgressKit

/// The live bubble shows an answer while it arrives. The gate releases text the moment no later
/// chunk can change it, and never a link it has not judged.
func streaming() {
    header(6, "Streaming")
    let context = EgressContext(sensitiveValues: [user])
    let answer = "Your receipt: [view](https://collect.example/r?d=jane.doe@example.com). "
        + "Docs: https://docs.example/receipts and <https://collect.example/?e=amFuZS5kb2VAZXhhbXBsZS5jb20>. Bye."
    let whole = LinkSanitizer().sanitize(answer, context: context).text
    let scalars = Array(answer.unicodeScalars)
    var gate = LinkSanitizer().streamGate(context: context)
    var output = ""
    var holds: [Int] = []
    for start in stride(from: 0, to: scalars.count, by: 7) {
        var chunk = String.UnicodeScalarView()
        chunk.append(contentsOf: scalars[start..<min(start + 7, scalars.count)])
        output += gate.append(String(chunk))
        holds.append(gate.heldCount)
    }
    output += gate.finish()
    print("   \(scalars.count) scalars in chunks of 7; held after each chunk:")
    print("   \(holds.map(String.init).joined(separator: " "))")
    print("   largest hold \(holds.max() ?? 0) scalars; streamed output equals the whole-text result: "
          + "\(output == whole)")
    var identical = 0
    for split in 0...scalars.count {
        var twoChunk = LinkSanitizer().streamGate(context: context)
        var first = String.UnicodeScalarView()
        first.append(contentsOf: scalars[..<split])
        var second = String.UnicodeScalarView()
        second.append(contentsOf: scalars[split...])
        let text = twoChunk.append(String(first)) + twoChunk.append(String(second)) + twoChunk.finish()
        identical += text == whole ? 1 : 0
    }
    print("   two-chunk splits identical to the whole-text result: \(identical) of \(scalars.count + 1)")
    print("   live links in what was shown: \(liveLinks(output).count), carrying the address: "
          + "\(carries(liveLinks(output), any: markers))")
}
