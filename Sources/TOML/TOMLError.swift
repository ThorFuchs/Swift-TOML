// SPDX-License-Identifier: Apache-2.0

/// A TOML failure with a stable code and the 1-based source position where it was detected.
///
/// Messages never contain file paths; callers add their own context.
public struct TOMLError: Error, Sendable, Equatable, CustomStringConvertible {
    /// What went wrong. New cases may be added in minor releases; switch with `default`.
    public enum Code: String, Sendable, Equatable, CaseIterable {
        /// The input is not valid UTF-8.
        case invalidEncoding
        /// A control character appears where TOML does not allow it, such as a bare
        /// carriage return or U+0000 in a comment or string.
        case controlCharacter
        /// The input does not follow the TOML 1.0 grammar.
        case syntax
        /// A basic string contains an unknown escape or a `\u`/`\U` escape that is not a
        /// Unicode scalar value.
        case invalidEscape
        /// An integer or float is malformed: leading zeros, misplaced underscores, a
        /// sign on a `0x`/`0o`/`0b` integer, a missing digit, and so on.
        case invalidNumber
        /// A date or time is malformed or out of range, such as `2021-02-29` or `24:00:00`.
        case invalidDateTime
        /// `inf` or `nan`, which JSON cannot represent.
        case nonFiniteNumber
        /// A number has more digits or a larger exponent than Swift-JSON's balanced limits allow.
        case numberOutOfRange
        /// A key is defined twice, or a key that already holds a value is used as a table.
        case duplicateKey
        /// A table is defined twice, or a table TOML has closed is extended: an inline
        /// table, a table defined by a `[header]` extended with dotted keys, or a table
        /// defined by dotted keys redefined with a `[header]`.
        case tableRedefinition
        /// A frontmatter block opened with `+++` was never closed.
        case unterminatedFrontmatter
        /// The input is larger than `TOMLLimits.maxInputBytes`.
        case inputTooLarge
        /// Nesting is deeper than `TOMLLimits.maxDepth`.
        case depthLimitExceeded
        /// The result has more values than `TOMLLimits.maxNodes`.
        case nodeLimitExceeded
        /// The surrounding task was cancelled.
        case cancelled
    }

    /// The failure category.
    public let code: Code
    /// A short human-readable explanation.
    public let message: String
    /// The 1-based line of the failure.
    public let line: Int
    /// The 1-based column of the failure, counted in Unicode scalars.
    public let column: Int

    /// Creates an error value.
    public init(_ code: Code, _ message: String, line: Int, column: Int) {
        self.code = code
        self.message = message
        self.line = line
        self.column = column
    }

    /// `line:column: message`.
    public var description: String { "\(line):\(column): \(message)" }

    /// The same error moved down by `lines`, used when TOML is embedded in a larger file.
    public func shifted(byLines lines: Int) -> TOMLError {
        TOMLError(code, message, line: line + lines, column: column)
    }
}

extension TOMLError {
    /// An error at a byte offset of `bytes`; line and column are computed from the offset.
    init(_ code: Code, _ message: String, offset: Int, in bytes: [UInt8]) {
        var line = 1
        var lineStart = 0
        let end = min(max(0, offset), bytes.count)
        var index = 0
        while index < end {
            if bytes[index] == 0x0A { line += 1; lineStart = index + 1 }
            index += 1
        }
        var column = 1
        index = lineStart
        while index < end {
            if bytes[index] & 0xC0 != 0x80 { column += 1 }  // count scalars, not continuation bytes
            index += 1
        }
        self.init(code, message, line: line, column: column)
    }
}
