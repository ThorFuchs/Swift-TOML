# Contributing to Swift-TOML

Thank you for helping. Bug reports, conformance findings and focused pull requests are
all welcome.

## Before you start

- **Bugs:** open an issue with the smallest TOML input that shows the problem, what you
  expected and what you got. Include the `TOMLError` code and position if there is one.
- **Behavior changes:** open an issue first, especially for anything that would change
  how TOML maps to JSON. The rules in README.md and the DocC articles are the
  specification.
- **Security issues:** do not open a public issue. See [SECURITY.md](SECURITY.md).

## Build and test

You need Swift 6.4 or later.

```sh
swift build
swift test
swift test -c release
sh Tools/build-docc.sh            # documentation, warnings are errors
```

For WebAssembly, install the Swift.org toolchain and the matching WASM SDK:

```sh
swift test --swift-sdk swift-6.4.2-RELEASE_wasm
```

[TESTING.md](TESTING.md) describes what each test suite covers and the rules for adding
tests.

## Code rules

- Swift 6 language mode and strict concurrency. Public types are `Sendable` and documented.
- The library uses only the standard library and Swift-JSON's `JSON` module. No
  Foundation, no C code, no new dependencies without discussion.
- No force unwraps and no `fatalError` in library code.
- Values are Swift-JSON `JSON`. Numbers never pass through `Double`. Missing, `null`
  and wrong kind stay distinct. There are no silent defaults or coercions.
- Nesting must never grow the call stack. The parser uses explicit stacks.
- Errors are `TOMLError` with a code, a line and a column. Messages never contain paths.
- Every limit fails rather than truncating.

## Pull requests

- Keep each pull request to one change that can be reviewed in under an hour.
- Include tests and, when behavior changes, updates to README.md, the DocC articles and
  CHANGELOG.md (under "Unreleased").
- CI must be green on macOS, Linux and WebAssembly.

By contributing, you agree that your contributions are licensed under the Apache License,
Version 2.0.
