import Foundation
import LinkEgressKit

/// The URLs Apple's Markdown parser turns into links or images, parsed the way SwiftUI's `Text`
/// parses a `LocalizedStringKey`.
func liveLinks(_ markdown: String) -> [String] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    guard let parsed = try? AttributedString(markdown: markdown, options: options) else { return [] }
    return parsed.runs.compactMap { $0.link?.absoluteString ?? $0.imageURL?.absoluteString }
}

/// What a typical hand-rolled sanitizer looks for: `[text](url)` and nothing else.
func naiveLinks(_ markdown: String) -> [String] {
    let pattern = /!?\[[^\]]*\]\(([^)\s]*)[^)]*\)/
    return markdown.matches(of: pattern).map { String($0.1) }
}

func carries(_ links: [String], any markers: [String]) -> Int {
    links.filter { link in markers.contains { link.contains($0) } }.count
}

func header(_ number: Int, _ title: String) {
    print("")
    print("== \(number). \(title)")
}

func pad(_ text: String, _ width: Int) -> String {
    text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
}

func show(_ report: LinkReport) {
    for judged in report.links {
        let reasons = judged.findings.map(\.kind.rawValue).joined(separator: ", ")
        let host = judged.target.hosts.first ?? judged.target.scheme ?? "-"
        print("   \(pad(judged.link.kind.rawValue, 10)) \(pad(host, 26)) \(pad(judged.action.rawValue, 9)) \(reasons)")
    }
}

let user = SensitiveValue(label: "email", value: "jane.doe@example.com")
let markers = ["jane", "EMAIL_1", "QX7", "amFuZS", "UVg3", "6a616e65"]
