# `String.firstIndexOf`, `lastIndexOf` and `indices` answer in UTF-16 code units

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

`./run.sh` prints the figure below.

## Summary

`String` is character-oriented: `count`, `slice`, `takeFirst`, `dropFirst`,
`reverse`, `toArray` and `pad` all work in codepoints, and #130 was fixed by
making `_String_slice` count codepoints rather than UTF-16 code units.

The three functions that *produce* an index were not part of that fix. They are
`String.prototype.indexOf` and `lastIndexOf`, so they answer in **UTF-16 code
units** — the unit no other function in the module accepts. For a string with a
non-BMP character before the match, an index handed back to `slice` points past
where it was found.

```
the string is "𝄞ab": three codepoints, four UTF-16 units

count                  = 3
unitLength             = 4

firstIndexOf "a"       = 2   (the codepoint index is 1)
lastIndexOf "b"        = 3   (the codepoint index is 2)
indices "b"            = 3   (the codepoint index is 2)

slice 1 2              = a   (slice takes codepoints, and is right)

slice at firstIndexOf "a" = b   (should be a)
slice at firstIndexOf "b" =     (should be b; the index is past the end)
```

The last two lines are the composition anyone would write:

```gren
when String.firstIndexOf needle haystack is
    Just i ->
        String.slice i (i + String.count needle) haystack
    Nothing ->
        ""
```

It is silent, and it only goes wrong for strings containing astral characters —
emoji, mathematical alphanumerics, most historic scripts, the higher CJK
extensions.

`String.indices` compounds it: its loop advances by `sub.length`, also code
units, so every offset it returns is shifted by the number of astral characters
before it.

## The fix

Convert the answer, which keeps `indexOf`'s native search:

```js
// Codepoints before UTF-16 offset `unitOffset`.
function _String_cpOffset(str, unitOffset) {
  var count = 0;
  for (var i = 0; i < unitOffset; ) {
    i += str.codePointAt(i) > 0xffff ? 2 : 1;
    count++;
  }
  return count;
}
```

`_String_indexOf` and `_String_lastIndexOf` wrap their result in it, and
`_String_indexes` maps over its own. `_String_indexes`'s `i = i + subLen`
advance stays in code units, since it is an offset into the string it is
searching; only what is pushed onto the result needs converting.

Two notes, since this is a behaviour change either way:

- The module documents itself as codepoint-oriented — "Unless otherwise noted,
  all functions in this module deal with code points" — and these three are not
  noted, so the fix is the documented behaviour rather than a new one.
- If the code-unit offsets are wanted, they belong beside the rest of that
  family (`unitLength`, `getUnit`, `sliceUnits`) under names that say so.
