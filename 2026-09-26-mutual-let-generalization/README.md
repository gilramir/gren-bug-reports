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

Found against `gren` 0.6.6, `gren-lang/core` 7.4.2.
