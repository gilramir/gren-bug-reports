# `HttpClient.send` splits header values at every comma, and still keeps one `set-cookie`

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` at
`ecf18b1` (`main`, 2026-09-27, the commit after `cab69f7`, which closed
node#71), node 22

`./run.sh` clones `gren-lang/node`, checks out `ecf18b1`, uses it as a
`local:` dependency, starts `server.mjs` and runs the program below against it
with the pinned Gren and node (devbox).

`cab69f7` fixed node#71 by splitting the string `Headers.entries()` gives on
`,`. That separates the values `fetch` joined, but it also cuts every value
that has a comma in it, so a `date` header, which nearly every response has,
comes back as two values. A cookie's `Expires` is cut the same way. Also, a
repeated `set-cookie` still keeps only the last cookie, which node#71 reported
too.

## Reproduction

`server.mjs` answers with

```
date: Mon, 28 Sep 2026 12:00:00 GMT
set-cookie: a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT
set-cookie: b=2
```

and `src/Main.gren` prints what `send` gives for each:

```gren
module Main exposing (main)

import Dict
import HttpClient
import Init
import Node
import Stream
import Task


main : Node.SimpleProgram a
main =
    Node.defineSimpleProgram <| \env ->
        Init.await HttpClient.initialize <| \http ->
            let
                print line =
                    Stream.writeLineAsBytes line env.stdout
                        |> Task.onError (\_ -> Task.succeed env.stdout)

                url =
                    "http://127.0.0.1:" ++ (Array.get 2 env.args |> Maybe.withDefault "") ++ "/"

                row headers name expected =
                    "| `" ++ name ++ "` | " ++ Debug.toString (Dict.get name headers) ++ " | " ++ expected ++ " |"
            in
            Node.endSimpleProgram
                (HttpClient.get url
                    |> HttpClient.expectAnything
                    |> HttpClient.send http
                    |> Task.andThen
                        (\response ->
                            print
                                (String.join "\n"
                                    [ "| header | result | expected |"
                                    , "|---|---|---|"
                                    , row response.headers "date" "Just [\"Mon, 28 Sep 2026 12:00:00 GMT\"]"
                                    , row response.headers "set-cookie" "Just [\"a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT\", \"b=2\"]"
                                    ]
                                )
                        )
                    |> Task.onError (\_ -> print "request failed")
                )
```

Output:

```
$ ./run.sh
$ node app 33969   # gren-lang/node ecf18b1
| header | result | expected |
|---|---|---|
| `date` | Just ["Mon", "28 Sep 2026 12:00:00 GMT"] | Just ["Mon, 28 Sep 2026 12:00:00 GMT"] |
| `set-cookie` | Just ["b=2"] | Just ["a=1; Expires=Wed, 21 Oct 2026 07:28:00 GMT", "b=2"] |
```

## Cause

`_HttpClient_formatResponse` in `Gren/Kernel/HttpClient.js`:

```js
for (const [key, value] of res.headers.entries()) {
  headerDict = A3(
    __Dict_set,
    key.toLowerCase(),
    value.split(",").map((v) => v.trimStart()),
    headerDict,
  );
}
```

A comma is not a reliable separator: HTTP dates contain one, and so can quoted
strings and cookie attributes. `entries()` gives `set-cookie` once per cookie
rather than joined, so each cookie goes through `__Dict_set` in turn and only
the last one is kept.

## Fix

Collect each header's entries by name instead of splitting them:

```js
const values = {};
for (const [key, value] of res.headers.entries()) {
  const name = key.toLowerCase();
  (values[name] ??= []).push(value);
}
for (const [name, list] of Object.entries(values)) {
  headerDict = A3(__Dict_set, name, list, headerDict);
}
```

With this change in `node-head` the program prints the expected column in both
rows.

The trade-off: `fetch` has already joined any other repeated header with
`", "` before Gren sees it, so under this fix a header sent twice (as
`withDuplicatedHeader` does in `cab69f7`'s new test) comes back as one value,
`["dup, dup2"]`, and that test would fail. `fetch` does not keep the separate
values of any header except `set-cookie`, so no fix inside `send` can split
those back apart without the comma problem. `res.headers.getSetCookie()`
gives the cookies separately if `set-cookie` is to be handled by itself.
