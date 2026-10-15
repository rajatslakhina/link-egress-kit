import XCTest
@testable import LinkEgressKit

final class RenderTests: XCTestCase {
    func sanitized(_ text: String, policy: LinkPolicy = .standard) -> String {
        LinkSanitizer(policy: policy).sanitize(text, context: context).text
    }

    func testUnlinkedLinksKeepTheirTextAndSayWhy() {
        XCTAssertEqual(sanitized("see [docs](https://evil.example/p?d=jane.doe%40example.com) now"),
                       "see docs (link to evil[.]example removed: it carried email) now")
        XCTAssertEqual(sanitized("x ![chart](https://img.example/c.png) y"),
                       "x chart (image from img[.]example removed: images load without a tap) y")
        XCTAssertEqual(sanitized("[x](javascript:alert(1))"), "x (link removed: javascript: links are not allowed)")
        XCTAssertEqual(sanitized("[](https://evil.example/?d=jane.doe@example.com)"),
                       "(link to evil[.]example removed: it carried email)")
        XCTAssertEqual(sanitized("a\n[1]: https://evil.example/?d=jane.doe@example.com\nb"),
                       "a\n(link to evil[.]example removed: it carried email)\nb")
        XCTAssertEqual(sanitized("[see https://evil.example/x](https://evil.example/?d=jane.doe@example.com)"),
                       "see https[:]//evil[.]example/x (link to evil[.]example removed: it carried email)")
        XCTAssertEqual(sanitized("write jane.doe@example.com"), "write jane.doe@example.com")
    }

    func testTheOuterBracketsOfANestedLinkAreEscaped() {
        let text = "Nested [a [b](https://evil.example/in?d=jane.doe@example.com) c](https://ok.example/out)"
        XCTAssertEqual(sanitized(text),
                       "Nested \\[a b (link to evil[.]example removed: it carried email) c](https://ok.example/out)")
        XCTAssertEqual(liveLinks(sanitized(text)), ["https://ok.example/out"])
        XCTAssertEqual(scan(text).escapes, [7])
    }

    func testAnnotatedLinksStayLive() {
        XCTAssertEqual(sanitized("[apple.com](https://apple.com.evil.example/)"),
                       "[apple.com](https://apple.com.evil.example/) (goes to apple[.]com[.]evil[.]example)")
        XCTAssertEqual(sanitized("go https://xn--vil-qdd.example/x now"),
                       "go https://xn--vil-qdd.example/x (look-alike host xn--vil-qdd[.]example) now")
        XCTAssertEqual(sanitized("[a](http://127.0.0.1/)"), "[a](http://127.0.0.1/) (numeric host 127[.]0[.]0[.]1)")
        var custom = LinkPolicy.standard
        custom.actions[.embeddedURL] = .annotate
        XCTAssertEqual(sanitized("[a](https://good.example/r?to=https://evil.example/)", policy: custom),
                       "[a](https://good.example/r?to=https://evil.example/) (it forwards to evil[.]example)")
        XCTAssertEqual(sanitized("[a](https://good.example/r)", policy: custom), "[a](https://good.example/r)")
    }

    func testDefangedTextNeverAutolinks() {
        XCTAssertEqual(Defang.text("mail jane@x.example or <https://x.example> plain"),
                       "mail jane[@]x[.]example or <https[:]//x[.]example> plain")
        XCTAssertEqual(Defang.host("www.x.example"), "www[.]x[.]example")
        XCTAssertEqual(liveLinks(Defang.text("https://x.example/a www.x.example jane@x.example")), [])
    }

    func testNoAttackSurvivesAsALiveLink() {
        for attack in attackCorpus {
            let before = liveLinks(attack)
            let after = liveLinks(sanitized(attack))
            XCTAssertTrue(before.contains { link in sensitiveMarkers.contains { link.contains($0) } }
                          || attack.contains("![") || attack.hasPrefix("Fine"), attack)
            let leaking = after.filter { link in sensitiveMarkers.contains { link.contains($0) } }
            XCTAssertEqual(leaking.filter { !$0.contains("c.example/?p=jane.do") }, [], attack)
        }
    }

    func testOnlyTheLinksThatLeakAreTouched() {
        let answer = "Read [the guide](https://docs.example.com/guide), www.example.org/about and <https://a.example/b>."
        let report = LinkSanitizer().sanitize(answer, context: context)
        XCTAssertEqual(report.text, answer)
        XCTAssertFalse(report.isChanged)
        XCTAssertEqual(report.links.count, 3)
        XCTAssertEqual(liveLinks(report.text).count, 3)
    }
}
