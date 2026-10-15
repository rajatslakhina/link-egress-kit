import Foundation
@testable import LinkEgressKit

func scan(_ text: String, partial: Bool = false) -> ScanOutcome {
    LinkScanner(Array(text.unicodeScalars), partial: partial).scan()
}

func kinds(_ text: String) -> [LinkKind] {
    scan(text).links.map(\.kind)
}

func destinations(_ text: String) -> [String] {
    scan(text).links.map(\.destination)
}

/// The URLs Apple's Markdown parser makes live, the way SwiftUI's `Text` renders an answer.
func liveLinks(_ markdown: String) -> [String] {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    guard let parsed = try? AttributedString(markdown: markdown, options: options) else { return ["<parse error>"] }
    return parsed.runs.compactMap { $0.link?.absoluteString ?? $0.imageURL?.absoluteString }
}

let email = SensitiveValue(label: "email", value: "jane.doe@example.com")
let token = SensitiveValue(label: "token", value: "[EMAIL_1]")
let booking = EgressSource(
    label: "user message",
    text: "My booking reference is QX7-ALPHA-2291 for the Lisbon trip on 14 March",
    origin: .user
)
let context = EgressContext(sensitiveValues: [email, token], sources: [booking])

func kindsOfFindings(_ text: String, policy: LinkPolicy = .standard, in context: EgressContext = context)
    -> [[FindingKind]] {
    LinkSanitizer(policy: policy).sanitize(text, context: context).links.map { $0.findings.map(\.kind) }
}
