# Getting Started

Add the package, parse a document, and read the result as JSON.

## Add the dependency

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/ThorFuchs/Swift-TOML.git", from: "0.1.0"),
],
targets: [
    .target(name: "App", dependencies: [
        .product(name: "TOML", package: "Swift-TOML"),
        .product(name: "JSON", package: "Swift-JSON"),
    ]),
]
```

Swift-TOML depends on Swift-JSON 1.9.0, which SwiftPM resolves automatically.

## Parse a document

``TOMLParser/parse(_:)-([UInt8])`` parses a whole document. The result is always an
object:

```swift
import JSON
import TOML

let site = try TOMLParser().parse("""
    title = "Example"
    port = 8080
    ratio = 0.1
    published = 2026-11-15

    [author]
    name = "Ada"
    """)

site.objectValue?["port"]         // .number(8080)
site.objectValue?["ratio"]        // .number(0.1), exact, not a Double
site.objectValue?["published"]    // .string("2026-11-15")
site.objectValue?["missing"]      // nil: absent
```

An empty document, or one containing only comments, parses to an empty object.
``TOMLParser/parse(_:)-(String)`` accepts a `String` and parses its UTF-8 bytes.

## Handle errors

Every failure is a ``TOMLError`` with a stable ``TOMLError/Code-swift.enum``, a message
and a 1-based line and column:

```swift
do {
    _ = try TOMLParser().parse("a = 1\na = 2\n")
} catch {
    error.code         // .duplicateKey
    error.description  // "2:1: key \"a\" is defined more than once"
}
```

The `parse` methods use typed throws, so `error` is a ``TOMLError`` without casting.
