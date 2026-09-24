# `compiler-common` accepts a lambda as a function's argument without parentheses, which `gren make` refuses

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0, `gren-lang/core` 7.4.2, node 22

`apply 1 \b -> b + 1` is refused by `gren make`, but
`Compiler.Parse.Module.parser` accepts it as a call of `apply` on `1` and the
lambda. So a tool built on `compiler-common` passes a file the compiler rejects.
If the relaxation is intended, the question is the other way round: will the
compiler take `apply 1 \b -> b + 1` too, so that the two parsers agree?

## Reproduction

`gren.json`: a node application with `"gren-lang/compiler-common": "3.0.0", "gren-lang/core": "7.4.2", "gren-lang/node": "6.1.3"` (indirect `"gren-lang/url": "6.0.0"`).

`src/Main.gren`, which prints what `compiler-common` says about each module:

```gren
module Main exposing (main)

import Compiler.Parse.Context as Context
import Compiler.Parse.Module as Module
import Init
import Node exposing (Environment)
import Stream
import String.Parser.Advanced as Parser
import Task exposing (Task)


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram init


init : Environment -> Init.Task (Cmd a)
init env =
    Node.endSimpleProgram (report env)


cases : Array { name : String, source : String }
cases =
    [ { name = "parenthesized"
      , source = "module Probe exposing (..)\n\n\napply a f =\n    f a\n\n\nv =\n    apply 1 (\\b -> b + 1)\n"
      }
    , { name = "bare"
      , source = "module Probe exposing (..)\n\n\napply a f =\n    f a\n\n\nv =\n    apply 1 \\b -> b + 1\n"
      }
    , { name = "after-backward-pipe"
      , source = "module Probe exposing (..)\n\n\napply a f =\n    f a\n\n\nv =\n    apply 1 <| \\b -> b + 1\n"
      }
    ]


parses : String -> String
parses source =
    when Parser.run Module.parser Context.empty source is
        Ok _ ->
            "accepts"

        Err _ ->
            "rejects"


report : Environment -> Task Never {}
report env =
    cases
        |> Array.map (\c -> c.name ++ " " ++ parses c.source)
        |> String.join "\n"
        |> (\text -> Stream.writeLineAsBytes text env.stdout)
        |> Task.map (\_ -> {})
        |> Task.onError (\_ -> Task.succeed {})
```

`./run.sh` runs `gren run Main`, then writes each case to `src/Probe.gren` and
runs `gren make Probe` on it.

Output:

```
case                  gren make   compiler-common
parenthesized         accepts     accepts
bare                  rejects     accepts
after-backward-pipe   accepts     accepts
```

What `gren make` says about `bare`:

```
-- SYNTAX PROBLEM ----------------------------------------------- src/Probe.gren

I got stuck here:

9|     apply 1 \b -> b + 1
               ^
Whatever I am running into is confusing me a lot! Normally I can give fairly
specific hints, but something is really tripping me up this time.
```

## Cause

In the compiler's grammar a lambda is not a term. It can start an expression, or
be the last operand of an operator, as in `apply 1 <| \b -> b + 1`, but it cannot
be an argument. `Compiler/Parse/Expression.gren` has `function` among `term`'s
alternatives, and `term` is what the argument loop reads.

## Fix

If the compiler's grammar is the intended one: move `function` from `term` into
`parserNoArgs`, where `if`, `when` and `let` already are.

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
expression. `-\b -> b`, which `possiblyNegativeTerm` also accepted, is refused,
as `gren make` refuses it. With this applied to 3.0.0, `./run.sh` prints
`rejects` for `bare` and the other two rows are unchanged. The package's suite
passes 280 tests and fails one, `function calls with lambda` in
`tests/src/Test/Compiler/Parse/Expression.gren`, which expects
`myFunc a \b -> b + 1` to parse and would change with the fix.
