# `String.words` of a string with no words in it answers with one word, and that word is `""`

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`String.words` never produces an empty word — except for one input, where every
word it produces is empty:

```gren
Array.length (String.words "a b")   -- 2
Array.length (String.words " a ")   -- 1, the padding dropped
Array.length (String.words "")      -- 1
Array.first  (String.words "")      -- Just ""
```

So the obvious loop over the words of some text visits one word that is not
there, and `Array.length (String.words text)` is not the number of words in
`text` when `text` is empty or is nothing but whitespace.

The reason this is a defect rather than a choice is that `words` already drops
empties everywhere else. `" a "` does not answer `[ "", "a", "" ]`; a run of
whitespace between two words does not answer with an empty word between them.
Every caller may therefore assume that a word is non-empty, and exactly one
input breaks that assumption.

`String.split` and `String.lines` are a different case and are right as they
stand: `split "," ""` is `[ "" ]` because the empty string is one field, and
`lines ""` is `[ "" ]` because a text with no line terminator in it is one line.
Neither of those functions drops an empty piece anywhere, so neither promises
anything about the empty input that it then breaks.

## Reproduction

`./run.sh` produces the rows below.

| call | result | expected |
|---|---|---|
| `String.words ""` | `[ "" ]` | `[]` |
| `String.words " "` | `[ "" ]` | `[]` |
| `String.words "\n\t "` | `[ "" ]` | `[]` |
| `String.words "a"` | `[ "a" ]` | `[ "a" ]` |
| `String.words " a "` | `[ "a" ]` | `[ "a" ]` |
| `String.words "a  b"` | `[ "a", "b" ]` | `[ "a", "b" ]` |

The last three rows are there to bound the fix: they are already right, and they
are what says the function means to drop empty pieces.

## The cause and the fix

`Gren/Kernel/String.js`:

```js
function _String_words(str) {
  return str.trim().split(/\s+/g);
}
```

`"".split(/\s+/g)` is `[ "" ]` — `String.prototype.split` answers with one empty
field for the empty string rather than with no fields, for every separator. The
`trim()` is what turns a whitespace-only input into that same case.

One line:

```js
function _String_words(str) {
  var trimmed = str.trim();
  return trimmed === "" ? [] : trimmed.split(/\s+/g);
}
```
