# Changelog

This project follows [Semantic Versioning](https://semver.org). Before 1.0.0, minor
releases may change the public API.

## 0.1.1

- Admit Swift-JSON 1.9.0..<1.11.0; qualify 1.9.0 and 1.10.0.
- Preserve the public API, format semantics and deployment floors.

## 0.1.0

First public release.

- `TOMLParser` parses TOML 1.0 into exact Swift-JSON 1.9.0 values:
  - `parse` for a document as `[UInt8]` or `String`; the root is always an object;
  - `parseFrontmatter` for Hugo-style `+++` Markdown frontmatter.
- Integers and floats are exact `JSONNumber` values; dates and times are strings with
  their exact source text; tables keep source key order.
- `TOMLFrontmatter.split` separates frontmatter from the body, with file-relative line
  numbers.
- `TOMLLimits` bounds input bytes, depth and node count. Cancellation is supported.
- `TOMLError` reports 15 stable codes with a 1-based line and column.
- All 679 TOML 1.0 cases of toml-test v2.2.0 are run: 0 known failures, and 3
  documented rejections of `inf`/`nan`, which JSON cannot represent.
- Tested on macOS, Linux x86_64 and arm64, and WebAssembly (WASI).
