# `compiler-common` accepts a type declaration's head continued in column 1

`gren make` refuses a `type` or `type alias` declaration whose head continues on
a later row in column 1:

```gren
type Foo
a
    = Foo a
```

```
-- UNFINISHED CUSTOM TYPE ----------------------------------------- src/Probe.gren

I am partway through parsing a custom type, but I got stuck here:

4| type Foo
           ^
I was expecting to see a type variable or an equals sign next.
```

`compiler-common`'s `Compiler.Parse.Module.parser` accepts it. A tool built on
`compiler-common` therefore passes a file the compiler rejects. A formatter that
reparses its own output as a check has no way to see that it wrote one.

`./run.sh` asks both parsers about four modules:

```
case                             gren make   compiler-common
type-var-indented                accepts     accepts
type-var-column-1                rejects     accepts
type-var-column-1-after-comment  rejects     accepts
alias-var-column-1               rejects     accepts
```

The third case is the one that turns up in practice. A `--` comment after the
type's name ends the row, so the variable has to go on the next row. Written in
column 1 there, `compiler-common` reads it as the type's variable, and
`gren make` reads a head with no variable followed by a new declaration.

## The fix

`typeArgLoopParser` in `Compiler/Parse/Declaration.gren` reads each variable,
and the `=`, without the indentation check that `variantParser` makes before a
variant's payload. Making the same check before each one refuses all three:

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

`gren make` refuses the `=` in column 1 as well (`type Foo a` over `= Foo a`),
and the check covers it, because the `=` is read by the same loop.

- **Filed as:** not yet filed
- **Package:** `gren-lang/compiler-common`, `Compiler.Parse.Declaration`
- **Versions:** `gren` 0.6.6, `gren-lang/compiler-common` 3.0.0
