# ``TOML``

Parse TOML 1.0 into exact Swift-JSON values.

## Overview

Swift-TOML reads TOML configuration and data files, and Hugo-style `+++` frontmatter,
into [Swift-JSON](https://github.com/ThorFuchs/Swift-JSON) `JSON` values. The root is
always an object. Integers and floats stay exact decimals and never pass through
`Double`. Dates and times keep their exact source text. Every violation of the TOML 1.0
specification is an error, and anything JSON cannot represent (`inf`, `nan`) is an
error rather than a silent conversion.

The package is pure Swift, with no C code and no Foundation in the library. It runs on
macOS, iOS, Linux and WebAssembly (WASI).

```swift
import JSON
import TOML

let value = try TOMLParser().parse("title = \"Hello\"\ncount = 3\n")
// {"title": "Hello", "count": 3}
```

## Topics

### Essentials

- <doc:GettingStarted>
- ``TOMLParser``

### Mapping TOML to JSON

- <doc:MappingRules>

### Frontmatter

- <doc:Frontmatter>
- ``TOMLFrontmatter``
- ``ParsedTOMLFrontmatter``

### Limits and errors

- <doc:LimitsAndErrors>
- ``TOMLLimits``
- ``TOMLError``

### Quality

- <doc:PlatformSupport>
- <doc:Conformance>
