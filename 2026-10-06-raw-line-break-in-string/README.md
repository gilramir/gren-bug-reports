# `compiler-common` accepts a line break written as itself inside a single-line string or a character, which `gren make` refuses

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0, `gren-lang/core` 7.4.2, node 22

`"one` on one line and `two"` on the next is refused by `gren make`, which
says the string has no end. `Compiler.Parse.Module.parser` accepts it as the
string `"one\ntwo"`, and the same with a CRLF, and it accepts a character
literal holding a raw line break. So a tool built on `compiler-common` passes a
file the compiler rejects. It also means the rule given in #16, that a string
literal whose start and end rows differ must be a multi-line string, does not
hold: a formatter that follows it writes such a single-line string as a
`"""` string.

Each case is the body of `v`:

| case | `v` | `gren make` | `compiler-common` |
|---|---|---|---|
| escaped | `"one\ntwo"` | `"one\ntwo"` | `"one\ntwo"` |
| raw-lf-in-string | `"one`, a line break, `two"` | refused | `"one\ntwo"` |
| raw-crlf-in-string | `"one`, a CRLF, `two"` | refused | `"one\ntwo"` |
| raw-lf-in-char | `String.fromChar '`, a line break, `'` | refused | accepted |

## Reproduction

`gren.json`: a node application with `"gren-lang/compiler-common": "3.0.0", "gren-lang/core": "7.4.2", "gren-lang/node": "6.1.3"` (indirect `"gren-lang/url": "6.0.0"`).

`src/Main.gren` parses a module `Probe` for each case with
`Compiler.Parse.Module.parser` and prints `v`'s string, or whether it was
accepted; `run.sh` then writes the same `Probe` to a fresh project, asks
`gren make` about it, and prints `Probe.v` with `gren run` when it compiles.

```gren
cases : Array { name : String, literal : String }
cases =
    [ { name = "escaped", literal = "    \"one\\ntwo\"" }
    , { name = "raw-lf-in-string", literal = "    \"one\ntwo\"" }
    , { name = "raw-crlf-in-string", literal = "    \"one\r\ntwo\"" }
    , { name = "raw-lf-in-char", literal = "    String.fromChar '\n'" }
    ]
```

`./run.sh` prints:

```
case                  gren make               compiler-common
escaped               "one\ntwo"              "one\ntwo"
raw-crlf-in-string    refused                 "one\ntwo"
raw-lf-in-char        refused                 accepted
raw-lf-in-string      refused                 "one\ntwo"
```

## Cause

`Compiler/Parse/String.gren`'s `innerSingleLineString`, which reads a
single-line string's content, has a branch that reads a CRLF as a line break,
and its last branch, `coreParser`, takes any character that is not an escape,
a raw line break included. `char` reads its one character with the same
`coreParser`. The compiler's scanner ends a single-line string, and a
character, at a raw line break with an error.

## Fix

Remove the CRLF branch from `innerSingleLineString`, and have `coreParser`'s
last branch refuse a `'\n'`. A multi-line string reads its line breaks with
its own branch before it reaches `coreParser`, so it is unaffected. Two of the
package's tests expect the raw line break to be read, "crlf is normalized to
lf" and "Can parse unicode chars" when its fuzzer gives `'\n'`.
