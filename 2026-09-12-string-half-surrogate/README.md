# `contains`, `startsWith`, `endsWith` and the three index functions match half a surrogate pair

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Terms

`String`'s own module documentation defines the two that matter:

> * Code units: represents the smallest primitive value of a string. In Gren,
>   code units are represented by a 16-bit value. […]
> * Code points: represents a unicode character. Code points can be represented
>   by one unit, or a pair of units.
>
> Unless otherwise noted, all functions in this module deal with code points.

`count`, `slice`, `takeFirst` and `toArray` work in code points. `unitLength`,
`getUnit` and `sliceUnits` say so in their names and work in code units. A code
point at or above U+10000 is stored as two code units — a **surrogate pair** —
and U+D800–U+DFFF are reserved so the halves of a pair cannot be mistaken for
anything else.

What that list leaves out is what this report turns on: **a surrogate is itself a
code point.** U+DD1E is a code point like any other in U+0000–U+10FFFF. It is not
a *scalar value*, which is Unicode's term for a code point that is not a
surrogate, but `String` draws that line nowhere — so `String.count` of a string
holding one is 1, and a program can hold such a string.

One number therefore names two different things: the code point U+DD1E and the
UTF-16 code unit 0xDD1E. They are numerically equal by design, which is what
makes the two easy to confuse — and confusing them is the defect below, where
`indexOf` compares code units and its answer is read as code points.

## Summary

`contains`, `startsWith`, `endsWith`, `firstIndexOf`, `lastIndexOf` and
`indices` are `String.prototype.indexOf` and `lastIndexOf`, which match UTF-16
code units. So half of a surrogate pair is found inside the character it is half
of.

`"𝄞ab"` has three characters: U+1D11E, `a`, `b`. On JavaScript U+1D11E is stored
as the code units 0xD834 and 0xDD1E, and neither of them is one of those three
characters. But:

```gren
clef = "𝄞ab"

secondUnit = String.sliceUnits 1 2 clef     -- the second code unit of 𝄞, alone

String.contains secondUnit clef             -- True
String.firstIndexOf secondUnit clef         -- Just 1
```

That `Just 1` cannot be used. `String.slice` counts code points, so index 1 of
`"𝄞ab"` is `"a"` — and no index would give back what matched, because what
matched is not a character of the string. That is the difference from #148:
there the index is in the wrong unit and converting it is the whole fix, and
here there is no index to convert to.

Anything that turns a code point into a `String` can build one of these. Checked
against 7.4.2: `sliceUnits`, `getUnit`, `foldlUnits`, a `\u{DD1E}` escape in a
literal, and `Char.fromCode 0xDD1E |> String.fromChar` — which is the `fromCode`
row in the table below, and reaches no `*Units` function at all.

## Reproduction

`./run.sh` produces the rows below.

```gren
clef       = "𝄞ab"                                   -- U+1D11E, a, b
clefChar   = "𝄞"
firstUnit  = String.sliceUnits 0 1 clef              -- 0xD834, alone
secondUnit = String.sliceUnits 1 2 clef              -- 0xDD1E, alone
fromCode   = String.fromChar (Char.fromCode 0xDD1E)  -- secondUnit, built
                                                     -- without any *Units call
```

| call | result | expected |
|---|---|---|
| `String.contains secondUnit clef` | `True` | `False` |
| `String.startsWith firstUnit clef` | `True` | `False` |
| `String.endsWith secondUnit clefChar` | `True` | `False` |
| `String.firstIndexOf secondUnit clef` | `Just 1` | `Nothing` |
| `String.firstIndexOf firstUnit clef` | `Just 0` | `Nothing` |
| `String.lastIndexOf secondUnit clef` | `Just 1` | `Nothing` |
| `String.indices secondUnit clef` | `[1]` | `[]` |
| `String.contains fromCode clef` | `True` | `False` |
| `String.firstIndexOf fromCode clef` | `Just 1` | `Nothing` |
| `String.contains clefChar clef` | `True` | `True` |
| `String.firstIndexOf secondUnit secondUnit` | `Just 0` | `Just 0` |

The last two rows are already right and are there to bound the fix. The second of
them is why the rule has to be about the *match* and not about the string being
searched for: `secondUnit` is one code point, so a `String` holding it really
does contain it, and rejecting every search string with a surrogate in it would
be wrong.

## The fix

A match counts only if it lands on code point boundaries at both ends. Whether a
UTF-16 offset falls between the halves of a pair is two `charCodeAt`s and no
scan:

```js
function _String_splitsPair(str, i) {
  if (i <= 0 || i >= str.length) return false;
  var lead = str.charCodeAt(i - 1);
  if (lead < 0xd800 || lead > 0xdbff) return false;
  var trail = str.charCodeAt(i);
  return trail >= 0xdc00 && trail <= 0xdfff;
}

function _String_aligned(sub, str, i) {
  return !_String_splitsPair(str, i) && !_String_splitsPair(str, i + sub.length);
}
```

`_String_contains` and the three index functions skip a match that is not
aligned and search on from `i + 1`; `_String_startsWith` checks the far end
(offset 0 cannot split a pair, but the end of `sub` can) and `_String_endsWith`
the near one.

**Both ends have to be checked**, which is easy to get wrong: checking only the
start gives the right answer for every row above except one — row 2, where
`firstUnit` matches at offset 0, aligned at the start and running out in the
middle.

The cost is two `charCodeAt`s per candidate match, and a candidate that fails the
test essentially never happens, so it is two comparisons on the successful path.
