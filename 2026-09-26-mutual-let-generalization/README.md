# Two unannotated local functions that call each other fix the enclosing function's type variable

`pick` is annotated `a -> a -> Int -> a`, and its body is two local functions
that call each other and return `x` or `y`. The compiler then refuses
`pick "x" "y" 3` in another definition, saying `pick` needs its first argument
to be `a`: the pair has fixed `a` where `pick`'s annotation says any type.

| `pick`'s body | `pick "x" "y" 3` |
|---|---|
| two local functions calling each other, neither annotated | **rejected**: "`pick` needs the 1st argument to be: `a`" |
| the same, with `first : Int -> a` | compiles, prints `y` |
| one local function calling itself | compiles, prints `y` |
| the pair moved to the top level, `x` and `y` passed along | compiles, prints `y` |

The same defect is open in Elm as
[elm/compiler#1766](https://github.com/elm/compiler/issues/1766) ("Compiler does
not match 2 identical types"), with a mutually recursive pair in a `let` and
the same workaround: annotating one of them.

## Reproduction

```
./run.sh
```

`src/Main.gren`:

```gren
pick : a -> a -> Int -> a
pick x y n =
    let
        first k =
            if k <= 0 then
                x

            else
                second (k - 1)

        second k =
            if k <= 0 then
                y

            else
                first (k - 1)
    in
    first n
```

called as `pick "x" "y" 3`:

```
-- TYPE MISMATCH --------------------------------------------------- src/Main.gren

The 1st argument to `pick` is not what I expect:

32|             (Stream.writeLineAsBytes (pick "x" "y" 3) env.stdout
                                               ^^^
This argument is a string of type:

    String

But `pick` needs the 1st argument to be:

    a
```

## Cause

`recDefsHelp` in `compiler/src/Type/Constrain/Expression.hs` constrains a group
of unannotated definitions that call each other. For each definition it seeds
the definition's *pattern* state with the variables of the definitions before
it, and then keeps only the current definition's variables for the group:

```haskell
(Args newFlexVars tipe resultType (Pattern.State headers pvars revCons)) <-
  argsHelp args (Pattern.State Map.empty flexVars [])
...
Info { _vars = newFlexVars, ... }
```

So the group's `CLet` introduces only the last definition's argument and
result variables, and every other definition's are introduced in the next
definition's pattern `CLet`, and generalized when that one closes, before the
rest of the group and the `let` body have used them. Elm's `recDefsHelp` is the
same code, which is why elm/compiler#1766 has the same symptom and workaround.

The fix introduces them all in the group's `CLet`:

```haskell
(Args newFlexVars tipe resultType (Pattern.State headers pvars revCons)) <-
  argsHelp args Pattern.emptyState
...
Info { _vars = newFlexVars ++ flexVars, ... }
```

With it, `pick "x" "y" 3` compiles and prints `y`, and `pick 1 2 4` prints `1`.

Found against `gren` 0.6.6, `gren-lang/core` 7.4.2.
