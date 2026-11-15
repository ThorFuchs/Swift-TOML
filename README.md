# Swift-TOML

**A pure-Swift TOML 1.0 parser that produces exact [Swift-JSON](https://github.com/ThorFuchs/Swift-JSON) values.**

[![CI](https://github.com/ThorFuchs/Swift-TOML/actions/workflows/ci.yml/badge.svg)](https://github.com/ThorFuchs/Swift-TOML/actions/workflows/ci.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
![Platforms: macOS | iOS | Linux | WebAssembly](https://img.shields.io/badge/platforms-macOS%20%7C%20iOS%20%7C%20Linux%20%7C%20WebAssembly-lightgrey.svg)

[Read the documentation →](https://thorfuchs.github.io/Swift-TOML/documentation/toml/)

Swift-TOML reads TOML configuration and data files, and Hugo-style `+++` frontmatter,
into Swift-JSON `JSON` values. Numbers stay exact decimals and never pass through
`Double`. Dates and times keep their exact source text. Keys stay in source order. Every
violation of the TOML 1.0 specification is an error, never a silent recovery.

- **Exact values.** `9223372036854775807` stays exact, `0.1` stays exactly `0.1`, and
  `1979-05-27 07:32:00Z` stays that string.
- **Strict.** Duplicate keys, table redefinitions, invalid escapes, leading zeros and
  out-of-range dates are errors. `inf` and `nan` are errors, because JSON cannot
  represent them.
- **Safe on untrusted input.** Explicit limits on input size, depth and node count. It
  has no recursion over nesting, so deep input cannot exhaust the stack.
- **Portable.** Pure Swift: no C code and no Foundation in the library. It is tested on
  macOS, Linux (x86_64 and arm64) and WebAssembly (WASI).
- **Conformant.** It runs all 679 TOML 1.0 cases of the official toml-test suite on every
  platform, with 0 known failures.

## Installation

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ThorFuchs/Swift-TOML.git", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "TOML", package: "Swift-TOML"),
        .product(name: "JSON", package: "Swift-JSON"),  // to work with the results
    ]),
]
```

| Requirement | Supported |
|---|---|
| Swift | 6.4 or later, Swift 6 language mode |
| Apple platforms | macOS 27, iOS 27 and later (the minimums of Swift-JSON 1.9.0); iOS is built in CI |
| Linux | x86_64 and arm64 |
| WebAssembly | `wasm32-unknown-wasip1` with the matching Swift.org WASM SDK |
| Dependencies | [Swift-JSON](https://github.com/ThorFuchs/Swift-JSON) 1.9.0 |

## Usage

```swift
import JSON
import TOML

let parser = TOMLParser()                                  // TOMLLimits.default

// A document; the root is always an object
let site = try parser.parse("title = \"Example\"\nport = 8080\nratio = 0.1\n")
site.objectValue?["port"]                                  // .number(8080)

// Markdown frontmatter between +++ fences
if let front = try parser.parseFrontmatter(Array(markdown.utf8)) {
    front.data            // JSON object ({} for an empty block)
    front.body            // [UInt8] after the closing fence
    front.bodyStartLine   // 1-based line of the first body line
}

// Errors are typed, positioned and stable
do {
    _ = try parser.parse("a = 1\na = 2\n")
} catch {
    print(error.code, error.line, error.column)            // duplicateKey 2 1
}
```

## Public API

```swift
public struct TOMLParser: Sendable {
    public var limits: TOMLLimits
    public init(limits: TOMLLimits = .default)
    public func parse(_ bytes: [UInt8]) throws(TOMLError) -> JSON   // root is always .object
    public func parse(_ text: String) throws(TOMLError) -> JSON
    public func parseFrontmatter(_ bytes: [UInt8]) throws(TOMLError) -> ParsedTOMLFrontmatter?
}

public struct TOMLLimits: Sendable, Equatable {
    public var maxInputBytes: Int   // default 8 MiB
    public var maxDepth: Int        // default 128
    public var maxNodes: Int        // default 1,000,000
    public init(maxInputBytes: Int = 8 * 1024 * 1024, maxDepth: Int = 128, maxNodes: Int = 1_000_000)
    public static let `default`: TOMLLimits
}

public struct TOMLError: Error, Sendable, Equatable, CustomStringConvertible {
    public enum Code: String, Sendable, Equatable, CaseIterable { /* 15 codes, see below */ }
    public let code: Code
    public let message: String      // never contains file paths
    public let line: Int            // 1-based
    public let column: Int          // 1-based, in Unicode scalars
    public init(_ code: Code, _ message: String, line: Int, column: Int)
    public var description: String  // "line:column: message"
    public func shifted(byLines lines: Int) -> TOMLError
}

public struct TOMLFrontmatter: Sendable, Equatable {
    public let toml: [UInt8]
    public let tomlStartLine: Int
    public let body: [UInt8]
    public let bodyStartLine: Int
    public static func split(_ bytes: [UInt8]) throws(TOMLError) -> TOMLFrontmatter?
}

public struct ParsedTOMLFrontmatter: Sendable, Equatable {
    public let data: JSON
    public let body: [UInt8]
    public let bodyStartLine: Int
}
```

## How TOML maps to JSON

| TOML | JSON |
|---|---|
| string (basic, literal, multi-line) | string; CRLF in multi-line strings becomes LF |
| `true`, `false` | boolean |
| `42`, `+17`, `1_000`, `0xDEAD_beef`, `0o755`, `0b1101` | exact integer (any size within Swift-JSON's limits) |
| `0.1`, `-3.5e-2`, `6.626e-34`, `1_000.5` | exact decimal |
| `inf`, `nan` with any sign | error `nonFiniteNumber` |
| offset date-time, local date-time, local date, local time | string with the exact source text, after validation |
| array | array, in source order |
| table, inline table, dotted keys | object, members in source order |
| array of tables `[[x]]` | array of objects |
| key defined twice | error `duplicateKey` |
| table defined twice or extended where TOML forbids it | error `tableRedefinition` |

`JSONNumber.originalLexeme` is the JSON spelling of the number: underscores and a
leading `+` are dropped, and `0x`/`0o`/`0b` integers are converted to decimal. See
[Mapping Rules](https://thorfuchs.github.io/Swift-TOML/documentation/toml/mappingrules)
for the details.

## Limits and errors

| Limit | Default | Error |
|---|---|---|
| `maxInputBytes` | 8 MiB | `inputTooLarge` |
| `maxDepth` (tables and arrays; the root is depth 1) | 128 | `depthLimitExceeded` |
| `maxNodes` (tables, arrays and scalars, except the root) | 1,000,000 | `nodeLimitExceeded` |

Every failure is a `TOMLError` with a `code`, a `message` without file paths, and a
1-based `line` and `column`. The codes are `invalidEncoding`, `controlCharacter`,
`syntax`, `invalidEscape`, `invalidNumber`, `invalidDateTime`, `nonFiniteNumber`,
`numberOutOfRange`, `duplicateKey`, `tableRedefinition`, `unterminatedFrontmatter`,
`inputTooLarge`, `depthLimitExceeded`, `nodeLimitExceeded` and `cancelled`; see the
[documentation](https://thorfuchs.github.io/Swift-TOML/documentation/toml/limitsanderrors).
Cancelling the surrounding task stops a parse with `cancelled`.

## Conformance

The tests contain all 679 TOML 1.0 cases of [toml-test](https://github.com/toml-lang/toml-test)
(release `v2.2.0`, the cases listed in `files-toml-1.0.0`), and every CI run executes
them on every platform:

- **Invalid TOML (474 cases):** all rejected.
- **Valid TOML that JSON can represent (202 cases):** all parsed and equal to the suite's
  expected JSON.
- **Valid TOML that JSON cannot represent (3 cases):** rejected on purpose with
  `nonFiniteNumber`, because they contain `inf` or `nan`:
  `valid/comment/after-literal-no-ws`, `valid/float/inf-and-nan`,
  `valid/spec-1.0.0/float-2`.
- **Known failures:** none.

Dates are compared to toml-test's normalized spelling (`T` for the separator, `Z`,
fractional seconds without trailing zeros), because Swift-TOML returns the exact source
text instead.

## Not supported, by design

- `inf` and `nan`: JSON cannot represent them.
- Typed dates and times: they are validated, then returned as strings.
- TOML 1.1 features: newlines and trailing commas in inline tables, `\e` and `\xHH`
  escapes, and times without seconds.
- UTF-16 and UTF-32 input.
- Writing (emitting) TOML.

## Documentation

- [API reference and guides](https://thorfuchs.github.io/Swift-TOML/documentation/toml/),
  built with DocC from `Sources/TOML/TOML.docc`
- [TESTING.md](TESTING.md): the test plan
- [CONTRIBUTING.md](CONTRIBUTING.md): how to build, test and propose changes
- [CHANGELOG.md](CHANGELOG.md): release history
- [SECURITY.md](SECURITY.md): how to report a vulnerability

## License

Apache-2.0. See [LICENSE](LICENSE) and [NOTICE](NOTICE). The vendored toml-test
fixtures are MIT-licensed; see
[their license](Tests/TOMLTests/Fixtures/toml-test/LICENSE).
