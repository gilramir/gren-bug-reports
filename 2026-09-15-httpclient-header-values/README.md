# `HttpClient.send` puts a header's string where `Response` says `Array String`

`gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22, Linux x86-64.

## Summary

`HttpClient.Response`'s headers are a `Dict String (Array String)`, so that a
header sent more than once keeps each value. `HttpClient.send` puts a string
there instead of an array. For a response whose `content-type` is `text/plain`:

| call on `Dict.get "content-type" response.headers \|> Maybe.withDefault []` | result | expected |
|---|---|---|
| `Array.length values` | **`10`** | `1` |
| `Array.first values` | **`Just "t"`** | `Just "text/plain"` |
| `String.join ", " values` | **the program stops**: nothing more is printed, stderr is empty, and it exits 0 | `"text/plain"` |

The last row is the worst of the three. `String.join` throws on the string, and
the throw happens inside `fetch`'s promise chain, so the request's own
`.catch` receives it, after the task has already succeeded, and nothing reports
it.

The cause is `_HttpClient_formatResponse` in `Gren/Kernel/HttpClient.js`, which
`send` uses:

```js
for (const [key, value] of res.headers.entries()) {
  headerPairs.push({ __$key: key.toLowerCase(), __$value: value });
}
```

`Headers.entries()` gives each value as a string. `fetch` joins a repeated
header with `", "` itself, except `set-cookie`, which `entries()` gives once
per cookie, so this also keeps only the last cookie. The streaming API's
`_HttpClient_formatResponseLegacy` reads `res.headersDistinct`, whose values
are arrays, and is not affected.

## Reproduction

```
$ node app
Array.length values = 10
Array.first values = t
String.join ", " values follows
```

The program's last two lines are never printed.

## The fix

Collect each header's values into an array, one entry per `entries()` item:

```js
let headerPairs = [];
let index = {};
for (const [key, value] of res.headers.entries()) {
  const name = key.toLowerCase();
  if (Object.prototype.hasOwnProperty.call(index, name)) {
    headerPairs[index[name]].__$value.push(value);
  } else {
    index[name] = headerPairs.length;
    headerPairs.push({ __$key: name, __$value: [value] });
  }
}
```
