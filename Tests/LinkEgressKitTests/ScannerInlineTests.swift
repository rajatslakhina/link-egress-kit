import XCTest
@testable import LinkEgressKit

final class ScannerInlineTests: XCTestCase {
    func testInlineLinksWithEveryTitleForm() {
        XCTAssertEqual(destinations("[a](https://x.example/1)"), ["https://x.example/1"])
        XCTAssertEqual(destinations("[a](https://x.example/2 \"t\")"), ["https://x.example/2"])
        XCTAssertEqual(destinations("[a](https://x.example/3 't')"), ["https://x.example/3"])
        XCTAssertEqual(destinations("[a](https://x.example/4 (t))"), ["https://x.example/4"])
        XCTAssertEqual(destinations("[a](https://x.example/5 \"a\\\"b\")"), ["https://x.example/5"])
        XCTAssertEqual(scan("[docs](https://x.example)").links.first?.label, "docs")
        XCTAssertEqual(scan("[docs](https://x.example)").links.first?.range, 0..<25)
    }

    func testDestinationsResolveEscapesEntitiesAndBrackets() {
        XCTAssertEqual(destinations("[a](<https://x.example/a b>)"), ["https://x.example/a b"])
        XCTAssertEqual(destinations("[a](https://x.example/x(1))"), ["https://x.example/x(1)"])
        XCTAssertEqual(destinations("[a](https://x.example/x\\)y)"), ["https://x.example/x)y"])
        XCTAssertEqual(destinations("[a](https://x.example/?a=1&amp;b=&#106;&#x61;ne)"), ["https://x.example/?a=1&b=jane"])
        XCTAssertEqual(destinations("[a](https://x.example/&bogus;&#zz;&toolongforanentity;)"),
                       ["https://x.example/&bogus;&#zz;&toolongforanentity;"])
        XCTAssertEqual(destinations("[a](<https://x.example/\\>>)"), ["https://x.example/>"])
        XCTAssertEqual(destinations("[a](\n  https://x.example/n)"), ["https://x.example/n"])
        XCTAssertEqual(destinations("[a]()"), [""])
        XCTAssertEqual(kinds("[](https://x.example/e)"), [.inline])
    }

    func testBrokenInlineLinksFallBackToTheBareURLInside() {
        XCTAssertEqual(kinds("[a](https://x.example/x y)"), [.bareURL])
        XCTAssertEqual(kinds("[a](https://x.example/x \"t\" junk)"), [.bareURL])
        XCTAssertEqual(kinds("[a] (https://x.example/sp)"), [.bareURL])
        XCTAssertEqual(kinds("[a](<https://x.example/\nb>)"), [.bareURL])
        XCTAssertEqual(kinds("[a](<https://x.example/<b>)"), [.bareURL])
        XCTAssertEqual(kinds("[a](<https://x.example/b"), [.bareURL])
        XCTAssertEqual(kinds("[a](https://x.example/b \"t"), [.bareURL])
        XCTAssertEqual(kinds("[a](https://x.example/b \"t\n\nx\")"), [.bareURL])
        XCTAssertEqual(kinds("[a](https://x.example/b \"t\""), [.bareURL])
        XCTAssertEqual(kinds("[a](https://x.example/b"), [.bareURL])
        XCTAssertEqual(kinds("[a]("), [])
        XCTAssertEqual(kinds("[a]"), [])
        XCTAssertEqual(kinds("[a"), [])
    }

    func testNestedLinksAndLabels() {
        let nested = scan("[a [b](https://x.example/in) c](https://x.example/out)").links
        XCTAssertEqual(nested.map(\.kind), [.inline, .bareURL])
        XCTAssertEqual(nested.map(\.destination), ["https://x.example/in", "https://x.example/out"])
        XCTAssertEqual(destinations("[a `]` b](https://x.example/c)"), ["https://x.example/c"])
        XCTAssertEqual(kinds("[a `]\n\n` b](https://x.example/c)"), [.bareURL])
        XCTAssertEqual(destinations("[a `]` b `x](https://x.example/d)"), ["https://x.example/d"])
        XCTAssertEqual(destinations("[a \\] b](https://x.example/e)"), ["https://x.example/e"])
        XCTAssertEqual(destinations("[a [b] c](https://x.example/f)"), ["https://x.example/f"])
        XCTAssertEqual(kinds("[a\n\nb](https://x.example/g)"), [.bareURL])
        XCTAssertEqual(kinds("[a\n \t\nb](https://x.example/g)"), [.bareURL])
        let long = "[" + String(repeating: "a", count: LinkScanner.labelLimit + 5) + "](https://x.example/h)"
        XCTAssertEqual(kinds(long), [.bareURL])
    }

    func testImages() {
        let link = scan("x ![alt](https://img.example/i.png) y").links
        XCTAssertEqual(link.map(\.kind), [.image])
        XCTAssertEqual(link.first?.label, "alt")
        XCTAssertEqual(link.first?.range, 2..<35)
        XCTAssertTrue(LinkKind.image.loadsWithoutTap)
        XCTAssertFalse(LinkKind.inline.loadsWithoutTap)
        XCTAssertEqual(kinds("wow! [a](https://x.example)"), [.inline])
        XCTAssertEqual(kinds("end!"), [])
    }

    func testEscapesAndCodeSpans() {
        XCTAssertEqual(kinds("\\[a](https://x.example/esc)"), [.bareURL])
        XCTAssertEqual(kinds("\\a [b](https://x.example)"), [.inline])
        XCTAssertEqual(kinds("trailing \\"), [])
        XCTAssertEqual(kinds("x `[a](https://x.example/code)` y"), [])
        XCTAssertEqual(kinds("x ``[a](https://x.example/code)` y"), [.inline])
        XCTAssertEqual(kinds("x `a\n\n[b](https://x.example/x)\n\n`"), [.inline])
        XCTAssertEqual(kinds("x `a [b](https://x.example/x)"), [.inline])
    }

    func testFences() {
        XCTAssertEqual(kinds("```\ncode\n\n[b](https://x.example/x)\n\nmore\n```\nafter https://x.example/y"),
                       [.bareURL])
        XCTAssertEqual(kinds("```\nunclosed [b](https://x.example/x)"), [.inline])
        XCTAssertEqual(kinds("```\ncode\n````\n[b](https://x.example/x)\n```"), [.inline])
        XCTAssertEqual(kinds("```\ncode\n  ````\n[b](https://x.example/x)\n```"), [.inline])
        XCTAssertEqual(kinds("```\ncode x ````\n[b](https://x.example/x)\n```"), [])
        XCTAssertEqual(kinds("~~~\n[b](https://x.example/x)\n~~~"), [.inline])
        XCTAssertEqual(kinds("``\n[b](https://x.example/x)\n``"), [])
        XCTAssertEqual(kinds("   ```\n[b](https://x.example/x)\n```"), [])
    }
}
