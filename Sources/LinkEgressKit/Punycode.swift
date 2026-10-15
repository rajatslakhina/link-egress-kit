/// RFC 3492 Punycode, encoding only: enough to show the ASCII form of a look-alike host.
enum Punycode {
    static let base = 36
    static let tMin = 1
    static let tMax = 26
    static let skew = 38
    static let damp = 700

    static func asciiHost(_ host: String) -> String {
        host.split(separator: ".", omittingEmptySubsequences: false).map { label in
            label.unicodeScalars.allSatisfy(\.isASCII) ? String(label) : "xn--" + encode(String(label).lowercased())
        }.joined(separator: ".")
    }

    static func encode(_ label: String) -> String {
        let input = label.unicodeScalars.map { Int($0.value) }
        var output = input.filter { $0 < 0x80 }.map(digitScalar(ascii:))
        let basic = output.count
        if basic > 0 { output.append("-") }
        var code = 0x80
        var delta = 0
        var bias = 72
        var handled = basic
        while handled < input.count {
            var next = Int.max
            for value in input where value >= code { next = min(next, value) }
            delta += (next - code) * (handled + 1)
            code = next
            for value in input {
                if value < code { delta += 1 }
                guard value == code else { continue }
                output += digits(for: delta, bias: bias)
                bias = adapt(delta: delta, points: handled + 1, first: handled == basic)
                delta = 0
                handled += 1
            }
            delta += 1
            code += 1
        }
        return String(scalars: output)
    }

    static func digits(for delta: Int, bias: Int) -> [Unicode.Scalar] {
        var result: [Unicode.Scalar] = []
        var remaining = delta
        var step = base
        while true {
            let threshold = step <= bias ? tMin : (step >= bias + tMax ? tMax : step - bias)
            if remaining < threshold { break }
            result.append(digit(threshold + (remaining - threshold) % (base - threshold)))
            remaining = (remaining - threshold) / (base - threshold)
            step += base
        }
        result.append(digit(remaining))
        return result
    }

    static func adapt(delta: Int, points: Int, first: Bool) -> Int {
        var delta = first ? delta / damp : delta / 2
        delta += delta / points
        var step = 0
        while delta > ((base - tMin) * tMax) / 2 {
            delta /= base - tMin
            step += base
        }
        return step + (base - tMin + 1) * delta / (delta + skew)
    }

    static func digit(_ value: Int) -> Unicode.Scalar {
        let code = value < 26 ? 0x61 + value : 0x30 + value - 26
        return Unicode.Scalar(UInt8(code))
    }

    static func digitScalar(ascii value: Int) -> Unicode.Scalar {
        Unicode.Scalar(UInt8(value))
    }
}
