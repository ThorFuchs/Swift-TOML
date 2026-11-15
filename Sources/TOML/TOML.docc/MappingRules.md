# Mapping Rules

How TOML values become exact JSON values.

## Values

| TOML | JSON |
|---|---|
| string (basic, literal, multi-line) | string |
| `true`, `false` | boolean |
| integer: decimal, `0x`, `0o`, `0b`, with underscores | exact number |
| float: fraction and/or exponent, with underscores | exact number |
| `inf`, `+inf`, `-inf`, `nan`, `+nan`, `-nan` | error ``TOMLError/Code-swift.enum/nonFiniteNumber`` |
| offset date-time, local date-time, local date, local time | string with the exact source text |
| array | array, in source order |
| table, inline table | object, members in source order |
| array of tables (`[[name]]`) | array of objects |

### Numbers

Numbers keep their exact mathematical value and never pass through `Double`. The
resulting `JSONNumber.originalLexeme` is the JSON spelling of the TOML number: underscores
and a leading `+` are dropped, and `0x`, `0o` and `0b` integers are converted to decimal.
So `1_000` becomes `1000`, `+1.5` becomes `1.5` and `0xff` becomes `255`. The digits of a
decimal integer or float are otherwise unchanged; `0.1` stays `0.1`.

TOML requires 64-bit integers. Larger integers are also accepted and kept exact, because
they can be represented without loss. A number beyond Swift-JSON's balanced limits (4,096
digits, exponent magnitude 1,000,000), or a hexadecimal, octal or binary integer with more
than 3,000 digits, is ``TOMLError/Code-swift.enum/numberOutOfRange``.

Malformed numbers are ``TOMLError/Code-swift.enum/invalidNumber``: leading zeros (`01`),
underscores that are not between two digits (`1__0`, `_1`, `1_`), a sign on `0x`, `0o`
or `0b` integers, uppercase prefixes (`0X1F`), and a missing digit (`1.`, `1e`).

### Dates and times

All four TOML date and time types become strings with the exact source text, so
`1979-05-27 07:32:00z` stays `1979-05-27 07:32:00z`. The parser validates them first:
the month, the day for the month (including leap years), the hour, minute, second
(0–60, for leap seconds) and the offset must be in range, and TOML 1.0 requires seconds.
A malformed or out-of-range value is ``TOMLError/Code-swift.enum/invalidDateTime``.

### Strings

Basic strings support the TOML 1.0 escapes `\b`, `\t`, `\n`, `\f`, `\r`, `\"`, `\\`,
`\uXXXX` and `\UXXXXXXXX`. Any other escape, or a `\u`/`\U` value that is a surrogate or
above U+10FFFF, is ``TOMLError/Code-swift.enum/invalidEscape``. Control characters other
than tab must be escaped (``TOMLError/Code-swift.enum/controlCharacter``).

In multi-line strings, a line break right after the opening delimiter is trimmed, a
line-ending backslash trims the following whitespace and line breaks, and each CRLF line
break becomes LF so the result does not depend on how the file was checked out.

## Tables and keys

Tables become objects whose members are in source order. Bare keys, quoted keys and
dotted keys are supported; whitespace around dots is allowed. Keys are compared by their
exact Unicode scalars, so a precomposed `é` and `e` followed by a combining accent are
different keys.

TOML forbids defining anything twice. These are errors:

| Input | Error |
|---|---|
| the same key twice, in any quoting (`a`, `"a"`, `'a'`) | ``TOMLError/Code-swift.enum/duplicateKey`` |
| a table header or dotted key through a key that holds a value (`a = 1` then `[a]`) | ``TOMLError/Code-swift.enum/duplicateKey`` |
| the same `[table]` twice | ``TOMLError/Code-swift.enum/tableRedefinition`` |
| a `[table]` over a table created with dotted keys | ``TOMLError/Code-swift.enum/tableRedefinition`` |
| dotted keys into a table defined by another header section | ``TOMLError/Code-swift.enum/tableRedefinition`` |
| anything added to an inline table after it closes | ``TOMLError/Code-swift.enum/tableRedefinition`` |
| `[table]` over an array of tables, or `[[table]]` over a table | ``TOMLError/Code-swift.enum/tableRedefinition`` |

A `[header]` may still define a table that an earlier header created implicitly
(`[a.b]` then `[a]`), and may add sub-tables to a table created with dotted keys.

## Input

The input must be UTF-8. A byte order mark at the very start is skipped; anywhere else
it is an error. Line breaks are LF or CRLF; a bare carriage return is
``TOMLError/Code-swift.enum/controlCharacter``.
