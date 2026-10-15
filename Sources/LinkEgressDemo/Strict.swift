import LinkEgressKit

/// An allowlist is not a wall when an allowed host forwards anywhere.
func strict() {
    header(7, "An allowlist and a redirector")
    let policy = LinkPolicy.strict(allowing: [HostRule("docs.acme.example"), HostRule("google.com")])
    let answer = """
    See [the handbook](https://docs.acme.example/handbook), \
    [search](https://www.google.com/search?q=acme+handbook) and \
    [this result](https://www.google.com/url?q=https%3A%2F%2Fcollect.example%2Fc%3Fd%3Djane) \
    or [the mirror](https://mirror.example/handbook).
    """
    let report = LinkSanitizer(policy: policy).sanitize(answer)
    show(report)
    print("   rendered: \(report.text)")
}
