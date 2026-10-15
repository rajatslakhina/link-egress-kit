import Foundation

/// An encoding a URL part was found to be wrapped in.
public enum PayloadEncoding: String, Sendable, CaseIterable {
    case percent
    /// `+` read as a space, as HTML forms encode it.
    case form
    case base64
    case hex
}

struct DecodedPayload: Sendable, Equatable {
    let text: String
    let encodings: [PayloadEncoding]
}

/// Unwraps the encodings an exfiltrating URL hides data in, so a check reads what the server
/// would read.
enum PayloadDecoder {
    static func variants(of raw: String) -> [DecodedPayload] {
        var result = percentChain(raw)
        append(DecodedPayload(text: percentDecoded(raw.replacingOccurrences(of: "+", with: " ")), encodings: [.form]),
               to: &result)
        for base in result {
            if let decoded = base64Decoded(base.text) {
                append(DecodedPayload(text: decoded, encodings: base.encodings + [.base64]), to: &result)
            }
            if let decoded = hexDecoded(base.text) {
                append(DecodedPayload(text: decoded, encodings: base.encodings + [.hex]), to: &result)
            }
        }
        return result
    }

    static func append(_ payload: DecodedPayload, to list: inout [DecodedPayload]) {
        if !list.contains(where: { $0.text == payload.text }) { list.append(payload) }
    }

    /// The raw text, then each round of percent-decoding that changes it, up to three.
    static func percentChain(_ raw: String) -> [DecodedPayload] {
        var result = [DecodedPayload(text: raw, encodings: [])]
        var chain: [PayloadEncoding] = []
        var current = raw
        for _ in 0..<3 {
            let next = percentDecoded(current)
            if next == current { break }
            chain.append(.percent)
            current = next
            result.append(DecodedPayload(text: next, encodings: chain))
        }
        return result
    }

    static func fullyDecoded(_ raw: String) -> String {
        let chain = percentChain(raw)
        return chain[chain.count - 1].text
    }

    /// Decodes every valid `%XX`, leaving malformed ones as written, as servers do.
    static func percentDecoded(_ text: String) -> String {
        let bytes = Array(text.utf8)
        var output: [UInt8] = []
        var index = 0
        while index < bytes.count {
            if bytes[index] == 0x25, index + 2 < bytes.count,
               let high = hexValue(bytes[index + 1]), let low = hexValue(bytes[index + 2]) {
                output.append(high << 4 | low)
                index += 3
            } else {
                output.append(bytes[index])
                index += 1
            }
        }
        return String(bytes: output, encoding: .utf8) ?? String(scalars: output.map { Unicode.Scalar($0) })
    }

    static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case 0x30...0x39: return byte - 0x30
        case 0x41...0x46: return byte - 0x37
        case 0x61...0x66: return byte - 0x57
        default: return nil
        }
    }

    /// Standard or URL-safe Base64, padded or not, accepted only when it decodes to readable text.
    static func base64Decoded(_ text: String) -> String? {
        let alphabet = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=-_".unicodeScalars)
        guard text.unicodeScalars.count >= 8, text.unicodeScalars.allSatisfy(alphabet.contains) else { return nil }
        var standard = text.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
            .replacingOccurrences(of: "=", with: "")
        let remainder = standard.count % 4
        guard remainder != 1 else { return nil }
        if remainder > 0 { standard += String(repeating: "=", count: 4 - remainder) }
        return Data(base64Encoded: standard).flatMap { readable(Array($0)) }
    }

    static func hexDecoded(_ text: String) -> String? {
        let digits = Array(text.utf8)
        guard digits.count >= 8, digits.count % 2 == 0 else { return nil }
        var bytes: [UInt8] = []
        var index = 0
        while index < digits.count {
            guard let high = hexValue(digits[index]), let low = hexValue(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
            index += 2
        }
        return readable(bytes)
    }

    /// UTF-8 text at least nine-tenths of which is printable; anything else is noise that
    /// happened to fit the alphabet.
    static func readable(_ bytes: [UInt8]) -> String? {
        guard let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        let scalars = text.unicodeScalars
        let printable = scalars.filter { !$0.isControl || $0 == "\n" || $0 == "\t" || $0 == "\r" }.count
        return printable * 10 >= scalars.count * 9 ? text : nil
    }
}

/// Letters and digits only, lowercased: the form two spellings of a value share.
enum Skeleton {
    static func of(_ text: String) -> [Unicode.Scalar] {
        Array(text.lowercased().unicodeScalars.filter {
            $0.properties.isAlphabetic || $0.properties.numericType != nil
        })
    }

    /// Shannon entropy in bits per scalar.
    static func entropy(_ text: String) -> Double {
        var counts: [Unicode.Scalar: Int] = [:]
        for scalar in text.unicodeScalars { counts[scalar, default: 0] += 1 }
        let total = Double(text.unicodeScalars.count)
        return counts.values.reduce(0) { sum, count in
            let share = Double(count) / total
            return sum - share * log2(share)
        }
    }
}
