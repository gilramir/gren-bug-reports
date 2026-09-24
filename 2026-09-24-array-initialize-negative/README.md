# `Array.initialize` and `Array.repeat` throw on a negative count

**Repository:** `gren-lang/core`
**Found against:** `gren-lang/core` 7.4.2 (`src/Gren/Kernel/Array.js`), node 22
**Reproduction:** https://github.com/gilramir/gren-bug-reports/tree/main/2026-09-24-array-initialize-negative
**Filed:** not yet.

`Array.repeat n x` and `Array.initialize n 0 f` with `n` computed as, say, a
padding width (`width - String.count s`) throw `RangeError: Invalid array length`
as soon as `n` goes below zero, and the program stops. Other `Array` functions
answer `[]` when asked for an impossible size (`slice 2 1`, `dropFirst 5` of a
three-element array, `range 6 3`), and nothing in `Array`'s docs puts a floor
under `n`.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren` and run `gren run Main`:

```gren
module Main exposing (main)

import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Node.endSimpleProgram
            (Stream.writeLineAsBytes
                (Debug.toString
                    { slice = Array.slice 2 1 [ 1, 2, 3 ] -- []
                    , range = Array.range 6 3 -- []
                    , repeatZero = Array.repeat 0 1 -- []
                    , repeatNegative = Array.repeat -1 1 -- expected [], throws RangeError
                    }
                )
                env.stdout
                |> Task.map (\_ -> {})
                |> Task.onError (\_ -> Task.succeed {})
            )
```

Output (stderr; paths shortened and the stack trace cut after `Array.repeat`):

```
RangeError: Invalid array length
    at Function.a3 (.../.gren/app:116:16)
    at A3 (.../.gren/app:82:23)
    at $gren_lang$core$Array$repeat$ (.../.gren/app:3176:9)
```

Nothing is printed on stdout, and node exits with status 0. `Array.initialize -1
0 identity` throws the same. When the call is evaluated after the program has
already written to a stream, the exception is swallowed instead and the program
just stops, silently, also with status 0 (`core#142`).

## Cause

The first line of the kernel function:

```js
var _Array_initialize = F3(function (size, offset, func) {
  var result = new Array(size);
```

`new Array(-1)` throws. `repeat n val` is `initialize n 0 (\_ -> val)`.

## Fix

In the kernel:

```js
var result = new Array(size < 0 ? 0 : size);
```

or in `Array.gren`, so it holds on any backend:

```gren
initialize len offset fn =
    if len < 1 then
        []

    else
        Gren.Kernel.Array.initialize len offset fn
```
