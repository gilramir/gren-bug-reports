# `String.indices`, `firstIndexOf` and `lastIndexOf` changed their answers for ASCII in 7.5.0

**Repository:** `gren-lang/core`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.5.0 (and `main` at
`2bd7c75`), `gren-lang/node` 6.2.0, node 22
**Filed:** not yet. It follows up
[core#148](https://github.com/gren-lang/core/issues/148), closed by `6636098`
and `98c3594`.

## Summary

7.5.0 moved `firstIndexOf`, `lastIndexOf` and `indices` from code units to code
points (core#148), and kept the old ones as `unitFirstIndexOf`,
`unitLastIndexOf` and `unitIndices`, documented as "same as … but operates on
character units". On an ASCII string a code point and a code unit are the same
thing, so the two families should agree with each other and with 7.4.2. They
do not, in two ways:

- **Overlapping matches.** `indices` now tests every position, so it counts
  matches that overlap. `unitIndices`, and `indices` in 7.4.2, go on after the
  end of each match.
- **The empty string as needle.** The new walk tests only positions that hold
  a code point, never the end of the string. So `firstIndexOf "" ""` is
  `Nothing` while `firstIndexOf "" "abc"` is `Just 0`. `lastIndexOf` is now
  `indices |> Array.last`, and `indices ""` is `[]`, so `lastIndexOf "" s` is
  `Nothing` for every `s`.

| call | 7.4.2 | 7.5.0 | 7.5.0's `unit…` form |
|---|---|---|---|
| `indices "aa" "aaaa"` | `[0,2]` | **`[0,1,2]`** | `[0,2]` |
| `indices "aa" "aaa"` | `[0]` | **`[0,1]`** | `[0]` |
| `firstIndexOf "" "abc"` | `Just 0` | `Just 0` | `Just 0` |
| `firstIndexOf "" ""` | `Just 0` | **`Nothing`** | `Just 0` |
| `lastIndexOf "" "abc"` | `Just 3` | **`Nothing`** | `Just 3` |

The changelog says only that the three functions "now operate on code points",
so these look like side effects of the rewrite rather than intended changes.
Neither answer is wrong in itself: overlapping matches are a choice. But a
program moving to 7.5.0 gets different results from ASCII input, and the two
families documented as the same disagree.

## Reproduction

`~/prj/gren-bug-reports/2026-10-08-string-indices-ascii-answers-changed`:
`./run.sh` builds and runs `src/Main.gren` under `devbox`, which provides
`gren` 0.6.6 and node 22. Each row prints the call, the code-point function's
answer and the unit function's answer:

```
indices "aa" "aaaa"	[0,1,2]	[0,2]
indices "aa" "aaa"	[0,1]	[0]
firstIndexOf "" "abc"	Just 0	Just 0
firstIndexOf "" ""	Nothing	Just 0
lastIndexOf "" "abc"	Nothing	Just 3
```

The 7.4.2 column was taken from the same calls without the `unit…` functions,
under core 7.4.2 and node 6.1.3.

## Fix

In `_String_indexes`, after a match, step over the match's code points before
testing again, as `unitIndices` steps over its code units. In
`_String_indexOf`, test the position after the last code point too, so that an
empty needle is found at the end. Give `lastIndexOf` the same end position, or
its own walk, so that `lastIndexOf "" s` is `Just (String.count s)`, as it was.
