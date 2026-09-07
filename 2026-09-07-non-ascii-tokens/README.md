# `keyword` ends a word at ASCII, so `let` matches the front of `letés`

`String.Parser.keyword` exists because `token` is not enough, and its
documentation is explicit about what it adds:

> **Note:** this would fail to chomp `letter` because of the subsequent
> characters. Use [token](String.Parser.Advanced#token) if you do not want that
> last letter check.

The check is there. It decides where a word ends with `Char.isAlphaNum`, which
is **ASCII by contract** — its own docs say "Detect upper case and lower case
ASCII characters" and give `isAlphaNum 'π' == False` as an example. So the
boundary holds for `letters` and fails for every name whose next character is a
letter outside ASCII.

The caller cannot fix this from outside. `keyword`'s boundary predicate is not a
parameter, and `Char.isAlphaNum` is the right function for what it says it does.
The mismatch is that `keyword` uses it to mean "part of a name", which is a
decision belonging to the language being parsed rather than to ASCII.

## Reproduction

```console
$ ./run.sh
```

`src/Main.gren` is a program with no I/O in it beyond printing. It builds a
small two-expression language — `let <name> = <int>`, or a bare reference to a
name — whose identifiers allow letters beyond ASCII, the way most languages'
identifiers do.

```
PART 1 -- `keyword "let"` on its own

  `keyword` promises a word boundary: its docs say `keyword "let"`
  will not chomp `letters`. Every row below is one name, so every
  row should say `refused`.

    letters   (ASCII)            -> refused
    let\u{00E9}s  (U+00E9,  2 bytes)  -> matched
    let\u{FF5A}s  (U+FF5A,  3 bytes)  -> matched
    let\u{1D41A}s (U+1D41A, 4 bytes)  -> matched


PART 2 -- the same names as whole programs

  Each is a bare reference to a variable, so each should parse as
  `Reference <the name>`.

    letters   (ASCII)            -> Reference "letters"
    let\u{00E9}s  (U+00E9,  2 bytes)  -> error at column 6
    let\u{FF5A}s  (U+FF5A,  3 bytes)  -> error at column 6
    let\u{1D41A}s (U+1D41A, 4 bytes)  -> error at column 4


  And a real binding, which has to keep working:

    let x = 1                     -> Binding "x" 1


PART 3 -- the silent one

  `leté = 1` is a binding whose variable is named
  `é`. `leté` is a reference to a variable
  named `leté`. They are different programs and only
  the first is written with a space:

    let\u{00E9} = 1                    -> Binding "é" 1
    let \u{00E9} = 1                   -> Binding "é" 1
```

Part 1 is the bug. Parts 2 and 3 are why it is worth fixing rather than
documenting.

**Part 2**: the error is not where the problem is. `letés` is one name, four
characters long. What is reported is a failure at **column 6** — past the end of
the name — because `let` matched, the binding branch committed, and the parser
then wanted an `=` after what it took to be the bound variable `és`. A user
looking at column 6 is looking at the wrong thing.

**Part 3** is worse, because nothing is reported at all. `leté = 1` and
`let é = 1` are different programs — the first binds nothing and names a
variable `leté`, the second binds a variable named `é` — and they parse to the
same value. A grammar where a keyword may be followed by a name with no space
between them turns this from a confusing error into a wrong answer.

The three widths are deliberate: U+00E9 is two UTF-8 bytes and one UTF-16 unit,
U+FF5A is three bytes and one unit, U+1D41A is four bytes and two units. All
three behave the same way, which is the point — this is not about the encoding.

## Cause

`src/String/Parser/Advanced.gren`:

```gren
keyword : String -> x -> Parser c x {}
keyword kwd expecting =
  …
    if newOffset == -1 || 0 <= isSubChar (\c -> Char.isAlphaNum c || c == '_') newOffset s.src then
      Bad { pred = False, bag = (fromState s expecting) }
```

`String.Parser.keyword` calls straight through to it.

The predicate is written inline, so there is no way to pass another one — and
the docs for `token`, which describe `keyword` as `token` plus "a trick to peek
ahead a bit", present the boundary as a caller-supplied `isVarChar` in their
illustrative code:

```gren
    keyword : String -> Parser {}
    keyword kwd =
      succeed identity
        |> skip (backtrackable (token kwd))
        |> keep (oneOf
            [ map (\_ -> True) (backtrackable (chompIf isVarChar))
            , succeed False
            ])
        |> andThen (checkEnding kwd)

    isVarChar : Char -> Bool
    isVarChar char =
      …
```

The illustration is what a caller wants. The implementation hardcodes one.

## Suggested fix

Two shapes, and the second is the one that solves it.

**Widen the predicate.** `\p{L}`, `\p{N}` and `_` are what "part of a name"
means in most languages this parser would be pointed at, and `String.Regex` is
already in `core`:

```gren
wordCharRegex : Regex
wordCharRegex =
  Regex.fromString "[\\p{L}\\p{N}_]"
    |> Maybe.withDefault Regex.never
```

That fixes every row above and costs a regex test per keyword. It is still a
guess about the caller's language — a parser whose identifiers allow `-` or `'`
is no better off than before.

**Take the predicate as an argument.** The honest fix, since the boundary
belongs to the grammar:

```gren
keywordWith : (Char -> Bool) -> String -> x -> Parser c x {}
```

with `keyword` defined as `keywordWith (\c -> Char.isAlphaNum c || c == '_')`,
so nothing that exists today changes. A caller with non-ASCII identifiers then
passes the same predicate it already chomps names with, and the two can no
longer disagree — which is the actual defect. `variable` takes its `inner`
predicate as a parameter and `keyword`'s boundary is not one, so a parser using
both is telling the library two different things about what a name is.

The two are not exclusive: widening the default is the fix for callers who never
notice the question, and the parameter is the fix for callers who have already
answered it.

## Not the same as core#138

[gren-lang/core#138](https://github.com/gren-lang/core/issues/138) — `isSubChar`
hands the predicate the undecoded lead surrogate of a pair — is in the same
function family and is a different bug. This one does not depend on it:

- Two of the three rows are single-unit BMP characters with no surrogate in them
  at all.
- The astral row behaves identically against a `core` with #138 fixed. Once
  `isSubChar` asks `Char.isAlphaNum` about U+1D41A instead of about 0xD835 the
  answer is still `False`, so `keyword` still matches. Checked by building this
  reproduction against both.
- The one thing #138 does change here is Part 2's astral row. Against stock it
  reports **column 4**, because `variable`'s own `start` predicate is handed the
  lead surrogate and refuses the name; with #138 fixed it reports **column 6**,
  joining the other two. The row fails either way, and it fails for this bug's
  reason.

`src/Main.gren`'s `isLetter` excludes the surrogate range for the same reason a
real Unicode predicate does: half a surrogate pair is not a character. A
predicate that accepts everything non-ASCII would accept the lead surrogate too,
and would hide #138 rather than sit beside it.

---

- **Filed as:** not yet filed
- **Package:** `gren-lang/core`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, Node.js v22, Linux x86-64
