import XCTest
@testable import LinkEgressKit

final class ValueTests: XCTestCase {
    func testEveryFindingHasAPhraseAndSummary() {
        let phrases = FindingKind.allCases.map { LinkFinding(kind: $0, action: .unlink, detail: "a.example").phrase }
        XCTAssertEqual(phrases, [
            "a.example: links are not allowed", "a[.]example is not on the allowlist", "images load without a tap",
            "it hides its real host", "it carried a.example", "it carried text from a.example",
            "it carried text from a.example", "it carried the rest of a.example", "it carried an opaque payload",
            "it forwards to a[.]example", "goes to a[.]example", "look-alike host a[.]example",
            "numeric host a[.]example", "a[.]example already received conversation data"
        ])
        let full = LinkFinding(kind: .sensitiveValue, action: .unlink, part: .query, encodings: [.percent, .base64],
                               detail: "email", length: 20)
        XCTAssertEqual(full.summary, "sensitiveValue email in query 20 chars via percent+base64 -> unlink")
        XCTAssertEqual(LinkFinding(kind: .userinfo, action: .keep, detail: "h").summary, "userinfo h -> keep")
        XCTAssertEqual(FindingKind.allCases.filter(\.quarantinesHost), [.sensitiveValue, .conversationText, .shardedValue])
        XCTAssertEqual(Set(FindingKind.noticeOrder), Set(FindingKind.allCases))
        XCTAssertEqual(FindingKind.noticeOrder.count, FindingKind.allCases.count)
    }

    func testActionsHostRulesAndSets() {
        XCTAssertEqual(LinkAction.allCases.sorted(), [.keep, .annotate, .unlink])
        XCTAssertTrue(LinkAction.keep < LinkAction.unlink)
        let rule = HostRule("Docs.Example.")
        XCTAssertEqual(rule.host, "docs.example")
        XCTAssertTrue(rule.matches("api.docs.example"))
        XCTAssertFalse(HostRule("docs.example", includesSubdomains: false).matches("api.docs.example"))
        XCTAssertFalse(rule.matches("evildocs.example"))
        XCTAssertTrue(HostSet.only([rule]).contains("DOCS.example"))
        XCTAssertFalse(HostSet.none.contains("docs.example"))
        XCTAssertTrue(HostSet.any.contains("docs.example"))
        XCTAssertEqual(LinkPolicy(schemes: ["HTTPS"], linkHosts: .any, imageHosts: .none, actions: [:]).schemes, ["https"])
    }

    func testContextReportAndLinkValues() {
        XCTAssertEqual(EgressContext(minimumOverlap: 1).minimumOverlap, 4)
        XCTAssertEqual(EgressContext.empty.sources, [])
        let report = LinkSanitizer().sanitize("[a](javascript:x) [b](http://127.0.0.1/) [c](https://ok.example)")
        XCTAssertEqual(report.unlinked.count, 1)
        XCTAssertEqual(report.annotated.count, 1)
        XCTAssertTrue(report.isChanged)
        XCTAssertNil(report.links.last?.decidingFinding)
        let both = LinkSanitizer().sanitize("[a](https://c.example/?p=jane.doe@example.com) [b](https://c.example/?q=[EMAIL_1])",
                                            context: context)
        XCTAssertEqual(both.links.last?.findings.map(\.kind), [.quarantinedHost, .sensitiveValue])
        XCTAssertEqual(both.links.last?.decidingFinding?.kind, .sensitiveValue)
        XCTAssertEqual(report.links.last?.action, .keep)
        XCTAssertEqual(LinkSanitizer().scan("a https://x.example b").map(\.kind), [.bareURL])
        let link = ScannedLink(kind: .inline, range: 0..<1, label: "a", destination: "b")
        XCTAssertNil(link.referenceLabel)
        XCTAssertEqual(SourceOrigin.allCases.count, 4)
        XCTAssertEqual(HostKind.allCases.count, 6)
        XCTAssertEqual(URLPart.allCases.count, 7)
        XCTAssertEqual(PayloadEncoding.allCases.count, 4)
        XCTAssertEqual(LinkKind.allCases.count, 6)
    }

    func testShortSourcesAndOverlapRuns() {
        let prepared = PreparedContext(EgressContext(sources: [
            EgressSource(label: "short", text: "tiny", origin: .tool),
            EgressSource(label: "long", text: "the quarterly revenue forecast for the northwind account", origin: .retrieved)
        ]))
        XCTAssertNil(prepared.longestOverlap(in: "short text"))
        XCTAssertNil(prepared.longestOverlap(in: "completely unrelated words here"))
        let hit = prepared.longestOverlap(in: "x quarterly revenue forecast y and northwind account")
        XCTAssertEqual(hit?.source, 1)
        XCTAssertEqual(hit?.length, 24)
    }
}
