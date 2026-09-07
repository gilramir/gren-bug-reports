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

`src/Main.gren` is a program with no I/O in it beyond printing, and it explains
itself as it goes. It builds a small two-form language — `let <name> = <int>`,
or a bare reference to a name — whose identifiers allow letters beyond ASCII,
the way most languages' identifiers do.

```
PART 1 -- what `keyword` is for, and what it does

  A keyword parser has to refuse to match when the keyword is only the
  front of a longer name. In `letters` the `let` is not a keyword, it is
  the first three letters of a variable. `token "let"` matches all four
  inputs below; `keyword "let"` exists to tell them apart, and its docs
  say it "would fail to chomp `letter` because of the subsequent
  characters".

  It decides by looking at the one character that comes AFTER the
  keyword and asking whether that character could be part of a name. If
  it could, this is not a keyword and the parser fails. That test is the
  word boundary. `String.Parser` makes it with `Char.isAlphaNum`, which
  is documented as answering for ASCII and nothing else -- its own
  docs give `isAlphaNum 'π' == False` as an example.

  So the boundary is not "a space" or "punctuation": it is "the next
  character is not a letter, digit or underscore", decided over ASCII
  alone. Every input below is a SINGLE name -- a variable called
  `letters`, a variable called `let\u{00E9}s`, and so on. No keyword
  occurs in any of them, so the right answer for all four is `refused`.

    refused  `run (keyword "let") input` returned Err. The parser did
             not accept `let` as a keyword here. This is correct.
    MATCHED  it returned Ok. The parser took `let` to be a whole
             keyword and consumed it, leaving the rest of the name
             behind for whatever the grammar expects next.

  input            character after `let`        keyword "let" says
  ---------------  ---------------------------  ------------------
  letters          U+0073 's', ASCII, 1 byte    refused
  let\u{00E9}s     U+00E9, 2 UTF-8 bytes        MATCHED  <- wrong
  let\u{FF5A}s     U+FF5A, 3 UTF-8 bytes        MATCHED  <- wrong
  let\u{1D41A}s    U+1D41A, 4 UTF-8 bytes       MATCHED  <- wrong


PART 2 -- what that does to a parser built on it

  A language with two forms:

      let <name> = <int>     a binding
      <name>                 a reference to a variable

  `<name>` allows letters beyond ASCII, the way most languages'
  identifiers do. Each input below is the whole program, and each is a
  bare reference -- one variable's name and nothing else.

  What happens instead: `keyword "let"` matches, the binding branch
  commits, and the parser then looks for the `=` of a binding nobody
  wrote. The failure is reported where that `=` was expected, which is
  past the end of a name four characters long.

  input            should parse as              actually
  ---------------  ---------------------------  --------------------------
  letters          Reference "letters"          Reference "letters"
  let\u{00E9}s     Reference "let\u{00E9}s"     error at column 6  <- wrong
  let\u{FF5A}s     Reference "let\u{FF5A}s"     error at column 6  <- wrong
  let\u{1D41A}s    Reference "let\u{1D41A}s"    error at column 4  <- wrong

  The last row's column differs, and that is a second bug, already
  filed as gren-lang/core#138: `variable`'s own `start` predicate is
  handed the lead surrogate of the pair rather than U+1D41A, so it
  refuses the name at column 4, instead of reading it and then looking
  for an `=` at column 6. With #138 fixed the row reads `error at
  column 6` like the other two. It fails either way, and for this
  bug's reason -- see the README.

  A real binding still works, which is the other half of the check --
  a fix must not turn `keyword` into `token`:

    let x = 1                       Binding "x" 1


PART 3 -- the same bug with no error at all

  Written with a space, this binds a variable whose name is the single
  character U+00E9. The result below is the right one; it prints the
  character itself rather than an escape:

    let \u{00E9} = 1                Binding "é" 1

  Written without one, `let\u{00E9}` is a single name, so the program is
  a reference followed by ` = 1` -- which this language has no rule for.
  The right answer is an error:

    let\u{00E9} = 1                 Binding "é" 1

  Both give the same value. Two different pieces of source, one of them
  not a valid program at all, parse to one result and no diagnostic.
  Part 2's failures are at least visible; this one is not.
```

Part 1 is the bug. Parts 2 and 3 are why it is worth fixing rather than
documenting: part 2 reports the failure in the wrong place, and part 3 does not
report it at all.

The three widths are deliberate. U+00E9 is two UTF-8 bytes and one UTF-16 unit,
U+FF5A is three bytes and one unit, U+1D41A is four bytes and two units. All
three behave the same way, which is the point — this is about
`Char.isAlphaNum`'s answer, not about the encoding.

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
