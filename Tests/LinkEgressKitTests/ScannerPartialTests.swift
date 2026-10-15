import XCTest
@testable import LinkEgressKit

final class ScannerPartialTests: XCTestCase {
    func hold(_ text: String) -> Int {
        scan(text, partial: true).holdFrom
    }

    func testIncompleteInlineLinksHoldFromTheirStart() {
        XCTAssertEqual(hold("see [docs"), 4)
        XCTAssertEqual(hold("see [docs] "), 11)
        XCTAssertEqual(hold("see [docs]("), 4)
        XCTAssertEqual(hold("see [docs](https://x.example "), 4)
        XCTAssertEqual(hold("see [docs](<https://x.example "), 4)
        XCTAssertEqual(hold("see [docs](https://x.example \"title "), 4)
        XCTAssertEqual(hold("see [docs](https://x.example \"title\" "), 4)
        XCTAssertEqual(hold("see ![alt]("), 4)
        XCTAssertEqual(hold("see [a `b](x) "), 4)
        XCTAssertEqual(hold("see [docs](https://x.example) now "), 34)
    }

    func testIncompleteLineConstructs() {
        XCTAssertEqual(hold("a\n[1]: https://x.example/r "), 2)
        XCTAssertEqual(hold("a\n[1]"), 2)
        XCTAssertEqual(hold("a\n[1]: "), 2)
        XCTAssertEqual(hold("a\n[1]: https://x.example/r\nb "), 29)
        XCTAssertEqual(hold("```\ncode [a](https://x.example) more "), 9)
        XCTAssertEqual(hold("```\ncode only "), 14)
    }

    func testIncompleteAutolinksBareLinksAndAddresses() {
        XCTAssertEqual(hold("see <https://x.example"), 4)
        XCTAssertEqual(hold("see <https://x.example/a b"), 25)
        XCTAssertEqual(hold("see https://x.example/a"), 4)
        XCTAssertEqual(hold("see https://x.example/a "), 24)
        XCTAssertEqual(hold("mail jo@x.example"), 5)
        XCTAssertEqual(hold("mail jo@x.example "), 18)
        XCTAssertEqual(hold("mail @x.example"), 5)
        XCTAssertEqual(hold("plain words "), 12)
        XCTAssertEqual(hold("plain words"), 6)
        XCTAssertEqual(hold(""), 0)
    }

    func testAnOpenCodeSpanHoldsTheFirstLinkAfterIt() {
        XCTAssertEqual(hold("x `code [a](https://x.example) y "), 8)
        XCTAssertEqual(hold("x `code y "), 10)
        XCTAssertEqual(hold("x `code` [a](https://x.example) y "), 34)
        XCTAssertEqual(hold("x `a\n\nb` [c](https://x.example) y "), 9)
    }

    func testAHoldNeverCutsALinkInTwo() {
        let outcome = scan("see [the docs](https://x.example/a)", partial: true)
        XCTAssertEqual(outcome.holdFrom, 4)
        XCTAssertEqual(outcome.links, [])
        let kept = scan("[a](https://x.example) [b](https://y.example)tail", partial: true)
        XCTAssertEqual(kept.holdFrom, 23)
        XCTAssertEqual(kept.links.map(\.destination), ["https://x.example"])
    }
}
