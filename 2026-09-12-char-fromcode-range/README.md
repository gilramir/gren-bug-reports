# `Char.fromCode` throws a `RangeError` for a code point out of range, and its documentation says it returns U+FFFD

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

`./run.sh` prints both halves of the figure below.

## Summary

`Char.fromCode : Int -> Char` is total in its type and its documentation says
what it does with a number that is not a code point:

> The full range of unicode is from `0` to `0x10FFFF`. With numbers outside that
> range, you get [the replacement character][fffd].

and the doc comment's own example is `fromCode -1 == '�'`.

It throws instead. `_Char_fromCode` is
`__Utils_chr(String.fromCodePoint(code))`, and `String.fromCodePoint` raises a
`RangeError` for anything below `0` or above `0x10FFFF`:

```
> Char.fromCode 65
'A' : Char
> Char.toCode (Char.fromCode 0xD800)
55296 : Int
> Char.fromCode -1
RangeError: Invalid code point -1
> Char.fromCode 0x110000
RangeError: Invalid code point 1114112
```

In a compiled program the exception is **invisible**: `gren run Main` prints the
lines before it, prints nothing for the line that throws, writes nothing to
stderr and exits `0`.

```
fromCode 65      = A
fromCode 0xD800  = 55296   (a lone surrogate, and no error)
exit code: 0
```

The third line — `fromCode -1` — is missing, and so is the fourth, which the
program would print afterwards. That part is not this report; it is why this is
easy to have and not notice, and it is two issues that are already open:
[core#142](https://github.com/gren-lang/core/issues/142), where an exception
raised after a stream write is swallowed and the scheduler stops for good, and
[compiler#385](https://github.com/gren-lang/compiler/issues/385), where a
crashing program exits zero. The REPL transcript above is the reproduction that
shows the exception, which is why `run.sh` prints both.

## Where it comes from

The doc comment is accurate about Elm, which this module was derived from.
`elm/core`'s kernel guards the range and returns the replacement character:

```js
function _Char_fromCode(code)
{
	return __Utils_chr(
		(code < 0 || 0x10FFFF < code)
			? '�'
			:
		(code <= 0xFFFF)
			? String.fromCharCode(code)
			:
		(code -= 0x10000,
			String.fromCharCode(Math.floor(code / 0x400) + 0xD800, code % 0x400 + 0xDC00)
		)
	);
}
```

Gren's is one line:

```js
function _Char_fromCode(code) {
  return __Utils_chr(String.fromCodePoint(code));
}
```

`String.fromCodePoint` is the better primitive — it builds the surrogate pair
itself, which is most of what Elm's version is doing by hand — and the guard was
dropped with the arithmetic. Nothing in the documentation was updated, so the
two disagree today.

## Two ways to fix it, and they are not the same fix

1. **Restore the documented behaviour**: return `'\u{FFFD}'` for `code < 0` or
   `code > 0x10FFFF`. Three lines, no signature change, no caller changes.

   ```js
   function _Char_fromCode(code) {
     return __Utils_chr(
       code < 0 || 0x10FFFF < code ? "�" : String.fromCodePoint(code),
     );
   }
   ```

2. **Change the signature to `Int -> Maybe Char`**, which is what the question
   "is this number a character?" actually has an answer for. It also covers the
   surrogates, which the second line of the transcript above shows are accepted
   today: `Char.fromCode 0xD800` hands back a `Char` holding an unpaired
   surrogate, which is not a Unicode scalar value and cannot be encoded in
   UTF-8. A replacement character does not distinguish "not a character" from "a
   string containing U+FFFD", either, so a caller that wants to know has to
   compare against U+FFFD and then ask whether the input *was* 0xFFFD.

The first is a bug fix and the second is an API change; only the first is
obviously in scope for a patch release. They are listed together because the
first one, written as above, is also the smaller half of the second, and because
whichever is chosen the documentation has to change: it currently describes
neither the code nor a design anyone would choose today.

[fffd]: https://en.wikipedia.org/wiki/Specials_(Unicode_block)#Replacement_character

## Running it

```bash
./run.sh
```

`src/Main.gren` is the program and `session.repl` is the REPL transcript. Each
line of the program is written before the next is built, so the output stops
where the exception is thrown rather than the program printing nothing at all.
