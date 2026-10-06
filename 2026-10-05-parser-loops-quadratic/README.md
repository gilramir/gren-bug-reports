# Parsing takes time quadratic in the number of declarations, list items, branches and fields

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0 (and `main` at
`11ef95a`, which has the same parser), `gren-lang/core` 7.4.2,
`gren-lang/node` 6.1.3, node 22
**Filed:** not yet.

`Compiler.Parse.Module.parser` takes time quadratic in the number of top-level
declarations in a module, and in the number of items in a list literal. A
module of 80,000 one-line declarations takes 14.5 s to parse, and a list of
80,000 integers takes 13.8 s. Each doubling of the input multiplies the time
by about four. The same happens with the branches of a `when`, the fields of a
record, the variants of a custom type, and every other construct the parser
collects with a loop.

An ordinary module doesn't show it: the cost only takes over at a few thousand
siblings. Those do turn up in practice: a generated module, a table of data
written as one list literal, or a long `when`. Every tool built on
`compiler-common` pays it, including formatters.

## Reproduction

`./run.sh` (it runs itself under `devbox`, which provides `gren` 0.6.6 and node
22) does three things:

1. It writes the inputs into `inputs/`. `WideN.gren` is a module of N one-line
   declarations, `xK =\n    K`. `ListN.gren` is one declaration whose body is
   a list of N integers, one per line. N is 10,000, 20,000, 40,000 and 80,000.
   The largest is 1.7 MB.
2. It builds `src/Main.gren` with `--optimize` against `compiler-common` 3.0.0,
   and runs it over the inputs.
3. It builds the same program against `compiler-common` 3.0.0 with
   `builder.patch` applied (see [Fix](#fix)), as a `local:` package, and runs
   that too.

`src/Main.gren` reads each file named on its command line. It then times
`Parser.run Module.parser Context.empty` on that file with `Time.now`, so the
time to read the file is not included.

```gren
timeParse : String -> Task Never { answer : String, ms : Int }
timeParse source =
    Time.now
        |> Task.andThen
            (\t0 ->
                let
                    answer =
                        when Parser.run Module.parser Context.empty source is
                            Ok ast ->
                                String.fromInt (Array.length ast.values) ++ " values"

                            Err _ ->
                                "error"
                in
                Time.now
                    |> Task.map (\t1 -> { answer = answer, ms = Time.posixToMillis t1 - Time.posixToMillis t0 })
            )
```

The output on one machine (times vary between runs and machines):

| input | 3.0.0, ms | with `builder.patch`, ms |
|---|--:|--:|
| `Wide10000.gren` | 271 | 235 |
| `Wide20000.gren` | 856 | 467 |
| `Wide40000.gren` | 3,810 | 835 |
| `Wide80000.gren` | 14,541 | 1,700 |
| `List10000.gren` | 206 | 169 |
| `List20000.gren` | 740 | 320 |
| `List40000.gren` | 3,818 | 665 |
| `List80000.gren` | 13,824 | 1,310 |

## Cause

Each loop that collects its results does it by adding one item at a time to the
end of an `Array`:

```gren
declarationLoopParser decls =
    Parser.oneOf
        [ Parser.succeed
            (\decl ->
                Parser.Loop <|
                    Array.pushLast decl decls
            )
            |> Parser.keep (Parser.mapError DeclarationError Declaration.parser)
            |> Parser.skip spaceParser
        , Parser.succeed (Parser.Done decls)
            |> Parser.skip (Parser.end ExpectedEnd)
        ]
```

`Array.pushLast` copies the array (it is a JavaScript array, and a Gren `Array`
is immutable). So the k-th item costs a copy of k − 1 items, and a loop that
collects n items copies about n²/2 of them. At 80,000 declarations that is
3.2 billion element copies, plus collecting the garbage they leave behind.

These are the loops at 3.0.0, all in `src/Compiler/Parse/`:

| function | file:line | grows with |
|---|---|---|
| `declarationLoopParser` | `Module.gren:452` | top-level declarations |
| `importLoopParser` | `Module.gren:361` | imports |
| `operatorLoopParser` | `Module.gren:436` | infix declarations |
| `parseExposingArray` | `Module.gren:258` | entries in an exposing list |
| `innerArrayParser` | `Expression.gren:761` | list literal items |
| `innerRecordParser` | `Expression.gren:855` | record literal and record update fields |
| `whenBranchLoopParser` | `Expression.gren:527` | `when` branches |
| `ifElseLoop` | `Expression.gren:460` | `else if` branches |
| `letDefLoopParser` | `Expression.gren:420` | `let` definitions |
| `functionArgsParser` | `Expression.gren:563` | a lambda's or definition's arguments |
| `variantLoopParser` | `Declaration.gren:269` | custom type variants |
| `typeArgLoopParser` | `Declaration.gren:205` | type parameters |
| `typeArgsParser` | `Type.gren:128` | type arguments |
| `innerRecordParser` | `Type.gren:245` | record type fields |
| `recordInnerLoop` | `Pattern.gren:117` | record pattern fields |
| `arrayInnerLoop` | `Pattern.gren:173` | array pattern items |

The first five are the ones that grow with a file's size in practice.
`Variable.gren`'s `foreignUpperLoop` and `foreignVarLoop` use the same pattern,
but they only collect the segments of one qualified name. `Expression.gren:214`
collects the arguments of one call. Neither is in the table.

## Fix

`Array.Builder`, which is in `gren-lang/core` from 7.4.0 (`compiler-common`'s
lower bound already), is meant for this. `Builder.pushLast` is amortised O(1).
A builder that is used again after it has been pushed to copies itself first,
so a backtracking parser still gets the right answer. Each loop keeps a
`Builder` as its state and turns it into an `Array` once, when it finishes. The
loop's own result is still an `Array`, so nothing outside the loop changes:

```gren
declarationLoopParser decls =
    Parser.oneOf
        [ Parser.succeed
            (\decl ->
                Parser.Loop <|
                    Builder.pushLast decl decls
            )
            |> Parser.keep (Parser.mapError DeclarationError Declaration.parser)
            |> Parser.skip spaceParser
        , Parser.end ExpectedEnd
            |> Parser.map (\_ -> Parser.Done (Builder.toArray decls))
        ]
```

The obvious translation of the `Done` branch has a trap:
`Parser.succeed (Parser.Done (Builder.toArray decls))`. Its argument is
evaluated when the `oneOf` is built, on every pass of the loop, before any
alternative has run. Converting the builder on every pass makes the next
`Builder.pushLast` copy it, so the cost is quadratic again. Written that way
in `declarationLoopParser` alone, `Wide40000.gren` took 9.7 s, against 3.8 s
for 3.0.0 and 0.9 s for `builder.patch`. The conversion has to be inside a
function that runs only when its alternative matches:
`Parser.map (\_ -> …)` after the token that ends the loop, or
`Parser.succeed {} |> Parser.map (\_ -> …)` where nothing ends it.

`Pattern.recordInnerLoop` needs a little more than the mechanical change. Its
inner `oneOf`s push to the accumulator in the argument of each `Parser.succeed`,
`Loop` and `Done` branches alike. So with a builder, two branches would push to
the same builder on every pass. Each push has to move behind the `,` or `}`
that selects its branch.

`builder.patch` makes this change to every loop in the table, against 3.0.0.
It builds with `gren` 0.6.6 unchanged. The second column of the table above is
that patch. Its ASTs were checked against 3.0.0's by building `gren-format`
twice, once with each, and comparing `gren-format --pre-ast` (the parsed module
as JSON, or the parse error) on 5,383 `.gren` files:

- On 5,126 files the ASTs are byte-for-byte the same.
- On 219 files both give the same error.
- The other 38 are pathological nesting tests that overflow the stack under
  both. Only the JavaScript stack trace differs.
