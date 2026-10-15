import XCTest
@testable import LinkEgressKit

final class StreamTests: XCTestCase {
    func streamed(_ chunks: [String], sanitizer: LinkSanitizer = LinkSanitizer()) -> (String, LinkStreamGate) {
        var gate = sanitizer.streamGate(context: context)
        var output = ""
        for chunk in chunks { output += gate.append(chunk) }
        output += gate.finish()
        return (output, gate)
    }

    func split(_ text: String, at offset: Int) -> [String] {
        let scalars = Array(text.unicodeScalars)
        return [String(scalars: scalars[..<offset]), String(scalars: scalars[offset...])]
    }

    func testEveryTwoChunkSplitMatchesTheWholeText() {
        let texts = attackCorpus + [
            "x `code [a](https://evil.example/?d=jane.doe@example.com) y` z https://evil.example/?d=jane.doe@example.com",
            "```\nfenced [a](https://evil.example/?d=jane.doe@example.com)\n```\nafter jo@x.example."
        ]
        for text in texts {
            let whole = LinkSanitizer().sanitize(text, context: context)
            for offset in 0...text.unicodeScalars.count {
                let (output, gate) = streamed(split(text, at: offset))
                XCTAssertEqual(output, whole.text, "\(text) split at \(offset)")
                XCTAssertEqual(gate.links, whole.links, "\(text) split at \(offset)")
            }
        }
    }

    func testThreeChunkSplitsAndSmallChunks() {
        let text = attackCorpus[10] + " " + attackCorpus[2]
        let whole = LinkSanitizer().sanitize(text, context: context).text
        let scalars = Array(text.unicodeScalars)
        for first in stride(from: 0, to: scalars.count, by: 5) {
            for second in stride(from: first, to: scalars.count, by: 9) {
                let chunks = [String(scalars: scalars[..<first]), String(scalars: scalars[first..<second]),
                              String(scalars: scalars[second...])]
                XCTAssertEqual(streamed(chunks).0, whole)
            }
        }
        let sevens = stride(from: 0, to: scalars.count, by: 7).map {
            String(scalars: scalars[$0..<min($0 + 7, scalars.count)])
        }
        XCTAssertEqual(streamed(sevens).0, whole)
    }

    func testTheGateHoldsOnlyWhatCouldChange() {
        var gate = LinkSanitizer().streamGate(context: context)
        XCTAssertEqual(gate.append("Read the "), "Read the ")
        XCTAssertEqual(gate.heldCount, 0)
        XCTAssertEqual(gate.append("[guide](https://evil.example/?d=jane"), "")
        XCTAssertEqual(gate.heldCount, 36)
        XCTAssertEqual(gate.append(".doe@example.com) now "),
                       "guide (link to evil[.]example removed: it carried email) now ")
        XCTAssertEqual(gate.heldCount, 0)
        XCTAssertEqual(gate.append("bye"), "")
        XCTAssertEqual(gate.report.links.count, 1)
        XCTAssertEqual(gate.finish(), "bye")
        XCTAssertEqual(gate.finish(), "")
        XCTAssertEqual(gate.output, "Read the guide (link to evil[.]example removed: it carried email) now bye")
        XCTAssertEqual(gate.report.original, "Read the [guide](https://evil.example/?d=jane.doe@example.com) now bye")
    }
}
