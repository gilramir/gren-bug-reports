# `gren make` takes time quadratic in a `when`'s branches: the decision tree and the pattern checks visit every branch once for each branch

**Repository:** `gren-lang/compiler`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22.23.2
**Filed:** not yet.

Compiling a `when` with 16,000 `Int` branches takes `gren make` about two
minutes, and a `when` over a 16,000-variant custom type takes three. Each
step of 4× in the number of branches multiplies the time by about 25. With the
change in `fix.patch`, the 0.6.6 tag builds both in under a second, and
64,000 branches in under two seconds.

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

`GREN_BIN` names the compiler binary the `gren` command runs, so the same
script times a build with the fix: `GREN_BIN=/path/to/gren ./run.sh`.

| shape | N | 0.6.6: `make Main` (s) | 0.6.6: `make Big` (s) | fixed: `make Main` (s) | fixed: `make Big` (s) |
|---|---|---|---|---|---|
| when-int | 1000 | 0.5 | 0.5 | 0.3 | 0.2 |
| when-int | 4000 | 4.8 | 4.9 | 0.3 | 0.3 |
| when-int | 16000 | 121.7 | 119.3 | 0.4 | 0.4 |
| when-int | 64000 | | | 1.2 | 0.9 |
| variants | 1000 | 0.3 | 0.2 | 0.2 | 0.3 |
| variants | 4000 | 0.3 | 0.3 | 0.3 | 0.3 |
| variants | 16000 | 0.3 | 0.3 | 0.3 | 0.3 |
| when-variants | 1000 | 0.7 | 0.6 | 0.3 | 0.3 |
| when-variants | 4000 | 7.9 | 7.9 | 0.3 | 0.3 |
| when-variants | 16000 | 182.7 | 182.2 | 0.6 | 0.5 |
| when-variants | 64000 | | | 1.7 | 1.4 |

The shapes:

- **when-int:** `when k is` with N `Int` branches and a wildcard.
- **variants:** a type `T = C0 | C1 | …` of N variants, matched once with a
  wildcard. It is here as a control, and stays flat.
- **when-variants:** the same type, and a `when` with one branch per
  variant.

"Fixed" is the 0.6.6 tag with `fix.patch` applied (`cabal build`, GHC
9.10.3), run through the same `gren` command with `GREN_BIN`. The 0.6.6 rows
at 64,000 were not run. Times vary between machines and runs.

## Where the time goes

Three places, each of which visits every branch once for each branch.

**`Optimize.DecisionTree`, most of it.** Building the tree for a `when` of N
literal branches:

- `gatherEdges` makes one edge for each test at the chosen path, and
  `edgesFor` filters all the branches for each edge with
  `toRelevantBranch`: N tests times N branches.
- `pickPath` weighs one path for each branch that tests one, so the same
  path N times, and each weight, `smallDefaults` and then
  `smallBranchingFactor`, looks at all N branches again.

**`Nitpick.PatternMatches`, the rest.**

- The redundancy check, `toSimplifiedUsefulRows`, asks `isUseful` for each
  branch against all the branches before it: N²/2 row comparisons.
- The exhaustiveness check, `isExhaustive`, specializes the whole matrix
  once for each constructor of a type every constructor of which is named:
  N constructors times N rows. In the missing-constructor case it also lists
  every constructor the rows do not name before it checks whether the rest is
  covered, which costs N for a `when` of two branches over a type of N.

Each part on its own, checking `Big` at 16,000 branches, where 0.6.6 takes
119.3 s for `when-int` and 182.2 s for `when-variants`: with only the decision
tree fixed, 1.36 s and 2.53 s; with only the redundancy check fixed, 113.9 s
and 188.9 s. With the decision tree fixed, the pattern checks still grow as
N²: at 64,000, 25.0 s for `when-int` and 92.5 s for `when-variants`, which
the whole patch takes to 0.9 s and 1.4 s.

## The fix

`fix.patch`, against the 0.6.6 tag:

- **`gatherEdges`** sorts the branches by the test each makes at the path
  once (`relevantBranches`): a branch that tests the path goes to its test's
  edge alone, and one that does not test it goes to every edge, in the
  branches' order as before.
- **`pickPath`** weighs each path once, at its first appearance. `bests`
  answers ties in the order it is given, and the first copy of a path is
  where it first stood, so the path chosen is the same.
- **`toNonRedundantRows`** finds every useful row in one walk over the whole
  matrix (`usefulRows`): the first column's rows are split by what they test,
  a row that tests nothing going to every group, and when the columns run out
  the first row left is the one some value reaches first. A row no value
  reaches first is redundant, and the first such row is the one the old check
  reported, with the same index.
- **`isExhaustive`** splits the rows by constructor once, and checks the
  rest of the row before listing the missing constructors.

Nothing the compiler writes changes: the JavaScript for `when-int` and
`when-variants` at 1,000 is byte for byte the same as 0.6.6's. The patch adds
`tests/Nitpick/PatternUsefulnessSpec.hs`, which holds `checkPatterns` to
brute force on 4,000 random `when`s over `Bool`, `Maybe`, `Int` literals,
arrays and records: every value of the scrutinee's type is enumerated, and a
branch is redundant when every value it matches matches a branch before it.
The test suite passes, 53 examples.

---

- **Filed as:** not yet
- **Package:** `gren-lang/compiler`, `Optimize.DecisionTree` and `Nitpick.PatternMatches`
- **Versions:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22.23.2
