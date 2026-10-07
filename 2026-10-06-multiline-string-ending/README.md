# `compiler-common` reads a multi-line string's end differently from `gren make`: trailing whitespace is dropped, `\u{0020}` with it, and `\u{000A}` is refused

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0, `gren-lang/core` 7.4.2, node 22

A multi-line string whose content ends in spaces, in a blank line, or in an
escaped space has one value under `gren make` and another under
`Compiler.Parse.Module.parser`. `compiler-common` drops all of the string's
trailing whitespace. `gren make` drops only the line break before the closing
`"""`. So a tool that reads a module with `compiler-common` and writes it back
from the parsed value, as a formatter does, changes what the program
computes. Separately, `\u{000A}` in a multi-line string is refused by
`compiler-common` and compiled by `gren make`.

Each case is the body of `v`, with the content indented as far as the
quotes, which is the layout both parsers are meant to accept (#20):

| case | `v`'s content lines | `gren make` | `compiler-common` |
|---|---|---|---|
| plain | `one`, `two` | `"one\ntwo"` | `"one\ntwo"` |
| trailing-blank-line | `one`, an empty line | `"one\n"` | `"one"` |
| trailing-spaces | `one` and three spaces | `"one   "` | `"one"` |
| escaped-space | `one\u{0020}` | `"one "` | `"one"` |
| escaped-newline | `one\u{000A}two` | `"one\ntwo"` | refused: "Multi-line string lines are not indented equally" |

An escaped space at the end cannot be written at all: `\u{0020}` is the
spelling meant for a space that should not be lost, and it is lost.

## Reproduction

`gren.json`: a node application with `"gren-lang/compiler-common": "3.0.0", "gren-lang/core": "7.4.2", "gren-lang/node": "6.1.3"` (indirect `"gren-lang/url": "6.0.0"`).

`src/Main.gren` parses a module `Probe` for each case with
`Compiler.Parse.Module.parser` and prints `v`'s string as a literal; `run.sh`
then writes the same `Probe` to a fresh project and prints `Probe.v` with
`gren run`. Both sides print through `src/Show.gren`, which writes the string
in quotes with each newline as `\n`.

```gren
cases : Array { name : String, literal : String }
cases =
    [ { name = "plain", literal = "    \"\"\"\n    one\n    two\n    \"\"\"" }
    , { name = "trailing-blank-line", literal = "    \"\"\"\n    one\n\n    \"\"\"" }
    , { name = "trailing-spaces", literal = "    \"\"\"\n    one   \n    \"\"\"" }
    , { name = "escaped-space", literal = "    \"\"\"\n    one\\u{0020}\n    \"\"\"" }
    , { name = "escaped-newline", literal = "    \"\"\"\n    one\\u{000A}two\n    \"\"\"" }
    ]


probe : String -> String
probe literal =
    "module Probe exposing (v)\n\n\nv : String\nv =\n" ++ literal ++ "\n"


parsed : String -> String
parsed literal =
    when Parser.run Module.parser Context.empty (probe literal) is
        Ok m ->
            when Array.first m.values is
                Just decl ->
                    when decl.value.value.body.value is
                        Src.StringLiteral s ->
                            show s

                        _ ->
                            "(not a string)"

                Nothing ->
                    "(no value)"

        Err _ ->
            "refused"
```

`./run.sh` prints:

```
case                  gren make               compiler-common
escaped-newline       "one\ntwo"              refused
escaped-space         "one "                  "one"
plain                 "one\ntwo"              "one\ntwo"
trailing-blank-line   "one\n"                 "one"
trailing-spaces       "one   "                "one"
```

## Cause

`Compiler/Parse/String.gren`'s multi-line branch reads the whole content,
decoding escapes as it goes, and then calls `String.trimRight` on it. That takes
off the closing line's indentation, which is meant to go, and also every space,
tab and line break the content ends with, escaped or not. The compiler's
scanner removes only a final line break and the indentation after it.

The indentation check then runs on the decoded text. `\u{000A}` has become a
line break by then, so `two` looks like a line with no indentation. In the
compiler's scanner an escape is never indentation and never a line break,
since it measures indentation on the source.

## Fix

For the ending: remove the closing line instead of trimming. The content as
read always ends in the line break before the closing `"""` and that line's
indentation, both written raw, so the fix is to drop the spaces after the
last line break and then the break itself, in place of `String.trimRight`:

```gren
dropClosingLine : String -> String
dropClosingLine str =
    when String.popLast str is
        Just { last, rest } ->
            if last == ' ' then
                dropClosingLine rest

            else if last == '\n' then
                rest

            else
                str

        Nothing ->
            str
```

For `\u{000A}`: the indentation has to be measured as the content is read,
before escapes are decoded, so that only raw spaces at the start of a raw
line count. This is a larger change, in `innerSingleLineString`'s loop, and
is not sketched here.

Neither fix has been applied to 3.0.0 and run.
