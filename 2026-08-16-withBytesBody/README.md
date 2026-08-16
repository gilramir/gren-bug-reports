# `HttpClient.withBytesBody` ignores `byteOffset`/`byteLength` and sends the whole backing buffer

`_HttpClient_prepBytes` builds its `Uint8Array` from `bytes.buffer` alone:

```js
// gren-lang/node/src/Gren/Kernel/HttpClient.js
var _HttpClient_prepBytes = function (bytes) {
  return new Uint8Array(bytes.buffer);
};
```

A `Bytes` value is a `DataView`, and a `DataView` is a *window* onto an
`ArrayBuffer` — `byteOffset` and `byteLength` are part of the value. Dropping
them sends everything in the backing buffer instead of the bytes the caller
asked for.

This is not a corner case in practice. `HttpServer` builds a request body with
`Buffer.concat`, and Node serves any allocation under 4096 bytes out of a shared
8 KiB pool, so **`request.body` is essentially always a view**. Forwarding one
with `withBytesBody` puts 8192 bytes on the wire regardless of how few were
received, and the extra bytes are whatever else is in the pool — other requests'
data, in a server that handles more than one.

- **Filed as:** [gren-lang/node#57](https://github.com/gren-lang/node/issues/57)
- **Package:** `gren-lang/node` (`HttpClient` kernel)
- **Versions:** gren 0.6.6, gren-lang/core 7.4.2, gren-lang/node 6.1.3, Node.js
  v25.1.0, Linux x86-64

## Reproducing

A minimal reproduction is in the https://github.com/gilramir/gren-bug-reports
repo.

```sh
$ git clone https://github.com/gilramir/gren-bug-reports.git
$ cd gren-bug-reports/2026-08-16-withBytesBody
$ ./run.sh
```

`src/Relay.gren` is one ~160-line program serving three paths on `:8086`:

- `POST /echo` reports how many bytes it received — the observer, nothing under
  test;
- `POST /relay` forwards the request body to `/echo` with `withBytesBody`;
- `POST /relay-compact` does the same after re-encoding the body through
  `Bytes.Encode.bytes`, which allocates an exact-width buffer at offset zero.

In the Relay.gren, `request.body` goes straight to
`withBytesBody`, and the length is measured on both ends with `Bytes.length`:

```gren
GotRequest { request, response } ->
    let
        sent =
            Bytes.length request.body       -- what we were handed
    in
    if request.url.path == "/echo" then
        -- The observer: say what actually arrived.
        { model = model
        , command =
            response
                |> Response.setStatus 200
                |> Response.setBody (String.fromInt sent)
                |> Response.send
        }

    else
        let
            -- THE ONLY DIFFERENCE between the two relay paths.
            body =
                if request.url.path == "/relay-compact" then
                    Bytes.Encode.encode (Bytes.Encode.bytes request.body)

                else
                    request.body
        in
        ...


forward : HttpClient.Permission -> Bytes -> Task String Int
forward permission body =
    HttpClient.post ("http://127.0.0.1:" ++ String.fromInt port_ ++ "/echo")
        |> HttpClient.withBytesBody "application/octet-stream" body
        |> HttpClient.expectString
        |> HttpClient.send permission
        |> Task.mapError HttpClient.errorToString
        |> Task.map (\response -> String.toInt response.data |> Maybe.withDefault -1)
```

Note that `Bytes.length request.body` already reports the right number — the
`DataView`'s `byteLength` is intact, and every Gren-level operation agrees with
it. Only the kernel's `new Uint8Array(bytes.buffer)` disagrees, which is why
this cannot be caught from inside the language.

`Bytes.Encode.encode (Bytes.Encode.bytes …)` on the `/relay-compact` path is a
copy into a buffer the value owns, fixing the behavior.
Each path answers `sent=<n> received=<n>`.

```
=== POST /relay — withBytesBody on the request body (expected: sent == received)
    8 bytes: sent=8 received=8192
  100 bytes: sent=100 received=8192
 4095 bytes: sent=4095 received=8192
 4096 bytes: sent=4096 received=4096
 5000 bytes: sent=5000 received=5000

=== POST /relay-compact — same, after re-encoding through Bytes.Encode.bytes
    8 bytes: sent=8 received=8
  100 bytes: sent=100 received=100
 4095 bytes: sent=4095 received=4095
 4096 bytes: sent=4096 received=4096
 5000 bytes: sent=5000 received=5000
```

By hand:

```sh
gren make Relay --output relay
node relay &
curl -s --data-binary '12345678' localhost:8086/relay          # sent=8 received=8192
curl -s --data-binary '12345678' localhost:8086/relay-compact  # sent=8 received=8
```

## Why the cutoff is at 4096

Node's `Buffer.allocUnsafe` serves requests smaller than `Buffer.poolSize >>> 1`
(4096, with the default 8192 pool) from a shared pool, and allocates
independently at or above it. `run.sh` prints this directly:

```
Buffer.poolSize = 8192 -> pooled when size < 4096
    8 byteOffset     8  buffer.byteLength 8192  new Uint8Array(b.buffer).byteLength 8192
 4095 byteOffset    16  buffer.byteLength 8192  new Uint8Array(b.buffer).byteLength 8192
 4096 byteOffset     0  buffer.byteLength 4096  new Uint8Array(b.buffer).byteLength 4096
```

So the bug affects **small** payloads and spares large ones.
A test suite that exercises `withBytesBody`
with a `Bytes.fromString` literal will also miss it, because
`Bytes.fromString` produces a fresh exact-width buffer at offset zero.

## Suggested fix

`HttpServer` already does this correctly;
`_HttpServer_setBodyAsBytes` passes all three arguments:

```js
// gren-lang/node/src/Gren/Kernel/HttpServer.js
var _HttpServer_setBodyAsBytes = F2(function (data, res) {
  let body = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
  res.write(body);
  return res;
});
```

`_HttpClient_prepBytes` should match:

```js
var _HttpClient_prepBytes = function (bytes) {
  return new Uint8Array(bytes.buffer, bytes.byteOffset, bytes.byteLength);
};
```

That one line covers both call sites: the one-shot body path
(`_HttpClient_extractRequestBody`, the `BYTES` case, line 323) and the streaming
chunk path (line 231) both go through `prepBytes`.

Those are the only two `new Uint8Array(` in `gren-lang/node`'s kernels, and the
other one is `HttpServer`'s correct version:

```
$ grep -rn 'new Uint8Array(' src/Gren/Kernel/
src/Gren/Kernel/HttpServer.js:84:  let body = new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
src/Gren/Kernel/HttpClient.js:330:  return new Uint8Array(bytes.buffer);
```

## Related

The sibling report in `2026-08-16-flatten/`
([gren-lang/node#58](https://github.com/gren-lang/node/issues/58)) is the same
mistake — `new Uint8Array(view.buffer)`, with the offset dropped — in
`gren-lang/core`'s `Bytes.flatten`. It behaves differently there: `flatten`
takes its length from `byteLength` and only its *contents* from the wrong place,
so the result is the right size and the wrong bytes, which is harder to notice
than this one. They are independent fixes in different packages.

Worth knowing here because `Bytes.flatten` is the obvious way to copy a `Bytes`
before handing it to `withBytesBody`, and it does not work. `Bytes.Encode.bytes`
does, which is what `/relay-compact` uses.

## Impact

1. **Wrong data.** Any program that receives bytes and forwards them — a proxy,
   a webhook relay, an event forwarder — sends a payload that neither matches
   what it received nor has the right length. A downstream signature check or
   content-length assertion fails, with nothing in the sending program to
   suggest why.

2. **Information disclosure.** The extra bytes are not padding; they are the
   rest of a shared pool. In a server handling concurrent requests, the surplus
   can contain fragments of *other* clients' request bodies, which the process
   then sends to a third party. A program can leak data it never asked to send
   and never touched.

Found while writing a Knative webhook receiver in
[gren-knative](https://github.com/gilramir/gren-knative): it verifies an HMAC
over the request body, then forwards the verified payload to an event sink. An
8-byte payload arrived at the sink as 8192 bytes. The package works around it by
re-encoding through `Bytes.Encode.bytes` before every `withBytesBody` call,
which is what `/relay-compact` above demonstrates.
