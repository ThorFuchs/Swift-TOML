// SPDX-License-Identifier: Apache-2.0
// TOML 1.0 scalars: strings, booleans, integers, floats, dates and times.
import JSON

private func isDigit(_ c: UInt8) -> Bool { c >= 0x30 && c <= 0x39 }

/// Bytes that can appear in a number, date or time token.
private func isTokenByte(_ c: UInt8) -> Bool {
    isDigit(c) || (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || c == 0x5F || c == 0x2B || c == 0x2D
        || c == 0x2E || c == 0x3A
}

extension Parser {
    /// Parses a string, boolean, number, date or time at `i`.
    mutating func parseScalar() throws(TOMLError) -> JSON {
        guard let c = peek() else { throw error(.syntax, "expected a value, found end of input") }
        switch c {
        case quote:
            if peek(1) == quote && peek(2) == quote { return .string(try parseMultilineBasicString()) }
            return .string(try parseBasicString())
        case apostrophe:
            if peek(1) == apostrophe && peek(2) == apostrophe { return .string(try parseMultilineLiteralString()) }
            return .string(try parseLiteralString())
        case 0x74, 0x66:  // t, f
            return try parseBoolean()
        case 0x2B, 0x2D, 0x30...0x39, 0x69, 0x6E:  // + - digits i n
            return try parseNumberOrDateTime()
        default:
            throw unexpected("expected a value")
        }
    }

    private mutating func parseBoolean() throws(TOMLError) -> JSON {
        let start = i
        while i < b.count && isTokenByte(b[i]) { i += 1 }
        switch b[start..<i].elementsEqual("true".utf8) ? 1 : b[start..<i].elementsEqual("false".utf8) ? 0 : -1 {
        case 1: return .boolean(true)
        case 0: return .boolean(false)
        default:
            throw error(.syntax, "expected a value; booleans are lowercase 'true' and 'false', and strings must be quoted",
                        at: start)
        }
    }

    // MARK: Strings

    /// Rejects control characters other than tab inside a string.
    private func checkStringByte(_ c: UInt8) throws(TOMLError) {
        if (c < 0x20 && c != 0x09) || c == 0x7F {
            if c == 0x0A {
                throw error(.syntax, "a single-line string cannot contain a line break; close it or use a multi-line string")
            }
            throw error(.controlCharacter, "control character U+\(Self.hex(c)) must be escaped in a string")
        }
    }

    /// `"..."`, starting at the opening quote.
    mutating func parseBasicString() throws(TOMLError) -> String {
        i += 1
        var out: [UInt8] = []
        while true {
            guard i < b.count else { throw error(.syntax, "unterminated string") }
            let c = b[i]
            if c == quote { i += 1; return String(decoding: out, as: UTF8.self) }
            if c == backslash {
                try parseEscape(into: &out)
                continue
            }
            try checkStringByte(c)
            out.append(c)
            i += 1
        }
    }

    /// `'...'`, starting at the opening apostrophe.
    mutating func parseLiteralString() throws(TOMLError) -> String {
        i += 1
        let start = i
        while true {
            guard i < b.count else { throw error(.syntax, "unterminated literal string") }
            let c = b[i]
            if c == apostrophe {
                let text = String(decoding: b[start..<i], as: UTF8.self)
                i += 1
                return text
            }
            try checkStringByte(c)
            i += 1
        }
    }

    /// Consumes a line break inside a multi-line string and appends it as LF.
    private mutating func multilineNewline(into out: inout [UInt8]) throws(TOMLError) -> Bool {
        guard try consumeNewline() else { return false }
        out.append(0x0A)
        return true
    }

    /// Handles a run of closing delimiters in a multi-line string. Returns true when the
    /// string ended. One or two delimiter characters right before the closing three
    /// belong to the content.
    private mutating func multilineDelimiter(_ delimiter: UInt8, into out: inout [UInt8]) throws(TOMLError) -> Bool {
        var count = 0
        while i + count < b.count && b[i + count] == delimiter { count += 1 }
        if count < 3 {
            out.append(contentsOf: repeatElement(delimiter, count: count))
            i += count
            return false
        }
        if count > 5 {
            throw error(.syntax, "too many quotes at the end of a multi-line string", at: i + 5)
        }
        out.append(contentsOf: repeatElement(delimiter, count: count - 3))
        i += count
        return true
    }

    /// `"""..."""`, starting at the first quote. Line breaks become LF.
    mutating func parseMultilineBasicString() throws(TOMLError) -> String {
        i += 3
        var out: [UInt8] = []
        _ = try consumeNewline()  // a line break right after the delimiter is trimmed
        while true {
            guard i < b.count else { throw error(.syntax, "unterminated multi-line string") }
            let c = b[i]
            if c == quote {
                if try multilineDelimiter(quote, into: &out) { return String(decoding: out, as: UTF8.self) }
                continue
            }
            if c == backslash {
                // A line-ending backslash trims all whitespace and line breaks that follow.
                var j = i + 1
                while j < b.count && (b[j] == 0x20 || b[j] == 0x09) { j += 1 }
                if j < b.count && (b[j] == 0x0A || b[j] == 0x0D) {
                    i = j
                    while true {
                        skipWhitespace()
                        guard try consumeNewline() else { break }
                        try tick()
                    }
                    continue
                }
                try parseEscape(into: &out)
                continue
            }
            if try multilineNewline(into: &out) { try tick(); continue }
            try checkStringByte(c)
            out.append(c)
            i += 1
        }
    }

    /// `'''...'''`, starting at the first apostrophe. Line breaks become LF.
    mutating func parseMultilineLiteralString() throws(TOMLError) -> String {
        i += 3
        var out: [UInt8] = []
        _ = try consumeNewline()
        while true {
            guard i < b.count else { throw error(.syntax, "unterminated multi-line literal string") }
            let c = b[i]
            if c == apostrophe {
                if try multilineDelimiter(apostrophe, into: &out) { return String(decoding: out, as: UTF8.self) }
                continue
            }
            if try multilineNewline(into: &out) { try tick(); continue }
            try checkStringByte(c)
            out.append(c)
            i += 1
        }
    }

    /// Parses an escape sequence starting at the backslash and appends its UTF-8 bytes.
    private mutating func parseEscape(into out: inout [UInt8]) throws(TOMLError) {
        let start = i
        guard i + 1 < b.count else { throw error(.syntax, "unterminated string") }
        let c = b[i + 1]
        i += 2
        switch c {
        case 0x62: out.append(0x08)  // \b
        case 0x74: out.append(0x09)  // \t
        case 0x6E: out.append(0x0A)  // \n
        case 0x66: out.append(0x0C)  // \f
        case 0x72: out.append(0x0D)  // \r
        case quote: out.append(quote)
        case backslash: out.append(backslash)
        case 0x75, 0x55:  // \u, \U
            let width = c == 0x75 ? 4 : 8
            var value: UInt32 = 0
            for _ in 0..<width {
                guard i < b.count, let digit = Self.hexValue(b[i]) else {
                    throw error(.invalidEscape, "\\\(c == 0x75 ? "u" : "U") needs exactly \(width) hexadecimal digits",
                                at: start)
                }
                value = value << 4 | UInt32(digit)
                i += 1
            }
            guard let scalar = Unicode.Scalar(value) else {
                throw error(.invalidEscape, "escape is not a Unicode scalar value (surrogate or above U+10FFFF)", at: start)
            }
            out.append(contentsOf: String(Character(scalar)).utf8)
        default:
            throw error(.invalidEscape, "invalid escape sequence in a basic string", at: start)
        }
    }

    static func digitValue(_ c: UInt8, radix: Int) -> Int? {
        guard let value = hexValue(c), Int(value) < radix else { return nil }
        return Int(value)
    }

    static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case 0x30...0x39: c - 0x30
        case 0x41...0x46: c - 0x41 + 10
        case 0x61...0x66: c - 0x61 + 10
        default: nil
        }
    }

    // MARK: Numbers, dates and times

    private mutating func parseNumberOrDateTime() throws(TOMLError) -> JSON {
        let start = i
        while i < b.count && isTokenByte(b[i]) { i += 1 }
        // A local date may be followed by a space and a time: `1979-05-27 07:32:00`.
        if i - start == 10 && looksLikeDate(start) && i + 3 < b.count && b[i] == 0x20
            && isDigit(b[i + 1]) && isDigit(b[i + 2]) && b[i + 3] == 0x3A {
            i += 1
            while i < b.count && isTokenByte(b[i]) { i += 1 }
        }
        let token = Array(b[start..<i])
        // A token whose leading digits are followed by '-' is a date; by ':', a time.
        let firstNonDigit = token.firstIndex { !isDigit($0) }
        if let firstNonDigit, firstNonDigit > 0, token[firstNonDigit] == 0x2D {
            try validateDateTime(token, at: start)
            return .string(String(decoding: token, as: UTF8.self))
        }
        if let firstNonDigit, firstNonDigit > 0, token[firstNonDigit] == 0x3A {
            try validateTime(token[...], at: start, mayHaveOffset: false)
            return .string(String(decoding: token, as: UTF8.self))
        }
        return try parseNumber(token, at: start)
    }

    private func looksLikeDate(_ start: Int) -> Bool {
        start + 4 < b.count && isDigit(b[start]) && isDigit(b[start + 1]) && isDigit(b[start + 2])
            && isDigit(b[start + 3]) && b[start + 4] == 0x2D
    }

    private func twoDigits(_ t: ArraySlice<UInt8>, _ at: Int) -> Int? {
        let index = t.startIndex + at
        guard index + 1 < t.endIndex, isDigit(t[index]), isDigit(t[index + 1]) else { return nil }
        return Int(t[index] - 0x30) * 10 + Int(t[index + 1] - 0x30)
    }

    /// Validates `full-date ( [Tt ] partial-time time-offset? )?`.
    private func validateDateTime(_ token: [UInt8], at start: Int) throws(TOMLError) {
        let t = token[...]
        func bad(_ message: String) -> TOMLError { error(.invalidDateTime, message, at: start) }
        guard t.count >= 10, t[0...3].allSatisfy(isDigit), t[4] == 0x2D, t[7] == 0x2D,
              let month = twoDigits(t, 5), let day = twoDigits(t, 8) else {
            throw bad("a date must have the form YYYY-MM-DD")
        }
        let year = Int(t[0] - 0x30) * 1000 + Int(t[1] - 0x30) * 100 + Int(t[2] - 0x30) * 10 + Int(t[3] - 0x30)
        guard (1...12).contains(month) else { throw bad("month \(month) is out of range") }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][month - 1]
        guard (1...days).contains(day) else { throw bad("day \(day) is out of range for the month") }
        if t.count == 10 { return }
        guard t[10] == 0x54 || t[10] == 0x74 || t[10] == 0x20 else {
            throw bad("a date and time must be separated by 'T' or a space")
        }
        try validateTime(t[(t.startIndex + 11)...], at: start, mayHaveOffset: true)
    }

    /// Validates `HH:MM:SS(.fraction)?` and, when allowed, an offset `Z` or `±HH:MM`.
    private func validateTime(_ t: ArraySlice<UInt8>, at start: Int, mayHaveOffset: Bool) throws(TOMLError) {
        func bad(_ message: String) -> TOMLError { error(.invalidDateTime, message, at: start) }
        guard t.count >= 8, let hour = twoDigits(t, 0), t[t.startIndex + 2] == 0x3A,
              let minute = twoDigits(t, 3), t[t.startIndex + 5] == 0x3A, let second = twoDigits(t, 6) else {
            throw bad("a time must have the form HH:MM:SS")
        }
        guard hour <= 23, minute <= 59, second <= 60 else { throw bad("time is out of range") }
        var index = t.startIndex + 8
        if index < t.endIndex && t[index] == 0x2E {
            index += 1
            let digits = index
            while index < t.endIndex && isDigit(t[index]) { index += 1 }
            guard index > digits else { throw bad("fractional seconds need at least one digit") }
        }
        guard index < t.endIndex else { return }
        guard mayHaveOffset else { throw bad("a local time cannot have a time zone offset or other trailing text") }
        let c = t[index]
        if c == 0x5A || c == 0x7A {  // Z z
            guard index + 1 == t.endIndex else { throw bad("unexpected text after the time zone") }
            return
        }
        guard c == 0x2B || c == 0x2D else { throw bad("expected a time zone offset 'Z' or '±HH:MM'") }
        let offset = t[(index + 1)...]
        guard offset.count == 5, let oh = twoDigits(offset, 0), offset[offset.startIndex + 2] == 0x3A,
              let om = twoDigits(offset, 3) else {
            throw bad("a time zone offset must have the form ±HH:MM")
        }
        guard oh <= 23, om <= 59 else { throw bad("time zone offset is out of range") }
    }

    /// Parses an integer or float token into an exact JSON number.
    private func parseNumber(_ t: [UInt8], at start: Int) throws(TOMLError) -> JSON {
        func bad(_ message: String) -> TOMLError { error(.invalidNumber, message, at: start) }
        var index = 0
        var negative = false
        var signed = false
        if index < t.count && (t[index] == 0x2B || t[index] == 0x2D) {
            negative = t[index] == 0x2D
            signed = true
            index += 1
        }
        let body = t[index...]
        if body.elementsEqual("inf".utf8) || body.elementsEqual("nan".utf8) {
            throw error(.nonFiniteNumber, "\(String(decoding: t, as: UTF8.self)) cannot be represented in JSON", at: start)
        }
        guard index < t.count else { throw bad("a sign must be followed by digits") }

        // 0x, 0o, 0b integers.
        if t.count - index >= 2 && t[index] == 0x30 && (t[index + 1] == 0x78 || t[index + 1] == 0x6F || t[index + 1] == 0x62) {
            guard !signed else { throw bad("hexadecimal, octal and binary integers cannot have a sign") }
            let radix = t[index + 1] == 0x78 ? 16 : t[index + 1] == 0x6F ? 8 : 2
            let digits = try digitRun(t, from: index + 2, radix: radix, at: start)
            guard digits.end == t.count else { throw bad("invalid digit in a base-\(radix) integer") }
            guard digits.values.count <= Self.maxRadixDigits else {
                throw error(.numberOutOfRange, "integer has too many digits", at: start)
            }
            return try exactNumber(Self.decimalString(digits.values, radix: radix), at: start)
        }

        let integer = try digitRun(t, from: index, radix: 10, at: start)
        if integer.values.count > 1 && integer.values[0] == 0 {
            throw bad("leading zeros are not allowed")
        }
        var text = negative ? "-" : ""
        text += Self.digitText(integer.values)
        index = integer.end
        if index < t.count && t[index] == 0x2E {
            let fraction = try digitRun(t, from: index + 1, radix: 10, at: start)
            text += "." + Self.digitText(fraction.values)
            index = fraction.end
        }
        if index < t.count && (t[index] == 0x65 || t[index] == 0x45) {
            index += 1
            text += "e"
            if index < t.count && (t[index] == 0x2B || t[index] == 0x2D) {
                if t[index] == 0x2D { text += "-" }
                index += 1
            }
            let exponent = try digitRun(t, from: index, radix: 10, at: start)
            text += Self.digitText(exponent.values)
            index = exponent.end
        }
        guard index == t.count else { throw bad("unexpected character in a number") }
        return try exactNumber(text, at: start)
    }

    /// Reads `digit ( "_"? digit )*` from `from`; at least one digit is required and
    /// every underscore must sit between two digits.
    private func digitRun(_ t: [UInt8], from: Int, radix: Int, at start: Int) throws(TOMLError) -> (values: [Int], end: Int) {
        var values: [Int] = []
        var index = from
        var lastWasDigit = false
        while index < t.count {
            let c = t[index]
            if c == 0x5F {
                guard lastWasDigit else { throw error(.invalidNumber, "an underscore must be between two digits", at: start) }
                lastWasDigit = false
                index += 1
                continue
            }
            guard let value = Self.digitValue(c, radix: radix) else {
                if radix < 10 && isDigit(c) {
                    throw error(.invalidNumber, "digit is not valid in a base-\(radix) integer", at: start)
                }
                break
            }
            values.append(value)
            lastWasDigit = true
            index += 1
        }
        guard !values.isEmpty else { throw error(.invalidNumber, "expected a digit", at: start) }
        guard lastWasDigit else { throw error(.invalidNumber, "an underscore must be between two digits", at: start) }
        return (values, index)
    }

    private static func digitText(_ values: [Int]) -> String {
        String(decoding: values.map { UInt8(0x30 + $0) }, as: UTF8.self)
    }

    private func exactNumber(_ text: String, at start: Int) throws(TOMLError) -> JSON {
        do {
            return .number(try JSONNumber(parsing: text, limits: .balanced))
        } catch {
            throw self.error(.numberOutOfRange, "number exceeds Swift-JSON's exact-number limits", at: start)
        }
    }

    /// Maximum source digits for hexadecimal, octal and binary conversion (keeps it cheap).
    static let maxRadixDigits = 3000

    private static func decimalString(_ values: [Int], radix: Int) -> String {
        var decimal: [Int] = [0]  // little-endian base-10 digits
        for value in values {
            var carry = value
            for k in decimal.indices {
                let product = decimal[k] * radix + carry
                decimal[k] = product % 10
                carry = product / 10
            }
            while carry > 0 { decimal.append(carry % 10); carry /= 10 }
        }
        while decimal.count > 1 && decimal.last == 0 { decimal.removeLast() }
        return digitText(decimal.reversed())
    }
}
