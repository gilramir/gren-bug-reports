# `HttpClient.send` splits header values at every comma, and still keeps one `set-cookie`

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` at
`ecf18b1` (`main`, 2026-09-27, the commit after `cab69f7`, which closed
node#71), node 22

`./run.sh` clones `gren-lang/node`, checks out `ecf18b1`, uses it as a
`local:` dependency, and runs the program below against `https://github.com`
with the pinned Gren and node (devbox), after printing the same headers as
`curl` sees them.

`cab69f7` fixed node#71 by splitting the string `Headers.entries()` gives on
`,`. That separates the values `fetch` joined, but it also cuts every value
that has a comma in it, so a `date` header, which nearly every response has,
comes back as two values. A cookie's `Expires` is cut the same way. Also, a
repeated `set-cookie` still keeps only the last cookie, which node#71 reported
too.

## Reproduction

`src/Main.gren` requests `https://github.com` and prints how many values `send`
gives for `date` and `set-cookie`, each cut to 40 characters:

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

                row headers name expected =
                    let
                        values =
                            Dict.get name headers |> Maybe.withDefault []
                    in
                    "| `"
                        ++ name
                        ++ "` | "
                        ++ String.fromInt (Array.length values)
                        ++ ": "
                        ++ Debug.toString (Array.map (String.takeFirst 40) values)
                        ++ " | "
                        ++ expected
                        ++ " |"
            in
            Node.endSimpleProgram
                (HttpClient.get "https://github.com"
                    |> HttpClient.expectAnything
                    |> HttpClient.send http
                    |> Task.andThen
                        (\response ->
                            print
                                (String.join "\n"
                                    [ "| header | values (each cut to 40 characters) | expected |"
                                    , "|---|---|---|"
                                    , row response.headers "date" "1: the date"
                                    , row response.headers "set-cookie" "one per cookie, each whole"
                                    ]
                                )
                        )
                    |> Task.onError (\_ -> print "request failed")
                )
```

Output (the dates and cookies change from run to run):

```
$ ./run.sh
$ curl -sI https://github.com | grep -iE "^(date|set-cookie):" | cut -c1-100
date: Mon, 28 Sep 2026 11:26:35 GMT
set-cookie: _gh_sess=MWq%2FcNUrf4Q3bNi1kv6q07OvwpE3Q3bKziMaF7XMMPgBgx%2BB03DhXftkqxARvrl2D5bfTXYUXZw
set-cookie: _octo=GH1.1.1348102763.1790594800; expires=Tue, 28 Sep 2027 11:26:40 GMT; domain=.github
set-cookie: logged_in=no; expires=Tue, 28 Sep 2027 11:26:40 GMT; domain=.github.com; path=/; HttpOnl

$ node app   # gren-lang/node ecf18b1
| header | values (each cut to 40 characters) | expected |
|---|---|---|
| `date` | 2: ["Mon", "28 Sep 2026 11:26:35 GMT"] | 1: the date |
| `set-cookie` | 2: ["logged_in=no; expires=Tue", "28 Sep 2027 11:26:41 GMT; domain=.github"] | one per cookie, each whole |
```

GitHub sent three cookies. `send` keeps only the last one and cuts it in two
at its `expires`.

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

With this change in `node-head` the program gives what `curl` sees:

```
| `date` | 1: ["Mon, 28 Sep 2026 11:26:45 GMT"] | 1: the date |
| `set-cookie` | 3: ["_gh_sess=w4Awl4kjIZ20t2CyOmVm4hFVV96%2Fh", "_octo=GH1.1.131319305.1790594810; expire", "logged_in=no; expires=Tue, 28 Sep 2027 1"] | one per cookie, each whole |
```

The trade-off: `fetch` has already joined any other repeated header with
`", "` before Gren sees it, so under this fix a header sent twice (as
`withDuplicatedHeader` does in `cab69f7`'s new test) comes back as one value,
`["dup, dup2"]`, and that test would fail. `fetch` does not keep the separate
values of any header except `set-cookie`, so no fix inside `send` can split
those back apart without the comma problem. `res.headers.getSetCookie()`
gives the cookies separately if `set-cookie` is to be handled by itself.
