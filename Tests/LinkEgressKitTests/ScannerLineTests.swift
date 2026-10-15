import XCTest
@testable import LinkEgressKit

final class ScannerLineTests: XCTestCase {
    func testDefinitions() {
        let found = scan("see [docs][1]\n\n[1]: https://x.example/r \"title\"\nnext").links
        XCTAssertEqual(found.map(\.kind), [.definition])
        XCTAssertEqual(found.first?.destination, "https://x.example/r")
        XCTAssertEqual(found.first?.referenceLabel, "1")
        XCTAssertEqual(found.first?.label, nil)
        XCTAssertEqual(found.first?.range, 15..<47)
        XCTAssertEqual(scan("   [My  Docs]: <https://x.example/a b>").links.first?.referenceLabel, "my docs")
        XCTAssertEqual(destinations("   [My  Docs]: <https://x.example/a b>"), ["https://x.example/a b"])
        XCTAssertEqual(destinations("[a]:\n  https://x.example/next-line"), ["https://x.example/next-line"])
        XCTAssertEqual(destinations("[a\\]b]: https://x.example/esc"), ["https://x.example/esc"])
    }

    func testThingsThatAreNotDefinitions() {
        XCTAssertEqual(kinds("    [a]: https://x.example/indented"), [.bareURL])
        XCTAssertEqual(kinds("[a[b]]: https://x.example/nested"), [.bareURL])
        XCTAssertEqual(kinds("[ ]: https://x.example/blank"), [.bareURL])
        XCTAssertEqual(kinds("[a\n\nb]: https://x.example/blank-line"), [.bareURL])
        XCTAssertEqual(kinds("[a] https://x.example/no-colon"), [.bareURL])
        XCTAssertEqual(kinds("[a]: <>"), [])
        XCTAssertEqual(kinds("[a]:"), [])
        XCTAssertEqual(kinds("[a]"), [])
        XCTAssertEqual(kinds("[" + String(repeating: "a", count: 1_200) + "]: https://x.example/long"), [.bareURL])
        XCTAssertEqual(kinds("[abc"), [])
    }

    func testAutolinks() {
        let found = scan("a <https://x.example/a?b=1> b <jane@x.example> c <ftp+x:y>").links
        XCTAssertEqual(found.map(\.kind), [.autolink, .autolink, .autolink])
        XCTAssertEqual(found.map(\.destination), ["https://x.example/a?b=1", "mailto:jane@x.example", "ftp+x:y"])
        XCTAssertEqual(found.first?.label, "https://x.example/a?b=1")
        XCTAssertEqual(kinds("<javascript:alert(1)>"), [.autolink])
        XCTAssertEqual(kinds("<a:b> <abc> <> <a@b@c> <@b> <a@> <a b> <x\u{7}y> <a<b>"), [])
        XCTAssertEqual(kinds("<j!ne@x.example> <ok@x_y>"), [.autolink])
        XCTAssertEqual(kinds("<" + String(repeating: "a", count: 40) + ":x>"), [])
        XCTAssertEqual(kinds("<9a:x> <a$b:x>"), [])
        XCTAssertEqual(kinds("<https://x.example/unclosed now"), [.bareURL])
        XCTAssertEqual(kinds("<https"), [])
    }

    func testBareURLs() {
        XCTAssertEqual(destinations("see https://x.example/a and HTTP://X.example/b and ftp://x.example"),
                       ["https://x.example/a", "HTTP://X.example/b", "ftp://x.example"])
        XCTAssertEqual(destinations("www.x.example/w and (www.y.example)"), ["http://www.x.example/w", "http://www.y.example"])
        XCTAssertEqual(destinations("xhttps://x.example wwww.x.example .www.x.example Www.x.example"), [])
        XCTAssertEqual(destinations("a.https://x.example/a"), ["https://x.example/a"])
        XCTAssertEqual(destinations("end https://x.example/a.,:;!?*_~'\" now"), ["https://x.example/a"])
        XCTAssertEqual(destinations("(https://x.example/a) and https://x.example/b(1)"),
                       ["https://x.example/a", "https://x.example/b(1)"])
        XCTAssertEqual(destinations("https://x.example/a&lt; https://x.example/b&amp;c https://x.example/&;"),
                       ["https://x.example/a", "https://x.example/b&amp;c", "https://x.example/&"])
        XCTAssertEqual(destinations("https:///x https:// http:/x.example"), [])
        XCTAssertEqual(destinations("https://x.example/a<b"), ["https://x.example/a"])
    }

    func testBareEmails() {
        let found = scan("mail x.jane+tag@mail.x.example. or mailto:jo@x.example?body=1").links
        XCTAssertEqual(found.map(\.kind), [.bareEmail, .bareEmail])
        XCTAssertEqual(found.map(\.destination), ["mailto:x.jane+tag@mail.x.example", "mailto:jo@x.example"])
        XCTAssertEqual(found.first?.label, "x.jane+tag@mail.x.example")
        XCTAssertEqual(kinds("jane@x jane@x.example_ @x.example j%ane@x.example"), [.bareEmail])
        XCTAssertEqual(destinations("j%ane@x.example"), ["mailto:ane@x.example"])
        XCTAssertEqual(kinds("<https://a.example>jo@x.example"), [.autolink, .bareEmail])
        XCTAssertEqual(scan("\\.jo@x.example").links.first?.label, "jo@x.example")
        XCTAssertEqual(kinds("`a`jo@x.example"), [.bareEmail])
        XCTAssertEqual(scan("`a`jo@x.example").links.first?.range, 3..<15)
    }
}
