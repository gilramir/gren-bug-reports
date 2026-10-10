# `gren make` takes time quadratic in a `when`'s branches, a module's declarations and a `let`'s definitions

**Repository:** `gren-lang/compiler`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22.23.2
**Filed:** not yet.

Compiling a `when` with 16,000 `Int` branches takes `gren make` about two
minutes, and a `when` over a 16,000-variant custom type takes three. Each
step of 4× in the number of branches multiplies the time by about 25. A
module of 64,000 top-level declarations, or a `let` of 64,000 definitions,
takes a minute or more, where 16,000 takes about 2.5 s.

These sizes are what generated code reaches: lookup tables, message
catalogues, a type with one variant per icon or per error code, or a big
`when` that dispatches over them.

## Reproduction

`./run.sh` runs under `devbox`, which provides `gren` 0.6.6 and node 22. For
each shape and size, `gen.py SHAPE N` writes `src/Big.gren`, and `src/Main.gren`
prints one value from it. `run.sh` then times `gren make` from an empty
`.gren` cache twice:
- `gren make Main --output=app` builds the whole program;
- `gren make Big` only checks the module, since `Big` has no `main` and so
  generates no code.

| shape | N | `gren make Main` (s) | `gren make Big` (s) |
|---|---|---|---|
| declarations | 4000 | 0.4 | 0.4 |
| declarations | 16000 | 2.5 | 2.6 |
| declarations | 64000 | 74.0 | 79.4 |
| let | 4000 | 0.4 | 0.4 |
| let | 16000 | 2.4 | 2.3 |
| let | 64000 | 60.8 | 65.8 |
| when-int | 1000 | 0.5 | 0.5 |
| when-int | 4000 | 4.8 | 4.9 |
| when-int | 16000 | 121.7 | 119.3 |
| variants | 1000 | 0.3 | 0.2 |
| variants | 4000 | 0.3 | 0.3 |
| variants | 16000 | 0.3 | 0.3 |
| when-variants | 1000 | 0.7 | 0.6 |
| when-variants | 4000 | 7.9 | 7.9 |
| when-variants | 16000 | 182.7 | 182.2 |

The shapes:

- **declarations:** N top-level `xK : Int` values, and `value = x0 + x(N-1)`.
- **let:** one `let` of N definitions, each the one before plus one.
- **when-int:** `when k is` with N `Int` branches and a wildcard.
- **variants:** a type `T = C0 | C1 | …` of N variants, matched once with a
  wildcard. It is here as a control, and stays flat.
- **when-variants:** the same type, and a `when` with one branch per
  variant.

Times vary between machines and runs.

## What it shows

- **The time is spent before code generation.** Checking `Big` alone takes
  as long as building the program.
- **It is the `when`, not the type.** A type of 16,000 variants costs
  nothing more than one of 1,000. A `when` over those variants costs about
  25× more for every 4× more branches, and so does a `when` over `Int`
  literals. That points at the pattern-match checks (exhaustiveness and
  redundancy) or at building the decision tree, rather than at the type
  checker.
- **Declarations and `let` definitions** grow more slowly at first, and by
  64,000 take a minute or more.

Where in the compiler the time goes has not been measured. A profiled
build of the compiler on these inputs would say.
