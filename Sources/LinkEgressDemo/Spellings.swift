import LinkEgressKit

/// One leak, written six ways. Each is a live link in SwiftUI's `Text`.
func spellings() {
    header(1, "One leak, six spellings")
    let leak = "https://collect.example/c?d=jane.doe%40example.com"
    let forms: [(String, String)] = [
        ("inline", "Confirm [here](\(leak))."),
        ("definition", "Confirm [here][1].\n\n[1]: \(leak)"),
        ("autolink", "Confirm at <\(leak)>."),
        ("bare URL", "Confirm at \(leak) now."),
        ("escaped", "Confirm \\[here](\(leak))."),
        ("www.", "Confirm at www.collect.example/c?d=jane.doe%40example.com now.")
    ]
    let sanitizer = LinkSanitizer()
    let context = EgressContext(sensitiveValues: [user])
    var naiveCaught = 0
    var kitCaught = 0
    print("   form         live before  naive regex sees it  LinkEgressKit  live after")
    for (name, answer) in forms {
        let report = sanitizer.sanitize(answer, context: context)
        let naive = carries(naiveLinks(answer), any: ["jane"]) > 0
        let caught = !report.unlinked.isEmpty
        naiveCaught += naive ? 1 : 0
        kitCaught += caught ? 1 : 0
        let before = carries(liveLinks(answer), any: ["jane"])
        let after = carries(liveLinks(report.text), any: ["jane"])
        print("   \(pad(name, 12)) \(pad(String(before), 12)) \(pad(naive ? "yes" : "no", 20)) "
              + "\(pad(caught ? "unlinked" : "missed", 14)) \(after)")
    }
    print("   a [text](url) regex sees \(naiveCaught) of \(forms.count); "
          + "LinkEgressKit unlinks \(kitCaught) of \(forms.count)")
    print("   escaped form after sanitizing: \(sanitizer.sanitize(forms[4].1, context: context).text)")
}
