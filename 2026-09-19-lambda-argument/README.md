# `compiler-common` accepts a lambda as a function's argument without parentheses

`gren make` refuses a lambda written as an argument without parentheses:

```gren
v =
    apply 1 \b -> b + 1
```

```
-- SYNTAX PROBLEM ----------------------------------------------- src/Probe.gren

I got stuck here:

9|     apply 1 \b -> b + 1
               ^
Whatever I am running into is confusing me a lot! Normally I can give fairly
specific hints, but something is really tripping me up this time.
```

`compiler-common`'s `Compiler.Parse.Module.parser` accepts it, and reads a call
of `apply` on `1` and the lambda. So a tool built on `compiler-common` passes a
file the compiler rejects, and a formatter that reparses its own output as a
check has no way to see that it wrote one.

If the relaxation is intended, as the newer parser's behaviour may be, then
the question is the other way round: whether the Haskell compiler will take
`apply 1 \b -> b + 1` too, so that the two parsers agree.

`./run.sh` asks both parsers about three modules:

```
case                  gren make   compiler-common
parenthesized         accepts     accepts
bare                  rejects     accepts
after-backward-pipe   accepts     accepts
```

## The fix

In the compiler's grammar a lambda is not a term. It can start an expression, or
be the last operand of an operator, as in `apply 1 <| \b -> b + 1`, but it cannot
be an argument. `Compiler/Parse/Expression.gren` has `function` among `term`'s
alternatives, and `term` is what the argument loop reads, so a lambda is
accepted there. Moving it from `term` into `parserNoArgs`, where `if`, `when`
and `let` already are, gives the compiler's reading of all three cases:

```diff
 parserNoArgs =
     Parser.oneOf
         [ ifParser
         , whenParser
         , letParser
+        , Parser.succeed (\start expr end -> SourcePosition.at start end expr)
+            |> Parser.keep Parser.getPosition
+            |> Parser.keep function
+            |> Parser.keep Parser.getPosition
         , possiblyNegativeTerm
         ]
```

and in `term`:

```diff
                             ]
                         )
-                , function
                 , lowerCaseVariable
```

A parenthesized lambda still parses, because the parentheses read a whole
expression. `-\b -> b`, which `possiblyNegativeTerm` also accepted, is refused
as `gren make` refuses it.

The test `function calls with lambda` in
`tests/src/Test/Compiler/Parse/Expression.gren` expects
`myFunc a \b -> b + 1` to parse, and it goes with the fix. With the change
above applied to 3.0.0, `./run.sh` prints `rejects` for `bare` and the other two
rows are unchanged, and the package's suite passes 280 tests and fails that one.

- **Filed as:** not yet filed
- **Package:** `gren-lang/compiler-common`, `Compiler.Parse.Expression`
- **Versions:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0
