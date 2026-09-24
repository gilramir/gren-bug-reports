# `compiler-common` accepts a type declaration whose head continues in column 1

**Repository:** `gren-lang/compiler-common`
**Found against:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0, `gren-lang/core` 7.4.2, node 22

A comment after a type's name ends the row, so its variable goes on the next
one. Written there in column 1, `type Foo -- c` / `a` / `    = Foo a` is refused
by `gren make`, which reads a head with no variable followed by a new
declaration, but `Compiler.Parse.Module.parser` accepts it and reads `a` as the
type's variable. A tool built on `compiler-common` passes a file the compiler
rejects.

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
    [ { name = "type-var-indented"
      , source = "module Probe exposing (..)\n\n\ntype Foo\n    a\n    = Foo a\n"
      }
    , { name = "type-var-column-1"
      , source = "module Probe exposing (..)\n\n\ntype Foo\na\n    = Foo a\n"
      }
    , { name = "type-var-column-1-after-comment"
      , source = "module Probe exposing (..)\n\n\ntype Foo -- c\na\n    = Foo a\n"
      }
    , { name = "alias-var-column-1"
      , source = "module Probe exposing (..)\n\n\ntype alias Bar\na =\n    Maybe a\n"
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
case                             gren make   compiler-common
type-var-indented                accepts     accepts
type-var-column-1                rejects     accepts
type-var-column-1-after-comment  rejects     accepts
alias-var-column-1               rejects     accepts
```

What `gren make` says about `type-var-column-1`:

```
-- UNFINISHED CUSTOM TYPE --------------------------------------- src/Probe.gren

I am partway through parsing a custom type, but I got stuck here:

4| type Foo
           ^
I was expecting to see a type variable or an equals sign next.
```

## Cause

`typeArgLoopParser` in `Compiler/Parse/Declaration.gren` reads each variable,
and the `=`, without the indentation check that `variantParser` makes before a
variant's payload.

## Fix

Make the same check before each one. It refuses all three column-1 cases, and
also `=` in column 1 (`type Foo a` over `= Foo a`), which `gren make` refuses
too, since the `=` is read by the same loop:

```diff
 typeArgLoopParser vars =
-    Parser.oneOf
-        [ Parser.succeed (Parser.Done vars)
-            |> Parser.skip (Parser.chompChar '=' (ExpectedChar '='))
-        , Parser.succeed
-            (\var -> Parser.Loop <| Array.pushLast var vars)
-            |> Parser.keep (SourcePosition.parser lowerCaseVariable)
-            |> Parser.skip spaceParser
-        ]
+    Parser.succeed identity
+        |> Parser.skip (Parser.mapError (\_ -> IndentationError) Space.checkIndent)
+        |> Parser.keep
+            (Parser.oneOf
+                [ Parser.succeed (Parser.Done vars)
+                    |> Parser.skip (Parser.chompChar '=' (ExpectedChar '='))
+                , Parser.succeed
+                    (\var -> Parser.Loop <| Array.pushLast var vars)
+                    |> Parser.keep (SourcePosition.parser lowerCaseVariable)
+                    |> Parser.skip spaceParser
+                ]
+            )
```
