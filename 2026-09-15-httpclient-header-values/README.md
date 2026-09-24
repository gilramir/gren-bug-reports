# `HttpClient.send` puts a header's string where `Response` says `Array String`

**Repository:** `gren-lang/node`
**Found against:** `gren` 0.6.6, `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3, node 22

`./run.sh` builds and runs the program below with the pinned Gren and node (devbox).

`HttpClient.Response`'s headers are a `Dict String (Array String)`, but
`HttpClient.send` stores each header's value as a plain string. So for
`content-type: text/plain`, `Array.length` of the values is 10 and
`Array.first` is `Just "t"`, and `String.join ", " values` throws inside
`fetch`'s promise chain after the task has already succeeded: the program
silently stops, with nothing on stderr and exit status 0. A repeated
`set-cookie` also keeps only the last cookie.

## Reproduction

`gren.json` dependencies: `gren-lang/core` 7.4.2, `gren-lang/node` 6.1.3. Save as `src/Main.gren`. Build and run with `gren make Main --output=app && node app`; the third row is never printed:

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
            in
            Node.endSimpleProgram
                (HttpClient.get "data:text/plain,x"
                    |> HttpClient.send http
                    |> Task.andThen
                        (\response ->
                            let
                                values =
                                    Dict.get "content-type" response.headers |> Maybe.withDefault []
                            in
                            print "| call | result | expected |\n|---|---|---|"
                                |> Task.andThen (\_ -> print ("| `Array.length values` | " ++ String.fromInt (Array.length values) ++ " | 1 |"))
                                |> Task.andThen (\_ -> print ("| `Array.first values` | " ++ Debug.toString (Array.first values) ++ " | Just \"text/plain\" |"))
                                |> Task.andThen (\_ -> print ("| `String.join \", \" values` | " ++ String.join ", " values ++ " | text/plain |"))
                        )
                    |> Task.onError (\_ -> print "request failed")
                )
```

Output:

```
$ node app; echo "exit status $?"
| call | result | expected |
|---|---|---|
| `Array.length values` | 10 | 1 |
| `Array.first values` | Just "t" | Just "text/plain" |
exit status 0
```

## Cause

`_HttpClient_formatResponse` in `Gren/Kernel/HttpClient.js`, which `send` uses:

```js
for (const [key, value] of res.headers.entries()) {
  headerDict = A3(__Dict_set, key.toLowerCase(), value, headerDict);
}
```

`Headers.entries()` gives each value as a string. `fetch` already joins a
repeated header with `", "`, except `set-cookie`, which `entries()` gives once
per cookie, so `__Dict_set` keeps only the last one. The streaming API's
`_HttpClient_formatResponseLegacy` reads `res.headersDistinct`, whose values are
arrays, and is not affected.

## Fix

Collect each header's values into an array:

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

With this change the program above prints all three rows with the expected
results.
