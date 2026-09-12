# `String.contains` and the index functions match half a surrogate pair

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

`./run.sh` prints the figure below.

## Summary

`String`'s module header says "Unless otherwise noted, all functions in this
module deal with code points", and `contains`, `startsWith`, `endsWith`,
`firstIndexOf`, `lastIndexOf` and `indices` are not noted. All six are
`String.prototype.indexOf` and `lastIndexOf`, which match **UTF-16 code units**,
so half of a surrogate pair is found inside the character it is half of.

`"𝄞ab"` has three characters: U+1D11E, `a`, `b`. On JavaScript U+1D11E is stored
as the two code units 0xD834 and 0xDD1E, and neither of those is one of the
string's characters. But:

```gren
clef = "𝄞ab"

trailHalf = String.sliceUnits 1 2 clef      -- the second unit of 𝄞, alone

String.contains trailHalf clef              -- True
String.firstIndexOf trailHalf clef          -- Just 1
```

The `Just 1` is the part with no way forward for the caller. `String.slice`
counts codepoints, so index 1 of `"𝄞ab"` is `"a"` — there is no index that
`slice` could be given to recover what was matched, because what was matched is
not a codepoint of the string. The answer is not merely in the wrong unit, as in
#148; there is no right answer to convert it to.

`String.sliceUnits` is how the needles above are made, so nothing here depends
on being able to write an escape for a lone surrogate. A program that slices
units — which is what that function is for — can produce one, and so can reading
a truncated UTF-16 buffer.

## Reproduction

```
the string is "𝄞ab": three codepoints (U+1D11E, a, b), four UTF-16 units
the needles are its first and second code unit, cut out with sliceUnits

count                            = 3
unitLength                       = 4
count of the trail half          = 1   (one codepoint, on its own)

-- half a character is reported as present
contains the trail half          = True   (should be False)
startsWith the lead half         = True   (should be False)
endsWith the trail half of "𝄞"   = True   (should be False)

-- and the index functions hand back an offset inside one codepoint
firstIndexOf the trail half      = Just 1   (should be Nothing)
firstIndexOf the lead half       = Just 0   (should be Nothing)
lastIndexOf the trail half       = Just 1   (should be Nothing)
indices of the trail half        = 1        (should be empty)

-- the controls: a whole character, and ASCII
contains the whole character     = True   (correct)
firstIndexOf the whole character = Just 0 (correct)

-- and a half on its own IS a codepoint, found in a string of itself
firstIndexOf the trail half in itself = Just 0 (correct)
```

The last line is why the rule has to be about the match and not about the
needle. An unpaired surrogate **is** a codepoint — it is not a scalar value, but
`String.count` of it is 1 — so a `String` holding one on its own really does
contain it, and refusing every needle with a surrogate in it would be wrong.

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

`_String_contains` and the three index functions then skip a match that is not
aligned and search on from `i + 1`; `_String_startsWith` checks the far end
(offset 0 cannot split a pair, but the end of the needle can) and
`_String_endsWith` the near one. Both ends have to be checked: the *lead* half
of `𝄞` matches at offset 0, which is aligned at the start and runs out in the
middle.

The cost is two `charCodeAt`s per candidate match, and a candidate match that
fails the test essentially never happens, so it is two comparisons on the
successful path.

This is independent of #148, which is about the *unit* the three index functions
answer in. Fixing #148 alone leaves `firstIndexOf trailHalf clef` answering an
index that no consumer can use; fixing this alone leaves the aligned indices
still counted in code units. A fix for #148 that converts a unit offset to a
codepoint offset has to decide what to do with this case in any event, which is
why the two are worth reading together.
