import XCTest
@testable import LinkEgressKit

final class PayloadTests: XCTestCase {
    func testPercentChainStopsAtThreeRounds() {
        XCTAssertEqual(PayloadDecoder.percentChain("plain").map(\.text), ["plain"])
        XCTAssertEqual(PayloadDecoder.percentChain("%252541").map(\.text), ["%252541", "%2541", "%41", "A"])
        XCTAssertEqual(PayloadDecoder.percentChain("%25252541").count, 4)
        XCTAssertEqual(PayloadDecoder.percentChain("%2541").last?.encodings, [.percent, .percent])
        XCTAssertEqual(PayloadDecoder.percentDecoded("%zz%4"), "%zz%4")
        XCTAssertEqual(PayloadDecoder.percentDecoded("%e2%82%ac%E2%82%AC"), "\u{20AC}\u{20AC}")
        XCTAssertEqual(PayloadDecoder.fullyDecoded("%2541"), "A")
        XCTAssertEqual(PayloadDecoder.percentDecoded("a%FFb"), "a\u{FF}b")
    }

    func testVariantsUnwrapFormBase64AndHex() {
        let form = PayloadDecoder.variants(of: "jane+doe")
        XCTAssertEqual(form.map(\.text), ["jane+doe", "jane doe"])
        XCTAssertEqual(form.last?.encodings, [.form])
        let base64 = PayloadDecoder.variants(of: "amFuZS5kb2VAZXhhbXBsZS5jb20")
        XCTAssertTrue(base64.contains(DecodedPayload(text: "jane.doe@example.com", encodings: [.base64])))
        let urlSafe = PayloadDecoder.variants(of: "Pz8_Pz8-Pj4-")
        XCTAssertTrue(urlSafe.contains { $0.text == "?????>>>>" })
        let wrapped = PayloadDecoder.variants(of: "amFuZQ%3D%3D")
        XCTAssertTrue(wrapped.contains(DecodedPayload(text: "jane", encodings: [.percent, .base64])))
        let hex = PayloadDecoder.variants(of: "6a616e65406578")
        XCTAssertTrue(hex.contains(DecodedPayload(text: "jane@ex", encodings: [.hex])))
    }

    func testDecodersRejectNoise() {
        XCTAssertNil(PayloadDecoder.base64Decoded("short"))
        XCTAssertNil(PayloadDecoder.base64Decoded("not base64!"))
        XCTAssertNil(PayloadDecoder.base64Decoded("abcdefghi"))
        XCTAssertNil(PayloadDecoder.base64Decoded("////////"))
        XCTAssertNil(PayloadDecoder.base64Decoded("AAAAAAAA"))
        XCTAssertNil(PayloadDecoder.hexDecoded("abc"))
        XCTAssertNil(PayloadDecoder.hexDecoded("abcdefg0"))
        XCTAssertNil(PayloadDecoder.hexDecoded("0001020304"))
        XCTAssertNil(PayloadDecoder.hexDecoded("abcdefgh"))
        XCTAssertNil(PayloadDecoder.readable([0xFF, 0xFE]))
        XCTAssertEqual(PayloadDecoder.readable(Array("a\tb\nc\r".utf8)), "a\tb\nc\r")
    }

    func testSkeletonAndEntropy() {
        XCTAssertEqual(String(scalars: Skeleton.of("Jane.Doe@Example.COM 42")), "janedoeexamplecom42")
        XCTAssertEqual(Skeleton.entropy("aaaa"), 0)
        XCTAssertEqual(Skeleton.entropy("abcd"), 2, accuracy: 0.0001)
        XCTAssertEqual(Skeleton.entropy(""), 0)
    }

    func testPunycodeMatchesKnownVectors() {
        XCTAssertEqual(Punycode.encode("\u{0435}vil"), "vil-qdd")
        XCTAssertEqual(Punycode.encode("b\u{FC}cher"), "bcher-kva")
        XCTAssertEqual(Punycode.encode("m\u{FC}nchen"), "mnchen-3ya")
        XCTAssertEqual(Punycode.encode("\u{4F8B}\u{3048}"), "r8jz45g")
        XCTAssertEqual(Punycode.asciiHost("b\u{FC}cher.example"), "xn--bcher-kva.example")
        XCTAssertEqual(Punycode.asciiHost("plain.example"), "plain.example")
    }

    func testDestinationEntities() {
        XCTAssertEqual(DestinationText.numeric("#106"), "j")
        XCTAssertEqual(DestinationText.numeric("#X61"), "a")
        XCTAssertNil(DestinationText.numeric("amp"))
        XCTAssertNil(DestinationText.numeric("#xD800"))
        XCTAssertEqual(DestinationText.decode(Array("a\\".unicodeScalars)[...]), "a\\")
        XCTAssertEqual(DestinationText.decode(Array("&amp".unicodeScalars)[...]), "&amp")
    }
}
