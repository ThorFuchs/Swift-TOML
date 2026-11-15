# Test Plan

All tests use Swift Testing and live in `Tests/TOMLTests`. Each test name describes a
behavior. There are no skipped tests, no placeholder tests and no tests that only check
that code compiles.

## How to run

```sh
swift test                                         # debug
swift test -c release                              # release
swift test --swift-sdk swift-6.4.2-RELEASE_wasm    # WebAssembly, run under WasmKit
TOML_SUITE_VERBOSE=1 swift test                    # also print the code of every rejected toml-test case
```

CI runs all of these on every push and pull request:

- macOS on Xcode 27.2, plus an iOS build
- Linux x86_64 and Linux arm64 in the `swift:6.4.2` container
- WebAssembly with the Swift 6.4.2 WASM SDK

CI also builds the DocC documentation with warnings treated as errors.

## What is tested where

| Area | Test suite (file) | What it guarantees |
|---|---|---|
| Specification conformance | `TOMLTestSuiteTests` | All 679 toml-test TOML 1.0 cases. Invalid TOML is rejected and valid TOML matches the expected JSON; the 3 deliberate rejections are exactly the listed `inf`/`nan` cases. Fails on any regression **and** on any newly passing known failure. |
| Error codes | `ErrorCodeCoverageTests` | Each `TOMLError.Code` case has a minimal reproducer that yields exactly that code with a valid position and a message without paths. The test is parameterized over `Code.allCases`, so a new code without a reproducer fails. |
| Integers | `IntegerTests` | Decimal, hex, octal and binary forms with underscores. 64-bit extremes and larger values stay exact, never `Double`. Malformed forms are `invalidNumber`. |
| Floats | `FloatTests` | Exact decimals and their lexemes. `inf`/`nan` fail. Malformed forms fail. Numbers beyond Swift-JSON's limits fail. |
| Booleans and strings | `BooleanAndStringTests` | Lowercase booleans only. Every escape, invalid escapes, literal and multi-line strings, delimiter quotes, line-ending backslashes, CRLF to LF, control characters. |
| Dates and times | `DateTimeTests` | All four types keep their exact source text. Leap years, leap seconds, ranges, offsets and malformed shapes. |
| Tables | `TableTests` | Source key order, dotted and quoted keys, implicit tables, arrays of tables, inline values, duplicate keys with position, exact key comparison, every table redefinition rule, missing vs wrong kind. |
| Syntax and encoding | `SyntaxTests` | Positions in Unicode scalars, a catalog of malformed inputs, comments, CRLF and bare CR, stray control characters, invalid UTF-8, the byte order mark. |
| Limits | `LimitTests` | Each limit at and beyond its ceiling. Depth through headers, dotted keys and inline values. 100,000-deep input fails without exhausting the stack. Depth 128 on a task thread. Cancellation. |
| Frontmatter | `FrontmatterTests` | Splitting, absence, CRLF, BOM, trailing blanks, empty blocks, unterminated fences, file-relative error lines, the input limit. |

## Rules for changes

1. **Every behavior change comes with a test.** Change README.md and the DocC articles
   in the same pull request.
2. **Every new `TOMLError.Code` gets a reproducer** in `ErrorCodeCoverageTests` and a
   behavior test in the matching suite.
3. **Keep toml-test at 0 known failures.** If a change makes a case fail, either fix it
   or add it to `knownFailures` with a reason, and list it in the README. CI fails on
   unexplained changes in either direction.
4. **Test inputs are small strings written in the test.** Only toml-test lives in
   `Fixtures/`. Its files are copied unmodified.
5. **Limit and safety tests use tiny limits** so that they run fast on every platform,
   including WebAssembly.
