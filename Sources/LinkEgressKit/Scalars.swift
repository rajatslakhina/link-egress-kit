extension Unicode.Scalar {
    static let asciiPunctuation = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~".unicodeScalars)

    var isASCIIDigit: Bool { value >= 0x30 && value <= 0x39 }

    var isASCIILetter: Bool { (value >= 0x41 && value <= 0x5A) || (value >= 0x61 && value <= 0x7A) }

    var isASCIIAlphanumeric: Bool { isASCIIDigit || isASCIILetter }

    var isASCIIPunctuation: Bool { Self.asciiPunctuation.contains(self) }

    var isLinkWhitespace: Bool { properties.isWhitespace }

    var isControl: Bool { value < 0x20 || value == 0x7F }

    var isSpaceOrTab: Bool { self == " " || self == "\t" }
}

extension String {
    init<Scalars: Sequence>(scalars: Scalars) where Scalars.Element == Unicode.Scalar {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        self.init(view)
    }
}
