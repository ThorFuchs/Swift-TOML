// SPDX-License-Identifier: Apache-2.0
import JSON
import Testing
import TOML

func toml(_ text: String, limits: TOMLLimits = .default) throws -> JSON {
    try TOMLParser(limits: limits).parse(text)
}

func json(_ text: String) throws -> JSON {
    try JSON.parse(text)
}

func tomlError(_ text: String, limits: TOMLLimits = .default) -> TOMLError? {
    do {
        _ = try TOMLParser(limits: limits).parse(text)
        return nil
    } catch {
        return error
    }
}

func keys(_ value: JSON?) -> [String] {
    value?.objectValue?.members.map(\.key.string) ?? []
}

struct IntegerTests {
    @Test("decimal, hexadecimal, octal and binary integers with underscores become exact numbers")
    func forms() throws {
        #expect(try toml("a = [0, +0, -0, 42, +17, -7, 1_000, 5_349_221, 0xDEAD_beef, 0o755, 0b1101_0110, 0x00ff]") ==
                json(#"{"a":[0,0,0,42,17,-7,1000,5349221,3735928559,493,214,255]}"#))
    }

    @Test("64-bit extremes and larger integers stay exact and never pass through Double")
    func exact() throws {
        let value = try toml("max = 9223372036854775807\nmin = -9223372036854775808\nbig = 9007199254740993\nhuge = 0xFFFF_FFFF_FFFF_FFFF_FFFF")
        let object = try #require(value.objectValue)
        #expect(object["max"] == (try JSON.number(parsing: "9223372036854775807")))
        #expect(object["min"] == (try JSON.number(parsing: "-9223372036854775808")))
        #expect(object["big"] == (try JSON.number(parsing: "9007199254740993")))
        #expect(object["big"] != (try JSON.number(parsing: "9007199254740992")))
        #expect(object["huge"] == (try JSON.number(parsing: "1208925819614629174706175")))
    }

    @Test("leading zeros, signed prefixes, uppercase prefixes and misplaced underscores are invalidNumber")
    func malformed() {
        for text in ["a = 01", "a = -01", "a = +0x1", "a = -0b1", "a = 0X1F", "a = 0B1", "a = 0O7", "a = 1__0",
                     "a = 1_", "a = 0x_1", "a = 0x", "a = 0b102", "a = 0o8", "a = +", "a = 0xg"] {
            #expect(tomlError(text)?.code == .invalidNumber, "\(text)")
        }
        #expect(tomlError("a = _1")?.code == .syntax)
        #expect(tomlError("a = 1x")?.code == .invalidNumber)
    }
}

struct FloatTests {
    @Test("floats keep their exact decimal value; underscores and a leading '+' are dropped from the lexeme")
    func exact() throws {
        let value = try toml("a = [0.1, +1.5, -0.25, 1_000.5, 6.626e-34, 5e+22, 1E6, 3.141_592_653_589_793_238_462, -0.0, 1e06]")
        #expect(value.objectValue?["a"] ==
                (try json("[0.1,1.5,-0.25,1000.5,6.626e-34,5e22,1e6,3.141592653589793238462,-0.0,1e6]")))
        let items = try #require(value.objectValue?["a"]?.arrayValue)
        #expect(items[0].numberValue?.originalLexeme == "0.1")
        #expect(items[1].numberValue?.originalLexeme == "1.5")
        #expect(items[3].numberValue?.originalLexeme == "1000.5")
        #expect(items[7].numberValue?.originalLexeme == "3.141592653589793238462")
    }

    @Test("inf and nan in any sign are nonFiniteNumber")
    func nonFinite() {
        for text in ["a = inf", "a = +inf", "a = -inf", "a = nan", "a = +nan", "a = -nan", "a = [1.0, inf]"] {
            #expect(tomlError(text)?.code == .nonFiniteNumber, "\(text)")
        }
    }

    @Test("malformed floats are invalidNumber")
    func malformed() {
        for text in ["a = 1.", "a = 1.e5", "a = 1e", "a = 1e+", "a = 1._5", "a = 1_.5", "a = 1.5_", "a = 01.5",
                     "a = 1.2.3", "a = 1e5.0", "a = 1ee5", "a = infinity", "a = Inf"] {
            #expect(tomlError(text)?.code == .invalidNumber || tomlError(text)?.code == .syntax, "\(text)")
        }
        #expect(tomlError("a = .5")?.code == .syntax)
    }

    @Test("numbers beyond Swift-JSON's exact limits are numberOutOfRange")
    func outOfRange() {
        #expect(tomlError("a = 1e9999999999")?.code == .numberOutOfRange)
        #expect(tomlError("a = 0x" + String(repeating: "F", count: 3001))?.code == .numberOutOfRange)
    }
}

struct BooleanAndStringTests {
    @Test("only lowercase true and false are booleans")
    func booleans() throws {
        #expect(try toml("t = true\nf = false") == json(#"{"t":true,"f":false}"#))
        for text in ["a = True", "a = FALSE", "a = yes", "a = tru", "a = truee"] {
            #expect(tomlError(text)?.code == .syntax, "\(text)")
        }
    }

    @Test("basic strings decode every TOML 1.0 escape")
    func escapes() throws {
        #expect(try toml(#"a = "\b\t\n\f\r\"\\ \u00E9 \U0001F600""#) == .object(try JSONObject(members: [
            JSONMember("a", value: .string("\u{8}\t\n\u{C}\r\"\\ é 😀")),
        ])))
    }

    @Test("unknown escapes and non-scalar code points are invalidEscape")
    func badEscapes() {
        for text in [#"a = "\x41""#, #"a = "\e""#, #"a = "\ ""#, #"a = "\u12""#, #"a = "\uD800""#,
                     #"a = "\U00110000""#, #"a = """\q""""#] {
            #expect(tomlError(text)?.code == .invalidEscape, "\(text)")
        }
    }

    @Test("literal strings take their content verbatim")
    func literal() throws {
        #expect(try toml(#"a = 'C:\Users\nodejs\templates'"#) == json(#"{"a":"C:\\Users\\nodejs\\templates"}"#))
    }

    @Test("multi-line strings trim the first line break, honor line-ending backslashes and allow quotes before the delimiter")
    func multiline() throws {
        let text = "a = \"\"\"\nRoses\nViolets\"\"\"\nb = \"\"\"\\\n   The quick \\\n\n   fox.\"\"\"\nc = \"\"\"\"\"Hi\"\"\"\"\"\nd = '''\nraw \\n '' text'''\ne = ''''x'''''"
        #expect(try toml(text) == json(#"{"a":"Roses\nViolets","b":"The quick fox.","c":"\"\"Hi\"\"","d":"raw \\n '' text","e":"'x''"}"#))
    }

    @Test("CRLF line breaks inside multi-line strings become LF")
    func crlfNormalized() throws {
        #expect(try toml("a = \"\"\"\r\none\r\ntwo\"\"\"\r\nb = '''x\r\ny'''\r\n") == json(#"{"a":"one\ntwo","b":"x\ny"}"#))
    }

    @Test("control characters must be escaped; line breaks end single-line strings")
    func controls() throws {
        #expect(tomlError("a = \"x\u{1}\"")?.code == .controlCharacter)
        #expect(tomlError("a = 'x\u{7F}'")?.code == .controlCharacter)
        #expect(tomlError("a = \"\"\"x\u{0}\"\"\"")?.code == .controlCharacter)
        #expect(tomlError("a = \"x\ny\"")?.code == .syntax)
        #expect(tomlError("a = \"x\ry\"")?.code == .controlCharacter)
        #expect(tomlError("a = \"\"\"\"\"\"\"\"\"")?.code == .syntax)
        #expect(try toml("a = \"\"\"\"\"\"\"") == json(#"{"a":"\""}"#))
        #expect(try toml("a = \"tab\there\"") == json(#"{"a":"tab\there"}"#))
    }
}

struct DateTimeTests {
    @Test("dates and times become strings with their exact source text")
    func exactText() throws {
        let text = """
        odt1 = 1979-05-27T07:32:00Z
        odt2 = 1979-05-27 00:32:00.999999-07:00
        odt3 = 1979-05-27t07:32:00z
        ldt = 1979-05-27T07:32:00.5
        ld = 1979-05-27
        lt = 07:32:00.123
        leap = 2000-02-29
        second60 = 1990-12-31T23:59:60Z
        """
        #expect(try toml(text) == json(#"""
        {"odt1":"1979-05-27T07:32:00Z","odt2":"1979-05-27 00:32:00.999999-07:00","odt3":"1979-05-27t07:32:00z",
         "ldt":"1979-05-27T07:32:00.5","ld":"1979-05-27","lt":"07:32:00.123","leap":"2000-02-29",
         "second60":"1990-12-31T23:59:60Z"}
        """#))
    }

    @Test("a date followed by a space and a comment stays a date")
    func dateThenComment() throws {
        #expect(try toml("d = 1979-05-27 # birthday") == json(#"{"d":"1979-05-27"}"#))
        #expect(try toml("d = [1979-05-27 , 07:00:00]") == json(#"{"d":["1979-05-27","07:00:00"]}"#))
    }

    @Test("out-of-range and malformed dates and times are invalidDateTime")
    func invalid() {
        for text in ["a = 2021-02-29", "a = 1900-02-29", "a = 2021-13-01", "a = 2021-04-31", "a = 2021-00-10",
                     "a = 24:00:00", "a = 12:60:00", "a = 12:00:61", "a = 07:32", "a = 1979-05-27T07:32",
                     "a = 1979-05-27T07:32:00+24:00", "a = 1979-05-27T07:32:00+05", "a = 1979-05-27X07:32:00",
                     "a = 07:32:00Z", "a = 07:32:00.", "a = 10000-01-01", "a = 979-05-27", "a = 1:32:00"] {
            #expect(tomlError(text)?.code == .invalidDateTime, "\(text)")
        }
    }
}

struct TableTests {
    @Test("members keep source order across key/values, headers and dotted keys")
    func sourceOrder() throws {
        let value = try toml("""
        zeta = 1
        alpha = 2
        mid.y = 3
        mid.b = 4
        [later]
        z = 1
        a = 2
        [early]
        """)
        #expect(keys(value) == ["zeta", "alpha", "mid", "later", "early"])
        #expect(keys(value.objectValue?["mid"]) == ["y", "b"])
        #expect(keys(value.objectValue?["later"]) == ["z", "a"])
        let inline = try toml("t = { z = 1, a = 2, m = 3 }")
        #expect(keys(inline.objectValue?["t"]) == ["z", "a", "m"])
    }

    @Test("an empty document is an empty object")
    func empty() throws {
        #expect(try toml("") == json("{}"))
        #expect(try toml("# only a comment\n\n") == json("{}"))
    }

    @Test("dotted and quoted keys build nested tables; whitespace around dots is allowed")
    func dottedKeys() throws {
        let value = try toml(#"""
        site . "google.com" = true
        a.b.c = 1
        a.b.d = 2
        "" = "empty"
        'quoted key' = 3
        3.14 = "pi"
        """#)
        #expect(value == (try json(#"""
        {"site":{"google.com":true},"a":{"b":{"c":1,"d":2}},"":"empty","quoted key":3,"3":{"14":"pi"}}
        """#)))
    }

    @Test("headers create implicit super-tables, which a later header may define once")
    func implicitTables() throws {
        let value = try toml("[a.b.c]\nx = 1\n[a]\ny = 2\n[a.b.e]\n")
        #expect(value == (try json(#"{"a":{"b":{"c":{"x":1},"e":{}},"y":2}}"#)))
        #expect(tomlError("[a.b]\n[a]\n[a]")?.code == .tableRedefinition)
    }

    @Test("arrays of tables become arrays of objects, with sub-tables attached to the last element")
    func arraysOfTables() throws {
        let value = try toml("""
        [[fruit]]
        name = "apple"
        [fruit.physical]
        color = "red"
        [[fruit.variety]]
        name = "red delicious"
        [[fruit.variety]]
        name = "granny smith"
        [[fruit]]
        name = "banana"
        [[fruit.variety]]
        name = "plantain"
        """)
        #expect(value == (try json(#"""
        {"fruit":[{"name":"apple","physical":{"color":"red"},"variety":[{"name":"red delicious"},{"name":"granny smith"}]},
                  {"name":"banana","variety":[{"name":"plantain"}]}]}
        """#)))
    }

    @Test("inline tables and arrays nest, arrays may mix types and span lines with comments")
    func inlineValues() throws {
        let value = try toml("""
        point = { x = 1, y = { z = [1, "two", 3.0, { w = true }] }, a.b = 1 }
        list = [
          1, # one
          [2, 3],
          {},
        ]
        empty = []
        """)
        #expect(value == (try json(#"""
        {"point":{"x":1,"y":{"z":[1,"two",3.0,{"w":true}]},"a":{"b":1}},"list":[1,[2,3],{}],"empty":[]}
        """#)))
    }

    @Test("inline tables reject line breaks and trailing commas")
    func inlineSyntax() {
        #expect(tomlError("a = { x = 1,\n y = 2 }")?.code == .syntax)
        #expect(tomlError("a = { x = 1, }")?.code == .syntax)
        #expect(tomlError("a = [1 2]")?.code == .syntax)
        #expect(tomlError("a = [,]")?.code == .syntax)
    }

    @Test("defining a key twice is duplicateKey, including quoted spellings of the same key")
    func duplicateKeys() {
        #expect(tomlError("a = 1\na = 2")?.code == .duplicateKey)
        #expect(tomlError("a = 1\n\"a\" = 2")?.code == .duplicateKey)
        #expect(tomlError("a = 1\n'a' = 2")?.code == .duplicateKey)
        #expect(tomlError("a.b = 1\na.b = 2")?.code == .duplicateKey)
        #expect(tomlError("a = { b = 1, b = 2 }")?.code == .duplicateKey)
        #expect(tomlError("a = 1\n[a]")?.code == .duplicateKey)
        #expect(tomlError("a = 1\na.b = 2")?.code == .duplicateKey)
        #expect(tomlError("a = []\n[[a]]")?.code == .duplicateKey)
        #expect(tomlError("a = [{}]\n[a.b]")?.code == .duplicateKey)
    }

    @Test("duplicate key errors point at the second definition")
    func duplicatePosition() throws {
        let error = try #require(tomlError("x = 1\n\n  x = 2"))
        #expect(error.code == .duplicateKey)
        #expect(error.line == 3)
        #expect(error.column == 3)
    }

    @Test("keys are compared by exact Unicode scalars, not canonical equivalence")
    func exactKeys() throws {
        let value = try toml("\"\u{E9}\" = 1\n\"e\u{301}\" = 2")
        #expect(value.objectValue?.count == 2)
    }

    @Test("TOML's table redefinition rules are enforced as tableRedefinition")
    func redefinitions() {
        let cases = [
            "[a]\n[a]",                              // header twice
            "[a]\nb.c = 1\n[a.b]",                   // header over a dotted-key table
            "a.b = 1\n[a]",                          // header over a dotted-key table at the root
            "[a.b.c]\n[a]\nb.c.d = 1",               // dotted keys into a header-created table
            "[a.b]\n[a]\nb.x = 1",                   // dotted keys into an implicit table from another header
            "a = {}\n[a]",                           // header over an inline table
            "a = { b = 1 }\na.c = 2",                // dotted keys into an inline table
            "a = { b = { c = 1 } }\n[a.b.d]",        // header into a nested inline table
            "a = { b.c = 1 }\n[a.b]",                // header over a table inside an inline table
            "[a]\n[[a]]",                            // array of tables over a table
            "[[a]]\n[a]",                            // table over an array of tables
        ]
        for text in cases {
            #expect(tomlError(text)?.code == .tableRedefinition, "\(text)")
        }
    }

    @Test("headers may add sub-tables to tables defined by dotted keys")
    func headerUnderDotted() throws {
        let value = try toml("[fruit]\napple.color = \"red\"\napple.taste.sweet = true\n[fruit.apple.texture]\nsmooth = true")
        #expect(value == (try json(#"{"fruit":{"apple":{"color":"red","taste":{"sweet":true},"texture":{"smooth":true}}}}"#)))
    }

    @Test("missing key, false, empty string and wrong kind stay distinct")
    func missingVersusWrongKind() throws {
        let object = try #require(try toml("flag = false\ntext = \"1\"\nnumber = 1\nempty = \"\"").objectValue)
        #expect(object["absent"] == nil)
        #expect(object["flag"] == .boolean(false))
        #expect(object["text"] == .string("1"))
        #expect(object["number"]?.numberValue != nil)
        #expect(object["empty"] == .string(""))
    }
}

struct SyntaxTests {
    @Test("errors report 1-based line and column counted in Unicode scalars")
    func positions() throws {
        let error = try #require(tomlError("a = 1\nkey = \"é\" x"))
        #expect(error.code == .syntax)
        #expect(error.line == 2)
        #expect(error.column == 11)
        #expect(error.description.hasPrefix("2:11: "))
    }

    @Test("malformed documents are syntax errors")
    func catalog() {
        for text in ["= 1", "a", "a =", "a = 1 b = 2", "[a", "[a]]", "[[a]", "[]", "[a.]", "[.a]", "a..b = 1",
                     "a = [1", "a = {", "a = { x = 1", "a = \"open", "a = '''open", "[[a] ]", "[ [a]]", "a = #",
                     "a b = 1", "\"a\nb\" = 1"] {
            #expect(tomlError(text)?.code == .syntax, "\(text)")
        }
    }

    @Test("comments may not contain control characters other than tab")
    func commentControls() throws {
        #expect(try toml("# tab\there\na = 1 # trailing") == json(#"{"a":1}"#))
        #expect(tomlError("# bad \u{1}")?.code == .controlCharacter)
        #expect(tomlError("# bad \u{7F}")?.code == .controlCharacter)
        #expect(tomlError("# bare\rcr")?.code == .controlCharacter)
    }

    @Test("CRLF line endings are accepted and a bare carriage return is rejected")
    func lineEndings() throws {
        #expect(try toml("a = 1\r\n[t]\r\nb = 2\r\n") == json(#"{"a":1,"t":{"b":2}}"#))
        #expect(tomlError("a = 1\rb = 2")?.code == .controlCharacter)
    }

    @Test("stray control characters outside strings are controlCharacter")
    func strayControls() {
        #expect(tomlError("\u{C}")?.code == .controlCharacter)
        #expect(tomlError("a = \u{0}")?.code == .controlCharacter)
    }

    @Test("invalid UTF-8 is invalidEncoding; a leading byte order mark is skipped")
    func encoding() throws {
        #expect(throws: TOMLError.self) { try TOMLParser().parse([0x61, 0x20, 0x3D, 0x20, 0xFF]) }
        for bytes: [UInt8] in [[0xFF], [0x23, 0xC0, 0x80], [0x23, 0xED, 0xA0, 0x80], [0x23, 0xF4, 0x90, 0x80, 0x80]] {
            do {
                _ = try TOMLParser().parse(bytes)
                Issue.record("expected an error for \(bytes)")
            } catch {
                #expect(error.code == .invalidEncoding)
            }
        }
        #expect(try TOMLParser().parse([0xEF, 0xBB, 0xBF] + Array("a = 1".utf8)) == json(#"{"a":1}"#))
        #expect(tomlError("a = 1\n\u{FEFF}b = 2")?.code == .syntax)
    }
}

struct LimitTests {
    @Test("maxInputBytes fails above the limit and allows input of exactly that size")
    func inputBytes() throws {
        #expect(try toml("a = 1", limits: TOMLLimits(maxInputBytes: 5)) == json(#"{"a":1}"#))
        #expect(tomlError("a = 1", limits: TOMLLimits(maxInputBytes: 4))?.code == .inputTooLarge)
    }

    @Test("maxDepth counts the root table, header paths, dotted keys and inline nesting")
    func depth() throws {
        let limits = TOMLLimits(maxDepth: 3)
        #expect(try toml("a = [[1]]", limits: limits) == json(#"{"a":[[1]]}"#))
        #expect(tomlError("a = [[[1]]]", limits: limits)?.code == .depthLimitExceeded)
        #expect(try toml("[a.b]", limits: limits) == json(#"{"a":{"b":{}}}"#))
        #expect(try toml("[a.b]\nc = 1", limits: limits) == json(#"{"a":{"b":{"c":1}}}"#))
        #expect(tomlError("[a.b]\nd.e = 2", limits: limits)?.code == .depthLimitExceeded)
        #expect(tomlError("[a.b.c]", limits: limits)?.code == .depthLimitExceeded)
        #expect(tomlError("a.b.c.d = 1", limits: limits)?.code == .depthLimitExceeded)
        #expect(tomlError("a = { b = { c = { d = 1 } } }", limits: limits)?.code == .depthLimitExceeded)
        #expect(tomlError("[[a]]\nb = [1]", limits: limits)?.code == .depthLimitExceeded)
    }

    @Test("deeply nested input fails at maxDepth without exhausting the stack")
    func deepInput() {
        let deep = "a = " + String(repeating: "[", count: 100_000)
        #expect(tomlError(deep)?.code == .depthLimitExceeded)
        let deepTables = "a = " + String(repeating: "{b = ", count: 100_000)
        #expect(tomlError(deepTables)?.code == .depthLimitExceeded)
        #expect(tomlError("[" + Array(repeating: "a", count: 10_000).joined(separator: ".") + "]")?.code == .depthLimitExceeded)
    }

    @Test("the default depth of 128 parses on a task thread")
    func defaultDepthOnTask() async throws {
        let text = "a = " + String(repeating: "[", count: 127) + "1" + String(repeating: "]", count: 127)
        let value = try await Task { try toml(text) }.value
        var current = value.objectValue?["a"]
        var depth = 1
        while let inner = current?.arrayValue?.first { current = inner; depth += 1 }
        #expect(depth == 128)
        #expect(current == .number(try JSONNumber(parsing: "1")))
        #expect(tomlError("a = " + String(repeating: "[", count: 128) + String(repeating: "]", count: 128))?.code ==
                .depthLimitExceeded)
    }

    @Test("maxNodes counts tables, arrays and scalars")
    func nodes() throws {
        let limits = TOMLLimits(maxNodes: 3)
        #expect(try toml("a = [1, 2]", limits: limits) == json(#"{"a":[1,2]}"#))
        #expect(tomlError("a = [1, 2, 3]", limits: limits)?.code == .nodeLimitExceeded)
        #expect(tomlError("[a]\n[b]\n[c]\n[d]", limits: limits)?.code == .nodeLimitExceeded)
    }

    @Test("a cancelled task stops parsing with cancelled")
    func cancellation() async {
        let big = (0..<5_000).map { "k\($0) = \($0)" }.joined(separator: "\n")
        let error = await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return tomlError(big)
        }.value
        #expect(error?.code == .cancelled)
    }
}
