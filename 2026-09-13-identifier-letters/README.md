# `compiler-common` rejects names that `gren make` compiles: `x中`, `xʰ`, `xǅ` and `ǅa`

`gren` 0.6.6, `gren-lang/compiler-common` 3.0.0, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

This compiles with `gren make`:

```gren
x中 : Int
x中 =
    1
```

and `compiler-common`'s parser cannot parse it. `Compiler.Parse.Variable.lowerCase`
stops at the `中` and gives back `"x"`, and the declaration then fails to parse.
Anything built on `compiler-common` — a formatter, a language server — refuses a
source file that the compiler accepts.

The two parsers disagree about which letters may appear in a name. Both
decide by a character's Unicode **General Category**, a two-letter code the
Unicode Character Database gives every character
([UAX #44, General_Category values](https://www.unicode.org/reports/tr44/#General_Category_Values)).
Letters fall into five categories:

| category | meaning | example |
|---|---|---|
| `Lu` | uppercase letter | `A`, `É` |
| `Ll` | lowercase letter | `a`, `é` |
| `Lt` | titlecase letter: a single character written as two letters, in the form that starts a capitalized word | `ǅ` (U+01C5), between `Ǆ` and `ǆ` |
| `Lm` | modifier letter | `ʰ` (U+02B0) |
| `Lo` | other letter, with no case | `中` (U+4E2D), `א`, `ก` |

In a regular expression, `\p{Ll}` matches one character of category `Ll`, and
`\p{L}` matches any of the five. What each parser accepts:

| | `gren make` | `compiler-common` |
|---|---|---|
| first letter of a lower-case name | lowercase letter (`Ll`) | `\p{Ll}` — the same |
| first letter of an upper-case name | uppercase **or titlecase** letter (`Lu`, `Lt`) | `\p{Lu}` |
| every later character | ASCII letter, digit or `_`, or **any** letter (`Lu`, `Ll`, `Lt`, `Lm`, `Lo`) | ASCII letter, digit or `_`, or `\p{Ll}` or `\p{Lu}` |

So the letters `compiler-common` is missing are titlecase (`Lt`, 31 characters,
such as `ǅ`), modifier letters (`Lm`, such as `ʰ`) and "other" letters (`Lo`,
which is most of CJK, Arabic, Hebrew, Devanagari and Thai, among others).

## Reproduction

`./run.sh` asks both questions about each name and prints the table below. For
`gren make` it compiles a module declaring the name, as a value (`lower`) or as
a type with one constructor of the same name (`upper`). For `compiler-common` it
runs `lowerCase` or `upperCase` followed by `end`, so a name counts as accepted
only if the parser consumed all of it.

| kind | name | `gren make` | `compiler-common` |
|---|---|---|---|
| lower | `xé` | accepts | accepts |
| lower | `xǅ` (U+01C5, `Lt`) | accepts | **rejects** |
| lower | `xʰ` (U+02B0, `Lm`) | accepts | **rejects** |
| lower | `x中` (U+4E2D, `Lo`) | accepts | **rejects** |
| upper | `Éa` | accepts | accepts |
| upper | `ǅa` (U+01C5, `Lt`) | accepts | **rejects** |

The two `accepts` rows are the control: an `Ll` or `Lu` letter, which both
parsers accept.

## The cause and the fix

`gren make` asks Haskell's `Data.Char`: `isUpper` (which is `Lu` or `Lt`) for
the first letter of an upper-case name, `isLower` for a lower-case one, and
`isAlpha` (every `L*` category) after that — `compiler/src/Parse/Variable.hs`.
`compiler-common`'s `Compiler/Parse/Variable.gren` uses two regexes instead:

```gren
lowerCaseLetterRegex = Regex.fromString "\\p{Ll}" ...
upperCaseLetterRegex = Regex.fromString "\\p{Lu}" ...

isInner char =
    Char.isAlphaNum char
        || char == '_'
        || isLowerCaseLetter char
        || isUpperCaseLetter char
```

Matching `gren make` means an upper-case first letter is `[\p{Lu}\p{Lt}]` and a
later character may be any `\p{L}`:

```gren
upperCaseLetterRegex = Regex.fromString "[\\p{Lu}\\p{Lt}]" ...
letterRegex = Regex.fromString "\\p{L}" ...

isInner char =
    Char.isAlphaNum char
        || char == '_'
        || isLetter char
```

- **Filed as:** not yet filed
- **Package:** `gren-lang/compiler-common`, `Compiler.Parse.Variable`
- **Versions:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0
