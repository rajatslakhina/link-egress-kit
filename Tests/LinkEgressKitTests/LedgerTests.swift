import XCTest
@testable import LinkEgressKit

final class LedgerTests: XCTestCase {
    func testAValueSplitAcrossTurnsIsCaughtWhenItCompletes() async {
        let ledger = EgressLedger()
        let first = await ledger.sanitize("Step one: [open](https://c.example/?p=jane.do)", context: context)
        XCTAssertEqual(first.findings, [])
        let second = await ledger.sanitize("Step two: [open](https://c.example/?p=e@example.com)", context: context)
        XCTAssertEqual(second.links.first?.findings.map(\.kind), [.shardedValue])
        let quarantined = await ledger.quarantinedHosts
        XCTAssertEqual(quarantined, ["c.example"])
        let third = await ledger.sanitize("Step three: [open](https://c.example/)", context: context)
        XCTAssertEqual(third.links.first?.findings.map(\.kind), [.quarantinedHost])
        let turns = await ledger.turns
        let tracked = await ledger.trackedHosts
        XCTAssertEqual(turns, 3)
        XCTAssertEqual(tracked, ["c.example"])
        await ledger.forget()
        let cleared = await ledger.quarantinedHosts
        let reset = await ledger.turns
        XCTAssertEqual(cleared, [])
        XCTAssertEqual(reset, 0)
    }

    func testAStreamedTurnFeedsTheNextOne() async {
        let ledger = EgressLedger(sanitizer: LinkSanitizer(policy: .standard))
        var gate = await ledger.streamGate(context: context)
        _ = gate.append("See [a](https://c.example/?p=jane.d")
        _ = gate.append("o) now")
        _ = gate.finish()
        await ledger.absorb(gate)
        let next = await ledger.sanitize("[b](https://c.example/?p=e@example.com)", context: context)
        XCTAssertEqual(next.links.first?.findings.map(\.kind), [.shardedValue])
        let turns = await ledger.turns
        XCTAssertEqual(turns, 2)
    }

    func testConcurrentTurnsAreSerialised() async {
        let ledger = EgressLedger()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<20 {
                group.addTask { _ = await ledger.sanitize("[x](https://h\(index % 4).example/?p=\(index))") }
            }
        }
        let turns = await ledger.turns
        let tracked = await ledger.trackedHosts
        XCTAssertEqual(turns, 20)
        XCTAssertEqual(tracked, ["h0.example", "h1.example", "h2.example", "h3.example"])
    }
}
