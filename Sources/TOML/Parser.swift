// SPDX-License-Identifier: Apache-2.0
// TOML 1.0 document structure: expressions, keys, headers, arrays and inline tables.
import JSON

private let space: UInt8 = 0x20
private let tab: UInt8 = 0x09
private let lf: UInt8 = 0x0A
private let cr: UInt8 = 0x0D
private let hash: UInt8 = 0x23
private let equals: UInt8 = 0x3D
private let dot: UInt8 = 0x2E
private let comma: UInt8 = 0x2C
private let openBracket: UInt8 = 0x5B
private let closeBracket: UInt8 = 0x5D
private let openBrace: UInt8 = 0x7B
private let closeBrace: UInt8 = 0x7D
let quote: UInt8 = 0x22
let apostrophe: UInt8 = 0x27
let backslash: UInt8 = 0x5C

/// Checks that `bytes` is valid UTF-8 (no overlongs, surrogates or values above U+10FFFF).
func validateUTF8(_ bytes: [UInt8]) throws(TOMLError) {
    var decoder = UTF8()
    var iterator = bytes.makeIterator()
    var consumed = 0
    while true {
        switch decoder.decode(&iterator) {
        case .scalarValue(let scalar):
            consumed += UTF8.width(scalar)
        case .emptyInput:
            return
        case .error:
            throw TOMLError(.invalidEncoding, "input is not valid UTF-8", offset: consumed, in: bytes)
        }
    }
}

struct Parser {
    let b: [UInt8]
    var i = 0
    var tree: Tree
    /// The table that key/value pairs go into: the root, or the table of the last header.
    private var current = Tree.root
    /// Identifies the current header section (or inline table) for dotted-key rules.
    private var section = 0
    private var nextSection = 1
    private var work = 0

    init(_ bytes: [UInt8], limits: TOMLLimits) {
        b = bytes
        tree = Tree(limits: limits)
    }

    // MARK: Errors and helpers

    func error(_ code: TOMLError.Code, _ message: String, at offset: Int? = nil) -> TOMLError {
        TOMLError(code, message, offset: offset ?? i, in: b)
    }

    var atEnd: Bool { i >= b.count }

    func peek(_ ahead: Int = 0) -> UInt8? {
        i + ahead < b.count ? b[i + ahead] : nil
    }

    /// Checks for cancellation every 1,024 units of work (lines and values).
    mutating func tick() throws(TOMLError) {
        work += 1
        if work & 1023 == 0 && Task.isCancelled {
            throw error(.cancelled, "parsing was cancelled")
        }
    }

    static func describe(_ byte: UInt8?) -> String {
        guard let byte else { return "end of input" }
        switch byte {
        case lf: return "a line break"
        case cr: return "a carriage return"
        case tab: return "a tab"
        case 0x20...0x7E: return "'\(Character(Unicode.Scalar(byte)))'"
        case 0x00...0x1F, 0x7F: return "control character U+\(hex(byte))"
        default: return "a non-ASCII character"
        }
    }

    /// A syntax error for the byte at `i`; a stray control character gets its own code.
    func unexpected(_ expectation: String) -> TOMLError {
        let found = peek()
        if let found, found < 0x20 && found != tab && found != lf && found != cr || found == 0x7F {
            return error(.controlCharacter, "\(expectation), found \(Self.describe(found))")
        }
        return error(.syntax, "\(expectation), found \(Self.describe(found))")
    }

    mutating func skipWhitespace() {
        while i < b.count && (b[i] == space || b[i] == tab) { i += 1 }
    }

    /// Consumes a line break (LF or CRLF) if one is next. A bare CR is an error.
    mutating func consumeNewline() throws(TOMLError) -> Bool {
        guard i < b.count else { return false }
        if b[i] == lf { i += 1; return true }
        if b[i] == cr {
            guard i + 1 < b.count && b[i + 1] == lf else {
                throw error(.controlCharacter, "a carriage return must be followed by a line feed")
            }
            i += 2
            return true
        }
        return false
    }

    /// Consumes a comment that starts at `#`, up to (not including) the line break.
    mutating func skipComment() throws(TOMLError) {
        guard i < b.count && b[i] == hash else { return }
        i += 1
        while i < b.count {
            let c = b[i]
            if c == lf { return }
            if c == cr {
                if i + 1 < b.count && b[i + 1] == lf { return }
                throw error(.controlCharacter, "a carriage return in a comment must be followed by a line feed")
            }
            if (c < 0x20 && c != tab) || c == 0x7F {
                throw error(.controlCharacter, "control character U+\(Self.hex(c)) is not allowed in a comment")
            }
            i += 1
        }
    }

    static func hex(_ byte: UInt8) -> String {
        let text = String(byte, radix: 16, uppercase: true)
        return String(repeating: "0", count: 4 - text.count) + text
    }

    /// After an expression: optional whitespace and comment, then a line break or the end.
    mutating func expectEndOfLine() throws(TOMLError) {
        skipWhitespace()
        try skipComment()
        if atEnd { return }
        guard try consumeNewline() else {
            throw unexpected("expected the end of the line")
        }
    }

    // MARK: Document

    mutating func parseDocument() throws(TOMLError) -> JSON {
        if b.starts(with: [0xEF, 0xBB, 0xBF]) { i = 3 }
        while true {
            try tick()
            skipWhitespace()
            guard let c = peek() else { break }
            if c == hash {
                try skipComment()
                try expectEndOfLine()
            } else if c == lf || c == cr {
                _ = try consumeNewline()
            } else if c == openBracket {
                try parseHeader()
                try expectEndOfLine()
            } else {
                try parseKeyValue(into: current, section: section, frozen: false)
                try expectEndOfLine()
            }
        }
        return try tree.json()
    }

    // MARK: Keys

    struct KeyPart {
        let key: JSONKey
        let offset: Int
    }

    static func isBareKeyByte(_ c: UInt8) -> Bool {
        (c >= 0x41 && c <= 0x5A) || (c >= 0x61 && c <= 0x7A) || (c >= 0x30 && c <= 0x39) || c == 0x5F || c == 0x2D
    }

    /// Parses `simple-key ( ws "." ws simple-key )*`, starting at the first key.
    mutating func parseKey() throws(TOMLError) -> [KeyPart] {
        var parts: [KeyPart] = []
        while true {
            skipWhitespace()
            let start = i
            guard let c = peek() else { throw error(.syntax, "expected a key, found end of input") }
            let text: String
            if c == quote || c == apostrophe {
                if peek(1) == c && peek(2) == c {
                    throw error(.syntax, "a key cannot be a multi-line string")
                }
                text = c == quote ? try parseBasicString() : try parseLiteralString()
            } else if Self.isBareKeyByte(c) {
                while i < b.count && Self.isBareKeyByte(b[i]) { i += 1 }
                text = String(decoding: b[start..<i], as: UTF8.self)
            } else {
                throw unexpected("expected a key")
            }
            parts.append(KeyPart(key: JSONKey(text), offset: start))
            skipWhitespace()
            guard peek() == dot else { return parts }
            i += 1
        }
    }

    static func display(_ parts: some Collection<KeyPart>) -> String {
        parts.map { $0.key.string }.joined(separator: ".")
    }

    // MARK: Headers

    mutating func parseHeader() throws(TOMLError) {
        let start = i
        i += 1
        let isArray = peek() == openBracket
        if isArray { i += 1 }
        let parts = try parseKey()
        guard peek() == closeBracket else {
            throw unexpected("expected ']' to close the table header")
        }
        i += 1
        if isArray {
            guard peek() == closeBracket else {
                throw unexpected("expected ']]' to close the array-of-tables header")
            }
            i += 1
        }

        section = nextSection
        nextSection += 1

        // Walk the intermediate keys, creating implicit tables as needed.
        var table = Tree.root
        for part in parts.dropLast() {
            table = try descendForHeader(from: table, part, parts: parts)
        }
        guard let last = parts.last else { throw error(.syntax, "expected a key", at: start) }
        if isArray {
            current = try appendTableArrayElement(in: table, last)
        } else {
            current = try defineTable(in: table, last, parts: parts)
        }
    }

    /// Steps into `part` of `table` while walking a header path.
    private mutating func descendForHeader(from table: Int, _ part: KeyPart, parts: [KeyPart]) throws(TOMLError) -> Int {
        guard let child = tree[table].lookup[part.key] else {
            let node = Node(kind: .table, origin: .implicit, depth: tree[table].depth + 1)
            let index = try tree.add(node, at: part.offset, in: b)
            tree.attach(index, as: part.key, to: table)
            return index
        }
        let node = tree[child]
        switch node.kind {
        case .table:
            if node.frozen || node.origin == .inline {
                throw error(.tableRedefinition, "cannot extend inline table \"\(part.key.string)\"", at: part.offset)
            }
            return child
        case .tableArray:
            guard let last = node.items.last else {
                throw error(.syntax, "internal state error: empty array of tables", at: part.offset)
            }
            return last
        case .array, .scalar:
            throw error(.duplicateKey, "key \"\(part.key.string)\" already holds a value and cannot be used as a table",
                        at: part.offset)
        }
    }

    /// Handles the last key of a `[header]`.
    private mutating func defineTable(in table: Int, _ part: KeyPart, parts: [KeyPart]) throws(TOMLError) -> Int {
        let name = Self.display(parts)
        guard let child = tree[table].lookup[part.key] else {
            let node = Node(kind: .table, origin: .header, depth: tree[table].depth + 1)
            let index = try tree.add(node, at: part.offset, in: b)
            tree.attach(index, as: part.key, to: table)
            return index
        }
        let node = tree[child]
        switch node.kind {
        case .table:
            switch node.origin {
            case .implicit:
                tree[child].origin = .header
                return child
            case .header:
                throw error(.tableRedefinition, "table [\(name)] is defined more than once", at: part.offset)
            case .dotted:
                throw error(.tableRedefinition, "table [\(name)] was already defined with dotted keys", at: part.offset)
            case .inline:
                throw error(.tableRedefinition, "table [\(name)] was already defined as an inline table", at: part.offset)
            }
        case .tableArray:
            throw error(.tableRedefinition, "[\(name)] is already an array of tables", at: part.offset)
        case .array, .scalar:
            throw error(.duplicateKey, "key \"\(part.key.string)\" already holds a value and cannot be used as a table",
                        at: part.offset)
        }
    }

    /// Handles the last key of a `[[header]]`.
    private mutating func appendTableArrayElement(in table: Int, _ part: KeyPart) throws(TOMLError) -> Int {
        let array: Int
        if let child = tree[table].lookup[part.key] {
            switch tree[child].kind {
            case .tableArray:
                array = child
            case .table:
                throw error(.tableRedefinition, "\"\(part.key.string)\" is already a table, not an array of tables",
                            at: part.offset)
            case .array, .scalar:
                throw error(.duplicateKey, "key \"\(part.key.string)\" already holds a value and cannot be an array of tables",
                            at: part.offset)
            }
        } else {
            let node = Node(kind: .tableArray, depth: tree[table].depth + 1)
            array = try tree.add(node, at: part.offset, in: b)
            tree.attach(array, as: part.key, to: table)
        }
        let element = Node(kind: .table, origin: .header, depth: tree[array].depth + 1)
        let index = try tree.add(element, at: part.offset, in: b)
        tree[array].items.append(index)
        return index
    }

    // MARK: Key/value pairs

    /// Parses `key = value` and stores it in `table`. `section` scopes dotted-key tables;
    /// `frozen` marks tables created inside an inline table.
    mutating func parseKeyValue(into table: Int, section: Int, frozen: Bool) throws(TOMLError) {
        let parts = try parseKey()
        let (target, last) = try resolveDottedTarget(parts, in: table, section: section, frozen: frozen)
        guard peek() == equals else {
            throw unexpected("expected '=' after key \"\(Self.display(parts))\"")
        }
        i += 1
        skipWhitespace()
        let value = try parseValue(depth: tree[target].depth + 1)
        tree.attach(value, as: last.key, to: target)
    }

    /// Creates or walks the dotted-key tables of `parts` and checks that the last key is new.
    /// Returns the table that receives the value and the last key.
    private mutating func resolveDottedTarget(
        _ parts: [KeyPart], in table: Int, section: Int, frozen: Bool
    ) throws(TOMLError) -> (Int, KeyPart) {
        var target = table
        for part in parts.dropLast() {
            if let child = tree[target].lookup[part.key] {
                let node = tree[child]
                switch node.kind {
                case .table:
                    guard node.origin == .dotted && node.section == section else {
                        throw error(.tableRedefinition,
                                    "cannot add keys to table \"\(part.key.string)\" with dotted keys here; it was defined elsewhere",
                                    at: part.offset)
                    }
                    target = child
                case .tableArray, .array, .scalar:
                    throw error(.duplicateKey, "key \"\(part.key.string)\" already holds a value and cannot be used as a table",
                                at: part.offset)
                }
            } else {
                var node = Node(kind: .table, origin: .dotted, depth: tree[target].depth + 1)
                node.section = section
                node.frozen = frozen
                let index = try tree.add(node, at: part.offset, in: b)
                tree.attach(index, as: part.key, to: target)
                target = index
            }
        }
        guard let last = parts.last else { throw error(.syntax, "expected a key") }
        if tree[target].lookup[last.key] != nil {
            throw error(.duplicateKey, "key \"\(Self.display(parts))\" is defined more than once", at: last.offset)
        }
        return (target, last)
    }

    // MARK: Values

    /// An array or inline table whose elements are being parsed.
    private struct Frame {
        let node: Int
        let isArray: Bool
        /// For inline tables: the section that scopes its dotted keys.
        let section: Int
        /// For inline tables: the table and key that receive the next value.
        var pendingTarget = 0
        var pendingKey: JSONKey = ""
    }

    /// Skips whitespace, line breaks and comments inside an array.
    private mutating func skipArrayWhitespace() throws(TOMLError) {
        while true {
            skipWhitespace()
            if peek() == hash { try skipComment() }
            guard try consumeNewline() else { return }
            try tick()
        }
    }

    /// Parses a value at `i` whose node will sit at `depth`, using an explicit stack for
    /// nested arrays and inline tables. Returns the node index.
    mutating func parseValue(depth: Int) throws(TOMLError) -> Int {
        var stack: [Frame] = []
        parsing: while true {
            try tick()
            let valueDepth = depth + stack.count
            var produced: Int
            switch peek() {
            case openBracket:
                let index = try tree.add(Node(kind: .array, depth: valueDepth), at: i, in: b)
                i += 1
                try skipArrayWhitespace()
                if peek() == closeBracket {
                    i += 1
                    produced = index
                } else {
                    stack.append(Frame(node: index, isArray: true, section: 0))
                    continue parsing
                }
            case openBrace:
                var node = Node(kind: .table, origin: .inline, depth: valueDepth)
                node.frozen = true
                let index = try tree.add(node, at: i, in: b)
                i += 1
                skipWhitespace()
                if peek() == closeBrace {
                    i += 1
                    produced = index
                } else {
                    var frame = Frame(node: index, isArray: false, section: nextSection)
                    nextSection += 1
                    try beginInlineMember(&frame)
                    stack.append(frame)
                    continue parsing
                }
            default:
                let start = i
                let scalar = try parseScalar()
                produced = try tree.add(Node(kind: .scalar, scalar: scalar, depth: valueDepth), at: start, in: b)
            }

            // Attach the finished value to its container, closing containers as they end.
            while var frame = stack.popLast() {
                if frame.isArray {
                    tree[frame.node].items.append(produced)
                    try skipArrayWhitespace()
                    if peek() == comma {
                        i += 1
                        try skipArrayWhitespace()
                        if peek() == closeBracket {
                            i += 1
                            produced = frame.node
                            continue
                        }
                        stack.append(frame)
                        continue parsing
                    }
                    if peek() == closeBracket {
                        i += 1
                        produced = frame.node
                        continue
                    }
                    throw unexpected("expected ',' or ']' in array")
                } else {
                    tree.attach(produced, as: frame.pendingKey, to: frame.pendingTarget)
                    skipWhitespace()
                    if peek() == comma {
                        i += 1
                        try beginInlineMember(&frame)
                        stack.append(frame)
                        continue parsing
                    }
                    if peek() == closeBrace {
                        i += 1
                        produced = frame.node
                        continue
                    }
                    throw unexpected("expected ',' or '}' in inline table")
                }
            }
            return produced
        }
    }

    /// Parses `key =` inside an inline table and records where the value goes.
    private mutating func beginInlineMember(_ frame: inout Frame) throws(TOMLError) {
        skipWhitespace()
        if peek() == closeBrace {
            throw error(.syntax, "an inline table cannot end with a trailing comma")
        }
        let parts = try parseKey()
        let (target, last) = try resolveDottedTarget(parts, in: frame.node, section: frame.section, frozen: true)
        guard peek() == equals else {
            throw unexpected("expected '=' after key \"\(Self.display(parts))\"")
        }
        i += 1
        skipWhitespace()
        frame.pendingTarget = target
        frame.pendingKey = last.key
    }
}
