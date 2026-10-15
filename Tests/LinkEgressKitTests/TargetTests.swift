import XCTest
@testable import LinkEgressKit

final class TargetTests: XCTestCase {
    func testHierarchicalURLs() {
        let target = LinkTarget(parsing: "HTTPS://user:pw@Evil.Example.:8443/a/b?x=1&y=2;z#frag")
        XCTAssertEqual(target.scheme, "https")
        XCTAssertEqual(target.userinfo, "user:pw")
        XCTAssertEqual(target.host, "evil.example")
        XCTAssertEqual(target.hostKind, .name)
        XCTAssertEqual(target.port, "8443")
        XCTAssertEqual(target.path, "/a/b")
        XCTAssertEqual(target.query, "x=1&y=2;z")
        XCTAssertEqual(target.fragment, "frag")
        XCTAssertEqual(target.queryItems.map(\.name), ["x", "y", "z"])
        XCTAssertEqual(target.queryItems.map(\.value), ["1", "2", ""])
        XCTAssertEqual(target.hosts, ["evil.example"])
        XCTAssertEqual(target.asciiHost, "evil.example")
    }

    func testBrowsersFindAHostWithoutTwoSlashes() {
        XCTAssertEqual(LinkTarget(parsing: "https:evil.example/a").host, "evil.example")
        XCTAssertEqual(LinkTarget(parsing: "https:\\\\evil.example\\a").host, "evil.example")
        XCTAssertEqual(LinkTarget(parsing: "//evil.example/x").host, "evil.example")
        XCTAssertNil(LinkTarget(parsing: "//evil.example/x").scheme)
        XCTAssertEqual(LinkTarget(parsing: "ht\ntps://ev\u{200B}il.example").host, "evil.example")
        XCTAssertEqual(LinkTarget(parsing: "  https://evil%2Eexample/  ").host, "evil.example")
        XCTAssertEqual(LinkTarget(parsing: "myapp://open/x").host, "open")
        XCTAssertNil(LinkTarget(parsing: "https://").host)
        XCTAssertEqual(LinkTarget(parsing: "https://x.example:").port, "")
        XCTAssertEqual(LinkTarget(parsing: "https://x.example:ab").host, "x.example:ab")
    }

    func testRelativeAndOpaqueDestinations() {
        let relative = LinkTarget(parsing: "/path/to?d=5#top")
        XCTAssertNil(relative.scheme)
        XCTAssertNil(relative.host)
        XCTAssertEqual(relative.hostKind, .none)
        XCTAssertEqual(relative.path, "/path/to")
        XCTAssertEqual(relative.hosts, [])
        XCTAssertNil(relative.asciiHost)
        XCTAssertNil(LinkTarget(parsing: "9ab:x").scheme)
        XCTAssertNil(LinkTarget(parsing: "a_b:x").scheme)
        XCTAssertNil(LinkTarget(parsing: ":x").scheme)
        let script = LinkTarget(parsing: "JavaScript:alert(1)")
        XCTAssertEqual(script.scheme, "javascript")
        XCTAssertEqual(script.path, "alert(1)")
        XCTAssertNil(script.host)
        XCTAssertEqual(LinkTarget(parsing: "data:text/html,hi").path, "text/html,hi")
    }

    func testMailto() {
        let target = LinkTarget(parsing: "mailto:Jane@Evil.example,%20bob@other.example,nodomain@?subject=hi&body=x")
        XCTAssertEqual(target.recipients, ["jane@evil.example", "bob@other.example", "nodomain@"])
        XCTAssertEqual(target.host, "evil.example")
        XCTAssertEqual(target.hosts, ["evil.example", "other.example"])
        XCTAssertEqual(target.path, "")
        XCTAssertEqual(target.query, "subject=hi&body=x")
        XCTAssertNil(LinkTarget(parsing: "mailto:").host)
        XCTAssertNil(LinkTarget(parsing: "mailto:nobody").host)
        XCTAssertEqual(target.segments.filter { $0.part == .recipient }.count, 3)
    }

    func testHostKinds() {
        XCTAssertEqual(LinkTarget(parsing: "http://127.0.0.1/").hostKind, .ipv4)
        XCTAssertEqual(LinkTarget(parsing: "http://2130706433/").hostKind, .ipv4)
        XCTAssertEqual(LinkTarget(parsing: "http://0x7f.1/").hostKind, .ipv4)
        XCTAssertEqual(LinkTarget(parsing: "http://a.0xzz/").hostKind, .name)
        let six = LinkTarget(parsing: "http://[::1]:8080/x")
        XCTAssertEqual(six.hostKind, .ipv6)
        XCTAssertEqual(six.host, "[::1]")
        XCTAssertEqual(six.port, "8080")
        XCTAssertNil(LinkTarget(parsing: "http://[::1]/x").port)
        XCTAssertEqual(LinkTarget(parsing: "https://xn--vil-qdd.example/").hostKind, .punycode)
        let cyrillic = LinkTarget(parsing: "https://\u{0435}vil.example/")
        XCTAssertEqual(cyrillic.hostKind, .nonASCII)
        XCTAssertEqual(cyrillic.asciiHost, "xn--vil-qdd.example")
    }

    func testSegmentsAndCarriers() {
        let target = LinkTarget(parsing: "https://u@a.b.evil.example/p/q?k=v&flag#f")
        XCTAssertEqual(target.segments.map(\.part), [.userinfo, .host, .path, .path, .query, .query, .query, .fragment])
        XCTAssertEqual(target.subdomainLabels, ["a", "b"])
        XCTAssertEqual(target.payloadCarriers.map(\.raw), ["v", "f", "a", "b"])
        XCTAssertEqual(target.spanning, "a.b.evil.example /p/q k=v&flag f")
        XCTAssertEqual(LinkTarget(parsing: "http://127.0.0.1/").subdomainLabels, [])
        XCTAssertEqual(LinkTarget(parsing: "/x").subdomainLabels, [])
        XCTAssertEqual(LinkTarget(parsing: "https://x.example?a=%2541").shardPayload, "A")
        XCTAssertEqual(LinkTarget(parsing: "https://x.example/").queryItems.count, 0)
        let redirect = LinkTarget(parsing: "https://good.example/r?to=https%3A%2F%2Fevil.example%2Fc&b=//x.example&c=plain")
        XCTAssertEqual(redirect.embeddedHosts, ["evil.example", "x.example"])
    }
}
