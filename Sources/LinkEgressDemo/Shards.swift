import LinkEgressKit

/// A value split so that no single link carries it whole.
func shards() async {
    header(5, "One value, several links")
    let context = EgressContext(sensitiveValues: [user])
    let answer = "Steps: [1](https://c.example/s?p=jane.d) [2](https://c.example/s?p=oe@exam) "
        + "[3](https://c.example/s?p=ple.com) [4](https://c.example/done) [5](https://docs.example/next)"
    let report = LinkSanitizer().sanitize(answer, context: context)
    show(report)
    print("   one answer: link 1 is released (a fragment); link 2 completes nothing; link 3 completes the address")
    let ledger = EgressLedger()
    let turns = [
        ("turn 1", "[continue](https://c.example/s?p=jane.doe)"),
        ("turn 2", "[continue](https://c.example/s?p=@example.com)"),
        ("turn 3", "[continue](https://c.example/s?p=thanks)")
    ]
    for (name, turn) in turns {
        let result = await ledger.sanitize(turn, context: context)
        let kinds = result.links.flatMap(\.findings).map(\.kind.rawValue)
        print("   ledger \(name) \(turn) -> \(result.links.first?.action.rawValue ?? "-") \(kinds)")
    }
    let quarantined = await ledger.quarantinedHosts.sorted()
    let count = await ledger.turns
    print("   ledger after \(count) turns: quarantined \(quarantined)")
}
