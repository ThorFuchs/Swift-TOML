# Limits and Errors

Explicit ceilings that fail instead of degrading, and errors you can act on.

## Limits

``TOMLLimits`` bounds every call:

| Limit | Default | Error |
|---|---|---|
| ``TOMLLimits/maxInputBytes`` | 8 MiB | ``TOMLError/Code-swift.enum/inputTooLarge`` |
| ``TOMLLimits/maxDepth`` | 128 | ``TOMLError/Code-swift.enum/depthLimitExceeded`` |
| ``TOMLLimits/maxNodes`` | 1,000,000 | ``TOMLError/Code-swift.enum/nodeLimitExceeded`` |

Depth counts nested tables and arrays, with the root table at depth 1: `a = [1]` has
depth 2, `[a.b]` has depth 3. Header paths, dotted keys and inline nesting all count;
scalars do not. The node count covers every table, array and scalar in the result except
the root. A result is never truncated: the call either returns the complete value or
throws.

Parsing uses explicit stacks rather than recursion, and the conversion to JSON is a
single pass over the document tree. Deep nesting up to the limit is therefore safe on
small thread stacks.

## Cancellation

The parser checks `Task.isCancelled` on entry and every 1,024 lines or values. It throws
``TOMLError/Code-swift.enum/cancelled`` when the surrounding task is cancelled.

## Errors

``TOMLError`` carries a ``TOMLError/code-swift.property``, a ``TOMLError/message``, and a
1-based ``TOMLError/line`` and ``TOMLError/column``. Columns count Unicode scalars.
Messages never contain file paths, so callers add their own context. Use
``TOMLError/shifted(byLines:)`` when the TOML is embedded in a larger file.

| Code | Meaning |
|---|---|
| ``TOMLError/Code-swift.enum/invalidEncoding`` | the input is not valid UTF-8 |
| ``TOMLError/Code-swift.enum/controlCharacter`` | a control character or bare carriage return where TOML forbids it |
| ``TOMLError/Code-swift.enum/syntax`` | the input does not follow the TOML 1.0 grammar |
| ``TOMLError/Code-swift.enum/invalidEscape`` | an unknown or invalid escape in a basic string |
| ``TOMLError/Code-swift.enum/invalidNumber`` | a malformed integer or float |
| ``TOMLError/Code-swift.enum/invalidDateTime`` | a malformed or out-of-range date or time |
| ``TOMLError/Code-swift.enum/nonFiniteNumber`` | `inf` or `nan` |
| ``TOMLError/Code-swift.enum/numberOutOfRange`` | a number beyond Swift-JSON's exact limits |
| ``TOMLError/Code-swift.enum/duplicateKey`` | a key defined twice, or a value used as a table |
| ``TOMLError/Code-swift.enum/tableRedefinition`` | a table defined twice or extended where TOML forbids it |
| ``TOMLError/Code-swift.enum/unterminatedFrontmatter`` | a `+++` block that is never closed |
| ``TOMLError/Code-swift.enum/inputTooLarge`` | the input is above ``TOMLLimits/maxInputBytes`` |
| ``TOMLError/Code-swift.enum/depthLimitExceeded`` | nesting is above ``TOMLLimits/maxDepth`` |
| ``TOMLError/Code-swift.enum/nodeLimitExceeded`` | the result has more values than ``TOMLLimits/maxNodes`` |
| ``TOMLError/Code-swift.enum/cancelled`` | the surrounding task was cancelled |

New codes may be added in minor releases, so `switch` over ``TOMLError/Code-swift.enum``
with a `default` case.
