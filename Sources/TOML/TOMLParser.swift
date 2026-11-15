// SPDX-License-Identifier: Apache-2.0
import JSON

/// Parses TOML 1.0 into exact Swift-JSON values.
///
/// - The root is always an object. Tables and inline tables become objects with members
///   in source order; arrays of tables become arrays of objects.
/// - Integers (decimal, `0x`, `0o`, `0b`) and floats become exact `JSONNumber` values;
///   they never pass through `Double`. `inf` and `nan` are errors.
/// - Offset date-times, local date-times, local dates and local times become strings
///   with their exact source text.
/// - Every violation of the TOML 1.0 specification is an error; nothing is recovered.
public struct TOMLParser: Sendable {
    /// The limits applied to every call.
    public var limits: TOMLLimits

    /// Creates a parser with the given limits.
    public init(limits: TOMLLimits = .default) {
        self.limits = limits
    }

    /// Parses a TOML document. An empty document yields an empty object.
    ///
    /// - Throws: `TOMLError`.
    public func parse(_ bytes: [UInt8]) throws(TOMLError) -> JSON {
        guard bytes.count <= limits.maxInputBytes else {
            throw TOMLError(.inputTooLarge, "input is larger than \(limits.maxInputBytes) bytes", line: 1, column: 1)
        }
        if Task.isCancelled { throw TOMLError(.cancelled, "parsing was cancelled", line: 1, column: 1) }
        try validateUTF8(bytes)
        var parser = Parser(bytes, limits: limits)
        return try parser.parseDocument()
    }

    /// Parses UTF-8 text. See `parse(_:)` for bytes.
    public func parse(_ text: String) throws(TOMLError) -> JSON {
        try parse(Array(text.utf8))
    }
}
