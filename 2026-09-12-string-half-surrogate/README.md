# `contains`, `startsWith`, `endsWith` and the three index functions match half a surrogate pair

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`contains`, `startsWith`, `endsWith`, `firstIndexOf`, `lastIndexOf` and
`indices` are `String.prototype.indexOf` and `lastIndexOf`, which match UTF-16
code units. So half of a surrogate pair is found inside the character it is half
of.

`"𝄞ab"` has three characters: U+1D11E, `a`, `b`. On JavaScript U+1D11E is stored
as the code units 0xD834 and 0xDD1E, and neither of those is one of those
characters. But:

```gren
clef = "𝄞ab"

secondUnit = String.sliceUnits 1 2 clef     -- the second code unit of 𝄞, alone

String.contains secondUnit clef             -- True
String.firstIndexOf secondUnit clef         -- Just 1
```

The `Just 1` is the part with no way forward for the caller: `String.slice`
counts codepoints, so index 1 of `"𝄞ab"` is `"a"`, and no index recovers what was
matched. This is not #148 — there the answer is in the wrong unit and converting
it is the fix; here there is no right answer to convert to.

`String.sliceUnits` is how `secondUnit` is built above, but that is not what this
depends on. `Char.fromCode 0xDD1E |> String.fromChar` builds the same string and
touches no `*Units` function, and so do `getUnit`, `foldlUnits` and a `\u{DD1E}`
escape in a literal — five routes, all checked against 7.4.2. A surrogate is a
codepoint, so anything that turns a codepoint into a `String` can produce one.

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
searched for: an unpaired surrogate is a codepoint — `String.count secondUnit` is
1 — so a `String` holding one on its own really does contain it, and rejecting
every search string with a surrogate in it would be wrong.

## The fix

A match counts only if it lands on codepoint boundaries at both ends. Whether a
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
