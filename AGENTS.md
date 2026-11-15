# Working in Swift-TOML

A pure-Swift TOML 1.0 parser producing exact Swift-JSON values. README.md and the DocC
articles in `Sources/TOML/TOML.docc` are the specification; update them in the same commit
when behavior changes. TESTING.md is the test plan; CONTRIBUTING.md has the code rules.

- Swift 6 language mode, strict concurrency; public types are `Sendable`.
- No force unwraps or `fatalError` in library code. No Foundation in `Sources/`.
- Values are Swift-JSON `JSON`; numbers never go through `Double`. Dates and times keep
  their exact source text. Missing, `null` and wrong kind stay distinct; no silent
  coercions or fallbacks.
- Nesting must never grow the call stack (the parser uses an explicit stack; the JSON
  conversion is one pass over the node arena).
- Errors are `TOMLError` with code, line and column; messages contain no paths.
- Tests use Swift Testing with behavior-named tests. Every `TOMLError.Code` has a
  negative test. The toml-test test must stay green; update `knownFailures` and the
  README together.
- Evidence is `swift test` (debug, release, WebAssembly) and `sh Tools/build-docc.sh`.
  No status or evidence files.
- Do not push, tag or publish without the owner's approval.
