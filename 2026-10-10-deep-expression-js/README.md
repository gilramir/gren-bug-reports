# A long `else if` chain, `|>` chain or `+` chain compiles to JavaScript that node cannot load

**Repository:** `gren-lang/compiler`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22.23.2
**Filed:** not yet.

A function with 2,000 `else if` branches compiles, and then node will not
load the program:

```
node:internal/modules/cjs/loader:1713
  const result = compileFunctionForCJSLoader(content, filename, false /* is_sea_main */, shouldDetectModule);
                 ^

RangeError: Maximum call stack size exceeded
    at wrapSafe (node:internal/modules/cjs/loader:1713:18)
```

The source is flat, but the JavaScript nests one level per branch, and V8's
parser recurses once per level. The same happens to a chain of `|>` and,
at 4,000, to a chain of `+`:

| shape | 500 | 1000 | 2000 | 4000 |
|---|---|---|---|---|
| `else if` chain | runs | runs | RangeError | RangeError |
| `+` chain | runs | runs | runs | RangeError |
| `\|>` chain | runs | runs | RangeError | RangeError |
| nested array literal | runs | runs | runs | RangeError |
| nested `Just` | runs | runs | RangeError | RangeError |

The last two rows are nested in the source as well, so they are here only to
show that the limit is the same one. The first three are not nested in the
source. A long `else if` chain or a long sum is what a code generator writes,
for example a lookup table or a big dispatch function.

## Reproduction

`./run.sh` runs under `devbox`, which provides `gren` 0.6.6 and node 22. For
each shape and size, `gen.py SHAPE N` writes `src/Main.gren`, whose `value` is
one expression of that shape, `N` deep. `run.sh` then builds it with
`gren make` and runs it with node. Every program builds. The table above is
its output. The `else if` shape at 5:

```gren
pick : Int -> Int
pick k =
    if k == 0 then
        0

    else if k == 1 then
        1

    else if k == 2 then
        2

    else
        -1
```

## What is emitted

| source | JavaScript |
|---|---|
| `if … else if … else …` | `(k === 0) ? 0 : ((k === 1) ? 1 : ((k === 2) ? 2 : -1))` |
| `0 + 1 + 2 + 3` | `((0 + 1) + 2) + 3` |
| `0 \|> inc \|> inc \|> inc` | `inc(inc(inc(0)))` |

The `+` chain's parentheses are redundant, because JavaScript's `+` is
left-associative already. Written without them, node loads a 20,000-term
sum. A 20,000-branch `switch` also loads, and so do 20,000 sequential
assignments `x = inc(x);`. A 20,000-branch `if … else if …` *statement*
does not load, because V8's parser recurses on `else if` too.

## Fix

The fix is to emit these chains flat:

- **Left-associative operators:** leave out the parentheses that JavaScript's
  own precedence and associativity already give.
- **An `else if` chain:**
  - when every test compares the same value with a literal, emit a `switch`;
  - otherwise, in a function body, emit a sequence of
    `if (c) { return x; }` statements.
- **A `|>` chain:** assign each step to a local variable instead of nesting
  the calls.
