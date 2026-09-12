# `contains`, `startsWith`, `endsWith` and the three index functions match half a surrogate pair

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

`./run.sh` prints the figure below.

## Summary

`contains`, `startsWith`, `endsWith`, `firstIndexOf`, `lastIndexOf` and
`indices` are `String.prototype.indexOf` and `lastIndexOf`, which match UTF-16
code units. So half of a surrogate pair is found inside the character it is half
of.

`"𝄞ab"` has three characters: U+1D11E, `a`, `b`. On JavaScript U+1D11E is stored
as the code units 0xD834 and 0xDD1E, and neither is one of those characters. But:

```gren
clef = "𝄞ab"

trailHalf = String.sliceUnits 1 2 clef      -- the second unit of 𝄞, alone

String.contains trailHalf clef              -- True
String.firstIndexOf trailHalf clef          -- Just 1
```

The `Just 1` is the part with no way forward for the caller: `String.slice`
counts codepoints, so index 1 of `"𝄞ab"` is `"a"`, and no index recovers what was
matched. This is not #148 — there the answer is in the wrong unit and converting
it is the fix; here there is no right answer to convert to.

`String.sliceUnits` is how the needle is made, so nothing depends on being able
to write an escape for a lone surrogate.

## Reproduction

```
the string is "𝄞ab": three codepoints (U+1D11E, a, b), four UTF-16 units
the needles are its first and second code unit, cut out with sliceUnits

contains the trail half          = True     (should be False)
startsWith the lead half         = True     (should be False)
endsWith the trail half of "𝄞"   = True     (should be False)

firstIndexOf the trail half      = Just 1   (should be Nothing)
firstIndexOf the lead half       = Just 0   (should be Nothing)
lastIndexOf the trail half       = Just 1   (should be Nothing)
indices of the trail half        = 1        (should be empty)

contains the whole character     = True     (correct)
firstIndexOf the trail half in itself = Just 0 (correct)
```

The last line is why the rule has to be about the match rather than the needle.
An unpaired surrogate is a codepoint — `String.count` of it is 1 — so a `String`
holding one on its own really does contain it, and refusing every needle with a
surrogate in it would be wrong.

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
(offset 0 cannot split a pair, but the end of the needle can) and
`_String_endsWith` the near one.

**Both ends have to be checked**, which is easy to get wrong: checking only the
start passes every test written with a trail-surrogate needle, because the *lead*
half of `𝄞` matches at offset 0 — aligned at the start, and running out in the
middle.

The cost is two `charCodeAt`s per candidate match, and a candidate that fails the
test essentially never happens, so it is two comparisons on the successful path.
