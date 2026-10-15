import LinkEgressKit

/// A session-masking layer sends the model `[EMAIL_1]` instead of the address, then restores the
/// answer for display. A link the model wrote around the token is restored too.
func restoreStep() {
    header(2, "The token the restore step would fill in")
    let answer = "Booked. [Confirm your seat](https://collect.example/s?u=[EMAIL_1]) or "
        + "<https://collect.example/t?u=%5BEMAIL_1%5D>."
    let restore = { (text: String) in text.replacingOccurrences(of: "[EMAIL_1]", with: "jane.doe@example.com") }
    let restoredFirst = restore(answer)
    print("   restore, then render: \(carries(liveLinks(restoredFirst), any: ["jane"])) live link(s) carry the address")
    let context = EgressContext(sensitiveValues: [SensitiveValue(label: "session token EMAIL_1", value: "[EMAIL_1]")])
    let report = LinkSanitizer().sanitize(answer, context: context)
    show(report)
    let checkedFirst = restore(report.text)
    print("   check, then restore:  \(carries(liveLinks(checkedFirst), any: ["jane", "EMAIL"])) live link(s) carry it")
    print("   shown: \(checkedFirst)")
}
