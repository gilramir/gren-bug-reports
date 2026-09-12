# `firstIndexOf` can return an index that `slice` cannot use: the match is half a character

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

This is the composition everyone writes — find something, then slice at what was
found:

```gren
when String.firstIndexOf sub str is
    Just i ->
        String.slice i (i + String.count sub) str

    Nothing ->
        ""
```

For one kind of match it does not return `sub`, and **no index would have made it
work**.

`String.sliceUnits` can cut between the two code units that a `𝄞` is stored as,
which gives a string holding half of one:

```gren
clef       = "𝄞ab"                       -- three characters: 𝄞, a, b
                                         -- the 𝄞 is U+1D11E, stored as the two
                                         -- code units 0xD834 and 0xDD1E
secondUnit = String.sliceUnits 1 2 clef  -- just the 0xDD1E

String.firstIndexOf secondUnit clef      -- Just 1
String.slice 1 2 clef                    -- "a"
```

`clef`'s characters are `𝄞`, `a` and `b`. `secondUnit` is not one of them, so
there is no character position for `firstIndexOf` to report: `Just 0` would mean
the `𝄞` and `Just 1` means the `a`, and neither is what matched. **`Nothing` is
the only answer that is not wrong.** `lastIndexOf` and `indices` do the same
thing.

This is not #148. There the index is a real position reported in the wrong unit,
and converting it is the whole fix. Here there is no position to convert to — so
whoever fixes #148 has to decide this case anyway, which is the main reason to
write it down.

`contains`, `startsWith` and `endsWith` say `True` for the same strings. They
return no index, so a fix for #148 would leave them alone, and they would then
disagree with the index functions about whether `secondUnit` is in `clef`.

## Terms

From `String`'s own module documentation: a **code unit** is "the smallest
primitive value of a string", 16 bits in Gren; a **code point** "represents a
unicode character", and takes one code unit or two. `count`, `slice` and
`toArray` work in code points, `unitLength` and `sliceUnits` in code units, and
"unless otherwise noted, all functions in this module deal with code points" —
none of the six named above is noted.

One thing that documentation leaves out matters here: a surrogate
(U+D800–U+DFFF, the values reserved for building pairs) is a code point too. So
`secondUnit` is a perfectly ordinary one-character `String` — `String.count` of
it is 1 — and it cannot be dismissed as malformed input.

Nor does it have to come from `sliceUnits`. Anything that turns a code point into
a `String` can build it; checked against 7.4.2: `sliceUnits`, `getUnit`,
`foldlUnits`, a `\u{DD1E}` escape in a literal, and
`Char.fromCode 0xDD1E |> String.fromChar`, which is the `fromCode` row in the
table below.

## Reproduction

`./run.sh` produces the rows below.

```gren
clef       = "𝄞ab"                                   -- 𝄞, a, b
clefChar   = "𝄞"                                     -- U+1D11E = 0xD834 0xDD1E
firstUnit  = String.sliceUnits 0 1 clef              -- 0xD834, the first half
secondUnit = String.sliceUnits 1 2 clef              -- 0xDD1E, the second half
fromCode   = String.fromChar (Char.fromCode 0xDD1E)  -- secondUnit again, built
                                                     -- without any *Units call
```

| call | result | expected |
|---|---|---|
| `String.firstIndexOf secondUnit clef` | `Just 1` | `Nothing` |
| `String.firstIndexOf firstUnit clef` | `Just 0` | `Nothing` |
| `String.lastIndexOf secondUnit clef` | `Just 1` | `Nothing` |
| `String.indices secondUnit clef` | `[1]` | `[]` |
| `String.firstIndexOf fromCode clef` | `Just 1` | `Nothing` |
| `String.contains secondUnit clef` | `True` | `False` |
| `String.startsWith firstUnit clef` | `True` | `False` |
| `String.endsWith secondUnit clefChar` | `True` | `False` |
| `String.contains fromCode clef` | `True` | `False` |
| `String.contains clefChar clef` | `True` | `True` |
| `String.firstIndexOf secondUnit secondUnit` | `Just 0` | `Just 0` |

The last two rows are already right, and they are there to bound the fix. The
final one is why the rule has to be about the *match* rather than about what is
being searched for: `secondUnit` is one code point, so a `String` holding just
that really does contain it, and rejecting every search string with a surrogate
in it would be wrong.

## The fix

A match counts only if both of its ends fall between characters. Whether a
UTF-16 offset falls inside a pair is two `charCodeAt`s and no scan:

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
(offset 0 cannot be inside a pair, but the end of `sub` can) and
`_String_endsWith` the near one.

**Both ends have to be checked**, which is easy to get wrong: checking only the
start gives the right answer for every row in the table except one — row 2, where
`firstUnit` matches at offset 0, fine at the start and running out in the middle
of the `𝄞`.

The cost is two `charCodeAt`s per candidate match, and a candidate that fails the
test essentially never happens, so it is two comparisons on the successful path.
