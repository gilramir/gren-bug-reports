# `String.Parser.keyword` treats every non-ASCII letter as a word boundary

## What `keyword` is for

A keyword parser has to refuse to match when the keyword is only the front of a
longer name. In `letters` the `let` is not a keyword — it is the first three
letters of a variable. `token "let"` matches both; `String.Parser.keyword`
exists to tell them apart, and its docs say so:

> **Note:** this would fail to chomp `letter` because of the subsequent
> characters. Use [token](String.Parser.Advanced#token) if you do not want that
> last letter check.

It makes that decision by looking at the **one character after the keyword** and
asking whether that character could be part of a name. If it could, this is not
a keyword and the parser fails. That test is the word boundary. It is not
"whitespace" and not "punctuation" — it is "the next character is not a letter,
digit or underscore".

## The bug

`keyword` asks `Char.isAlphaNum`, which is **ASCII by contract**. Its own docs
say "Detect upper case and lower case ASCII characters" and give
`isAlphaNum 'π' == False` as an example. So every letter outside ASCII looks
like the end of the keyword, and `keyword "let"` matches the front of a name
that continues into one.

The caller cannot correct it from outside: the boundary predicate is not a
parameter. And `Char.isAlphaNum` is the right function for what it says it does
— the mismatch is that `keyword` uses it to mean "part of a name", which is a
decision belonging to the language being parsed rather than to ASCII.

## Reproduction

```console
$ ./run.sh
```

Three programs. None prints any commentary; this file is where the commentary
is.

### `src/Identifiers.gren` — the premise

A module whose every identifier is non-ASCII. It exists to be compiled: if this
does not build, nothing else in this report matters. It prints `7`.

```gren
café : Int
ｚebra : Int
𝐚stral : Int

type Týpe
    = Éins
    | Zwölf
```

### `src/Boundary.gren` — `keyword` on its own

It runs `keyword "let"` against four names and prints `Ok` or `Err` for each.
All four are single names — a variable called `letters`, a variable called
`letés`, and so on. **No keyword occurs in any of them, so `Err` is correct
for all four.**

```
Err   letters
Ok    letés
Ok    letｚs
Ok    let𝐚s
```

| source | character after `let` | | correct | actual |
|---|---|---|---|---|
| `letters` | `s` | U+0073, ASCII | `Err` | `Err` |
| `letés` | `é` | U+00E9, 2 UTF-8 bytes | `Err` | **`Ok`** |
| `letｚs` | `ｚ` | U+FF5A, 3 UTF-8 bytes | `Err` | **`Ok`** |
| `let𝐚s` | `𝐚` | U+1D41A, 4 UTF-8 bytes | `Err` | **`Ok`** |

`Ok` means the parser took `let` to be a whole keyword and consumed it, leaving
`és` behind for whatever the grammar expects next.

The three widths are deliberate — two UTF-8 bytes, three, four — and they all
behave the same way, which is the point: this is about `Char.isAlphaNum`'s
answer, not about the encoding.

### `src/Language.gren` — what that does to a parser built on it

A language with two forms:

```
let <name> = <int>     a binding
<name>                 a reference to a variable
```

`<name>` allows letters beyond ASCII, the way most languages' identifiers do.
Each line of input is a whole program.

```
letters   =>   Reference letters
letés   =>   error at column 6
letｚs   =>   error at column 6
let𝐚s   =>   error at column 4
let x = 1   =>   Binding x = 1
let é = 1   =>   Binding é = 1
leté = 1   =>   Binding é = 1
```

**Lines 1–4: the error is not where the problem is.** Each of those four is a
bare reference — one variable's name and nothing else — so each should be
`Reference <that name>`. What happens instead is that `keyword "let"` matches,
the binding branch commits, and the parser then looks for the `=` of a binding
nobody wrote. The failure is reported where that `=` was expected: **column 6**,
past the end of a name four characters long. A user reading the error is looking
at the wrong place.

**Line 5** is the check that a fix must not break: a real binding still parses,
so `keyword` must not simply become `token`.

**Lines 6 and 7: the same bug with no error at all.** These two are different
source:

- `let é = 1` — with a space — binds a variable whose name is the single
  character `é`. `Binding é = 1` is right.
- `leté = 1` — without one — has no keyword in it. `leté` is a single name, so
  the program is a reference followed by ` = 1`, which this language has no rule
  for. **The right answer is an error.**

Both produce `Binding é = 1`. Two different pieces of source, one of them not a
valid program at all, parse to one value and no diagnostic. Lines 1–4 are at
least visible; this is not.

### Why line 4's column differs

`let𝐚s` reports column 4 where the other two report column 6. That is a second,
already-filed bug — [core#138](https://github.com/gren-lang/core/issues/138),
`isSubChar` handing a predicate the undecoded lead surrogate of a pair. Here it
means `name`'s own `start` predicate is asked about 0xD835 and refuses the name
at column 4, instead of reading it and then looking for an `=` at column 6.

With #138 fixed, line 4 reads `error at column 6` like the other two. **The line
fails either way, and it fails for this bug's reason.** See below.

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

## Where this already bites: the two Gren parsers disagree

Non-ASCII identifiers are legal Gren, deliberately. `src/Identifiers.gren` is a
module whose every name is one, and it compiles:

```gren
café : Int
ｚebra : Int
𝐚stral : Int

type Týpe
    = Éins
    | Zwölf
```

`compiler/src/Parse/Variable.hs` is where that is decided, and it is not an
accident of a byte-oriented scanner — there is a hand-written branch per UTF-8
width, each one decoding the codepoint before asking about it:

```haskell
getInnerWidthHelp :: Ptr Word8 -> Ptr Word8 -> Word8 -> Int
getInnerWidthHelp pos _ word
  | 0x61 {- a -} <= word && word <= 0x7A {- z -} = 1
  | 0x41 {- A -} <= word && word <= 0x5A {- Z -} = 1
  | 0x30 {- 0 -} <= word && word <= 0x39 {- 9 -} = 1
  | word == 0x5F {- _ -} = 1
  | word < 0xc0 = 0
  | word < 0xe0 = if Char.isAlpha (chr2 pos word) then 2 else 0
  | word < 0xf0 = if Char.isAlpha (chr3 pos word) then 3 else 0
  | word < 0xf8 = if Char.isAlpha (chr4 pos word) then 4 else 0
  | True = 0
```

**And that function is also its keyword boundary.** `Parse/Keyword.hs` defines
`type_` as `k4 0x74 0x79 0x70 0x65`, and `k4` ends with:

```haskell
          && P.unsafeIndex (plusPtr pos 3) == w4
          && Var.getInnerWidth pos4 end == 0
          then let !s = P.State src pos4 end indent row (col + 4) in cok () s
          else eerr row col toError
```

`Var.getInnerWidth` is the identifier rule itself. The Haskell frontend derives
"where does this keyword end" *from* "what continues a name", so the two cannot
come apart.

`gren-lang/compiler-common` parses the same language and cannot do that. It has
its own, matching, notion of a name character —
`Compiler/Parse/Variable.gren`:

```gren
isInner : Char -> Bool
isInner char =
    Char.isAlphaNum char
        || char == '_'
        || isLowerCaseLetter char      -- a \p{Ll} regex
        || isUpperCaseLetter char      -- a \p{Lu} regex
```

— but its keywords go through `String.Parser.Advanced`, whose boundary is the
hardcoded predicate above. On `main` (3.0.0) that is **11 call sites**:

```
src/Compiler/Parse/Declaration.gren:180  Parser.keyword "type"
src/Compiler/Parse/Declaration.gren:195  Parser.keyword "alias"
src/Compiler/Parse/Declaration.gren:289  Parser.keyword "port"
src/Compiler/Parse/Expression.gren:306   Parser.keyword "let"
src/Compiler/Parse/Expression.gren:423   Parser.keyword "in"
src/Compiler/Parse/Expression.gren:447   Parser.keyword "if"
src/Compiler/Parse/Expression.gren:451   Parser.keyword "then"
src/Compiler/Parse/Expression.gren:455   Parser.keyword "else"
src/Compiler/Parse/Expression.gren:488   Parser.keyword "when"
src/Compiler/Parse/Expression.gren:492   Parser.keyword "is"
src/Compiler/Parse/Expression.gren:520   Parser.keyword "->"
```

So one package holds both halves of a contradiction: `isInner` says `é`
continues a name, and `keyword` says it ends one. The result is that
`compiler-common` rejects `typeé`, `typeｚ` and `type𝐚` — three declarations the
Haskell frontend compiles.

It cannot be fixed inside `compiler-common` by passing the right predicate,
because there is nowhere to pass it. That is what makes this a `core` issue
rather than a caller's: `variable` takes its `inner` predicate as a parameter
and `keyword`'s boundary is a literal, so a parser using both is telling the
library two different things about what a name is and has no way to stop.

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

[core#138](https://github.com/gren-lang/core/issues/138) — `isSubChar` hands the
predicate the undecoded lead surrogate of a pair — is in the same function
family and is a different bug. This one does not depend on it:

- Two of the three failing names are single-unit BMP characters with no
  surrogate in them at all.
- `let𝐚s` behaves identically against a `core` with #138 fixed. Once `isSubChar`
  asks `Char.isAlphaNum` about U+1D41A instead of about 0xD835 the answer is
  still `False`, so `keyword` still matches. Checked by building this
  reproduction against both.
- The only thing #138 changes here is `Language.gren`'s line 4, from column 4 to
  column 6, as above.

`Language.gren`'s `isLetter` excludes the surrogate range for the same reason a
real Unicode predicate does: half a surrogate pair is not a character. A
predicate that accepted everything non-ASCII would accept the lead surrogate
too, and would hide #138 rather than sit beside it.

---

- **Filed as:** [gren-lang/core#144](https://github.com/gren-lang/core/issues/144)
- **Package:** `gren-lang/core`
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, Node.js v22, Linux x86-64
