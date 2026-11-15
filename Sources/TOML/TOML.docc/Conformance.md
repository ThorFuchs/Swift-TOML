# Conformance

How Swift-TOML is checked against the TOML specification.

## toml-test

The test target contains all 679 TOML 1.0 cases of the official
[toml-test](https://github.com/toml-lang/toml-test) suite, release `v2.2.0`, as listed in
its `files-toml-1.0.0`. Every run of `swift test` executes all of them on every platform:

| Category | Cases | Result |
|---|---|---|
| Invalid TOML | 474 | all rejected |
| Valid TOML that JSON can represent | 202 | all parsed and equal to the suite's expected JSON |
| Valid TOML that JSON cannot represent | 3 | rejected on purpose with ``TOMLError/Code-swift.enum/nonFiniteNumber`` |
| Known failures | 0 | the test fails on any regression |

The three deliberate rejections contain `inf` or `nan`: `valid/comment/after-literal-no-ws`,
`valid/float/inf-and-nan` and `valid/spec-1.0.0/float-2`.

toml-test spells expected dates and floats in a normalized form. Because Swift-TOML keeps
the exact source text of dates and times, the comparison treats `T`, `t` and a space as
the same separator, `Z` and `z` as the same offset, and ignores trailing zeros of
fractional seconds. Floats are compared exactly, and as binary64 values where toml-test
gives the shortest binary64 spelling.

The suite does not check error codes or positions. Those are covered by the unit tests,
which are described in the repository's `TESTING.md`.
